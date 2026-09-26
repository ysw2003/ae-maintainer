# AE Maintainer (GTNH OpenComputers) 사용 설명서

작성: 2026-09-26 · 대상 팩: **GTNH 2.9.0-beta-3** (`GTNH_Beta_3_GOG_Addon` 서버)
작업 폴더: `/home/ubuntu/github/ae-maintainer/`

```
~/github/ae-maintainer/            (GitHub: ysw2003/ae-maintainer)
├── ae_maintainer.lua              OC 컴퓨터에 넣을 프로그램 (본체)
├── ae_maintainer.cfg              기본 설정 (인게임에서 그대로 내려받아 수정해 사용)
├── ae_maintainer_setup.lua        OC용 설치 스크립트 (프로그램 + 설정 함께 설치)
├── AE_MAINTAINER.md               이 문서
└── tests/
    ├── oc_mock_test.lua           프로그램 검증 하네스 (OC 없이 실행)
    └── oc_mock_setup.lua          설치 스크립트 검증 하네스
```

검증: Lua 5.3 문법 검사 + 목(mock) 하네스 실행 검증. 하네스 실행 예: `aetest once` / `aetest drive 5`

---

## 1. 결론 요약

| 항목 | 결과 |
|---|---|
| "AE Maintainer"의 정체 | **AE2FC(AE2 Fluid Crafting Rework)의 `ME Level Maintainer` 블록** (`tile.level_maintainer.name=ME Level Maintainer`) |
| AE2 기본 모드에 존재? | **없음** (AE2 `rv3-beta-1050-GTNH` 안에 Maintainer 관련 클래스 0개) |
| OpenComputers로 읽을 수 있나? | **예 — ae2fc가 OC 드라이버를 내장**하고 있음 (`component "level_maintainer"`) |
| 슬롯 수 / 인덱스 | **5개, 1부터 시작(1~5)** (`TileLevelMaintainer.REQ_COUNT = 5`) |
| 다중 유지기 | 어댑터에 붙은 **모든** `level_maintainer` 를 인식(주소 오름차순). 기본 화면은 **2대씩 슬롯 5줄 상세 + 자동 페이지 전환**(`detailPerPage`, `pageSeconds`), `summary` 한 줄 요약, `show <번호>` 고정 상세, `list` 전체 출력 |
| 읽을 수 있는 값 | 품목(아이템/유체), 유지 수량 `quantity`, 1회 제작량 `batch`, 슬롯 사용여부, 작업 진행상태 |
| 요청(제작)도 가능? | **예** — `me_controller` 컴포넌트의 `getCraftables(filter)` → `craftable.request(수량)` |
| 주기 제어 | 프로그램에서 `interval`(초)로 제어. 유지기 자체 주기는 `config/ae2fc.cfg`의 `levelmaintainer.minTick/maxTick` |

**핵심**: 유지기 블록에 어댑터를 붙이면 `level_maintainer` 컴포넌트가 생기고, 여기서 설정을 읽습니다.
제작 요청은 `me_controller`(= 어댑터 + ME Controller 블록) 컴포넌트로 넣습니다.

---

## 2. 확인 근거 (실측)

이 문서의 내용은 추측이 아니라 **서버에 설치된 실제 jar를 직접 열어 확인**한 값입니다.

| 근거 | 명령/결과 |
|---|---|
| 팩 버전 | `changelog from 2.9.0-beta-2 to 2.9.0-beta-3.md` 파일 존재 |
| 모드 파일 | `mods/appliedenergistics2-rv3-beta-1050-GTNH.jar`, `mods/ae2fc-1.5.106-gtnh.jar`, `mods/OpenComputers-1.12.61-GTNH.jar` |
| Maintainer는 ae2fc | jar 전체 스캔 결과 Maintainer 클래스는 **ae2fc 에만** 존재 (`com/glodblock/github/common/tile/TileLevelMaintainer`, `GuiLevelMaintainer`, `CPacketLevelMaintainer` …) |
| OC 드라이버 내장 | `com/glodblock/github/crossmod/opencomputers/DriverLevelMaintainer$Environment` |
| 컴포넌트 이름/우선순위 | 바이트코드 `preferredName()` → `"level_maintainer"`, `priority()` → `6` |
| 슬롯 개수 | `TileLevelMaintainer.REQ_COUNT` ConstantValue = **int 5** |
| 슬롯 인덱스 | `getSlot` 내부 `checkInteger(0) - 1` → **1-based** |
| 반환 테이블 키 | `damage, hasTag, label, maxDamage, name, quantity, batch, isFluid, fluid, isEnable, isDone` |
| `name` 값 | `GameRegistry.findUniqueIdentifierFor(item).toString()` → `"modid:itemname"` 형식 (OC 아이템 테이블의 `name`과 동일 규칙) |
| 유체 표시 | 슬롯이 유체면 `isFluid=true` + `fluid`(OC fluid 테이블: `name`, `label`, `amount`) |
| 요청 API | OC AE2 통합 `li.cil.oc.integration.appeng.NetworkControl$Craftable.request()` → `ICraftingGrid.beginCraftingJob(...)` |
| args 타입 | AE2 `AEItemStackType.ITEM_STACK_ID="item"`, `AEFluidStackType.FLUID_STACK_ID="fluid"` |

