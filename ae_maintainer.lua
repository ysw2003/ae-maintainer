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
--   2) 어댑터 + ME Controller 블록        -> 컴포넌트 "me_controller"    (보관량 조회/요청)
--      (ME Controller 대신 **ME Interface** 를 붙여도 됩니다 -> "me_interface")
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

local VERSION = "1.3"

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

  -- [v1.2] 중복 요청 방지
  skipIfCrafting   = true,  -- AE CPU 가 같은 품목을 이미 제작 중이면 요청하지 않음(finalOutput 비교)
  scanActiveItems  = false, -- 위 판단에 activeItems/storedItems/pendingItems 까지 포함(오탐 가능)
  skipIfMaintainer = true,  -- 유지기 자체가 그 슬롯 작업 중(isDone=false)이면 요청하지 않음

  -- [v1.2] 응답 없는 요청 자동 중단
  requestTimeout  = 60,   -- 요청 후 이 초 안에 완료되지 않으면 중단(+AE CPU 취소 시도). 0=비활성
  cancelOnTimeout = true, -- 타임아웃 시 해당 AE CPU 작업 취소 시도
  timeoutCooldown = 0,    -- 중단 후 이 초 동안 그 슬롯 재요청 금지 (0=즉시 재시도 가능)

  -- [v1.2] 화면
  countdown = true,       -- 화면에 다음 주기까지 남은 시간을 1초마다 갱신
}

-- 선택: 같은 폴더에 ae_maintainer.cfg 가 있으면 위 값을 덮어쓴다.
--   예)  mode=drive
--        interval=120
--        takeover=true
local CONFIG_FILE = "ae_maintainer.cfg"

-- ======================= OC API 로딩 (전역이 아님!) ==========================
-- OpenOS 는 `component` / `computer` / `term` 을 **전역(global)으로 노출하지 않습니다.**
-- (실측: OC jar 의 boot/04_component.lua 1~2행이 `local component = require("component")`
--  처럼 모듈로 받아 씁니다.)
-- 전역을 쓰면 게임에서 즉시:
--   attempt to index a nil value (global 'component')
-- 으로 죽습니다. (v1.0 에서 실제 발생한 오류)
local component, computer, term = nil, nil, nil
do
  local okc, c = pcall(require, "component")
  if okc and type(c) == "table" then component = c end
  local okp, p = pcall(require, "computer")
  if okp and type(p) == "table" then computer = p end
  local okt, t = pcall(require, "term")
  if okt and type(t) == "table" then term = t end
end

-- ============================== 공용 유틸 ====================================
local function nowStamp()
  local ok, t = pcall(os.time)
  if ok and type(t) == "number" then
    local ok2, s = pcall(os.date, "%H:%M:%S", t)
    if ok2 and type(s) == "string" then return s end
  end
  if computer then
    local ok3, u = pcall(computer.uptime)
    if ok3 and type(u) == "number" then return string.format("t+%d", math.floor(u)) end
  end
  return "t+?"
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

-- 경과 시간 측정용 (초). computer.uptime() 우선, 없으면 os.time()
local function nowSeconds()
  if computer then
    local ok, u = pcall(computer.uptime)
    if ok and type(u) == "number" then return u end
  end
  local ok2, t = pcall(os.time)
  if ok2 and type(t) == "number" then return t end
  return nil
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

-- 기본 설정 파일이 없으면 만들어 준다 (인게임에서 cfg 를 따로 받지 않아도 되게)
local CFG_KEYS = {
  "mode", "interval", "takeover", "batchMode", "dryRun", "labelFallback", "autoRestore",
  "skipIfCrafting", "scanActiveItems", "skipIfMaintainer",
  "requestTimeout", "cancelOnTimeout", "timeoutCooldown", "countdown",
}

