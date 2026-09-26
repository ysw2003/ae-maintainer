--------------------------------------------------------------------------------
-- ae_maintainer.lua  v1.0
--
-- 대상: GTNH 2.9.0-beta-3
--   mods: appliedenergistics2-rv3-beta-1050-GTNH
--         ae2fc-1.5.106-gtnh        ← "ME Level Maintainer" 제공 모드
--         OpenComputers-1.12.61-GTNH
--
-- 하는 일
--   AE2FC 의 ME Level Maintainer(= level_maintainer 컴포넌트)에 등록된
--   아이템/유체, 유지 수량(quantity), 1회 제작량(batch) 을 OC 어댑터로 읽고,
--   내가 정한 주기마다 ME 네트워크에 크래프트 요청을 넣는다.
--
-- 필요한 장비
--   1) 어댑터 + ME Level Maintainer 블록  -> 컴포넌트 "level_maintainer" (필수)
--   2) 어댑터 + ME Controller 블록        -> 컴포넌트 "me_controller"    (drive 모드)
--   3) 어댑터 + 화면(선택)                -> 상태 표시
--
-- 사용법 (OC 컴퓨터에서)
--   ae_maintainer                  CONFIG 값대로 상시 실행
--   ae_maintainer monitor          읽기/표시만 (요청 안 함)
--   ae_maintainer drive [주기초]    직접 요청 (기본 60초)
--   ae_maintainer once             1회 계산/표시만, 설정 변경 없음
--   ae_maintainer set 슬롯 유지 배치  유지기의 유지수량/배치를 프로그램으로 수정
--   ae_maintainer help
--
-- 주의: 이 프로그램은 OC 컴퓨터가 켜져 있을 때만 동작한다.
--       takeover=true 로 쓰면 유지기 자체의 자동요청을 꺼두므로,
--       컴퓨터를 끄기 전에 ae_maintainer 를 먼저 종료(복원)하는 편이 안전하다.
--------------------------------------------------------------------------------

local VERSION = "1.0"

-- ============================ 사용자 설정 ====================================
local CONFIG = {
  mode      = "drive",   -- "drive"=직접 요청, "monitor"=읽기만
  interval  = 60,        -- 요청 주기(초)
  takeover  = true,      -- true=유지기 슬롯 자동요청을 끄고 OC가 단독으로 관리
  batchMode = "need",    -- "need"=min(batch,부족분), "batch"=batch 고정, "fill"=부족분을 batch 단위로 올림
  dryRun    = false,     -- true=요청하지 않고 계산 결과만 출력
  labelFallback = true,  -- 아이템 이름(name) 매칭 실패 시 표시이름(label)로 재시도
  autoRestore   = true,  -- 종료(Ctrl+C) 시 유지기 슬롯 enable 상태를 원래대로 복구
  maintainerAddress = nil, -- 유지기가 여러 대일 때 어댑터 주소로 지정
  controllerAddress = nil, -- ME Controller 가 여러 대일 때 어댑터 주소로 지정
}

-- 선택: 같은 폴더에 ae_maintainer.cfg 가 있으면 위 값을 덮어쓴다.
--   예)  mode=drive
--        interval=120
--        takeover=true
local CONFIG_FILE = "ae_maintainer.cfg"
-- ============================== 공용 유틸 ====================================
local function nowStamp()
  local ok, t = pcall(os.time)
  if ok and type(t) == "number" then
    local ok2, s = pcall(os.date, "%H:%M:%S", t)
    if ok2 and type(s) == "string" then return s end
  end
  local ok3, u = pcall(function() return computer.uptime() end)
  return string.format("t+%s", ok3 and math.floor(u) or "?")
end

local function log(fmt, ...)
  local msg = fmt
  if select("#", ...) > 0 then
    local ok, s = pcall(string.format, fmt, ...)
    msg = ok and s or tostring(fmt)
  end
  print(string.format("[%s] %s", nowStamp(), msg))
end

local function toInt(v)
  local n = tonumber(v)
  if not n then return 0 end
  return math.floor(n)
end

local function comma(v)
  local s = string.format("%d", toInt(v))
  local rev = s:reverse():gsub("(%d%d%d)", "%1,")
  rev = rev:reverse()
  return (rev:gsub("^,", ""))
end