> `level_maintainer` / `me_controller` 컴포넌트는 **어댑터에 블록을 붙였을 때만** 목록에 나타납니다.

---

## 3. 컴포넌트 API (1-based)

### `level_maintainer` — ME Level Maintainer (ae2fc)

| 메서드 | 반환 | 설명 |
|---|---|---|
| `getSlot([slot])` | `table` 또는 `nil` | 슬롯 내용. 생략하면 1번. 빈 슬롯은 `nil` |
| `setSlot(slot, quantity, batch)` | `boolean` | 유지 수량 / 1회 제작량 변경 |
| `setSlot(slot, dbAddress, dbIndex, quantity, batch)` | `boolean` | 데이터베이스 항목으로 품목까지 지정 |
| `isDone(slot)` | `boolean` | `true` = 그 슬롯에 진행 중인 제작 작업이 없음 |
| `isEnable(slot)` | `boolean` | 슬롯 사용 여부 |
| `setEnable(slot, value)` | `boolean` | 슬롯 사용/중지 (유지기 자체의 자동요청 스위치) |
| `active()` | `boolean` | 유지기가 현재 동작 중인지 |

`getSlot(slot)` 반환 예:
```lua
{ name = "gregtech:gt.blockmachines", label = "Machine Casing", damage = 0, maxDamage = 0,
  hasTag = false, quantity = 4096, batch = 512, isFluid = false, isEnable = true, isDone = true }

-- 유체 슬롯이면
{ name = "ae2fc:fluid_drop", isFluid = true, fluid = { name = "water", label = "Water", amount = 1000 },
  quantity = 100000, batch = 16000, isEnable = true, isDone = true, ... }
```

### `me_controller` / `me_interface` — ME 네트워크 접근 (OC의 AE2 통합)

ME Controller 블록은 `me_controller`, ME Interface 블록은 `me_interface` 컴포넌트가 됩니다.
**두 드라이버 모두 OC의 `NetworkControl` 을 구현**하므로 아래 메서드를 동일하게 제공합니다(실측: `DriverController$Environment`, `DriverBlockInterface$Environment` 모두
`implements NetworkControl<TileEntity>`). 프로그램은 `me_controller` → `me_interface` 순으로 먼저 잡히는 것을 사용합니다.

| 메서드 | 설명 |
|---|---|
| `getItemsInNetwork([filter])` | 보관 아이템 목록. `filter`는 테이블 키/값이 일치하는 것만 |
| `getItemInNetwork(name 또는 테이블[, damage[, nbt]])` | 특정 아이템 1종 |
| `getFluidsInNetwork([filter])` | 보관 유체 목록 |
| `getCraftables([filter])` | **제작 가능(레시피가 있는) 품목 목록** — 아이템+유체 모두 |
| `getCraftable([detail, type])` | 특정 레시피 1개 (`type`은 `"item"`/`"fluid"`) |
| `store(filter, dbAddress[, startSlot[, count]])` | 네트워크 아이템을 데이터베이스에 저장 |
| `getCpus()` | CPU 목록 |
| `setItemEventSubscription(bool)` 등 | 아이템/유체 변화 이벤트 구독 |

Craftable(userdata) 메서드: `getStack()` · `request([amount[, prioritizePower[, cpuName]]])`
요청 반환값(상태 userdata): `isComputing()` · `hasFailed()` · `isCanceled()` · `isDone()`

### `getCpus()` 가 돌려주는 CPU (제작 중 감지 · 취소)

`getCpus()` 는 제작 CPU 마다 userdata 를 돌려줍니다. 실측 콜백(OC jar `NetworkControl$Cpu`):

| 메서드 | 반환 | 설명 |
|---|---|---|
| `isBusy()` | boolean | 이 CPU 가 작업 중인가 |
| `isActive()` | boolean | CPU 가 활성인가 |
| `finalOutput()` | table 또는 nil | **이 CPU 가 만들고 있는 최종 결과물** (제작 중 감지의 핵심) |
| `activeItems()` | table | 현재 제작 중인 중간 산출물들 |
| `pendingItems()` | table | 아직 조달이 필요한 아이템들 |
| `storedItems()` | table | CPU 내부에 보관된 아이템들 |
| `cancel()` | boolean | **이 CPU 의 현재 제작 작업을 취소** |

