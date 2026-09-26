--------------------------------------------------------------------------------
-- ae_maintainer.lua  v2.0
--
-- 대상: GTNH 2.9.0-beta-3
--   mods: appliedenergistics2-rv3-beta-1050-GTNH
--         ae2fc-1.5.106-gtnh        ← "ME Level Maintainer" 제공 모드
--         OpenComputers-1.12.61-GTNH
--
-- 하는 일
--   어댑터에 연결된 **모든** ME Level Maintainer(level_maintainer 컴포넌트)를 인식해서
--   각 슬롯의 품목/유지수량/배치를 읽고, 정한 주기마다 부족분을 요청한다.
--   (유지기 자체가 작업 중이거나 AE CPU 가 이미 만들고 있으면 요청하지 않는다)
--
-- 필요한 장비
--   · 어댑터 + ME Level Maintainer (여러 대 가능) -> 컴포넌트 "level_maintainer"
--   · 어댑터 + ME Controller 또는 ME Interface     -> "me_controller" / "me_interface"
--   · 어댑터 + 화면(선택)
--
-- 사용법 (OC 컴퓨터에서)
--   ae_maintainer                  설정대로 상시 실행 (기본: 상세 보기, 2대씩 페이지 전환)
--   ae_maintainer monitor          읽기/표시만
--   ae_maintainer drive [주기초]    직접 요청
--   ae_maintainer summary          한 줄 요약 보기 (pageSize 대씩)
--   ae_maintainer detail           상세 보기 (detailPerPage 대씩)
--   ae_maintainer show <번호>       특정 유지기 1대만 고정 상세
--   ae_maintainer list             전체 유지기/슬롯 상세 1회 출력
--   ae_maintainer set <번호> <슬롯> <유지> <배치>
--   ae_maintainer diag             진단 정보(모든 유지기 + 값 타입)
--   ae_maintainer help
--
-- 설정: 같은 폴더의 ae_maintainer.cfg (없으면 첫 실행 때 자동 생성)
--   name.<어댑터주소>=창고A   ← 유지기에 별칭을 붙일 수 있음
--------------------------------------------------------------------------------

local VERSION = "2.5"

-- ============================ 사용자 설정 ====================================
local CONFIG = {
  mode      = "drive",   -- "drive"=직접 요청, "monitor"=읽기만
  interval  = 60,        -- 요청 주기(초)
  takeover  = true,      -- true=유지기 슬롯 자동요청을 끄고 OC가 단독으로 관리
  batchMode = "need",    -- "need"=min(batch,부족분), "batch"=batch 고정, "fill"=부족분을 batch 단위로 올림
  dryRun    = false,     -- true=요청하지 않고 계산 결과만 출력
  labelFallback = true,  -- 아이템 이름(name) 매칭 실패 시 표시이름(label)로 재시도
  autoRestore   = true,  -- 종료(Ctrl+C) 시 유지기 슬롯 enable 상태를 원래대로 복구

  -- 중복 요청 방지
  skipIfCrafting   = true,  -- AE CPU 작업에 같은 품목이 들어 있으면 요청하지 않음
  cpuSkipScope     = "any", -- "any"=CPU 의 최종산출물/보관/대기/제작중 어디에든 있으면 스킵(사람 요청 포함)
                            -- "final"=그 CPU 의 최종 결과물일 때만 스킵
  skipIfMaintainer = true,  -- 유지기 자체가 그 슬롯 작업 중(isDone=false)이면 요청하지 않음

  -- 응답 없는 요청 자동 중단
  requestTimeout  = 60,   -- 요청 후 이 초 안에 결과물이 안 나오면 중단(+CPU 취소 시도). 0=비활성
  stallCycles     = 2,    -- 요청 후 N번의 주기 동안 생산량이 늘지 않으면 정지로 보고 취소 (0=끔)
  stallMinProgress = 1,   -- 진행으로 인정할 최소 증가량(개수/mB)
  cancelOnTimeout = true, -- 타임아웃/정지 시 해당 AE CPU 작업 취소 시도
  cancelFallback  = "single", -- 취소 대상을 못 찾았을 때: "single"=사용 중 CPU가 1대뿐이면 취소 / "none"=취소 안 함
  timeoutCooldown = 0,    -- 중단 후 이 초 동안 그 슬롯 재요청 금지 (0=즉시 재시도 가능)
  skipIfAnyCpuBusy = false, -- true=사용 중 CPU 가 있으면 모든 요청 보류(중복 방지 극대화)

  -- 화면
  countdown = true,       -- 다음 주기까지 남은 시간을 1초마다 갱신
  view      = "detail",   -- "detail"=유지기별 상세(슬롯 5줄) 페이지 | "summary"=한 줄 요약
  detailPerPage = 2,      -- 상세 화면 한 페이지에 보여줄 유지기 수 (2 → 2대씩 5슬롯)
  pageSize  = 10,         -- 요약 화면 한 페이지에 보여줄 유지기 수
  pageSeconds = 10,       -- 자동 페이지 전환 간격(초). 0=전환 안 함

  -- 여러 유지기
  maxMaintainers = 0,     -- 0=전부, N=앞에서 N대만 사용
  bulkQuery = true,       -- 보관량을 사이클당 1회 전체 조회(유지기가 많을 때 훨씬 빠름)
  names = {},             -- name.<주소>=이름  (cfg 에서 채워짐)
  maintainerAddress = nil, -- 특정 유지기 1대만 쓰고 싶을 때 어댑터 주소
  controllerAddress = nil, -- ME 컴포넌트가 여러 개일 때 어댑터 주소
}

local CONFIG_FILE = "ae_maintainer.cfg"

-- ======================= OC API 로딩 (전역이 아님!) ==========================
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
local unpack = table.unpack or unpack

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

-- 경과 시간 측정용 (초)
local function nowSeconds()
  if computer then
    local ok, u = pcall(computer.uptime)
    if ok and type(u) == "number" then return u end
  end
  local ok2, t = pcall(os.time)
  if ok2 and type(t) == "number" then return t end
  return nil
end