local function ensureConfigFile(path)
  local f = io.open(path, "r")
  if f then f:close(); return false end
  local out = io.open(path, "w")
  if not out then return false end
  out:write("# ae_maintainer 기본 설정 (자동 생성)\n")
  out:write("# 값을 바꾼 뒤 프로그램을 다시 실행하세요. 주석(#)과 빈 줄은 무시됩니다.\n")
  out:write("# 설명: https://github.com/ysw2003/ae-maintainer  (ae_maintainer.cfg)\n\n")
  for _, k in ipairs(CFG_KEYS) do
    local v = CONFIG[k]
    if type(v) == "boolean" then
      out:write(string.format("%s=%s\n", k, tostring(v)))
    elseif type(v) == "number" then
      out:write(string.format("%s=%d\n", k, v))
    elseif type(v) == "string" then
      out:write(string.format("%s=%s\n", k, v))
    end
  end
  out:close()
  return true
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
  pending = {},        -- [슬롯] = { status=, amount=, slot=, startedAt= }
  cooldownUntil = {},  -- [슬롯] = 타임아웃 중단 후 재요청 가능 시각
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

-- ME 네트워크 접근 컴포넌트: ME Controller(me_controller) 또는 ME Interface(me_interface)
--   실측: OC jar 의 두 드라이버 모두 NetworkControl 을 구현 →
--         getItemsInNetwork / getFluidsInNetwork / getCraftables / store 등 동일 API 제공
local NET_COMPONENTS = { "me_controller", "me_interface" }

local function findController()
  if CONFIG.controllerAddress then
    local p = proxy(CONFIG.controllerAddress)
    if p then return p, CONFIG.controllerAddress, 1, "지정된 컴포넌트" end
  end
  for _, name in ipairs(NET_COMPONENTS) do
    local addrs = listOf(name)
    if #addrs > 0 then
      return proxy(addrs[1]), addrs[1], #addrs, name
    end
  end
  return nil, nil, 0, nil
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
  local p = state.pending[i]
  if not p then return false end
  local st = p.status
  local computing = st and callBool(st, "isComputing")
  if computing == nil then
    state.pending[i] = nil
    return false
  end
  if computing then return true end
  local elapsed = p.startedAt and nowSeconds() and (nowSeconds() - p.startedAt) or 0
  if callBool(st, "hasFailed") then
    log("슬롯 %d: 이전 요청 실패 (%.0f초)", i, elapsed)
  elseif callBool(st, "isCanceled") then
    log("슬롯 %d: 이전 요청 취소됨 (%.0f초)", i, elapsed)
  elseif callBool(st, "isDone") then
    log("슬롯 %d: 이전 요청 완료 (%.0f초)", i, elapsed)
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


-- =================== 4) AE 제작 중 감지 / 타임아웃 처리 ======================
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

-- AE 스택표(table)가 이 슬롯의 품목과 같은가
local function stackMatches(slot, st)
  if type(st) ~= "table" then return false end
  if slot.isFluid then
    if slot.fluidName and st.name == slot.fluidName then return true end
    if CONFIG.labelFallback and slot.label and st.label == slot.label and st.amount ~= nil then
      return true
    end
    return false
  end
  if slot.name and st.name == slot.name and toInt(st.damage) == slot.damage then return true end
  if CONFIG.labelFallback and slot.label and st.label == slot.label
     and toInt(st.damage) == slot.damage and st.size ~= nil then
    return true
  end
  return false
end

-- 이 품목을 "이미 제작 중"인 CPU 를 찾는다 (없으면 nil)
--   Cpu 콜백: isBusy/isActive, finalOutput, activeItems, storedItems, pendingItems, cancel
--   force=true 이면 skipIfCrafting 설정과 무관하게 검사(타임아웃 취소용)
local function findCraftingCpu(mc, slot, force)
  if not mc then return nil end
  if not (force or CONFIG.skipIfCrafting) then return nil end
  local ok, cpus = pcall(mc.getCpus)
  if not ok or type(cpus) ~= "table" then return nil end
  for _, cpu in ipairs(cpus) do
    if callBool(cpu, "isBusy") then
      local okOut, final = callValue(cpu, "finalOutput")
      if okOut and stackMatches(slot, final) then return cpu end
      if CONFIG.scanActiveItems then
        for _, meth in ipairs({ "activeItems", "storedItems", "pendingItems" }) do
          local okL, list = callValue(cpu, meth)
          if okL and type(list) == "table" then
            for _, st in ipairs(list) do
              if stackMatches(slot, st) then return cpu end
            end
          end
        end
      end
    end
  end
  return nil