-- 설정 파일(단순 key=value) 읽기. 코드 실행 없음.
local function loadConfigFile(path)
  local f = io.open(path, "r")
  if not f then return 0 end
  local n = 0
  for line in f:lines() do
    line = line:gsub("#.*$", ""):gsub("%s+$", "")
    local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if k and CONFIG[k] ~= nil then
      if type(CONFIG[k]) == "boolean" then
        CONFIG[k] = (v == "true" or v == "1" or v == "yes")
      elseif type(CONFIG[k]) == "number" then
        CONFIG[k] = tonumber(v) or CONFIG[k]
      else
        if v ~= "" and v ~= "nil" then CONFIG[k] = v end
      end
      n = n + 1
    end
  end
  f:close()
  return n
end

-- 컴포넌트 탐색 ---------------------------------------------------------------
local function listOf(name)
  local out = {}
  local ok, t = pcall(component.list, name, true)
  if not ok or type(t) ~= "table" then
    ok, t = pcall(component.list, name)
  end
  if ok and type(t) == "table" then
    for addr in pairs(t) do out[#out + 1] = addr end
    table.sort(out)
  end
  return out
end

local function proxy(addr)
  local ok, p = pcall(component.proxy, addr)
  if ok and p then return p end
  return nil
end

-- ===================== 1) 유지기(level_maintainer) 읽기 ======================
local SLOT_COUNT = 5          -- ae2fc TileLevelMaintainer.REQ_COUNT = 5 (슬롯 1~5)

local state = {
  pending = {},        -- [슬롯] = request() 가 돌려준 상태 userdata
  originalEnable = {}, -- [슬롯] = takeover 전 원래 enable 값
  tookOver = false,
}

local function findMaintainer()
  if CONFIG.maintainerAddress then
    local p = proxy(CONFIG.maintainerAddress)
    if p then return p, CONFIG.maintainerAddress, 1 end
  end
  local addrs = listOf("level_maintainer")
  if #addrs == 0 then return nil, nil, 0 end
  return proxy(addrs[1]), addrs[1], #addrs
end

local function findController()
  if CONFIG.controllerAddress then
    local p = proxy(CONFIG.controllerAddress)
    if p then return p, CONFIG.controllerAddress, 1 end
  end
  local addrs = listOf("me_controller")
  if #addrs == 0 then return nil, nil, 0 end
  return proxy(addrs[1]), addrs[1], #addrs
end

-- 슬롯 1개 읽기. 비어 있으면 nil.
local function readSlot(lm, i)
  local ok, s = pcall(lm.getSlot, i)
  if not ok then return nil, tostring(s) end
  if type(s) ~= "table" then return nil end
  local slot = {
    index     = i,
    name      = s.name,
    label     = s.label,
    damage    = toInt(s.damage),
    hasTag    = s.hasTag and true or false,
    isFluid   = s.isFluid and true or false,
    quantity  = toInt(s.quantity),   -- 유지해야 하는 수량
    batch     = toInt(s.batch),      -- 1회 제작(요청)량
    isEnable  = s.isEnable and true or false,
    isDone    = s.isDone and true or false, -- true = 진행 중인 작업 없음
    fluidName = nil,
  }
  if slot.isFluid then
    if type(s.fluid) == "table" then
      slot.fluidName = s.fluid.name
      slot.label = s.fluid.label or slot.label
    end
  end
  return slot
end

local function readAllSlots(lm)
  local slots, errs = {}, {}
  for i = 1, SLOT_COUNT do
    local s, err = readSlot(lm, i)
    if s then slots[i] = s elseif err then errs[#errs + 1] = string.format("%d:%s", i, err) end
  end
  return slots, errs
end

-- ======================= 2) ME 네트워크 조회 (me_controller) =================
-- 현재 네트워크에 있는 수량. 유체는 mB, 아이템은 개수.
local function storedAmount(mc, slot)
  if slot.isFluid then
    if not slot.fluidName then return nil, "유체 이름 확인 불가" end
    local ok, list = pcall(mc.getFluidsInNetwork, { name = slot.fluidName })
    if not ok or type(list) ~= "table" then return nil, "getFluidsInNetwork 실패" end
    local total = 0
    for _, f in ipairs(list) do total = total + toInt(f.amount) end
    return total, "fluid"
  end

  local total = 0
  local ok, list = pcall(mc.getItemsInNetwork, { name = slot.name, damage = slot.damage })
  if ok and type(list) == "table" then
    for _, it in ipairs(list) do total = total + toInt(it.size) end
  end
  if total == 0 and CONFIG.labelFallback and slot.label then
    local ok2, list2 = pcall(mc.getItemsInNetwork, { label = slot.label, damage = slot.damage })
    if ok2 and type(list2) == "table" then
      local t2 = 0
      for _, it in ipairs(list2) do t2 = t2 + toInt(it.size) end
      if t2 > 0 then return t2, "label" end
    end
  end
  return total, "name"