-- OC 값(userdata) 메서드 호출 -------------------------------------------------
--   OC 커널(machine.lua)은 값을 "프록시 테이블"로 감싸고 각 메서드를
--   호출 가능한 '테이블'(__call)로 노출한다. → type(value.method) 는 "function" 이 아니다.
local function callValue(obj, method, ...)
  if obj == nil then return false, method .. " 대상 없음" end
  local fn = obj[method]
  if fn == nil then return false, method .. " 메서드 없음(nil)" end
  local args = { ... }
  local ok, v = pcall(fn, unpack(args))              -- OC 표준: value.method(args...)
  if ok then return true, v end
  local firstErr = v
  local ok2, v2 = pcall(fn, obj, unpack(args))       -- self 를 명시하는 규약도 시도
  if ok2 then return true, v2 end
  return false, string.format("%s 호출 실패(%s): %s", method, type(fn), tostring(firstErr))
end

local function callBool(obj, method)
  local ok, v = callValue(obj, method)
  if not ok then return nil end
  return v and true or false
end

local function shortText(s, n)
  s = tostring(s or "?")
  if #s <= n then return s end
  return s:sub(1, n - 3) .. "..."
end

local function shortAddr(a)
  a = tostring(a or "?"):gsub("%-", "")
  return a:sub(1, 8)
end

-- 설정 파일 (단순 key=value + name.<주소>=이름) -------------------------------
local function loadConfigFile(path)
  local f = io.open(path, "r")
  if not f then return 0 end
  local n = 0
  for line in f:lines() do
    line = line:gsub("#.*$", ""):gsub("%s+$", "")
    local addr, nm = line:match("^%s*name%.([%w%-]+)%s*=%s*(.-)%s*$")
    if addr then
      CONFIG.names[addr] = nm
      n = n + 1
    else
      local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
      if k and CONFIG[k] ~= nil and type(CONFIG[k]) ~= "table" then
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
  end
  f:close()
  return n
end

local CFG_KEYS = {
  "mode", "interval", "takeover", "batchMode", "dryRun", "labelFallback", "autoRestore",
  "skipIfCrafting", "cpuSkipScope", "skipIfMaintainer",
  "requestTimeout", "cancelOnTimeout", "cancelFallback", "timeoutCooldown",
  "stallCycles", "stallMinProgress", "skipIfAnyCpuBusy",
  "countdown", "view", "detailPerPage", "pageSize", "pageSeconds",
  "maxMaintainers", "bulkQuery",
}

local function ensureConfigFile(path)
  local f = io.open(path, "r")
  if f then f:close(); return false end
  local out = io.open(path, "w")
  if not out then return false end
  out:write("# ae_maintainer 기본 설정 (자동 생성)\n")
  out:write("# 값을 바꾼 뒤 프로그램을 다시 실행하세요. 주석(#)과 빈 줄은 무시됩니다.\n")
  out:write("# 설명: https://github.com/ysw2003/ae-maintainer  (ae_maintainer.cfg)\n")
  out:write("# 유지기에 이름을 붙이려면:  name.<어댑터주소>=창고A\n\n")
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

-- ==================== 1) 유지기 / ME 네트워크 컴포넌트 =======================
local SLOT_COUNT = 5          -- ae2fc TileLevelMaintainer.REQ_COUNT = 5

local function findMaintainers()
  local out = {}
  if CONFIG.maintainerAddress then
    local p = proxy(CONFIG.maintainerAddress)
    if p then
      out[1] = { addr = CONFIG.maintainerAddress, proxy = p,
                 name = CONFIG.names[CONFIG.maintainerAddress] }
    end
    return out
  end
  for _, a in ipairs(listOf("level_maintainer")) do
    local p = proxy(a)
    if p then
      out[#out + 1] = { addr = a, proxy = p, name = CONFIG.names[a] }
      if CONFIG.maxMaintainers > 0 and #out >= CONFIG.maxMaintainers then break end
    end
  end
  return out
end

-- ME 네트워크 접근 컴포넌트: me_controller 또는 me_interface (둘 다 NetworkControl 구현)
local NET_COMPONENTS = { "me_controller", "me_interface" }

local function findNetwork()
  if CONFIG.controllerAddress then
    local p = proxy(CONFIG.controllerAddress)
    if p then return p, CONFIG.controllerAddress, 1, "지정된 컴포넌트" end
  end
  for _, name in ipairs(NET_COMPONENTS) do
    local addrs = listOf(name)
    if #addrs > 0 then return proxy(addrs[1]), addrs[1], #addrs, name end
  end
  return nil, nil, 0, nil
end

-- 슬롯 1개 읽기 (비어 있으면 nil)
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
    quantity  = toInt(s.quantity),
    batch     = toInt(s.batch),
    isEnable  = s.isEnable and true or false,
    isDone    = s.isDone and true or false,
    fluidName = nil,
  }
  if slot.isFluid and type(s.fluid) == "table" then
    slot.fluidName = s.fluid.name
    slot.label = s.fluid.label or slot.label
  end
  return slot
end

local function readAllSlots(lm)
  local slots = {}
  for i = 1, SLOT_COUNT do
    local s = readSlot(lm, i)
    if s then slots[i] = s end
  end
  return slots
end

-- ==================== 2) 보관량 조회 (일괄 / 개별) ==========================
-- 유지기가 많을 때를 위해 사이클당 1회 전체 목록을 받아 로컬에서 합산한다.
local function buildStock(mc)
  local items, fluids = {}, {}
  local gotItems = false
  local ok1, listI = pcall(mc.getItemsInNetwork)
  if ok1 and type(listI) == "table" then
    gotItems = true
    for _, it in ipairs(listI) do
      local k = tostring(it.name) .. ":" .. toInt(it.damage)
      items[k] = (items[k] or 0) + toInt(it.size)
      if it.label then
        local kl = "L:" .. tostring(it.label) .. ":" .. toInt(it.damage)
        items[kl] = (items[kl] or 0) + toInt(it.size)
      end
    end
  end
  local ok2, listF = pcall(mc.getFluidsInNetwork)
  if ok2 and type(listF) == "table" then
    for _, f in ipairs(listF) do
      local k = tostring(f.name)
      fluids[k] = (fluids[k] or 0) + toInt(f.amount)
    end
  end
  return items, fluids, gotItems