> v1.2 는 `finalOutput()` 을 슬롯 품목과 비교해 "이미 제작 중"을 판단하고, 타임아웃 시 그 CPU 를 `cancel()` 합니다.
> 주의: 취소는 **그 품목을 제작 중인 CPU 의 작업**을 끊습니다. 같은 CPU 작업에 다른 산출물이 함께 있다면 같이 중단될 수 있습니다.

### 값(userdata) 메서드 호출 규약 (v1.4에서 수정한 핵심)

OC 커널 `assets/opencomputers/lua/machine.lua` 실측:

```lua
local proxy = {type = "userdata"}
for method in pairs(spcall(userdata.methods, data)) do
  proxy[method] = setmetatable({name=method, proxy=proxy}, userdataCallback)  -- __call 을 가진 '테이블'
end
return setmetatable(proxy, userdataWrapper)
```

- **값(Craftable/CPU/CraftingStatus 등)은 프록시 테이블**이고 `type(...) == "table"` 입니다.
- 그 **메서드는 함수가 아니라 호출 가능한 테이블**(`__call` 메타메서드 보유)입니다.
  → `type(craftable.request)` 는 `"function"` 이 아니라 `"table"` 입니다.
- 호출은 **점 호출 + self 자동 주입**: `craftable.request(수량)` (내부적으로 프록시가 첫 인자로 전달됨)

> 그래서 "`type(fn)=="function"` 인지 검사"하는 코드는 값 메서드에서 실패합니다. v1.4는 타입을 따지지 않고
> 그대로 호출합니다. (`ae_maintainer diag` 로 실제 타입을 확인할 수 있습니다.)


---

## 4. 게임 내 배치 (필수)

```
[어댑터]  ← (6면 중 아무 면) ← ME Level Maintainer   → 필요: level_maintainer
[어댑터]  ←                 ← ME Controller         → 필요: me_controller
[어댑터]  ←                 ← ME Interface(대체 가능) → 필요: me_interface
[어댑터]  ←                 ← 화면(선택)            → 출력
어댑터와 컴퓨터/케이블을 연결 (어댑터 = 컴퓨터에 붙이는 '부품 상자' 블록)
```
- 어댑터에 **해당 블록을 직접 접촉**시켜야 컴포넌트가 잡힙니다(유지기·컨트롤러는 ME 네트워크에 연결되어 있어야 함).
- 컴퓨터에서 `lua` 실행 후 `component.list("level_maintainer")` 로 잡히는지 먼저 확인하세요.
  - 비어 있으면 컴포넌트 이름이 다르거나 배치가 잘못된 것입니다.

## 5. 파일을 컴퓨터에 넣는 방법

**방법 A — 설치 스크립트 (프로그램 + 설정 한 번에, 인터넷 카드 필요)**
```lua
wget -f https://raw.githubusercontent.com/ysw2003/ae-maintainer/main/ae_maintainer_setup.lua /home/ae_maintainer_setup.lua && ae_maintainer_setup
```
- `ae_maintainer.lua` 와 `ae_maintainer.cfg` 를 `/home` 에 설치합니다.
- 수정한 cfg 는 보존(`--force` 로 강제 갱신).
- OpenOS 셸은 `&&`/`;` 연결을 지원합니다(`lib/sh.lua` 실측 확인).
- ⚠️ **`install` 이라는 이름은 쓰면 안 됩니다**: OpenOS 내장 명령(`/bin/install.lua` = OS 디스크 설치)이
  PATH(`/bin:/usr/bin:/home/bin:.`)에서 먼저 잡혀 OpenOS 설치 화면이 뜹니다. 그래서 `ae_maintainer_setup` 입니다.

**방법 B — 파일 직접 받기**
```lua
wget -f https://raw.githubusercontent.com/ysw2003/ae-maintainer/main/ae_maintainer.lua /home/ae_maintainer.lua
wget -f https://raw.githubusercontent.com/ysw2003/ae-maintainer/main/ae_maintainer.cfg /home/ae_maintainer.cfg
```

**방법 C — 인터넷 카드가 없을 때 (복붙)**
1. 이 문서/저장소의 `ae_maintainer.lua` 내용을 복사 (`aecode` 별칭으로 바로 볼 수 있습니다)
2. OC 컴퓨터에서 `edit /home/ae_maintainer.lua` → 붙여넣기 → `Ctrl+S` → `Ctrl+W`
3. `ae_maintainer.cfg` 는 만들지 않아도 됩니다 — **첫 실행 때 프로그램이 기본값으로 자동 생성**합니다.

실행(3가지 방법 공통): `ae_maintainer monitor` → 정상이면 `ae_maintainer drive 30`