end

-- 슬롯 줄의 고정 부분
local function slotHead(s)
  local kind = s.isFluid and "F" or "I"
  local id = s.isFluid and (s.fluidName or "?")
              or string.format("%s:%d", tostring(s.name or "?"), s.damage)
  return string.format(" %d %s %-26s 유지 %-10s 배치 %-8s",
    s.index, kind, shortText(s.label or id, 26), comma(s.quantity), comma(s.batch))
end

-- 진행 중인 "내 요청"의 경과/타임아웃 표시 (매 초 갱신됨)
local function pendingInfo(i)
  local p = state.pending[i]
  if not p then return "" end
  local t = nowSeconds()
  local elapsed = (t and p.startedAt) and math.floor(t - p.startedAt) or 0
  if CONFIG.requestTimeout and CONFIG.requestTimeout > 0 then
    return string.format("  [요청 %s 진행 %d/%d초]",
      comma(p.amount), elapsed, CONFIG.requestTimeout)
  end
  return string.format("  [요청 %s 진행 %d초]", comma(p.amount), elapsed)
end

-- 타임아웃 감시 (매 초). 응답 없는 요청은 중단하고, 가능하면 AE 작업도 취소한다.
local function checkPending(ctx)
  local t = nowSeconds()
  if not t then return end
  for i = 1, SLOT_COUNT do
    local p = state.pending[i]
    if p then
      local timeout = CONFIG.requestTimeout or 0
      local elapsed = p.startedAt and (t - p.startedAt) or 0
      if timeout > 0 and elapsed >= timeout then
        local wasDone = callBool(p.status, "isDone")
        state.pending[i] = nil
        if wasDone then
          log("슬롯 %d: 요청 완료(%.0f초)", i, elapsed)
        else
          local canceled = false
          if CONFIG.cancelOnTimeout and ctx.mc then
            local cpu = findCraftingCpu(ctx.mc, p.slot, true)
            if cpu then
              local ok = callValue(cpu, "cancel")
              canceled = ok and true or false
            end
          end
          if CONFIG.timeoutCooldown and CONFIG.timeoutCooldown > 0 then
            state.cooldownUntil[i] = t + CONFIG.timeoutCooldown
          end
          log("슬롯 %d: %.0f초 동안 완료되지 않아 요청을 중단했습니다%s", i, elapsed,
            canceled and " (AE CPU 작업 취소됨)"
                     or " (해당 CPU를 못 찾아 취소 못 함 — AE 크래프팅 GUI에서 취소 가능)")
        end
      end
    end
  end
end