end

-- 슬롯의 현재 보관량. items/fluids 가 주어지면(일괄 모드) 그걸 사용.
local function storedAmount(mc, slot, items, fluids)
  if items and fluids then
    if slot.isFluid then
      if not slot.fluidName then return nil, "유체 이름 확인 불가" end
      return fluids[slot.fluidName] or 0, "bulk"
    end
    local v = items[tostring(slot.name) .. ":" .. slot.damage]
    if v then return v, "bulk" end
    if CONFIG.labelFallback and slot.label then
      local lv = items["L:" .. tostring(slot.label) .. ":" .. slot.damage]
      if lv then return lv, "bulk-label" end
    end
    return 0, "bulk"
  end

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

-- ==================== 3) 제작 중 감지 / 레시피 찾기 ==========================
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

-- 사이클당 1회: 모든 CPU 의 상태/내용을 미리 읽어 스냅샷으로 만든다.
--   ★ getCpus() 는 "표(row) 목록"을 돌려준다 (설치된 jar 실측 키):
--       { name=, storage=, coprocessors=, busy=, cpu=<실제 CPU 값> }
--     실제 값은 entry.cpu 이며, busy 는 테이블의 boolean 필드다.
--   ★ busy(=활발히 제작 중) 여부와 무관하게 목록을 읽는다.
--     (AE2 는 출력 막힘/재료 대기 상태에서 isBusy=false, isActive=true 일 수 있음)
local function buildCpuSnapshot(cpus)
  local snap = {}
  if type(cpus) ~= "table" then return snap end
  for i, raw in ipairs(cpus) do
    local e = { idx = i, value = raw, name = nil, busy = nil, active = false, final = nil, lists = {} }
    if type(raw) == "table" then
      if raw.cpu ~= nil then
        e.value = raw.cpu                     -- 표준 구조: 값은 .cpu 필드
        e.name = raw.name
        e.storage = raw.storage
        e.coprocessors = raw.coprocessors
        if raw.busy ~= nil then e.busy = (raw.busy == true) end
      elseif raw.name ~= nil or raw.busy ~= nil then
        -- 값 자체도 테이블인 변형 구조(구버전/모드 호환): 그대로 사용
        e.name = raw.name
      end
    end
    if e.busy == nil then e.busy = (callBool(e.value, "isBusy") == true) end
    e.active = (callBool(e.value, "isActive") == true)
    local okf, final = callValue(e.value, "finalOutput")
    if okf and type(final) == "table" then e.final = final end
    for _, meth in ipairs({ "activeItems", "storedItems", "pendingItems" }) do
      local ok, list = callValue(e.value, meth)
      if ok and type(list) == "table" then e.lists[meth] = list end
    end
    snap[#snap + 1] = e
  end
  return snap
end

local function cpuLabel(e)
  return string.format("CPU%d%s", e.idx, e.name and (" " .. tostring(e.name)) or "")
end

-- 스냅샷에서 이 품목을 가진 CPU 찾기. 반환: 값(취소용), 이유
local function findCraftingCpuSnap(snap, slot, force)
  if not (force or CONFIG.skipIfCrafting) then return nil end
  if type(snap) ~= "table" then return nil end
  for _, e in ipairs(snap) do
    if e.final and stackMatches(slot, e.final) then
      return e.value, string.format("finalOutput(%s)", cpuLabel(e))
    end
    if CONFIG.cpuSkipScope ~= "final" then
      for _, meth in ipairs({ "activeItems", "storedItems", "pendingItems" }) do
        local list = e.lists[meth]
        if list then
          for _, st in ipairs(list) do
            if stackMatches(slot, st) then
              return e.value, string.format("%s(%s)", meth, cpuLabel(e))
            end
          end
        end
      end
    end
  end
  return nil
end

-- 스냅샷 기준: 사용 중(제작 중이거나 활성) CPU 가 하나라도 있는가
local function anyCpuBusySnap(snap)
  for _, e in ipairs(snap) do
    if e.busy or e.active then return true end
  end
  return false
end

-- 레시피(Craftable 값) 찾기
local function findCraftable(mc, slot)
  local filter
  if slot.isFluid then
    if not slot.fluidName then return nil end
    filter = { name = slot.fluidName }
  else
    filter = { name = slot.name, damage = slot.damage }
  end
  local ok, list = pcall(mc.getCraftables, filter)
  if ok and type(list) == "table" and list[1] then return list[1] end

  if CONFIG.labelFallback and not slot.isFluid and slot.label then
    local ok2, all = pcall(mc.getCraftables)
    if ok2 and type(all) == "table" then
      for _, c in ipairs(all) do
        local ok3, st = callValue(c, "getStack")
        if ok3 and type(st) == "table" and st.label == slot.label
           and toInt(st.damage) == slot.damage then
          return c
        end
      end
    end
  end
  return nil
end

-- ==================== 4) 상태(요청 추적 / 타임아웃 / takeover) ==============
local state = {
  pending = {},        -- [addr#slot] = { status=, amount=, slot=, maint=, startedAt= }
  cooldownUntil = {},  -- [addr#slot] = 재요청 가능 시각
  originalEnable = {}, -- [addr] = { [slot] = enable }
  tookOver = {},       -- [addr] = true
}

local function keyOf(m, i) return m.addr .. "#" .. i end

local function jobBusy(key)
  local p = state.pending[key]
  if not p then return false end
  local st = p.status
  local computing = st and callBool(st, "isComputing")
  if computing == nil then
    -- 상태 객체를 못 읽어도, 기록해 둔 CPU 가 아직 작업 중이면 진행 중으로 본다
    if p.cpu and callBool(p.cpu, "isBusy") then return true end
    state.pending[key] = nil
    return false
  end
  if computing then return true end
  local t = nowSeconds()
  local elapsed = (p.startedAt and t) and (t - p.startedAt) or 0
  if callBool(st, "hasFailed") then
    log("%s 슬롯%d: 이전 요청 실패 (%.0f초)", shortAddr(p.maint), p.slot.index, elapsed)
  elseif callBool(st, "isCanceled") then
    log("%s 슬롯%d: 이전 요청 취소됨 (%.0f초)", shortAddr(p.maint), p.slot.index, elapsed)
  elseif callBool(st, "isDone") then
    log("%s 슬롯%d: 이전 요청 완료 (%.0f초)", shortAddr(p.maint), p.slot.index, elapsed)
  end
  state.pending[key] = nil
  return false
end

local function pendingInfo(key, compact)
  local p = state.pending[key]
  if not p then return "" end
  if compact then return "*" end
  local t = nowSeconds()
  local elapsed = (t and p.startedAt) and math.floor(t - p.startedAt) or 0
  local parts = { "요청 " .. comma(p.amount) }
  if p.produced and p.produced > 0 then
    parts[#parts + 1] = string.format("생산 %s", comma(p.produced))
  end
  if (CONFIG.stallCycles or 0) > 0 then
    parts[#parts + 1] = string.format("정지 %d/%d주기", p.stallCount or 0, CONFIG.stallCycles)
  end
  if CONFIG.requestTimeout and CONFIG.requestTimeout > 0 then
    parts[#parts + 1] = string.format("%d/%d초", elapsed, CONFIG.requestTimeout)
  else
    parts[#parts + 1] = string.format("%d초", elapsed)
  end
  return "  [" .. table.concat(parts, " · ") .. "]"
end

-- 요청의 CPU 작업을 찾아 취소. 반환: cpu, why, canceled, res
--   ① 요청 시 기록해 둔 CPU ② 그 품목이 포함된 CPU 재탐색 ③ (옵션) 사용 중 CPU 1대
local function cancelCraft(ctx, p)
  if not (CONFIG.cancelOnTimeout and ctx.mc) then return nil, nil, false, nil end
  local cpu, why = nil, nil
  if p.cpu then cpu, why = p.cpu, "요청 시 기록된 CPU" end
  local okc, cpus = pcall(ctx.mc.getCpus)
  local snap = okc and buildCpuSnapshot(cpus) or {}
  if not cpu and #snap > 0 then cpu, why = findCraftingCpuSnap(snap, p.slot, true) end
  if not cpu and CONFIG.cancelFallback == "single" then
    local busy = {}
    for _, e in ipairs(snap) do
      if e.busy or e.active then busy[#busy + 1] = e.value end
    end
    if #busy == 1 then cpu, why = busy[1], "사용 중 CPU 1대(대상 특정 불가)" end
  end
  if not cpu then return nil, nil, false, nil end
  local ok2, r = callValue(cpu, "cancel")
  return cpu, why, (ok2 and (r ~= false)), r
end

-- 타임아웃 감시 (매 초). 응답 없는 요청은 중단하고 가능하면 CPU 작업도 취소.
local function checkPending(ctx)
  local t = nowSeconds()
  if not t then return end
  for key, p in pairs(state.pending) do
    local timeout = CONFIG.requestTimeout or 0
    local elapsed = p.startedAt and (t - p.startedAt) or 0
    if timeout > 0 and elapsed >= timeout then
      local wasDone = callBool(p.status, "isDone")
      -- "결과물이 나왔는가" 확인: 재고가 목표(유지수량)에 도달했으면 완료로 본다
      local satisfied = false
      if not wasDone and ctx.mc and p.slot then
        local stored = storedAmount(ctx.mc, p.slot, nil, nil)
        if stored and p.slot.quantity and stored >= p.slot.quantity then satisfied = true end
      end
      state.pending[key] = nil
      if wasDone or satisfied then
        log("%s 슬롯%d: 요청 완료(%.0f초%s)", shortAddr(p.maint), p.slot.index, elapsed,
          satisfied and ", 결과물 확인" or "")
      else
        local cpu, why, canceled, res = cancelCraft(ctx, p)
        if CONFIG.timeoutCooldown and CONFIG.timeoutCooldown > 0 then
          state.cooldownUntil[key] = t + CONFIG.timeoutCooldown
        end
        log("%s 슬롯%d: %.0f초 동안 결과물이 나오지 않아 요청을 중단했습니다%s",
          shortAddr(p.maint), p.slot.index, elapsed,
          cpu and (canceled and (" (CPU 취소됨: " .. tostring(why) .. ")")
                            or (" (CPU 취소 실패: " .. tostring(why) ..
                                ", cancel()=" .. tostring(res) .. ")"))
              or " (취소할 CPU를 찾지 못함)")
      end
    end
  end
end

-- takeover: 유지기 자체의 자동요청을 끄고 OC 가 단독으로 요청하게 한다.
local function takeOver(m)
  if not CONFIG.takeover or state.tookOver[m.addr] then return 0 end
  local n = 0
  state.originalEnable[m.addr] = {}
  for i = 1, SLOT_COUNT do
    local s = readSlot(m.proxy, i)
    if s then
      state.originalEnable[m.addr][i] = s.isEnable
      if s.isEnable then
        local ok = pcall(m.proxy.setEnable, i, false)
        if ok then n = n + 1 end
      end
    end
  end
  state.tookOver[m.addr] = true
  return n
end

local function restoreAll(ctx)
  if not ctx or not ctx.maints then return end
  if not (CONFIG.takeover and CONFIG.autoRestore) then return end
  local n = 0
  for _, m in ipairs(ctx.maints) do
    if state.tookOver[m.addr] and state.originalEnable[m.addr] then
      for i = 1, SLOT_COUNT do
        if state.originalEnable[m.addr][i] then
          local ok = pcall(m.proxy.setEnable, i, true)
          if ok then n = n + 1 end
        end
      end
      state.tookOver[m.addr] = nil
    end
  end
  if n > 0 then log("유지기 슬롯 %d개를 다시 켰습니다(원상복구).", n) end
end

-- ==================== 5) 한 주기 처리 (모든 유지기) ==========================
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

local function slotHead(s)
  local kind = s.isFluid and "F" or "I"
  local id = s.isFluid and (s.fluidName or "?")
              or string.format("%s:%d", tostring(s.name or "?"), s.damage)
  return string.format("  %d %s %-24s 유지 %-10s 배치 %-8s",
    s.index, kind, shortText(s.label or id, 24), comma(s.quantity), comma(s.batch))
end

-- 유지기 1대의 슬롯들을 처리해 통계(st)와 상세 줄(st.lines)을 채운다
local function processMaintainer(ctx, m, items, fluids, cpuSnap, st)
  local t = nowSeconds()
  for i = 1, SLOT_COUNT do
    local s = readSlot(m.proxy, i)
    local key = keyOf(m, i)
    if not s then
      st.lines[i] = string.format("  %d (빈 슬롯)", i)
    else
      st.used = st.used + 1
      local head = slotHead(s)
      if not ctx.mc then
        st.lines[i] = head .. "  ME 조회 불가(me_controller/me_interface 없음)"
      else
        local stored, how = storedAmount(ctx.mc, s, items, fluids)
        if stored == nil then
          st.lines[i] = head .. "  조회 실패: " .. tostring(how)
        else
          local deficit = s.quantity - stored
          local cooling = state.cooldownUntil[key] and t and (state.cooldownUntil[key] > t)

          -- 진행/정지 판정: 직전 주기 대비 생산량이 늘었는지 확인
          local p = state.pending[key]
          local stalled = false
          if p and deficit > 0 then
            if p.stockAtRequest == nil then p.stockAtRequest = stored end
            p.produced = stored - p.stockAtRequest
            if p.lastStock ~= nil then
              if (stored - p.lastStock) >= (CONFIG.stallMinProgress or 1) then
                p.stallCount = 0                                  -- 진행 중
              else
                p.stallCount = (p.stallCount or 0) + 1            -- 제자리
              end
            end
            p.lastStock = stored
            if (CONFIG.stallCycles or 0) > 0 and (p.stallCount or 0) >= CONFIG.stallCycles then
              stalled = true
            end
          end

          if deficit <= 0 then
            if state.pending[key] then
              state.pending[key] = nil
              state.cooldownUntil[key] = nil
              log("%s 슬롯%d: 재고가 목표치에 도달해 요청을 완료 처리(보관 %s)",
                shortAddr(m.addr), s.index, comma(stored))
            end
            st.lines[i] = head .. string.format("  보관 %-11s 충족", comma(stored))
          elseif stalled then
            st.short = st.short + 1
            local cpu, why, canceled = cancelCraft(ctx, p)
            state.pending[key] = nil
            if CONFIG.timeoutCooldown and CONFIG.timeoutCooldown > 0 then
              state.cooldownUntil[key] = t + CONFIG.timeoutCooldown
            end
            log("%s 슬롯%d: %d주기 동안 진행이 없어(보관 %s · 생산 %s/%s) 요청을 중단했습니다%s",
              shortAddr(m.addr), s.index, CONFIG.stallCycles, comma(stored),
              comma(p.produced or 0), comma(p.amount),
              cpu and (canceled and (" (CPU 취소됨: " .. tostring(why) .. ")")
                                or (" (CPU 취소 실패: " .. tostring(why) .. ")"))
                  or " (취소할 CPU를 찾지 못함)")
            st.lines[i] = head .. string.format("  보관 %-11s 정지 감지 → 요청 중단", comma(stored))
          elseif jobBusy(key) then
            st.short = st.short + 1
            st.pendingN = st.pendingN + 1
            st.lines[i] = head .. string.format("  보관 %-11s 이전 요청 진행 중", comma(stored))
              .. pendingInfo(key)
          elseif cooling then
            st.short = st.short + 1
            st.waiting = st.waiting + 1
            st.lines[i] = head .. string.format("  보관 %-11s 타임아웃 후 대기 %d초",
              comma(stored), math.floor(state.cooldownUntil[key] - t))
          elseif CONFIG.skipIfMaintainer and not s.isDone then
            st.short = st.short + 1
            st.crafting = st.crafting + 1
            st.lines[i] = head .. "  유지기 자체 작업 진행 중(중복 요청 안 함)"
          else
            local cpu, why = findCraftingCpuSnap(cpuSnap, s)
            if cpu then
              st.short = st.short + 1
              st.crafting = st.crafting + 1
              st.lines[i] = head .. "  AE 제작 중(중복 요청 안 함) " .. tostring(why or "")
            elseif CONFIG.skipIfAnyCpuBusy and anyCpuBusySnap(cpuSnap) then
              st.short = st.short + 1
              st.crafting = st.crafting + 1
              st.lines[i] = head .. "  다른 CPU 작업 중(보류)"
            elseif (not ctx.drive) or CONFIG.dryRun then
              st.short = st.short + 1
              st.lines[i] = head .. string.format("  보관 %-11s 부족 %s (요청 안 함)",
                comma(stored), comma(deficit))
            else
              st.short = st.short + 1
              local amount = decideAmount(s, deficit)
              local craftable = findCraftable(ctx.mc, s)
              if not craftable then
                st.missing = st.missing + 1
                st.lines[i] = head .. string.format("  보관 %-11s 레시피 없음(Not Found)", comma(stored))
              else
                local ok, stt = callValue(craftable, "request", amount)
                if ok then
                  -- 요청 직후 그 작업을 담당하는 CPU 참조를 확보해 둔다(타임아웃 취소용)
                  local cpuRef = nil
                  local okc, fresh = pcall(ctx.mc.getCpus)
                  if okc then cpuRef = findCraftingCpuSnap(buildCpuSnapshot(fresh), s, true) end
                  state.pending[key] = { status = stt, amount = amount, slot = s,
                                         maint = m.addr, startedAt = nowSeconds(), cpu = cpuRef,
                                         stockAtRequest = stored, lastStock = stored }
                  state.cooldownUntil[key] = nil
                  st.requested = st.requested + 1
                  st.pendingN = st.pendingN + 1
                  st.lines[i] = head .. string.format("  보관 %-11s -> 요청 %s",
                    comma(stored), comma(amount))
                else
                  st.missing = st.missing + 1
                  st.lines[i] = head .. string.format("  보관 %-11s 요청 실패: %s",
                    comma(stored), tostring(stt))
                end
              end
            end
          end
        end
      end
    end
  end
end

-- ctx = { maint=, drive=, mc=, mcAddr=, mcKind=, mcCount= }
local function runCycle(ctx)
  local recs, total = {}, { short = 0, requested = 0, crafting = 0, waiting = 0, missing = 0, pending = 0 }
  ctx.maints = findMaintainers()          -- 매 주기 갱신(추가/제거 반영)

  if ctx.drive and CONFIG.takeover then
    local n = 0
    for _, m in ipairs(ctx.maints) do n = n + takeOver(m) end
    if n > 0 and not ctx.takeOverLogged then
      log("유지기 자동요청 %d개 슬롯 OFF (OC 단독 관리). 종료 시 복구합니다.", n)
      ctx.takeOverLogged = true
    end
  end

  local items, fluids, cpuSnap = nil, nil, {}
  if ctx.mc then
    if CONFIG.bulkQuery then
      local okb, it, fl, gotItems = pcall(buildStock, ctx.mc)
      if okb and gotItems then items, fluids = it, fl end
      -- 실패하면 items=nil → 슬롯별 개별 조회로 자동 폴백
    end
    local okc, c = pcall(ctx.mc.getCpus)
    if okc then cpuSnap = buildCpuSnapshot(c) end
  end

  for idx, m in ipairs(ctx.maints) do
    local st = { idx = idx, maint = m, lines = {}, used = 0, short = 0, requested = 0,
                 crafting = 0, waiting = 0, missing = 0, pendingN = 0 }
    processMaintainer(ctx, m, items, fluids, cpuSnap, st)
    for _, k in ipairs({ "short", "requested", "crafting", "waiting", "missing" }) do
      total[k] = (total[k] or 0) + (st[k] or 0)
    end
    total.pending = (total.pending or 0) + st.pendingN
    recs[m.addr] = st
  end

  ctx.recs = recs
  return recs, total
end

-- ============================== 6) 화면 출력 ================================
local hasScreen = false
if component then
  local ok, gpu = pcall(component.isAvailable, "gpu")
  local ok2, scr = pcall(component.isAvailable, "screen")
  hasScreen = (ok and gpu and ok2 and scr) and true or false
end

local function drawLines(lines)
  if hasScreen and term then
    pcall(term.clear)
    pcall(term.setCursorPos, 1, 1)
  end
  for _, l in ipairs(lines) do print(l) end
end

-- 요약 화면(페이지)
local function buildSummary(ctx, recs, total, remain, page)
  local n = #ctx.maints
  local pages = math.max(1, math.ceil(n / math.max(1, CONFIG.pageSize)))
  page = ((page - 1) % pages) + 1
  local out = {}
  out[#out + 1] = string.format("== AE Maintainer %s | %s | %d대 | %d/%d 페이지 | 다음 주기 %d초 ==",
    VERSION, ctx.drive and "DRIVE" or "MONITOR", n, page, pages, math.max(0, remain))
  local from = (page - 1) * CONFIG.pageSize + 1
  local to = math.min(n, from + CONFIG.pageSize - 1)
  for i = from, to do
    local m = ctx.maints[i]
    local st = recs[m.addr] or {}
    out[#out + 1] = string.format(" #%-3d %s %-14s 슬롯 %d/%d  부족 %-3d 요청 %-3d 제작 %-3d%s",
      i, shortAddr(m.addr), shortText(m.name or "-", 14), st.used or 0, SLOT_COUNT,
      st.short or 0, st.requested or 0, st.crafting or 0,
      (st.pendingN or 0) > 0 and string.format(" 진행 %d", st.pendingN) or "")
  end
  if to < n then out[#out + 1] = string.format(" ... (다음 페이지에 %d대 더)", n - to) end
  out[#out + 1] = string.format(" 합계 부족 %d · 신규요청 %d · 제작중 %d · 대기 %d · 레시피없음 %d · 진행 %d",
    total.short or 0, total.requested or 0, total.crafting or 0,
    total.waiting or 0, total.missing or 0, total.pending or 0)
  out[#out + 1] = " show <번호> 상세 · list 전체 · Ctrl+C 종료"
  return out
end

-- 특정 유지기 상세 화면
local function buildDetail(ctx, st, remain)
  if not st then return { " (유지기 정보 없음)" } end
  local out = {}
  out[#out + 1] = string.format("== %s #%d %s (%s) | 다음 주기 %d초 ==", VERSION, st.idx,
    shortAddr(st.maint.addr), st.maint.name or "이름없음", math.max(0, remain))
  for i = 1, SLOT_COUNT do out[#out + 1] = st.lines[i] or string.format("  %d -", i) end
  out[#out + 1] = string.format(" 부족 %d · 신규요청 %d · 제작중 %d · 대기 %d · 레시피없음 %d · 진행 %d",
    st.short, st.requested, st.crafting, st.waiting, st.missing, st.pendingN)
  return out
end

-- 상세 페이지: 여러 대를 한 화면에 (기본 2대 × 슬롯 5줄)
local function buildDetailPage(ctx, recs, page, remain)
  local n = #ctx.maints
  local per = math.max(1, CONFIG.detailPerPage or 2)
  local pages = math.max(1, math.ceil(n / per))
  page = ((page - 1) % pages) + 1
  local from = (page - 1) * per + 1
  local to = math.min(n, from + per - 1)
  local out = {}
  out[#out + 1] = string.format(
    "== AE Maintainer %s | %s | 상세 %d~%d / %d대 | %d/%d 페이지 | 다음 주기 %d초 ==",
    VERSION, ctx.drive and "DRIVE" or "MONITOR", from, to, n, page, pages, math.max(0, remain))
  for i = from, to do
    local m = ctx.maints[i]
    local st = recs[m.addr]
    out[#out + 1] = string.format(" #%d %s %s   부족 %d · 요청 %d · 제작 %d · 진행 %d",
      i, shortAddr(m.addr), shortText(m.name or "-", 16),
      st and st.short or 0, st and st.requested or 0, st and st.crafting or 0, st and st.pendingN or 0)
    for k = 1, SLOT_COUNT do
      out[#out + 1] = (st and st.lines[k]) or string.format("  %d -", k)
    end
  end
  if to < n then
    out[#out + 1] = string.format(" (%d초마다 다음 %d대로 넘어갑니다 · %d대 남음)",
      CONFIG.pageSeconds or 10, per, n - to)
  else
    out[#out + 1] = string.format(" (마지막 페이지 · %d초마다 처음으로)", CONFIG.pageSeconds or 10)
  end
  return out
end

-- ============================== 7) 실행부 ===================================
local HELP = [[
ae_maintainer VERSION  (GTNH 2.9.0-beta-3 / AE2FC ME Level Maintainer 다중 지원)

  ae_maintainer                  설정대로 상시 실행 (기본: 상세 보기, 2대씩 페이지 전환)
  ae_maintainer monitor          읽기/표시만 (요청 안 함)
  ae_maintainer drive [주기초]    지정 주기(기본 60초)로 직접 요청
  ae_maintainer summary          한 줄 요약 보기로 전환 (pageSize 대씩)
  ae_maintainer detail           상세 보기로 전환 (detailPerPage 대씩)
  ae_maintainer show <번호>       특정 유지기 1대만 고정 상세
  ae_maintainer list             전체 유지기/슬롯 상세 1회 출력
  ae_maintainer once             1회 계산/표시 (설정 변경 없음)
  ae_maintainer set <번호> <슬롯> <유지> <배치>
  ae_maintainer diag             진단 정보 출력 (문제 보고용)
  ae_maintainer help

설정 파일: ./ae_maintainer.cfg
  interval / batchMode / takeover / requestTimeout / bulkQuery ...
  view=detail|summary        화면 종류 (기본 detail: 유지기별 슬롯 5줄)
  detailPerPage=2            상세 화면에 한 번에 보여줄 유지기 수
  pageSize / pageSeconds     요약 화면 페이지 크기 / 자동 페이지 전환 간격(초)
  name.<어댑터주소>=창고A    ← 유지기 별칭

필요 컴포넌트
  - 어댑터 + ME Level Maintainer (여러 대) : level_maintainer
  - 어댑터 + ME Controller 또는 ME Interface : me_controller / me_interface
]]

local function mainLoop(ctx, viewIdx)
  local perPage = (ctx.view == "summary") and math.max(1, CONFIG.pageSize or 10)
                                          or math.max(1, CONFIG.detailPerPage or 2)
  log("%s 시작: 주기 %d초 · 유지기 %d대 · 보기=%s(%d대/페이지, %s초마다 전환) (중단: Ctrl+C)",
    ctx.drive and "DRIVE" or "MONITOR", toInt(CONFIG.interval), #ctx.maints,
    tostring(ctx.view), perPage,
    (CONFIG.pageSeconds and CONFIG.pageSeconds > 0) and tostring(CONFIG.pageSeconds) or "자동전환없음")
  if not ctx.mc then
    log("경고: me_controller/me_interface 가 없어 보관량 조회/요청을 할 수 없습니다.")
  end
  local page = 1
  local lastFlip = nowSeconds() or 0
  while true do
    local recs, total = runCycle(ctx)
    local remain = toInt(CONFIG.interval)
    local firstDraw = true
    while true do
      if not viewIdx and CONFIG.pageSeconds and CONFIG.pageSeconds > 0
         and #ctx.maints > perPage then
        local t = nowSeconds()
        if t and (t - lastFlip) >= CONFIG.pageSeconds then
          page = page + 1
          lastFlip = t
        end
      end
      local lines
      if viewIdx then
        local m = ctx.maints[viewIdx]
        if m then
          lines = buildDetail(ctx, recs[m.addr], remain)
        elseif ctx.view == "summary" then
          lines = buildSummary(ctx, recs, total, remain, page)
        else
          lines = buildDetailPage(ctx, recs, page, remain)
        end
      elseif ctx.view == "summary" then
        lines = buildSummary(ctx, recs, total, remain, page)
      else
        lines = buildDetailPage(ctx, recs, page, remain)
      end
      if firstDraw or remain <= 0 or (hasScreen and CONFIG.countdown) or (remain % 5 == 0) then
        drawLines(lines)
      end
      firstDraw = false
      if remain <= 0 then break end
      local step = math.min(1, remain)
      os.sleep(step)
      remain = remain - step
      checkPending(ctx)
    end
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

  local maints = findMaintainers()
  if #maints == 0 then
    print("ME Level Maintainer(level_maintainer) 컴포넌트를 찾지 못했습니다.")
    print(" - 어댑터를 ME Level Maintainer 블록에 붙였는지 확인하세요(여러 대 가능).")
    return
  end
  local mc, mcAddr, mcCount, mcKind = findNetwork()

  -- ---- 진단 ---------------------------------------------------------------
  if cmd == "diag" then
    print(string.format("ae_maintainer v%s 진단", VERSION))
    print(string.format("유지기(level_maintainer) : %d대", #maints))
    for i, m in ipairs(maints) do
      local n = 0
      for k = 1, SLOT_COUNT do
        if readSlot(m.proxy, k) then n = n + 1 end
      end
      print(string.format("  #%-3d %s  %-16s 슬롯 %d/%d", i, m.addr, m.name or "-", n, SLOT_COUNT))
    end
    print(string.format("ME 컴포넌트 : %s (%s, 총 %d개)",
      tostring(mcKind or "없음"), tostring(mcAddr), tonumber(mcCount) or 0))
    print(string.format("모듈        : component=%s computer=%s term=%s",
      tostring(component ~= nil), tostring(computer ~= nil), tostring(term ~= nil)))
    if mc then
      for _, m in ipairs(maints) do
        local s = readSlot(m.proxy, 1)
        if s then
          local c
          local okc, list = pcall(mc.getCraftables, { name = s.name, damage = s.damage })
          if okc and type(list) == "table" then c = list[1] end
          if not c then
            local ok2, all = pcall(mc.getCraftables)
            if ok2 and type(all) == "table" then c = all[1] end
          end
          if c then
            print(string.format("레시피 값   : type=%s / .request=%s / .getStack=%s",
              type(c), type(c.request), type(c.getStack)))
            local ok4, st2 = callValue(c, "getStack")
            print(string.format("getStack()  : %s%s", tostring(ok4),
              ok4 and (" → " .. type(st2)) or (" 실패: " .. tostring(st2))))
          else
            print("레시피 값   : 없음(필터 결과 0)")
          end
          break
        end
      end
      local ok5, cpus = pcall(mc.getCpus)
      print(string.format("CPU 목록    : ok=%s type=%s count=%s", tostring(ok5), type(cpus),
        (type(cpus) == "table") and tostring(#cpus) or "?"))
      -- getCpus() 는 표(row) 목록: {name, storage, coprocessors, busy, cpu=값}
      if type(cpus) == "table" and cpus[1] then
        local raw = cpus[1]
        print(string.format("  항목 구조: type=%s / .name=%s / .busy=%s / .storage=%s / .coprocessors=%s / .cpu=%s",
          type(raw), type(raw and raw.name), type(raw and raw.busy), type(raw and raw.storage),
          type(raw and raw.coprocessors), type(raw and raw.cpu)))
      end
      local snap = buildCpuSnapshot(cpus)
      local function stackText(st)
        if type(st) ~= "table" then return "?" end
        return string.format("%s x%s [%s]", tostring(st.label or st.name),
          comma(st.size or st.amount or 0), tostring(st.name))
      end
      local function listText(list)
        if list == nil then return "읽기 실패/없음" end
        if #list == 0 then return "0개" end
        local out = {}
        for k = 1, math.min(#list, 3) do out[#out + 1] = stackText(list[k]) end
        return string.format("%d개: %s%s", #list, table.concat(out, " | "), (#list > 3) and " ..." or "")
      end
      for _, e in ipairs(snap) do
        print(string.format("  %s  busy=%s active=%s storage=%s copro=%s", cpuLabel(e),
          tostring(e.busy), tostring(e.active), tostring(e.storage), tostring(e.coprocessors)))
        print("       finalOutput : " .. (e.final and stackText(e.final) or "없음(nil)"))
        print("       activeItems : " .. listText(e.lists.activeItems))
        print("       pendingItems: " .. listText(e.lists.pendingItems))
        print("       storedItems : " .. listText(e.lists.storedItems))
      end
      if #snap == 0 then
        print("  (CPU 없음 — 어댑터가 ME Controller/Interface 에 붙어 있고 그 네트워크에 크래프팅 CPU 가 있어야 합니다)")
      end
    end
    return
  end

  -- ---- set <번호> <슬롯> <유지> <배치> -------------------------------------
  if cmd == "set" then
    local mi, slot = tonumber(argv[2]), tonumber(argv[3])
    local qty, bat = tonumber(argv[4]), tonumber(argv[5])
    if not (mi and slot and qty and bat) then
      print("사용법: ae_maintainer set <유지기번호> <슬롯1-5> <유지수량> <배치수량>")
      print("        유지기 번호는 list 또는 요약 화면의 #번호")
      return
    end
    local m = maints[mi]
    if not m then
      print("그런 번호의 유지기가 없습니다: " .. tostring(mi) .. " (list 로 확인)")
      return
    end
    local ok, res = pcall(m.proxy.setSlot, slot, qty, bat)
    if ok then
      log("#%d(%s) 슬롯%d 설정 완료: 유지=%s, 배치=%s (반환 %s)",
        mi, shortAddr(m.addr), slot, comma(qty), comma(bat), tostring(res))
    else
      log("설정 실패: %s", tostring(res))
    end
    return
  end

  local ctx = { maints = maints, mc = mc, mcAddr = mcAddr, mcKind = mcKind,
                mcCount = mcCount, drive = (CONFIG.mode == "drive"), view = CONFIG.view }
  local viewIdx = nil

  if cmd == "monitor" then
    ctx.drive = false
  elseif cmd == "summary" then
    ctx.view = "summary"
  elseif cmd == "detail" then
    ctx.view = "detail"
  elseif cmd == "drive" then
    ctx.drive = true
    if argv[2] then CONFIG.interval = tonumber(argv[2]) or CONFIG.interval end
  elseif cmd == "show" then
    viewIdx = tonumber(argv[2])
    if not (viewIdx and maints[viewIdx]) then
      print("사용법: ae_maintainer show <유지기번호>   (번호는 list 또는 요약 화면 #번호)")
      return
    end
  elseif cmd == "list" or cmd == "once" then
    ctx.drive = false
    local recs, total = runCycle(ctx)
    for i, m in ipairs(ctx.maints) do
      local st = recs[m.addr]
      print(string.format("#%-3d %s %-16s (슬롯 %d/%d)", i, shortAddr(m.addr), m.name or "-",
        st and st.used or 0, SLOT_COUNT))
      for k = 1, SLOT_COUNT do
        print((st and st.lines[k]) or string.format("  %d -", k))
      end
    end
    print(string.format("합계: 부족 %d · 신규요청 %d · 제작중 %d · 대기 %d · 레시피없음 %d · 진행 %d",
      total.short or 0, total.requested or 0, total.crafting or 0,
      total.waiting or 0, total.missing or 0, total.pending or 0))
    return
  elseif cmd ~= nil then
    log("알 수 없는 명령입니다: %s (help 참조)", tostring(cmd))
    return
  end

  if not mc then
    log("me_controller/me_interface 가 없어 읽기만 표시합니다(보관량 조회/요청 불가).")
  elseif mcCount and mcCount > 1 then
    log("%s 가 %d개 감지되어 첫 번째(%s)를 사용합니다. controllerAddress 로 지정할 수 있습니다.",
      tostring(mcKind), mcCount, shortAddr(mcAddr))
  end
  if #ctx.maints > 1 then
    local ids = {}
    for i, m in ipairs(ctx.maints) do ids[i] = string.format("#%d:%s", i, shortAddr(m.addr)) end
    log("유지기 %d대 감지: %s", #ctx.maints, table.concat(ids, " "))
  end

  local ok, err = pcall(mainLoop, ctx, viewIdx)
  restoreAll(ctx)
  if not ok then log("중단됨: %s", tostring(err)) end
end

main(...)