end

-- 이 슬롯을 제작할 수 있는 레시피(= Craftable userdata) 찾기
local function findCraftable(mc, slot)
  local filter
  if slot.isFluid then
    if not slot.fluidName then return nil end
    filter = { name = slot.fluidName }
  else
    filter = { name = slot.name, damage = slot.damage }
  end
  local ok, list = pcall(mc.getCraftables, filter)
  if ok and type(list) == "table" and list[1] then return list[1], #list end

  -- 이름 매칭 실패 시 표시이름(label)로 전체 검색 (네트워크가 크면 느릴 수 있음)
  if CONFIG.labelFallback and not slot.isFluid and slot.label then
    local ok2, all = pcall(mc.getCraftables)
    if ok2 and type(all) == "table" then
      for _, c in ipairs(all) do
        local ok3, st = pcall(c.getStack, c)
        if not ok3 then ok3, st = pcall(c.getStack) end
        if ok3 and type(st) == "table" and st.label == slot.label
           and toInt(st.damage) == slot.damage then
          return c, 1, "label"
        end
      end
    end
  end
  return nil
end


-- ======================= 3) 요청 상태 추적 / takeover ========================
local unpack = table.unpack or unpack

-- userdata 메서드 호출 (OC는 값 종류에 따라 self 주입 여부가 달라 둘 다 시도)
local function callValue(obj, method, ...)
  if obj == nil then return false, method .. " 대상 없음" end
  local fn = obj[method]
  if type(fn) ~= "function" then return false, method .. " 메서드 없음" end
  local args = { ... }
  local ok, v = pcall(fn, obj, unpack(args))
  if ok then return true, v end
  local ok2, v2 = pcall(fn, unpack(args))
  if ok2 then return true, v2 end
  return false, v
end

local function callBool(obj, method)
  local ok, v = callValue(obj, method)
  if not ok then return nil end
  return v and true or false
end

-- 이 슬롯에 대해 프로그램이 넣은 요청이 아직 진행 중인가?
local function jobBusy(i)
  local st = state.pending[i]
  if not st then return false end
  local computing = callBool(st, "isComputing")
  if computing == nil then
    state.pending[i] = nil
    return false
  end
  if computing then return true end
  if callBool(st, "hasFailed") then
    log("슬롯 %d: 이전 요청 실패", i)
  elseif callBool(st, "isCanceled") then
    log("슬롯 %d: 이전 요청 취소됨", i)
  elseif callBool(st, "isDone") then
    log("슬롯 %d: 이전 요청 완료", i)
  end
  state.pending[i] = nil
  return false
end

-- takeover: 유지기 자체의 자동요청을 끄고 OC가 단독으로 요청하게 한다.
local function takeOver(lm, slots)
  if not CONFIG.takeover or state.tookOver then return end
  local n = 0
  for i = 1, SLOT_COUNT do
    local s = slots[i]
    if s then
      state.originalEnable[i] = s.isEnable
      if s.isEnable then
        local ok = pcall(lm.setEnable, i, false)
        if ok then
          n = n + 1
          s.isEnable = false
        end
      end
    end
  end
  state.tookOver = true
  if n > 0 then
    log("유지기 자동요청 %d개 슬롯 OFF (OC 단독 관리). 종료 시 복구합니다.", n)
  end
end

local function restoreAll(lm)
  if not lm then return end
  if not (CONFIG.takeover and CONFIG.autoRestore and state.tookOver) then return end
  local n = 0
  for i = 1, SLOT_COUNT do
    if state.originalEnable[i] then
      local ok = pcall(lm.setEnable, i, true)
      if ok then n = n + 1 end
    end
  end
  state.tookOver = false
  if n > 0 then log("유지기 슬롯 %d개를 다시 켰습니다(원상복구).", n) end
