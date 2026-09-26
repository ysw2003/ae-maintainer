--------------------------------------------------------------------------------
-- tests/oc_mock_setup.lua — ae_maintainer_setup.lua 를 OC 없이 검증하는 하네스
--
--   · 인터넷/파일시스템을 흉내 내고, 실제 저장소 파일을 "다운로드"로 공급한다
--   · 실제 OpenOS 처럼 component/filesystem/internet 을 전역이 아니라 모듈로만 제공
--
--   사용법
--     TARGET_DIR=/tmp/ocinstall lua5.3 tests/oc_mock_setup.lua
--     TARGET_DIR=/tmp/ocinstall lua5.3 tests/oc_mock_setup.lua --force
--     REPO_DIR=/home/ubuntu/github/ae-maintainer TARGET_DIR=... lua5.3 ...
--------------------------------------------------------------------------------
local REPO = os.getenv("REPO_DIR") or "/home/ubuntu/github/ae-maintainer"
local TARGET = os.getenv("TARGET_DIR") or "/tmp/ocinstall"
local TARGET_SRC = os.getenv("TARGET_SRC") or (REPO .. "/ae_maintainer_setup.lua")

-- OpenOS 에 없는 전역 사용 금지 (회귀 방지)
setmetatable(_G, {
  __index = function(_, k)
    if k == "component" or k == "computer" or k == "term" or k == "filesystem" or k == "internet" then
      error("OpenOS에 없는 전역 '" .. tostring(k) .. "' 사용 (require 로 받아야 함)", 2)
    end
    return nil
  end,
})

package.preload["component"] = function()
  return { isAvailable = function(n) return n == "internet" end }
end

package.preload["filesystem"] = function()
  local fs = {}
  function fs.canonical(p)
    p = tostring(p):gsub("/+$", "")
    if p == "" then p = "/" end
    return p
  end
  function fs.concat(a, b)
    if a:sub(-1) == "/" then return a .. b end
    return a .. "/" .. b
  end
  function fs.exists(p)
    local f = io.open(p, "r")
    if f then f:close(); return true end
    return (os.rename(p, p) and true or false)   -- 디렉터리 존재 확인
  end
  function fs.isDirectory(p)
    if io.open(p .. "/.", "r") then return true end
    return (os.rename(p, p) and true or false)
  end
  function fs.open(p, mode) return io.open(p, mode) end
  return fs
end

-- internet.request(url) → 로컬 저장소의 같은 이름 파일 내용을 돌려주는 가짜 소켓
--   실제 OpenOS internet.lua 와 동일하게:
--     · handle() / for chunk in handle do 로 읽는다
--     · handle.close 는 '호출 불가 테이블'(연쇄 __call 미지원) → close() 를 쓰면 테스트 실패
package.preload["internet"] = function()
  return {
    request = function(url)
      local name = url:match("([^/]+)$")
      local src = REPO .. "/" .. name
      io.write(string.format("   >> (mock) GET %s  (← %s)\n", url, src))
      local f = io.open(src, "r")
      local data = f and f:read("*a") or nil
      if f then f:close() end
      local served = false
      local handle
      handle = setmetatable({}, {
        __call = function()
          if served then return nil end
          served = true
          if not data then error("mock: 파일 없음 " .. src, 2) end
          return data
        end,
        __index = {
          close = setmetatable({}, {
            __call = function()
              error("attempt to call a table value (field 'close')", 2)
            end,
          }),
        },
      })
      return handle
    end,
  }
end

io.write(string.format("### setup 하네스: TARGET_DIR=%s REPO_DIR=%s\n", TARGET, REPO))
os.execute("mkdir -p '" .. TARGET .. "'")
local chunk = assert(loadfile(TARGET_SRC))
local runArgs = { TARGET, ... }          -- 대상폴더 + 하네스 인자(--force 등)
local ok, err = pcall(chunk, table.unpack(runArgs))
io.write("### (mock) 종료 (결과 " .. tostring(ok) .. (ok and "" or (", 오류: " .. tostring(err))) .. ")\n")
