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
--     CPU_BUSY_MATCH=1                  처음부터 같은 품목을 제작 중인 CPU 가 있는 상황
--     MAX_SLEEPS=N                      N초 후 인터럽트(mock Ctrl+C) 발생 (기본 2)
--     CFG_EXTRA="k=v;k=v"               임시 ae_maintainer.cfg 를 만들어 설정 변경
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

-- ---- Crafting CPU 상태 (craftable.request 가 busy 로 바꾼다) ----
local cpuBusy = false
local cpuCanceled = false

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
  cpuBusy = true          -- 요청하면 CPU 가 그 작업으로 바빠진다
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

-- ---- Crafting CPU 흉내 (getCpus) ----
--   CPU_BUSY_MATCH=1 : 처음부터 slot1 품목을 제작 중인 CPU 가 있는 상황
--   기본            : 요청(request) 후에 그 CPU 가 busy 가 되는 상황(타임아웃/취소 검증용)
cpuBusy = (os.getenv("CPU_BUSY_MATCH") == "1")
local cpuObj = { __ud = true }
function cpuObj.isBusy(a, b)  resolve(a, b); return cpuBusy end
function cpuObj.isActive(a, b) resolve(a, b); return cpuBusy end
function cpuObj.finalOutput(a, b)
  resolve(a, b)
  if not cpuBusy then return nil end
  return { name = "gregtech:gt.blockmachines", label = "Machine Casing", damage = 0, size = 512 }
end
function cpuObj.activeItems(a, b)  resolve(a, b); return {} end
function cpuObj.storedItems(a, b)  resolve(a, b); return {} end
function cpuObj.pendingItems(a, b) resolve(a, b); return {} end
function cpuObj.cancel(a, b)
  resolve(a, b)
  cpuCanceled = true
  io.write("   >> (mock) CPU cancel() 호출됨\n")
  return true
end
function mcObj.getCpus() return { cpuObj } end

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

io.write(string.format("### STRICT=%s  COMPONENT_SET=%s  cpuBusy=%s  MAX_SLEEPS=%d\n",
  tostring(STRICT), COMPONENT_SET, tostring(cpuBusy), MAX_SLEEPS))

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
os.remove("ae_maintainer.cfg")
io.write(string.format("### (mock) 프로그램 종료 (cpuCanceled=%s, sleeps=%d)\n",
  tostring(cpuCanceled), sleeps))
if not ok then io.write("### (mock) 오류: " .. tostring(err) .. "\n") end