부팅 시 자동 실행: OpenOS 부팅 스크립트(`/home/.shrc` 등)에 `ae_maintainer &` 를 넣으면 됩니다.
(버전에 따라 다를 수 있으니 안 되면 부팅 후 수동 실행)

## 6. 사용법

| 명령 | 동작 |
|---|---|
| `ae_maintainer` | 설정대로 상시 실행 (기본 = drive / 60초) |
| `ae_maintainer monitor` | **읽기/표시만** (요청 안 함) — 먼저 이걸로 값을 확인하세요 |
| `ae_maintainer drive 30` | 30초 주기로 직접 요청 |
| `ae_maintainer once` | 1회만 계산해서 표시 (설정 변경 없음) |
| `ae_maintainer set 1 4096 512` | — (v2.0에서 형식 변경) |
| `ae_maintainer diag` | 값/메서드 호출 **진단 정보** 출력 (문제 발생 시 이 출력을 보내주세요) |
| `ae_maintainer help` | 도움말 |

### v2.0/v2.1 명령 (여러 유지기)

| 명령 | 동작 |
|---|---|
| `ae_maintainer` / `monitor` / `drive 30` | **기본 상세 보기**(2대씩 슬롯 5줄, `pageSeconds`마다 다음 2대로 전환)로 실행 / 읽기만 / 요청 |
| `ae_maintainer summary` | 한 줄 요약 보기(`pageSize` 대씩)로 전환 |
| `ae_maintainer detail` | 상세 보기(`detailPerPage` 대씩)로 전환 |
| `ae_maintainer show <번호>` | 그 유지기 1대만 고정 상세 표시 |
| `ae_maintainer list` | 전체 유지기·슬롯 상세를 1회 출력(스크롤 확인용) |
| `ae_maintainer set <번호> <슬롯> <유지> <배치>` | 해당 유지기의 유지수량/배치 변경 |
| `ae_maintainer diag` | 모든 유지기 + 값 타입 진단 |

화면 줄 수(참고): 상세 2대 = 헤더 1 + (유지기 1 + 슬롯 5) × 2 + 안내 1 = **14줄**. 화면이 작으면 `detailPerPage=1` 로 낮추세요.

설정 파일(선택): 프로그램과 같은 폴더에 `ae_maintainer.cfg` 를 두면 값이 덮어써집니다.
```ini
mode=drive
interval=120
takeover=true
batchMode=need
dryRun=false
# maintainerAddress=aaaa-1111-...
# controllerAddress=bbbb-2222-...
```

### 설정 항목

| 키 | 기본 | 설명 |
|---|---|---|
| `mode` | `drive` | `drive`=OC가 요청, `monitor`=읽기만 |
| `interval` | `60` | 요청 주기(초). 5초 단위로 나눠 대기하므로 Ctrl+C에 반응 |
| `takeover` | `true` | `true` = 관리하는 슬롯의 유지기 자동요청을 끔(`setEnable=false`) → OC 단독 관리 (중복 요청 방지) |
| `batchMode` | `need` | `need`=min(배치, 부족분) / `batch`=배치 고정 / `fill`=부족분을 배치 단위로 올림 |
| `dryRun` | `false` | `true` = 요청 없이 계산 결과만 표시 |
| `labelFallback` | `true` | 이름 매칭 실패 시 표시이름으로 재검색 |
| `autoRestore` | `true` | 종료(Ctrl+C) 시 유지기 슬롯 enable 상태를 원래대로 복구 |
| `skipIfCrafting` | `true` | AE CPU 작업에 같은 품목이 있으면 새 요청 안 함 |
| `cpuSkipScope` | `any` | `any`=CPU 의 최종산출물/보관/대기/제작중 어디에든 있으면 스킵(**사람이 요청한 것 포함**) / `final`=최종 결과물만 |
| `skipIfMaintainer` | `true` | 유지기 자체가 그 슬롯을 작업 중(`isDone=false`)이면 건너뜀 |
| `requestTimeout` | `60` | 요청 후 이 초 안에 **결과물이 안 나오면** 중단(+CPU 취소 시도). `0`=끔 |
| `cancelOnTimeout` | `true` | 타임아웃 시 그 품목을 제작 중인 CPU 의 작업을 취소 |
| `cancelFallback` | `single` | 취소 대상을 못 찾았을 때 `single`=사용 중 CPU 1대면 취소 / `none`=취소 안 함 |
| `timeoutCooldown` | `0` | 중단 후 그 슬롯 재요청까지 대기(초). `0`=즉시 재시도 |
| `countdown` | `true` | 화면에 다음 주기까지 남은 시간을 1초마다 표시 |
| `view` | `detail` | 기본 화면 종류: `detail`(유지기별 슬롯 5줄) / `summary`(한 줄 요약) |
| `detailPerPage` | `2` | 상세 화면 한 페이지당 유지기 수 (2 → 2대씩) |
| `pageSize` / `pageSeconds` | `10` / `10` | 요약 화면 페이지당 유지기 수 / 자동 페이지 전환 간격(초, 0=끔) |
| `maxMaintainers` | `0` | `0`=모든 유지기, N=앞에서 N대만 |
| `bulkQuery` | `true` | 보관량을 사이클당 1회 전체 조회(유지기 많을 때 빠름). 실패 시 자동으로 슬롯별 조회 |
| `name.<주소>` | 없음 | 유지기 별칭 (예: `name.36720bcd-…=창고A`) |
| `maintainerAddress` | 없음 | 특정 유지기 1대만 사용할 때 어댑터 주소 |