-- ctx = { lm=, lmAddr=, mc=, mcAddr=, kind=, count=, drive=bool }
local function runCycle(ctx)
  local lm, mc = ctx.lm, ctx.mc
  local recs = {}
  local slots = readAllSlots(lm)

  if ctx.drive then takeOver(lm, slots) end

  local requested, missing, crafting, waiting = 0, 0, 0, 0
  local t = nowSeconds()

  for i = 1, SLOT_COUNT do
    local s = slots[i]
    if not s then
      recs[i] = { text = string.format(" %d  (빈 슬롯)", i) }
    else
      local head = slotHead(s)
      if mc == nil then
        recs[i] = { text = head .. "  ME 조회 불가(me_controller/me_interface 없음)" }
      else
        local stored, how = storedAmount(mc, s)
        if stored == nil then
          recs[i] = { text = head .. "  조회 실패: " .. tostring(how) }
        else
          local deficit = s.quantity - stored
          local cooling = state.cooldownUntil[i] and t and (state.cooldownUntil[i] > t)
          if deficit <= 0 then
            recs[i] = { text = head .. string.format("  보관 %-11s 충족", comma(stored)) }
          elseif (not ctx.drive) or CONFIG.dryRun then
            recs[i] = { text = head .. string.format("  보관 %-11s 부족 %s (요청 안 함)",
              comma(stored), comma(deficit)) }
          elseif jobBusy(i) then
            recs[i] = { text = head .. string.format("  보관 %-11s 이전 요청 진행 중", comma(stored)) }
          elseif cooling then
            waiting = waiting + 1
            recs[i] = { text = head .. string.format("  보관 %-11s 타임아웃 후 대기 %d초",
              comma(stored), math.floor(state.cooldownUntil[i] - t)) }
          elseif CONFIG.skipIfMaintainer and not s.isDone then
            recs[i] = { text = head .. "  유지기 자체 작업 진행 중(중복 요청 안 함)" }
          else
            local cpu = findCraftingCpu(mc, s)
            if cpu then
              crafting = crafting + 1
              recs[i] = { text = head .. "  AE 제작 중(중복 요청 안 함)" }
            else
              local amount = decideAmount(s, deficit)
              local craftable = findCraftable(mc, s)
              if not craftable then
                missing = missing + 1
                recs[i] = { text = head .. string.format("  보관 %-11s 레시피 없음(Not Found)", comma(stored)) }
              else
                local ok, st = callValue(craftable, "request", amount)
                if ok then
                  state.pending[i] = { status = st, amount = amount, slot = s, startedAt = nowSeconds() }
                  state.cooldownUntil[i] = nil
                  requested = requested + 1
                  recs[i] = { text = head .. string.format("  보관 %-11s -> 요청 %s",
                    comma(stored), comma(amount)) }
                else
                  recs[i] = { text = head .. string.format("  보관 %-11s 요청 실패: %s",
                    comma(stored), tostring(st)) }
                end
              end
            end
          end
        end
      end
    end
  end

  return recs, requested, missing, crafting, waiting
end

-- ============================== 5) 화면 출력 ================================
local hasScreen = false
if component then
  local ok, gpu = pcall(component.isAvailable, "gpu")
  local ok2, scr = pcall(component.isAvailable, "screen")
  hasScreen = (ok and gpu and ok2 and scr) and true or false
end

local function headerText(ctx)
  return string.format("== AE Maintainer %s | %s | 주기 %d초 | takeover=%s | %s ==",
    VERSION, ctx.drive and "DRIVE" or "MONITOR", CONFIG.interval,
    tostring(CONFIG.takeover), CONFIG.batchMode)
end

