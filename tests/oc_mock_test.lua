--------------------------------------------------------------------------------
-- tests/oc_mock_test.lua — OC(OpenComputers) 없이 ae_maintainer.lua 를 돌려보는 검증 하네스
--
--   사용법 (서버 터미널)
--     lua5.3 tests/oc_mock_test.lua once        읽기 전용 1회 실행 검증
--     lua5.3 tests/oc_mock_test.lua drive 5     요청/원상복구 경로 검증
--     lua5.3 tests/oc_mock_test.lua set 2 250000 32000
--     STRICT=1 lua5.3 tests/oc_mock_test.lua drive 5   (userdata self 미주입 규약 검증)
--
--   환경변수
--     TARGET=/경로/ae_maintainer.lua   검사 대상 변경 (기본: ../ae_maintainer.lua 위치)
--     COMPONENT_SET=controller|interface|none   네트워크 컴포넌트 구성 (기본 controller)
--     MAINTAINER_COUNT=N                유지기 대수(기본 1, 2대 이상이면 다중 처리 검증)
--     CPU_BUSY_MATCH=1                  처음부터 같은 품목을 제작 중인 CPU 가 있는 상황
--     MAX_SLEEPS=N                      N초 후 인터럽트(mock Ctrl+C) 발생 (기본 2)
--     CFG_EXTRA="k=v;k=v"               임시 ae_maintainer.cfg 를 만들어 설정 변경
--
--   주의: 실제 환경을 그대로 흉내 낸다.
--     1) component/computer/term 을 전역으로 만들지 않는다(모듈 require 로만 제공)
--     2) OC 커널(machine.lua)과 같이 userdata 값은 프록시 테이블, 그 메서드는
--        __call 을 가진 '테이블'(함수가 아님)이며 self 가 자동 주입된다
--        → 이 두 가지를 어기면 이 하네스가 즉시 실패한다(회귀 방지)
--     3) 인터넷 핸들의 close() 는 실제와 같이 호출 불가로 둔다
--------------------------------------------------------------------------------
local selfDir = (arg and arg[0] and arg[0]:match("^(.*)[/\\]")) or "."
local TARGET = os.getenv("TARGET") or (selfDir .. "/../ae_maintainer.lua")

-- ---- OC 값(userdata) 흉내: 실제 커널(machine.lua)과 동일한 구조 ----
--   값 = 프록시 테이블, 메서드 = __call 을 가진 '테이블'(함수가 아님), self(프록시) 자동 주입
local function wrapValue(raw)
  local proxy = { type = "userdata" }
  for name, fn in pairs(raw) do
    proxy[name] = setmetatable({ name = name, proxy = proxy }, {
      __call = function(_, ...) return fn(proxy, ...) end,
      __tostring = function() return "function" end,
    })
  end
  return proxy
end

-- ---- Crafting CPU 상태 (craftable.request 가 busy 로 바꾼다) ----
local cpuBusy = false
local cpuCanceled = false

-- ---- 네트워크 보관량(이름 -> 수량) — craftable.request 가 결과물을 넣을 수 있음 ----
local NET = {
  ["gregtech:gt.blockmachines"] = 1024,
  ["minecraft:iron_ingot"] = 300,
}

-- ---- 상태 객체(CraftingStatus) 흉내 ----
local status = wrapValue({
  isComputing = function(self) return true end,
  hasFailed   = function(self) return false end,
  isCanceled  = function(self) return false end,
  isDone      = function(self) return false end,
})

-- ---- Craftable 흉내 ----
local craftable = wrapValue({
  getStack = function(self)
    return { name = "gregtech:gt.blockmachines", label = "Machine Casing", damage = 0, size = 1 }
  end,
  request = function(self, amount)
    io.write(string.format("   >> (mock) request(%s) 호출됨\n", tostring(amount)))
    cpuBusy = true          -- 요청하면 CPU 가 그 작업으로 바빠진다
    if os.getenv("STOCK_AFTER_REQUEST") == "1" then
      NET["gregtech:gt.blockmachines"] = 4096   -- 결과물이 들어온 상황(완료 판정 검증)
    end
    if os.getenv("PARTIAL_AFTER_REQUEST") == "1" then
      NET["gregtech:gt.blockmachines"] = (NET["gregtech:gt.blockmachines"] or 0) + 30
      io.write(string.format("   >> (mock) 부분 납품만 됨: 보관 %d (이후 정지)\n",
        NET["gregtech:gt.blockmachines"]))
    end
    return status
  end,
})