### 매 주기 판단 순서 (v2.0)

1. `component.list("level_maintainer")` 로 **모든 유지기** 열거(주소 오름차순) → 각 유지기의 슬롯 1~5 읽기
2. (drive 모드면) **모든 유지기**의 사용 중 슬롯 자동요청을 끔(takeover)
3. 보관량: `bulkQuery=true` 면 `getItemsInNetwork()`·`getFluidsInNetwork()` 를 **사이클당 1회** 호출해
   로컬에서 이름/표시이름으로 합산(유지기가 많을 때 빠름). 실패하거나 끄면 슬롯별 개별 조회로 자동 폴백
4. 각 슬롯: `부족분 = 유지수량 - 보관량` → 0 이하면 "충족"
5. 부족하면 아래 순서로 **중복 요청을 걸러냄**
   1. 내가 넣은 요청이 아직 진행 중(`isComputing`) → 건너뜀
   2. 타임아웃 중단 후 대기(`timeoutCooldown`) → 건너뜀
   3. 유지기 자체가 그 슬롯 작업 중(`isDone=false`) → 건너뜀
   4. **AE CPU 작업에 그 품목이 포함**(`cpuSkipScope=any`: `finalOutput` + `storedItems`/`pendingItems`/`activeItems`) → 건너뜀 (사람이 요청한 작업이어도 동일)
6. 위에 해당 없으면 `batchMode` 규칙으로 요청량 계산 → 레시피(`getCraftables`) 검색 → `request(요청량)` (요청 시각 기록)

### 매 초 동작 (대기 중) — v2.2

- 화면을 다시 그려 **다음 요청까지 남은 시간**과 진행 중 요청의 `경과/타임아웃초` 를 실시간 표시
- 진행 중 요청이 `requestTimeout` 을 넘기면:
  1. **결과물이 나왔는지 확인** — 작업 완료(`isDone`)이거나 재고가 유지수량에 도달했으면 완료로 처리
  2. 아니면 요청 추적 해제 + **CPU 취소**: ① 요청 직후 기억해 둔 CPU → ② `getCpus()` 재조회로 그 품목이 포함된 CPU → ③ `cancelFallback=single` 이면 사용 중 CPU 가 1대뿐일 때 그 CPU
  3. 로그에 취소 결과를 남김 (예: `(CPU 취소됨: 요청 시 기록된 CPU)` / `(취소할 CPU를 찾지 못함)`)

---

## 7. 검증 결과 (실제 실행)

`tests/oc_mock_test.lua` 하네스로 OC 런타임을 흉내 내어 실제 실행했습니다(문법 검사 포함, Lua 5.3).
실행 방법: `aetest once` / `aetest drive 5` / `aetest diag`