end


-- =========================== 4) 한 주기 처리 =================================
-- 요청량 결정: need=부족분까지만, batch=batch 고정, fill=부족분을 batch 단위로 올림
local function decideAmount(slot, deficit)
  local batch = slot.batch
  if batch <= 0 then return deficit end
  if CONFIG.batchMode == "batch" then
    return batch
  elseif CONFIG.batchMode == "fill" then
    return math.ceil(deficit / batch) * batch
  end
  return math.min(batch, deficit)
end

local function shortText(s, n)
  s = tostring(s or "?")
  if #s <= n then return s end
  return s:sub(1, n - 3) .. "..."
end

local function slotLine(s)
  local kind = s.isFluid and "F" or "I"
  local id = s.isFluid and (s.fluidName or "?")
              or string.format("%s:%d", tostring(s.name or "?"), s.damage)
  return string.format(" %d %s %-26s 유지 %-10s 배치 %-8s",
    s.index, kind, shortText(s.label or id, 26), comma(s.quantity), comma(s.batch))
end

-- ctx = { lm=, lmAddr=, mc=, mcAddr=, count=, drive=bool }
local function runCycle(ctx)
  local lm, mc = ctx.lm, ctx.mc
  local out = {}
  local slots = readAllSlots(lm)

  if ctx.drive then takeOver(lm, slots) end

  local requested, missing = 0, 0
  for i = 1, SLOT_COUNT do
    local s = slots[i]
    if not s then
      out[#out + 1] = string.format(" %d  (빈 슬롯)", i)
    else
      local head = slotLine(s)
      if mc == nil then
        out[#out + 1] = head .. "  ME 조회 불가(me_controller 없음)"
      else
        local stored, how = storedAmount(mc, s)
        if stored == nil then
          out[#out + 1] = head .. "  조회 실패: " .. tostring(how)
        else
          local deficit = s.quantity - stored
          if deficit <= 0 then
            out[#out + 1] = head .. string.format("  보관 %-11s 충족", comma(stored))
          elseif (not ctx.drive) or CONFIG.dryRun then
            out[#out + 1] = head .. string.format("  보관 %-11s 부족 %s (요청 안 함)",
              comma(stored), comma(deficit))
          elseif jobBusy(i) then
            out[#out + 1] = head .. string.format("  보관 %-11s 이전 요청 진행 중", comma(stored))
          else
            local amount = decideAmount(s, deficit)
            local craftable = findCraftable(mc, s)
            if not craftable then
              missing = missing + 1
              out[#out + 1] = head .. string.format("  보관 %-11s 레시피 없음(Not Found)", comma(stored))
            else
              local ok, st = callValue(craftable, "request", amount)
              if ok then
                state.pending[i] = st
                requested = requested + 1
                out[#out + 1] = head .. string.format("  보관 %-11s -> 요청 %s",
                  comma(stored), comma(amount))
              else
                out[#out + 1] = head .. string.format("  보관 %-11s 요청 실패: %s",
                  comma(stored), tostring(st))
              end
            end
          end
        end
      end
    end
  end

  return out, requested, missing
end

-- ============================== 5) 화면 출력 ================================
local hasScreen = false
do
  local ok, gpu = pcall(component.isAvailable, "gpu")
  local ok2, scr = pcall(component.isAvailable, "screen")
  hasScreen = (ok and gpu and ok2 and scr) and true or false
end

local function render(header, lines, footer)
  if hasScreen and type(term) == "table" then
    pcall(term.clear)
    pcall(term.setCursorPos, 1, 1)
  end
  print(header)
  for _, l in ipairs(lines) do print(l) end
  if footer and footer ~= "" then print(footer) end
end



-- ============================== 6) 실행부 ===================================
local HELP = [[
ae_maintainer VERSION  (GTNH 2.9.0-beta-3 / AE2FC ME Level Maintainer)

  ae_maintainer                  설정대로 상시 실행
  ae_maintainer monitor          읽기/표시만 (요청 X)
  ae_maintainer drive [주기초]    지정 주기(기본 60초)로 직접 요청
  ae_maintainer once             1회만 계산/표시 (설정 변경 X)
  ae_maintainer set 슬롯 유지 배치  유지기의 유지수량/배치를 프로그램으로 수정
  ae_maintainer help

설정 파일: ./ae_maintainer.cfg (key=value, 예: interval=120 / takeover=false)

필요 컴포넌트
  - 어댑터 + ME Level Maintainer : level_maintainer  (설정/수량 읽기)
  - 어댑터 + ME Controller       : me_controller    (보관량 조회 + 크래프트 요청)
]]

local function headerText(ctx)
  return string.format("== AE Maintainer %s | %s | 주기 %d초 | takeover=%s | batchMode=%s ==",
    VERSION, ctx.drive and "DRIVE" or "MONITOR", CONFIG.interval,
    tostring(CONFIG.takeover), CONFIG.batchMode)
end

local function mainLoop(ctx)
  log("시작: %s 모드, 주기 %d초 (중단하려면 Ctrl+C)", ctx.drive and "DRIVE" or "MONITOR", CONFIG.interval)
  while true do
    local lines, requested, missing = runCycle(ctx)
    render(headerText(ctx), lines,
      string.format(" 이번 주기: 요청 %d건 / 레시피 없음 %d건", requested, missing))
    local remain = CONFIG.interval
    while remain > 0 do
      local step = math.min(remain, 5)
      os.sleep(step)
      remain = remain - step
    end
  end
end

local function main(...)
  local argv = { ... }
  local cmd = argv[1]
  local hadCfg = loadConfigFile(CONFIG_FILE)
  if hadCfg > 0 then log("설정 파일 %s 에서 %d개 항목을 읽었습니다.", CONFIG_FILE, hadCfg) end

  if cmd == "help" or cmd == "-h" or cmd == "--help" then
    print((HELP:gsub("VERSION", VERSION)))
    return
  end

  local lm, lmAddr, lmCount = findMaintainer()
  if not lm then
    print("ME Level Maintainer(level_maintainer) 컴포넌트를 찾지 못했습니다.")
    print(" - 어댑터를 ME Level Maintainer 블록에 붙였는지 확인하세요.")
    print(" - 유지기 자체도 ME 네트워크에 연결되어 있어야 합니다.")
    return
  end
  local mc, mcAddr, mcCount = findController()

  if cmd == "set" then
    local slot = tonumber(argv[2])
    local qty  = tonumber(argv[3])
    local bat  = tonumber(argv[4])
    if not (slot and qty and bat) then
      print("사용법: ae_maintainer set 슬롯(1-5) 유지수량 배치수량")
      return
    end
    local ok, res = pcall(lm.setSlot, slot, qty, bat)
    if ok then
      log("슬롯 %d 설정 완료: 유지=%s, 배치=%s (반환 %s)", slot, comma(qty), comma(bat), tostring(res))
    else
      log("설정 실패: %s", tostring(res))
    end
    return
  end

  local ctx = {
    lm = lm, lmAddr = lmAddr, count = lmCount,
    mc = mc, mcAddr = mcAddr,
    drive = (CONFIG.mode == "drive"),
  }

  if cmd == "monitor" then
    ctx.drive = false
  elseif cmd == "drive" then
    ctx.drive = true
    if argv[2] then CONFIG.interval = tonumber(argv[2]) or CONFIG.interval end
  elseif cmd == "once" then
    ctx.drive = false
    local lines, requested, missing = runCycle(ctx)
    render(headerText(ctx), lines,
      string.format(" [1회 실행] 부족분 계산/요청 %d건, 레시피 없음 %d건", requested, missing))
    return
  elseif cmd ~= nil then
    log("알 수 없는 명령입니다: %s (help 를 확인하세요)", tostring(cmd))
    return
  end

  if lmCount > 1 then
    log("유지기가 %d대 감지되어 첫 번째(%s)를 사용합니다. maintainerAddress 로 지정할 수 있습니다.",
      lmCount, tostring(lmAddr))
  end
  if mcCount and mcCount > 1 then
    log("ME Controller 가 %d대 감지되어 첫 번째(%s)를 사용합니다.", mcCount, tostring(mcAddr))
  end
  if not mc then
    log("me_controller 컴포넌트가 없습니다: 보관량 조회/요청이 불가해 읽기만 표시합니다.")
  end

  local ok, err = pcall(mainLoop, ctx)
  restoreAll(lm)
  if not ok then log("중단됨: %s", tostring(err)) end
end

main(...)
