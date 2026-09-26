--------------------------------------------------------------------------------
-- ae_maintainer_setup.lua v1.1 — OpenComputers 컴퓨터용 설치 도우미
--
--   ae_maintainer.lua (프로그램) 과 ae_maintainer.cfg (기본 설정) 을 함께 내려받습니다.
--
-- 이름 주의
--   OpenOS 에는 **내장 `install` 명령**(/bin/install.lua = OS 디스크 설치)이 있습니다.
--   PATH 순서가 /bin:/usr/bin:/home/bin:. 이라 `install` 로 실행하면 OpenOS 설치 프로그램이
--   먼저 잡히므로, 이 파일은 충돌을 피해 ae_maintainer_setup.lua 입니다.
--
-- 사용법 (인게임, 인터넷 카드 필요)
--   wget -f https://raw.githubusercontent.com/ysw2003/ae-maintainer/main/ae_maintainer_setup.lua /home/ae_maintainer_setup.lua && ae_maintainer_setup
--   ae_maintainer_setup [대상폴더] [--force]     --force = 기존 ae_maintainer.cfg 도 덮어씀
--
--   동작
--     · ae_maintainer.lua 는 항상 최신으로 덮어씁니다.
--     · ae_maintainer.cfg 는 없을 때만 만듭니다(수정한 설정 보호). --force 로 강제 갱신.
--------------------------------------------------------------------------------
local VERSION = "1.2"
local SELF = "ae_maintainer_setup"
local BASE = "https://raw.githubusercontent.com/ysw2003/ae-maintainer/main"
local FILES = {
  { name = "ae_maintainer.lua", overwrite = true,  desc = "프로그램" },
  { name = "ae_maintainer.cfg", overwrite = false, desc = "기본 설정" },
}

local function fail(msg)
  io.stderr:write(SELF .. ": " .. tostring(msg) .. "\n")
  return 1
end

local okc, component = pcall(require, "component")
if not (okc and type(component) == "table") then
  return fail("component 모듈을 불러올 수 없습니다 (OpenOS 컴퓨터에서 실행하세요)")
end
local okfs, fs = pcall(require, "filesystem")
if not (okfs and type(fs) == "table") then
  return fail("filesystem 모듈을 불러올 수 없습니다")
end
local okinet, internet = pcall(require, "internet")
if not (okinet and type(internet) == "table") then
  return fail("internet 모듈을 불러올 수 없습니다")
end
if not component.isAvailable("internet") then
  return fail("인터넷 카드가 필요합니다 (컴퓨터에 Internet Card 를 꽂으세요)")
end

-- ---- 인자 처리 --------------------------------------------------------------
local dir, force = "/home", false
for _, a in ipairs({ ... }) do
  if a == "--force" or a == "-f" then
    force = true
  elseif a == "-h" or a == "--help" then
    print("사용법: " .. SELF .. " [대상폴더] [--force]   (기본 대상폴더 /home)")
    return 0
  else
    dir = a
  end
end
dir = fs.canonical(dir)
if not fs.isDirectory(dir) then return fail("대상 폴더가 없습니다: " .. tostring(dir)) end

-- ---- 다운로드/저장 ----------------------------------------------------------
local function download(url)
  local handle = internet.request(url)
  local parts = {}
  -- OpenOS 의 wget 과 같은 방식(이터레이터)으로 읽는다.
  --   handle.close() 는 이 환경에서 호출할 수 없다(연쇄 __call 미지원 → "attempt to call a table value").
  --   EOF 에서 라이브러리(internet.lua)가 내부적으로 연결을 닫아주므로 close 를 부르지 않는다.
  for chunk in handle do
    parts[#parts + 1] = chunk
  end
  return table.concat(parts)
end

local function save(path, data)
  local f = assert(fs.open(path, "w"))
  f:write(data)
  f:close()
end

-- ---- 실행 -------------------------------------------------------------------
print(SELF .. " v" .. VERSION .. "  → 대상 폴더: " .. dir)
local installed, skipped, failed = 0, 0, 0
for _, item in ipairs(FILES) do
  local path = fs.concat(dir, item.name)
  local exists = fs.exists(path)
  if exists and not (item.overwrite or force) then
    print(string.format(" - %-19s 건너뜀(이미 있음)  %s", item.name, path))
    skipped = skipped + 1
  else
    local okd, data = pcall(download, BASE .. "/" .. item.name)
    if not okd or type(data) ~= "string" or #data == 0 then
      print(string.format(" - %-19s 다운로드 실패: %s", item.name, tostring(data)))
      failed = failed + 1
    else
      local okw, err = pcall(save, path, data)
      if not okw then
        print(string.format(" - %-19s 저장 실패: %s", item.name, tostring(err)))
        failed = failed + 1
      else
        local ver = data:match('local VERSION = "([^"]+)"')
        print(string.format(" - %-19s 설치 완료 (%d bytes%s)  %s", item.name, #data,
          ver and (", v" .. ver) or "", path))
        installed = installed + 1
      end
    end
  end
end

print(string.format("완료: 설치 %d / 건너뜀 %d / 실패 %d", installed, skipped, failed))
if failed > 0 then return 1 end

-- ---- 다음 단계 안내 ---------------------------------------------------------
local cfgPath = fs.concat(dir, "ae_maintainer.cfg")
local progPath = fs.concat(dir, "ae_maintainer.lua")
print("")
print("다음 단계")
print("  1) 설정 확인/수정 :  edit " .. cfgPath)
print("  2) 어댑터에 ME Level Maintainer + (ME Controller 또는 ME Interface) 연결")
print("  3) 먼저 확인      :  " .. progPath .. " monitor")
print("  4) 상시 실행      :  " .. progPath .. " drive 30")
print("     (PATH 에 포함된 폴더라면 ae_maintainer monitor / ae_maintainer drive 30 로도 실행됩니다)")
return 0