| 테스트 | 결과 |
|---|---|
| `luac5.3 -p ae_maintainer.lua` (v1.2) | 통과 (오류 없음) |
| `once` (monitor) | 5개 슬롯 읽기 정상, 아이템 부족 3,072 / 유체 부족 50,000 mB 계산, 요청 안 함 |
| `drive 5` | `setEnable(1,false)`, `setEnable(2,false)` → `request(512)`, `request(16000)` → 화면에 `[요청 512 진행 0/60초]`, `다음 요청까지 5초` 표시 → 인터럽트 시 **원상복구** |
| **`CPU_BUSY_MATCH=1 drive 30`** | 슬롯1은 `AE 제작 중(중복 요청 안 함)` 으로 건너뛰고, 슬롯2만 `request(16000)` 실행 (중복 방지 확인) |
| **타임아웃** `requestTimeout=3` | 3초 경과 시 로그 `슬롯 1: 3초 동안 완료되지 않아 요청을 중단했습니다 (AE CPU 작업 취소됨)` + mock `CPU cancel()` 호출 확인. 카운트다운은 60→59→58초로 실시간 갱신 |
| `COMPONENT_SET=interface` + drive | `me_interface` 로 인식해 동일하게 요청/원상복구 |
| `COMPONENT_SET=none` | 크래시 없이 `ME 조회 불가(me_controller/me_interface 없음)` |
| **v1.4 값 메서드 호출 수정** | 값(userdata) 대신 **프록시 테이블**(메서드는 `__call` 테이블)로 흉내 내도록 하네스를 실제와 일치시킴 → 이전 코드가 즉시 실패해 버그를 재현, 수정 후 `request(512)`/`isBusy()`/`cancel()`/`getStack()` 모두 정상 |
| **v1.4 `diag`** | `type=`table`, .request=table, .getStack=table` 등 실제 타입을 출력해 원인 파악 가능 |
| **setup v1.2 (close 제거)** | 인터넷 핸들의 `close()` 를 **호출 불가**로 흉내 낸 하네스에서도 설치 성공(원격 해시 로컬과 일치). OpenOS `wget` 과 동일하게 이터레이터만 사용 |
| **v2.2 CPU 포함 스킵** | `CPU_ITEM_IN_LIST=1`(최종산출물에는 없고 `storedItems` 에만 있는 상황) → `list` 에서 `AE 제작 중(중복 요청 안 함)`, drive 에서 요청 1건(물)만 발생 |
| **v2.2 타임아웃=결과물 기준** | `requestTimeout=3` 하네스: `aaa…0001 슬롯1: 3초 동안 결과물이 나오지 않아 요청을 중단했습니다 (CPU 취소됨: 요청 시 기록된 CPU)` / 다른 슬롯은 `(CPU 취소됨: 사용 중 CPU 1대(대상 특정 불가))` — mock `CPU cancel()` 호출 확인 |
| **v2.2 완료 판정** | `STOCK_AFTER_REQUEST=1`(결과물이 네트워크에 들어옴) → 다음 주기에 `재고가 목표치에 도달해 요청을 완료 처리(보관 4,096)` + `충족` 표시 |
| **v2.1 상세 페이지 전환** | 3대 + `detailPerPage=2` + `pageSeconds=1` 하네스: `상세 1~2 / 3대 | 1/2 페이지` → 1초 후 `상세 3~3 / 3대 | 2/2 페이지` → 다시 1페이지로 순환 확인. `summary` 명령은 한 줄 요약, `show 2` 는 고정 상세 |
| **v2.0 다중 유지기** | 3대 구성 하네스로 검증: `유지기 3대 감지: #1:aaaa0001 #2:aaaa0002 #3:aaaa0003` → 3대 모두 takeover + `request(512)`, `request(16000)`, `request(256)` 발행 → 인터럽트 시 3대 전부 `setEnable(...,true)` 원상복구. `list` 로 슬롯 2/5·1/5·0/5 표시 |
| **v2.0 show/set/diag** | `show 2` → 그 유지기 슬롯 상세 + 요청, `set 2 1 4096 512` → `maint2.setSlot(1, …)`, `diag` → 3대 목록 + `type=table / .request=table` |
| **v2.0 bulkQuery** | `getItemsInNetwork()` 무필터 1회 호출로 1,024(기계 케이싱)·300(철괴) 를 잡아 각각 부족 계산(필터 방식도 유지) |
| `set 2 250000 32000` / `help` | (v2.0은 `set <번호> <슬롯> <유지> <배치>`) / 도움말 정상 |
| **v1.3 cfg 자동 생성** | 빈 폴더에서 실행 → `설정 파일 ae_maintainer.cfg 가 없어 기본값으로 만들었습니다` 로그 + 14개 키가 든 파일 생성 확인 |
| **v1.3 `ae_maintainer_setup.lua`** (mock) | 1회차 프로그램+cfg 설치(원본과 sha256 일치), 2회차 cfg `건너뜀(이미 있음)`, 3회차 `--force` 로 둘 다 갱신 |

---

## 8. 주의사항 · 한계

1. **컴퓨터가 꺼져 있으면 아무 것도 유지되지 않습니다.** `takeover=true` 는 유지기 자체 기능을 끄기 때문에,
   컴퓨터를 끄기 전에 `Ctrl+C` 로 프로그램을 종료(자동 복구)하는 편이 안전합니다.
   안전을 최우선하면 `takeover=false` + `batchMode=need` 로 두고, 유지기의 자체 요청과 병행하세요(중복 요청 가능성 있음).
2. **주기만 바꾸고 싶다면** OC를 쓰지 않고 `config/ae2fc.cfg` 의 `levelmaintainer { minTick=5, maxTick=120 }` 를 조정하는 방법이 더 안전합니다(현재 이 서버 값: minTick=5, maxTick=120).
3. **아이템 이름 매칭**: 유지기 슬롯의 `name` 은 `modid:itemname` 이고 네트워크 조회도 같은 형식이라 대부분 일치합니다.
   일치하지 않으면 표시이름(`label`)으로 재검색하지만, 같은 표시이름의 다른 아이템(예: 내구도/변형)이 있으면 오차가 날 수 있습니다.
