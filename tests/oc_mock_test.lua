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
--     STRICT=1                          userdata 메서드를 self 없이 부르는 규약으로 흉내
--     COMPONENT_SET=controller|interface|none   네트워크 컴포넌트 구성 (기본 controller)
--
--   주의: 실제 OpenOS 처럼 component/computer/term 을 **전역으로 만들지 않는다.**
--         (모듈 require 로만 제공) → 프로그램이 전역을 쓰면 즉시 실패한다.
--------------------------------------------------------------------------------
local STRICT = os.getenv("STRICT") == "1"
-- 대상 프로그램은 이 하네스 기준 ../ae_maintainer.lua (TARGET 환경변수로 변경 가능)
local selfDir = (arg and arg[0] and arg[0]:match("^(.*)[/\\]")) or "."
local TARGET = os.getenv("TARGET") or (selfDir .. "/../ae_maintainer.lua")

-- userdata 메서드의 self 처리 (OC 규약 두 가지를 모두 흉내)
local function resolve(a, b)
  if type(a) == "table" and a.__ud then
    if STRICT then error("unexpected self argument") end
    return a, b
  end
  return nil, a
end

-- ---- 상태 객체(CraftingStatus) 흉내 ----
local status = { __ud = true }
function status.isComputing(a, b) resolve(a, b); return true end
function status.hasFailed(a, b)   resolve(a, b); return false end
function status.isCanceled(a, b)  resolve(a, b); return false end
function status.isDone(a, b)      resolve(a, b); return false end

-- ---- Craftable 흉내 ----
local craftable = { __ud = true }
function craftable.getStack(a, b)
  resolve(a, b)
  return { name = "gregtech:gt.blockmachines", label = "Machine Casing", damage = 0, size = 1 }
end
function craftable.request(a, b)
  local _, amount = resolve(a, b)
  io.write(string.format("   >> (mock) request(%s) 호출됨\n", tostring(amount)))
  return status
end

-- ---- me_controller 컴포넌트 흉내 ----
local mcObj = {}
local NET = { ["gregtech:gt.blockmachines"] = 1024 }   -- 아이템 보관량
function mcObj.getItemsInNetwork(filter)
  filter = filter or {}
  local out = {}
  if filter.name and NET[filter.name] then
    out[1] = { name = filter.name, label = "Machine Casing", damage = filter.damage or 0,
               size = NET[filter.name], maxSize = 64, hasTag = false }
  end
  return out
end
function mcObj.getFluidsInNetwork(filter)
  filter = filter or {}
  if filter.name == "water" then
    return { { name = "water", label = "Water", amount = 50000 } }
  end
  return {}
end
function mcObj.getCraftables(filter)
  return { craftable }
end

-- ---- level_maintainer 컴포넌트 흉내 ----
local lmObj = {}
local SLOTS = {
  [1] = { name = "gregtech:gt.blockmachines", label = "Machine Casing", damage = 0, maxDamage = 0,
          hasTag = false, quantity = 4096, batch = 512, isFluid = false, isEnable = true, isDone = true },
  [2] = { name = "ae2fc:fluid_drop", label = "Fluid Drop", damage = 0, maxDamage = 0,
          hasTag = false, quantity = 100000, batch = 16000, isFluid = true, isEnable = true, isDone = true,
          fluid = { name = "water", label = "Water", amount = 1000 } },
}
function lmObj.getSlot(i) return SLOTS[tonumber(i) or 1] end
function lmObj.setEnable(i, v)
  io.write(string.format("   >> (mock) setEnable(%s, %s)\n", tostring(i), tostring(v)))
  return true
end
function lmObj.setSlot(i, q, b)
  io.write(string.format("   >> (mock) setSlot(%s, %s, %s)\n", tostring(i), tostring(q), tostring(b)))
  return true
end
function lmObj.isDone(i) return true end
function lmObj.isEnable(i) return true end
function lmObj.active() return true end

-- ---- OC 런타임 흉내 (실제 OpenOS와 동일: 전역이 아니라 '모듈'로 제공) ----
-- 컴포넌트 구성: COMPONENT_SET=controller(기본) | interface | none
local COMPONENT_SET = os.getenv("COMPONENT_SET") or "controller"

local comps = {
  ["aaaa-1111"] = { t = "level_maintainer", o = lmObj },
}
if COMPONENT_SET == "controller" then
  comps["bbbb-2222"] = { t = "me_controller", o = mcObj }
elseif COMPONENT_SET == "interface" then
  comps["cccc-3333"] = { t = "me_interface", o = mcObj }
end

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
package.preload["computer"] = function() return { uptime = function() return 42 end } end
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

-- os.sleep: 2번째 호출에서 인터럽트(에러)를 던져 루프 종료/복구 경로까지 검증
local sleeps = 0
os.sleep = function()
  sleeps = sleeps + 1
  if sleeps >= 2 then error("interrupted (mock Ctrl+C)", 0) end
end

io.write(string.format("### STRICT=%s  TARGET=%s\n", tostring(STRICT), TARGET))
local chunk = assert(loadfile(TARGET))
chunk(...)
io.write("### (mock) 프로그램 종료\n")