-- ---- me_controller 컴포넌트 흉내 ----
local mcObj = {}
local ITEM_LABELS = {
  ["gregtech:gt.blockmachines"] = "Machine Casing",
  ["minecraft:iron_ingot"] = "Iron Ingot",
}
function mcObj.getItemsInNetwork(filter)
  filter = filter or {}
  local out = {}
  for name, size in pairs(NET) do
    if (not filter.name) or filter.name == name then
      out[#out + 1] = { name = name, label = ITEM_LABELS[name] or name,
                        damage = filter.damage or 0, size = size, maxSize = 64, hasTag = false }
    end
  end
  return out
end
function mcObj.getFluidsInNetwork(filter)
  filter = filter or {}
  if (not filter.name) or filter.name == "water" then
    return { { name = "water", label = "Water", amount = 50000 } }
  end
  return {}
end
function mcObj.getCraftables(filter)
  return { craftable }
end

-- ---- Crafting CPU 흉내 (getCpus) ---- (값 = 프록시 테이블)
--   CPU_BUSY_MATCH=1  : 처음부터 CPU 가 사용 중
--   CPU_NOT_BUSY=1    : isBusy=false, isActive=true (출력 막힘/재료 대기 상태 흉내 — 제보된 증상)
--   CPU_ITEM_IN_LIST=1: 최종산출물로는 안 보이고 storedItems 에만 우리 품목이 있는 상황
--   CPU_OTHER_ITEM=1  : CPU 가 다른 품목을 제작 중(우리 품목 없음 → 단일 CPU 폴백 검증)
cpuBusy = (os.getenv("CPU_BUSY_MATCH") == "1")
local CPU_NOT_BUSY = os.getenv("CPU_NOT_BUSY") == "1"
local CPU_ITEM_IN_LIST = os.getenv("CPU_ITEM_IN_LIST") == "1"
local CPU_OTHER_ITEM = os.getenv("CPU_OTHER_ITEM") == "1"
local cpuObj = wrapValue({
  isBusy  = function(self) if CPU_NOT_BUSY then return false end return cpuBusy end,
  isActive = function(self) return cpuBusy end,
  finalOutput = function(self)
    if not cpuBusy then return nil end
    if CPU_ITEM_IN_LIST or CPU_OTHER_ITEM then
      if CPU_OTHER_ITEM then
        return { name = "minecraft:diamond", label = "Diamond", damage = 0, size = 64 }
      end
      return nil
    end
    return { name = "gregtech:gt.blockmachines", label = "Machine Casing", damage = 0, size = 512 }
  end,
  activeItems  = function(self) return {} end,
  storedItems  = function(self)
    if cpuBusy and CPU_ITEM_IN_LIST then
      return { { name = "gregtech:gt.blockmachines", label = "Machine Casing", damage = 0, size = 128 } }
    end
    return {}
  end,
  pendingItems = function(self) return {} end,
  cancel = function(self)
    cpuCanceled = true
    io.write("   >> (mock) CPU cancel() 호출됨\n")
    return true
  end,
})
function mcObj.getCpus() return { cpuObj } end

-- ---- level_maintainer 컴포넌트 흉내 (여러 대) ----
--   MAINTAINER_COUNT=1(기본) | 3 등
local MAINTAINER_COUNT = tonumber(os.getenv("MAINTAINER_COUNT") or "1")
local maintainers = {}

local function makeSlot(name, label, quantity, batch, fluidName)
  local s = { name = name, label = label, damage = 0, maxDamage = 0, hasTag = false,
              quantity = quantity, batch = batch, isFluid = (fluidName ~= nil),
              isEnable = true, isDone = true }
  if fluidName then
    s.fluid = { name = fluidName, label = fluidName, amount = 1000 }
  end
  return s
end

-- 유지기별 슬롯 (1대: GT 기계 케이싱 + 물 / 2대: 철괴 / 3대: 비어 있음)
local SLOT_SETS = {
  { makeSlot("gregtech:gt.blockmachines", "Machine Casing", 4096, 512),
    makeSlot("ae2fc:fluid_drop", "Water", 100000, 16000, "water") },
  { makeSlot("minecraft:iron_ingot", "Iron Ingot", 2048, 256) },
  {},
}