4. **유체 단위는 mB** 입니다. 유지기 GUI에 넣는 숫자와 같은 단위입니다.
5. `labelFallback` 이 동작하는 경로(이름 불일치 시)는 네트워크의 전체 목록/레시피를 훑기 때문에 **네트워크가 크면 느릴 수 있습니다.**
6. 한글 표시이름은 터미널 폭 계산이 정확하지 않아 열이 조금 어긋날 수 있습니다(기능에는 영향 없음).
7. 컴퓨터 재시작 시 "이전 요청 진행 중" 추적 정보는 사라집니다(요청 자체는 AE2가 계속 처리).

## 9. 되돌리는 방법

| 대상 | 방법 |
|---|---|
| 프로그램 | OC 컴퓨터에서 `rm /usr/bin/ae_maintainer.lua` |
| 유지기 슬롯 enable | 프로그램이 종료 시 자동 복구. 강제 종료했다면 게임에서 슬롯을 다시 켜거나 `ae_maintainer` 실행 → Ctrl+C |
| 이 문서/파일(서버) | `rm -r /home/ubuntu/github/ae-maintainer` (폴더째 삭제) |
| Lua 인터프리터(검증용 설치) | `sudo apt-get remove -y lua5.3 lua5.3-dev` |

## 10. 문제 해결

| 증상 | 원인 / 해결 |
|---|---|
| `attempt to index a nil value (global 'component')` 로 즉시 종료 | **v1.0 버그**. OpenOS는 `component`/`computer`/`term` 을 **전역으로 제공하지 않습니다**(OC jar `boot/04_component.lua` 1~2행이 `require` 로 받아 로컬에서 사용). v1.1은 `local component = require("component")` 방식으로 수정. `wget -f` 로 다시 받으세요 |
| `ME 조회 불가(me_controller/me_interface 없음)` | 어댑터를 ME Controller 또는 ME Interface 에 붙이세요 |
| 유지기 자체가 안 움직임 | `takeover=true` 이면 의도된 동작(OC 단독 관리). OC를 종료하면 자동 복구 |
| `레시피 없음(Not Found)` | AE2 패턴 미등록 / CPU·재료 부족 |
| `슬롯 N: 60초 동안 완료되지 않아 요청을 중단했습니다 (해당 CPU를 못 찾아 취소 못 함…)` | 그 품목을 제작 중인 CPU 를 찾지 못한 경우입니다(AE 크래프팅 상태 GUI에서 직접 취소 가능). 재요청을 잠시 막고 싶으면 `timeoutCooldown` 값을 주세요 |
| `AE 제작 중(중복 요청 안 함)` 이 계속 뜸 | 의도된 동작입니다(`cpuSkipScope=any` — 사람이 요청한 작업도 포함). 최종 결과물만 기준으로 하려면 `cpuSkipScope=final`, 검사 자체를 끄려면 `skipIfCrafting=false` |
| **타임아웃인데 CPU 취소가 안 됨** | v2.2에서 수정(요청 시 CPU 기록 → 재탐색 → 단일 CPU 폴백). 로그의 `(CPU 취소됨: …)` / `(취소할 CPU를 찾지 못함)` 로 결과를 확인하세요. AE CPU 가 여러 대인데 대상을 못 찾으면 `cancelFallback` 을 조정하세요 |
| 취소했는데도 같은 품목이 계속 제작됨 | 유지기 자체가 다시 요청했거나(`takeover=false`), 다른 시스템이 요청한 경우입니다. `takeover=true` 확인 |
| `요청 실패: request 호출 실패(table)` | **v1.3 이하 버그**(v1.4에서 수정). OC는 값의 메서드를 "호출 가능한 테이블"로 노출하는데, v1.3 이하는 함수인지 검사해 거부했습니다. v1.4로 갱신하세요 |
| 설치 중 `attempt to call a table value (field 'close')` | **setup v1.1 이하 버그**(v1.2에서 수정). `handle.close()` 는 이 환경에서 호출 불가이며 호출할 필요도 없습니다(EOF에서 자동 종료) |
| 원인 파악이 안 됨 | `ae_maintainer diag` 를 실행해 출력을 그대로 보내주세요 |
| 유지기가 많아 한 주기가 느림 | `bulkQuery=true`(기본) 확인, `pageSize` 조정. 그래도 느리면 `interval` 을 늘리거나 `maxMaintainers` 로 분할 운영 |
| 일부 유지기가 목록에 안 보임 | `list` 출력의 `#번호`/주소 확인. 어댑터 접촉 여부·`level_maintainer` 컴포넌트 존재 여부(`diag`) 점검. `maintainerAddress` 를 설정했다면 그 1대만 표시됩니다 |

## 11. 변경 이력