-- 화면에 뿌릴 줄 목록 (매 초 다시 만든다 → 진행 시간/남은 시간이 실시간으로 바뀜)
local function buildView(ctx, recs, requested, missing, crafting, waiting, remain)
  local view = {}
  view[#view + 1] = headerText(ctx)
  for i = 1, SLOT_COUNT do
    local r = recs[i]
    view[#view + 1] = (r and r.text or string.format(" %d  -", i)) .. pendingInfo(i)
  end
  view[#view + 1] = string.format(
    " 이번 주기: 신규요청 %d / AE제작중 %d / 타임아웃대기 %d / 레시피없음 %d",
    requested, crafting, waiting, missing)
  view[#view + 1] = string.format(" 다음 요청까지 %d초    (중단: Ctrl+C)", math.max(0, remain))
  return view
end

local function drawView(view)
  if hasScreen and term then
    pcall(term.clear)
    pcall(term.setCursorPos, 1, 1)
  end
  for _, l in ipairs(view) do print(l) end
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

주요 설정
  interval        요청 주기(초)
  batchMode       need | batch | fill
  skipIfCrafting  AE CPU 가 같은 품목을 제작 중이면 요청 안 함 (기본 true)
  requestTimeout  요청 후 이 초(기본 60) 안에 완료 안 되면 중단 + CPU 취소 (0=끔)
  timeoutCooldown 중단 후 재요청까지 대기(초, 기본 0)
  countdown       화면에 다음 주기 남은 시간 표시 (기본 true)

필요 컴포넌트
  - 어댑터 + ME Level Maintainer : level_maintainer  (설정/수량 읽기)
  - 어댑터 + ME Controller       : me_controller    (보관량 조회 + 크래프트 요청/취소)
    (ME Controller 대신 ME Interface 를 붙여도 됩니다 -> me_interface)
]]

-- 다음 주기까지 대기하면서 1초마다 화면을 갱신하고 타임아웃을 감시한다.
local function waitWithCountdown(ctx, recs, requested, missing, crafting, waiting)
  local remain = CONFIG.interval
  local firstDraw = true
  while true do
    local force = firstDraw or (remain <= 0)
    firstDraw = false
    if (hasScreen and CONFIG.countdown) or force or (remain % 5 == 0) then
      drawView(buildView(ctx, recs, requested, missing, crafting, waiting, remain))
    end
    if remain <= 0 then break end
    local step = math.min(1, remain)
    os.sleep(step)
    remain = remain - step
    checkPending(ctx)          -- 매 초: 타임아웃 낸 요청 중단/취소
  end
end

local function mainLoop(ctx)
  log("시작: %s 모드, 주기 %d초 (중단하려면 Ctrl+C)", ctx.drive and "DRIVE" or "MONITOR", CONFIG.interval)
  while true do
    local recs, requested, missing, crafting, waiting = runCycle(ctx)
    waitWithCountdown(ctx, recs, requested, missing, crafting, waiting)
  end
end

local function main(...)
  local argv = { ... }
  local cmd = argv[1]
  if ensureConfigFile(CONFIG_FILE) then
    log("설정 파일 %s 가 없어 기본값으로 만들었습니다(필요하면 수정하세요).", CONFIG_FILE)
  end
  local hadCfg = loadConfigFile(CONFIG_FILE)
  if hadCfg > 0 then log("설정 파일 %s 에서 %d개 항목을 읽었습니다.", CONFIG_FILE, hadCfg) end

  if cmd == "help" or cmd == "-h" or cmd == "--help" then
    print((HELP:gsub("VERSION", VERSION)))
    return
  end

  if not component then
    print("component 모듈을 불러오지 못했습니다. OpenOS 컴퓨터에서 실행해 주세요.")
    return
  end

  local lm, lmAddr, lmCount = findMaintainer()
  if not lm then
    print("ME Level Maintainer(level_maintainer) 컴포넌트를 찾지 못했습니다.")
    print(" - 어댑터를 ME Level Maintainer 블록에 붙였는지 확인하세요.")
    print(" - 유지기 자체도 ME 네트워크에 연결되어 있어야 합니다.")
    return
  end
  local mc, mcAddr, mcCount, mcKind = findController()

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
    local recs, requested, missing, crafting, waiting = runCycle(ctx)
    drawView(buildView(ctx, recs, requested, missing, crafting, waiting, 0))
    return
  elseif cmd ~= nil then
    log("알 수 없는 명령입니다: %s (help 를 확인하세요)", tostring(cmd))
    return
  end

  if lmCount > 1 then
    log("유지기가 %d대 감지되어 첫 번째(%s)를 사용합니다. maintainerAddress 로 지정할 수 있습니다.",
      lmCount, tostring(lmAddr))
  end
  if mc then
    log("ME 네트워크 컴포넌트: %s (%s)", tostring(mcKind), tostring(mcAddr))
  else
    log("ME 네트워크 컴포넌트가 없습니다: 어댑터를 ME Controller 또는 ME Interface 에 붙이세요. (지금은 읽기만 가능)")
  end
  if mcCount and mcCount > 1 then
    log("같은 종류의 컴포넌트가 %d대 감지되어 첫 번째(%s)를 사용합니다.", mcCount, tostring(mcAddr))
  end

  local ok, err = pcall(mainLoop, ctx)
  restoreAll(lm)
  if not ok then log("중단됨: %s", tostring(err)) end
end

main(...)