local function makeMaintainer(tag, slots)
  local lm = {}
  local data = slots or {}
  function lm.getSlot(i) return data[tonumber(i) or 1] end
  function lm.setEnable(slot, v)
    io.write(string.format("   >> (mock) %s.setEnable(%s, %s)\n", tag, tostring(slot), tostring(v)))
    return true
  end
  function lm.setSlot(slot, q, b)
    io.write(string.format("   >> (mock) %s.setSlot(%s, %s, %s)\n", tag, tostring(slot), tostring(q), tostring(b)))
    return true
  end
  function lm.isDone(i) return true end
  function lm.isEnable(i) return true end
  function lm.active() return true end
  return lm
end

local comps = {}
for i = 1, MAINTAINER_COUNT do
  local addr = string.format("aaaa-%04d", i)
  maintainers[i] = { addr = addr, proxy = makeMaintainer("maint" .. i, SLOT_SETS[i] or {}) }
  comps[addr] = { t = "level_maintainer", o = maintainers[i].proxy }
end

-- ---- OC 런타임 흉내 (실제 OpenOS와 동일: 전역이 아니라 '모듈'로 제공) ----
-- 컴포넌트 구성: COMPONENT_SET=controller(기본) | interface | none
local COMPONENT_SET = os.getenv("COMPONENT_SET") or "controller"

if COMPONENT_SET == "controller" then
  comps["bbbb-2222"] = { t = "me_controller", o = mcObj }
elseif COMPONENT_SET == "interface" then
  comps["cccc-3333"] = { t = "me_interface", o = mcObj }
end

local uptime = 0     -- os.sleep 이 진행시킨다 (타임아웃/경과시간 검증용)
local componentModule = {
  isAvailable = function(n) return n == "screen" or n == "gpu" or n == "internet" end,
  list = function(filter, exact)
    local out = {}
    for a, c in pairs(comps) do
      if not filter then out[a] = c.t
      elseif exact and c.t == filter then out[a] = c.t
      elseif (not exact) and c.t:find(filter, 1, true) then out[a] = c.t end
    end
    return out
  end,
  proxy = function(a) return comps[a] and comps[a].o or nil end,
}

package.preload["component"] = function() return componentModule end
package.preload["computer"] = function()
  return { uptime = function() return uptime end }
end
package.preload["term"] = function()
  return { clear = function() end, setCursorPos = function() end }
end

-- 회귀 방지: OpenOS에 없는 전역(component/computer/term)을 쓰면 즉시 실패시킨다.
-- (v1.0 이 이 실수를 해서 게임에서 죽었다)
setmetatable(_G, {
  __index = function(_, k)
    if k == "component" or k == "computer" or k == "term" or k == "unicode" then
      error("OpenOS에 없는 전역 '" .. tostring(k) .. "' 사용 (require 로 받아야 함)", 2)
    end
    return nil
  end,
})

-- os.sleep: uptime 을 실제처럼 진행시키고, MAX_SLEEPS 회 후 인터럽트(에러)를 던져
--           루프 종료/원상복구 경로까지 검증한다.
local sleeps = 0
local MAX_SLEEPS = tonumber(os.getenv("MAX_SLEEPS") or "2")
os.sleep = function(s)
  uptime = uptime + (tonumber(s) or 0)
  sleeps = sleeps + 1
  if sleeps >= MAX_SLEEPS then error("interrupted (mock Ctrl+C)", 0) end
end

io.write(string.format("### TARGET=%s  COMPONENT_SET=%s  유지기=%d대  cpuBusy=%s  MAX_SLEEPS=%d\n",
  TARGET, COMPONENT_SET, MAINTAINER_COUNT, tostring(cpuBusy), MAX_SLEEPS))

-- CFG_EXTRA 로 임시 설정 파일을 만들어 프로그램 설정을 바꿀 수 있다
local cfgText = os.getenv("CFG_EXTRA")
if cfgText and cfgText ~= "" then
  local f = assert(io.open("ae_maintainer.cfg", "w"))
  f:write(cfgText, "\n")
  f:close()
  io.write("### (mock) ae_maintainer.cfg 생성: " .. cfgText:gsub("\n", " ") .. "\n")
end

local chunk = assert(loadfile(TARGET))
local ok, err = pcall(chunk, ...)
if cfgText and cfgText ~= "" then os.remove("ae_maintainer.cfg") end
io.write(string.format("### (mock) 프로그램 종료 (cpuCanceled=%s, sleeps=%d)\n",
  tostring(cpuCanceled), sleeps))
if not ok then io.write("### (mock) 오류: " .. tostring(err) .. "\n") end