| 버전 | 날짜 | 내용 |
|---|---|---|
| v2.2 | 2026-09-26 | **CPU 포함 스킵**: `cpuSkipScope=any`(기본) — CPU 의 최종산출물뿐 아니라 `storedItems`/`pendingItems`/`activeItems` 에 그 품목이 있으면(사람이 요청한 작업 포함) 요청하지 않음. **타임아웃 기준을 "결과물"로**: `requestTimeout` 초과 시 재고/작업완료를 확인해 결과물이 없으면 중단. **CPU 취소 실패 수정**: 요청 직후 그 작업의 CPU 참조를 기록 → 타임아웃 때 ①기록된 CPU ②품목 포함 CPU 재탐색 ③`cancelFallback=single`(사용 중 CPU 1대) 순으로 `cancel()` 하고 결과를 로그로 표시. 재고 도달 시 요청을 완료 처리 |
| v2.1 | 2026-09-26 | **상세 페이지 전환**: 기본 화면을 "유지기별 상세(슬롯 5줄)"로 바꾸고 **`detailPerPage`(기본 2대)씩 `pageSeconds` 마다 자동 전환**. `summary`/`detail` 명령으로 보기 전환, `show <번호>` 는 고정 상세. 설정 키 `view`,`detailPerPage` 추가 |
| v2.0 | 2026-09-26 | **다중 유지기 지원**: 어댑터에 붙은 모든 `level_maintainer` 자동 인식(주소 오름차순). 요약 화면(페이지 + 자동 전환 `pageSize`/`pageSeconds`, 별칭 `name.<주소>`), `show <번호>` 상세, `list` 전체 출력. `set` 이 `<번호> <슬롯> <유지> <배치>` 로 변경. **성능**: 보관량을 사이클당 1회 일괄 조회(`bulkQuery`, 실패 시 슬롯별 폴백), CPU 목록도 사이클당 1회. 요청 추적/타임아웃/원상복구를 유지기별로 처리 |
| v1.4 | 2026-09-26 | **긴급 수정(게임 내 요청 실패)**: OC 값(userdata)의 메서드는 함수가 아니라 **호출 가능한 테이블**로 노출되는데(v1.3 이하는 `type(fn)=="function"` 검사로 거부 → `요청 실패: request 메서드 없음`), 타입을 따지지 않고 호출하도록 변경. `getStack`/`isBusy`/`cancel` 등 모든 값 메서드에 적용. **`ae_maintainer diag`** 진단 명령 추가. 하네스를 실제와 동일하게(프록시 테이블) 개선해 회귀 방지 |
| setup v1.2 | 2026-09-26 | **설치 실패 수정**: `handle.close()` 호출 제거(이 환경은 연쇄 `__call` 미지원 → `attempt to call a table value (field 'close')`). OpenOS `wget` 과 같이 이터레이터로 읽고 EOF 에서 자동 종료 |
| v1.3.1 | 2026-09-26 | **설치 스크립트 이름 변경**: `install.lua` → **`ae_maintainer_setup.lua`**. OpenOS 내장 `install`(`/bin/install.lua`, OS 디스크 설치)과 이름이 겹쳐 PATH 상 내장 명령이 먼저 실행되는 문제 수정(스크립트 VERSION 1.1). 검증 하네스도 `tests/oc_mock_setup.lua` 로 변경 |
| v1.3 | 2026-09-26 | **설정 파일 동봉**: `ae_maintainer.cfg` 를 저장소에 포함해 인게임에서 그대로 내려받을 수 있게 함. **cfg 자동 생성**(없으면 첫 실행 때 기본값으로 생성). **`install.lua`** 추가(프로그램+설정을 한 줄로 설치, 수정한 cfg 는 보존, `--force` 지원). 검증 하네스에 설치 스크립트 테스트 추가 |
| v1.2 | 2026-09-26 | **중복 요청 방지 강화**: AE CPU 가 같은 품목을 제작 중이면(`getCpus().finalOutput` 비교) 요청하지 않고, 유지기 자체 작업 중인 슬롯도 건너뜀. **응답 없는 요청 자동 중단**: `requestTimeout`(기본 60초) 초과 시 요청 중단 + 그 CPU 작업 `cancel()`. 화면에 **다음 주기까지 남은 시간/진행 경과를 1초마다** 표시 |
| v1.1 | 2026-09-26 | **긴급 수정**: `component`/`computer`/`term` 을 전역 대신 `require` 로 받도록 변경(게임 내 즉시 크래시 원인). 네트워크 컴포넌트로 **`me_interface` 도 지원**(`me_controller` 우선). 검증 하네스가 실제 OpenOS처럼 전역을 금지하도록 개선(회귀 방지) |
| v1.0 | 2026-09-26 | 최초 공개: 유지기 슬롯 5개 읽기, 주기별 요청, takeover/원상복구, monitor/once/set 모드 |

