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

Craftable(userdata) 메서드: `getItemStack()` · `request([amount[, prioritizePower[, cpuName]]])`
  - OC jar 실측(`NetworkControl$Craftable`): `getItemStack()` / `request()` (일부 버전은 `getStack()` — 프로그램은 둘 다 시도)
요청 반환값(상태 userdata): `isComputing()` · `hasFailed()` · `isCanceled()` · `isDone()`
  - **상태 객체에는 `cancel()` 이 없습니다.** 취소는 **CPU 값의 `cancel()`** 으로만 가능합니다(`NetworkControl$CraftingStatus` 실측).

### `getCpus()` 가 돌려주는 CPU (제작 중 감지 · 취소)

`getCpus()` 는 제작 CPU 마다 userdata 를 돌려줍니다. 실측 콜백(OC jar `NetworkControl$Cpu`):

| 메서드 | 반환 | 설명 |
|---|---|---|
| `isBusy()` | boolean | 이 CPU 가 **활발히 제작 중**인가 (대기/막힘 상태에서는 false 일 수 있음) |
| `isActive()` | boolean | CPU 가 **작업을 가진 상태**인가 (대기 중이어도 true) |
| `finalOutput()` | table 또는 nil | **이 CPU 가 만들고 있는 최종 결과물** (제작 중 감지의 핵심) |
| `activeItems()` | table | 현재 제작 중인 중간 산출물들 |
| `pendingItems()` | table | 아직 조달이 필요한 아이템들 |
| `storedItems()` | table | CPU 내부에 보관된 아이템들 |
| `cancel()` | boolean | **이 CPU 의 현재 제작 작업을 취소** |

> v1.2 는 `finalOutput()` 을 슬롯 품목과 비교해 "이미 제작 중"을 판단하고, 타임아웃 시 그 CPU 를 `cancel()` 합니다.
> 주의: 취소는 **그 품목을 제작 중인 CPU 의 작업**을 끊습니다. 같은 CPU 작업에 다른 산출물이 함께 있다면 같이 중단될 수 있습니다.

### `getCpus()` 반환 구조 (v2.5에서 바로잡은 핵심)

`getCpus()` 는 **CPU 값의 배열이 아니라 "행(row) 테이블"의 배열**을 돌려줍니다. 실제 CPU 값은 각 행의 **`.cpu` 필드**에 있습니다.
(출처: GTNH OpenComputers `NetworkControl.scala` + 설치된 `OpenComputers-1.12.61-GTNH.jar` 바이트코드에서 키 확인)

```scala
def getCpus(context, args) = {
  val buffer = new mutable.ListBuffer[Map[String, Any]]
  tile.getProxy.getCrafting.getCpus.foreach(cpu => {
    buffer.append(Map(
      "name" -> cpu.getName, "storage" -> cpu.getAvailableStorage,
      "coprocessors" -> cpu.getCoProcessors, "busy" -> cpu.isBusy,
      "cpu" -> new Cpu(tile, ...)          // ← 실제 값
    ))
  })
  buffer.result()
}
```

| 행 필드 | 형식 | 의미 |
|---|---|---|
| `name` | string | CPU 이름(예: `CPU #1`) — 화면 표시에 사용 |
| `storage` / `coprocessors` | number | 저장량 / 코프로세서 수 |
| `busy` | boolean | 그 시점의 `cpu.isBusy` |
| **`cpu`** | 값(userdata) | **실제 CPU 값** — 여기에 `finalOutput()`/`activeItems()`/`storedItems()`/`pendingItems()`/`cancel()`, `isActive()`, `isBusy()` 가 있음 |

> v2.4 이하 버그: 행 테이블을 값으로 착각해 `row.isBusy()` 같은 없는 메서드를 호출 → **모든 CPU 가 "판독 실패"로 건너뛰어져**
> 중복 요청이 계속 들어가고 취소도 실패했습니다. v2.5는 `.cpu` 를 꺼내 검사합니다.
> `ae_maintainer diag` 로 `항목 구조: type=table / .name=string / .busy=boolean / .cpu=table` 과 CPU별 내용을 확인할 수 있습니다.

### CPU 에서 읽을 수 있는 것 / 한계

| 한계 | 설명 |
|---|---|
| 진행률/남은 시간 | 제공되지 않습니다(스택 목록과 busy 여부만) |
| CPU 이름 | 행 테이블의 `name`(예: `CPU #1`)으로 표시합니다 (값 자체에는 이름 콜백이 없음) |
| `finalOutput()` | CPU 구조에 **크래프팅 모니터 타일**이 있어야 값이 나옵니다("No crafting monitor" 경로). 없으면 `nil`/오류 → 프로그램은 목록 검사로 폴백 |
| 값 형식 | 아이템은 `{name,label,damage,size}`, 유체는 `{name,label,amount}` (AE2FC 유체 제작 포함) |
| 확인 방법 | **`ae_maintainer diag`** → 행 구조 + CPU별 `finalOutput`/`activeItems`/`pendingItems`/`storedItems` 를 이름·수량까지 출력 |

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
| `cancelAfter` | `600` | OC 가 요청한 작업이 이 초를 넘기면 취소. `0`=끔 (플레이어 작업은 대상 아님) |
| `cancelTarget` | `recorded` | 취소할 CPU 선택 `recorded`(요청 시 기억한 CPU만) / `single`(기억이 없으면 사용 중 CPU 1대) / `none`(취소 안 함) |
| `cancelCooldown` | `0` | 취소 후 그 슬롯 재요청까지 대기(초). `0`=즉시 재시도 |
| `skipIfAnyCpuBusy` | `false` | `true`=사용 중 CPU 가 하나라도 있으면 모든 요청 보류 |
| `countdown` | `true` | 화면에 다음 주기까지 남은 시간을 1초마다 표시 |
| `view` | `detail` | 기본 화면 종류: `detail`(유지기별 슬롯 5줄) / `summary`(한 줄 요약) |
| `detailPerPage` | `2` | 상세 화면 한 페이지당 유지기 수 (2 → 2대씩) |
| `pageSize` / `pageSeconds` | `10` / `10` | 요약 화면 페이지당 유지기 수 / 자동 페이지 전환 간격(초, 0=끔) |
| `maxMaintainers` | `0` | `0`=모든 유지기, N=앞에서 N대만 |
| `bulkQuery` | `true` | 보관량을 사이클당 1회 전체 조회(유지기 많을 때 빠름). 실패 시 자동으로 슬롯별 조회 |
| `name.<주소>` | 없음 | 유지기 별칭 (예: `name.36720bcd-…=창고A`) |
| `maintainerAddress` | 없음 | 특정 유지기 1대만 사용할 때 어댑터 주소 |

### 매 주기 판단 순서

1. `component.list("level_maintainer")` 로 **모든 유지기** 열거(주소 오름차순) → 각 유지기의 슬롯 1~5 읽기
2. (drive 모드면) **모든 유지기**의 사용 중 슬롯 자동요청을 끔(takeover)
3. 보관량: `bulkQuery=true` 면 `getItemsInNetwork()`·`getFluidsInNetwork()` 를 **사이클당 1회** 호출해
   로컬에서 이름/표시이름으로 합산(유지기가 많을 때 빠름). 실패하거나 끄면 슬롯별 개별 조회로 자동 폴백
4. **만료된 요청 정리/취소**(`cancelAfter`) — OC 가 넣은 요청만 대상
5. 각 슬롯: `부족분 = 유지수량 - 보관량` → 0 이하면 "충족"
6. 부족하면 아래 순서로 **중복 요청을 걸러냄**
   1. 내가 넣은 요청이 아직 진행 중(`isComputing`) → 건너뜀
   2. 취소 후 대기(`cancelCooldown`) → 건너뜀
   3. 유지기 자체가 그 슬롯 작업 중(`isDone=false`) → 건너뜀
   4. **AE CPU 작업에 그 품목이 포함**(`cpuSkipScope=any`: `finalOutput` + `storedItems`/`pendingItems`/`activeItems`) → 건너뜀 (사람이 요청한 작업이어도 동일)
      - `getCpus()` 의 **행 테이블에서 `.cpu` 값**을 꺼내 검사합니다.
      - **`isBusy` 여부와 무관하게** 모든 CPU 의 목록을 읽습니다(출력 막힘/재료 대기로 `isBusy=false` 인 CPU 도 포함). 스냅샷은 사이클당 1회만 읽습니다.
      - CPU 내용을 읽지 못하면 이 검사는 자동으로 건너뛰어집니다(오류 없음).
7. 위에 해당 없으면 `batchMode` 규칙으로 요청량 계산 → 레시피(`getCraftables`) 검색 → `request(요청량)`
   → 요청 시각과 **그 작업의 CPU** 를 기억해 둠(만료 시 취소 대상)

### 요청 만료 → 자동 취소 (시간 기준)

**CPU 제작 현황(제작중 수치 등)을 읽지 못하는 환경에서도 동작**하도록, 판정은 시간만 씁니다.

| 항목 | 동작 |
|---|---|
| 대상 | **OC 가 요청한 작업만**. 플레이어가 직접 넣은 작업은 추적 목록에 없으므로 건드리지 않음 |
| 기준 | 요청을 넣은 시각부터 `cancelAfter`(기본 **600초 = 10분**, `0`=끔) |
| 확인 시점 | 대기 중 **1초마다** + 각 주기 시작 시 (만료 즉시 취소) |
| 완료 확인 | 만료 시점에 재고가 유지수량에 도달했으면 **취소하지 않고 완료 처리** |
| 취소 방법 | 요청 직후 기억해 둔 CPU 값의 `cancel()` 호출 (AE GUI 의 그 작업 취소와 동일) |
| CPU 기억 방법 | ① CPU 목록에서 그 품목이 보이면 그 CPU ② 안 보이면 **요청 전후로 `busy` 가 바뀐 CPU** (둘 다 실패하면 CPU 를 특정하지 못한 것으로 보고 취소하지 않음) |
| 취소 대상 범위 | `cancelTarget=recorded`(기본)=기억한 그 CPU만 / `single`=기억이 없을 때 사용 중 CPU 가 1대뿐이면 그 CPU / `none`=취소 안 함 |
| 취소 후 | 그 슬롯 추적 해제. `cancelCooldown`(기본 0)초 동안은 재요청하지 않음 |

로그 예:
```
[11:49:53] aaaa0001 슬롯1: 요청 후 600초가 지나 중단했습니다 (CPU 취소됨: 요청 시 기록된 CPU)
```
CPU 를 특정하지 못하면:
```
[11:49:53] aaaa0001 슬롯2: 요청 후 600초가 지나 중단했습니다 (취소 대상 CPU 를 특정하지 못해 취소하지 않았습니다)
```

### 매 초 동작 (대기 중)

- 화면을 다시 그려 **다음 요청까지 남은 시간**과 진행 중 요청의 `경과/남은 시간` 을 실시간 표시
  (`[요청 512 · 132초 경과 · 468초 후 취소]`)
- 만료된 요청이 있으면 **즉시 취소하고 다음 주기로 넘어갑니다**(화면도 바로 갱신)

---

## 7. 검증 결과 (실제 실행)

`tests/oc_mock_test.lua` 하네스로 OC 런타임을 흉내 내어 실제 실행했습니다(문법 검사 포함, Lua 5.3).
실행 방법: `aetest once` / `aetest drive 5` / `aetest diag`

| 테스트 | 결과 |
|---|---|
| **v4.0 시간 기준 취소** | `cancelAfter=60` + `interval=600`: 60초에 `aaaa0001 슬롯1: 요청 후 60초가 지나 중단했습니다 (CPU 취소됨: 요청 시 기록된 CPU)` + mock `CPU cancel()` 호출 확인. 화면 줄이 `[요청 512 · 1초 경과 · 59초 후 취소]` → `[요청 512 · 9초 경과 · 51초 후 취소]` 로 **매 초 갱신** |
| **v4.0 취소 끄기 / 대상** | `cancelAfter=0` → 취소 0건, `cancelTarget=none` → `(cancelTarget=none: 취소하지 않음)` 로그 + `cancel()` 미호출 |
| **v4.0 CPU 특정 실패 → 취소 안 함** | `CPU_PRE_BUSY=1`(요청 전부터 사용 중) + `CPU_UNREADABLE=1`(내용 조회 실패) + `cancelTarget=recorded` → `(취소 대상 CPU 를 특정하지 못해 취소하지 않았습니다)`, `cancel()` 미호출 |
| **v4.0 `cancelTarget=single`** | 같은 상황에서 `(CPU 취소됨: 사용 중 CPU 1대(대상 특정 불가))` + `cancel()` 호출 확인 |
| **v4.0 플레이어 작업 보호** | `CPU_BUSY_MATCH=1`(우리가 넣지 않은 작업이 CPU 점유) + `cancelAfter=60` → 그 슬롯은 `AE 제작 중(중복 요청 안 함)`, 60초가 지나도 **`cancel()` 미호출**(`cpuCanceled=false`) |
| **v4.0 완료 확인** | `STOCK_AFTER_REQUEST=1`(만료 시점에 재고가 목표치) → `요청 후 60초 — 재고가 목표치에 도달해 요청을 완료 처리(보관 4,096)` (취소하지 않음) |
| **v4.0 회귀** | `drive 5` 요청 2건 / `CPU_BUSY_MATCH=1` 겹침 스킵 1건 / 3대 유지기 3건 / setup 설치 후 해시 일치(v4.0) |
| `luac5.3 -p` | `ae_maintainer.lua` · `tests/oc_mock_test.lua` · `tests/oc_mock_setup.lua` 통과 |
| `once` (monitor) | 5개 슬롯 읽기 정상, 아이템 부족 3,072 / 유체 부족 50,000 mB 계산, 요청 안 함 |
| `drive 5` | `setEnable(1,false)`, `setEnable(2,false)` → `request(512)`, `request(16000)` 표시 → 인터럽트 시 **원상복구** |
| `COMPONENT_SET=interface` + drive | `me_interface` 로 인식해 동일하게 요청/원상복구 |
| `COMPONENT_SET=none` | 크래시 없이 `ME 조회 불가(me_controller/me_interface 없음)` |
| **v1.4 값 메서드 호출 수정** | 값(userdata) 대신 **프록시 테이블**(메서드는 `__call` 테이블)로 흉내 내도록 하네스를 실제와 일치시킴 → 이전 코드가 즉시 실패해 버그를 재현, 수정 후 `request(512)`/`isBusy()`/`cancel()`/`getStack()` 모두 정상 |
| **v1.4 `diag`** | `type=`table`, .request=table, .getStack=table` 등 실제 타입을 출력해 원인 파악 가능 |
| **setup v1.2 (close 제거)** | 인터넷 핸들의 `close()` 를 **호출 불가**로 흉내 낸 하네스에서도 설치 성공(원격 해시 로컬과 일치). OpenOS `wget` 과 동일하게 이터레이터만 사용 |
| **v3.1 재고량 기준 제거** | `CPU_CRAFT_COUNT` 없이(=CPU 수치 못 읽음) 부분 납품 후 정지시킨 `PARTIAL_AFTER_REQUEST=1` + `stallCycles=2` → **취소 0건**, 화면에 `제작중 수치 없음(정지 감지 제외)` 표시(재고는 판정에 쓰지 않음). `CPU_CRAFT_COUNT=52` 고정 케이스는 그대로 2회 루프 후 취소 1건, `CPU_CRAFT_DECREASE=1`(진행 중)은 취소 0건 |
| **v3.0 정지 감지(CPU 수치 기준)** | `CPU_CRAFT_COUNT=52`(고정) + `stallCycles=2`: `[요청 512 · 제작중 52(activeItems, CPU1 CPU #1) · 정지 1/2회]` → 2회 루프째 `2회 루프 동안 진행이 없어(제작중 52(activeItems, CPU1 CPU #1)) 요청을 중단했습니다 (CPU 취소됨: 요청 시 기록된 CPU)` |
| **v3.0 진행 중이면 취소 안 함** | `CPU_CRAFT_DECREASE=1`(수치가 매 루프 52→42→32… 변함) → 그 슬롯은 **정지 0/2회 유지**(취소 없음) |
| **v3.0 타임아웃 제거** | `requestTimeout`(절대 시간) 설정·코드 삭제(`cancelOnTimeout`→`cancelOnStall`, `timeoutCooldown`→`stallCooldown` 로 이름 변경) |
| **v2.5 getCpus 구조 수정** | 하네스를 실제와 동일하게(`getCpus()` = 행 테이블 목록, 값은 `.cpu`) 바꾼 뒤: 품목이 **CPU#2** 에만 있어도 `AE 제작 중(중복 요청 안 함) finalOutput(CPU2 CPU #2)` / `storedItems(CPU2 CPU #2)` 로 스킵, `busy=false, active=true` 상태에서도 스킵, 신규 요청은 물 1건만 |
| **v2.4 isBusy 무관 스캔** | `CPU_NOT_BUSY=1`(isBusy=false, isActive=true, `storedItems` 에만 품목) 재현 → 스킵, `diag` 에서도 `busy=false active=true` + `storedItems : 1개: …` 확인 |
| **v2.3 정지 감지** (재고 기준, v3.1에서 제거) | `PARTIAL_AFTER_REQUEST=1`(부분 납품 30개 후 정지) + `stallCycles=2`: `2주기 동안 진행이 없어(보관 1,084 · 생산 60/512) 요청을 중단했습니다` + mock `cancel()` 호출 확인 |
| **v2.2.1 diag 강화** | `ae_maintainer diag` 가 CPU별 `finalOutput`/`activeItems`/`pendingItems`/`storedItems` 를 이름·수량까지 출력 (예: `storedItems : 1개: Machine Casing x128 [gregtech:gt.blockmachines]`) |
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
| `슬롯 N: 60초 동안 완료되지 않아 요청을 중단했습니다 (해당 CPU를 못 찾아 취소 못 함…)` (v2.5 이하) | v4.0은 시간 기준 `cancelAfter`(기본 600초)로 취소합니다. 로그의 `(CPU 취소됨: …)` / `(취소 대상 CPU 를 특정하지 못해 취소하지 않았습니다)` 로 결과를 확인하세요 |
| `AE 제작 중(중복 요청 안 함)` 이 계속 뜸 | 의도된 동작입니다(`cpuSkipScope=any` — 사람이 요청한 작업도 포함). 최종 결과물만 기준으로 하려면 `cpuSkipScope=final`, 검사 자체를 끄려면 `skipIfCrafting=false` |
| `CPU 제작중 수치 없음(정지 감지 제외)` 로 표시됨 (v3.x에서만) | v4.0에서는 CPU 내용을 읽지 않아도 시간 기준으로 취소하므로 이 표시가 나오지 않습니다. `cancelAfter`(기본 10분)를 확인하세요 |
| 재고가 그대로인데 취소가 안 됨 | `cancelAfter`(기본 600초)를 넘겨야 취소합니다. `cancelAfter=0` 이면 취소 기능이 꺼진 상태입니다 |
| 취소했는데도 같은 품목이 계속 제작됨 | 유지기 자체가 다시 요청했거나(`takeover=false`), 다른 시스템이 요청한 경우입니다. `takeover=true` 확인 |
| `요청 실패: request 호출 실패(table)` | **v1.3 이하 버그**(v1.4에서 수정). OC는 값의 메서드를 "호출 가능한 테이블"로 노출하는데, v1.3 이하는 함수인지 검사해 거부했습니다. v1.4로 갱신하세요 |
| 설치 중 `attempt to call a table value (field 'close')` | **setup v1.1 이하 버그**(v1.2에서 수정). `handle.close()` 는 이 환경에서 호출 불가이며 호출할 필요도 없습니다(EOF에서 자동 종료) |
| 원인 파악이 안 됨 | `ae_maintainer diag` 를 실행해 출력을 그대로 보내주세요 |
| 유지기가 많아 한 주기가 느림 | `bulkQuery=true`(기본) 확인, `pageSize` 조정. 그래도 느리면 `interval` 을 늘리거나 `maxMaintainers` 로 분할 운영 |
| 일부 유지기가 목록에 안 보임 | `list` 출력의 `#번호`/주소 확인. 어댑터 접촉 여부·`level_maintainer` 컴포넌트 존재 여부(`diag`) 점검. `maintainerAddress` 를 설정했다면 그 1대만 표시됩니다 |

## 11. 변경 이력

| 버전 | 날짜 | 내용 |
|---|---|---|
| v4.0 | 2026-09-26 | **시간 기준 취소로 전환(CPU 제작 현황 판독 제거)**: 현장에서 CPU 제작 현황(`activeItems` 등)을 읽지 못해, 정지 감지(제작중 수치 비교)를 **전부 삭제**하고 **요청 후 `cancelAfter`(기본 600초=10분, 0=끔)가 지나면 취소**하도록 변경. 취소 대상은 **OC 가 요청한 작업만**(요청 직후 그 작업의 CPU 를 ① CPU 목록의 품목 매칭 ② 요청 전후 `busy` 변화 로 기억)이며, 플레이어가 넣은 작업은 건드리지 않음(`cancelTarget=recorded` 기본). 만료 시점에 재고가 유지수량에 도달했으면 취소하지 않고 완료 처리. 확인은 **대기 중 1초마다** + 주기 시작 시. 설정 키: `cancelAfter`/`cancelTarget`/`cancelCooldown` (기존 `stallCycles`/`cancelOnStall`/`cancelFallback`/`stallCooldown` 삭제). 화면은 `[요청 512 · 132초 경과 · 468초 후 취소]` 로 매 초 갱신. `diag` 는 레시피 값 메서드를 `getItemStack()`(구버전 `getStack`)로 확인하고 CPU별 `cancel=` 가능 여부도 표시 |
| v3.1 | 2026-09-26 | **정지 판정에서 네트워크 재고량 제거**: 재고는 소비·보충으로 수시로 크게 변해 판정 기준으로 쓸 수 없어, 보관량 비교 폴백(및 `stallMinProgress` 설정)을 **삭제**. 이제 정지 판정은 **CPU 안 제작중 수치(`Crafting: N`) 단일 기준**이며, 그 수치를 읽을 수 없는 품목(유체 등)은 **정지 감지 대상에서 제외**(화면에 `CPU 제작중 수치 없음(정지 감지 제외)` 표시). 작업 완료/취소 판정은 추적 중인 작업 상태 객체(`isDone`/`isComputing`)가 계속 담당 |
| v3.0 | 2026-09-26 | **타임아웃 제거 + 정지 감지를 CPU 수치 기준으로**: 절대 시간(`requestTimeout`) 감시를 삭제하고, 요청 루프마다 **CPU 안 그 품목의 제작중 수치**(`activeItems`→`storedItems`→`pendingItems`, AE GUI의 `Crafting: N` 에 해당)를 비교 → `stallCycles`(기본 2회 루프) 동안 **그대로면** 즉시 중단 + CPU 취소(수치가 변하면 진행 중으로 보고 취소하지 않음). `cancelOnTimeout`→`cancelOnStall`, `timeoutCooldown`→`stallCooldown` 로 키 이름 변경 |
| v2.5 | 2026-09-26 | **중복 요청·취소 실패의 진짜 원인 수정**: GTNH OpenComputers 소스 확인 결과 **`getCpus()` 는 CPU 값 배열이 아니라 "행 테이블" 배열**이고 실제 값은 **`.cpu` 필드**에 있습니다(`{name, storage, coprocessors, busy, cpu}` — 설치된 jar 바이트코드로 키 확인). 이전 버전은 행을 값으로 착각해 `row.isBusy()` 같은 없는 메서드를 호출 → **모든 CPU 를 판독 실패로 건너뛰어** 중복 요청이 계속 들어가고 취소도 못 했습니다. v2.5는 `.cpu` 를 꺼내 검사하고, 행의 `name`(CPU #1 …)을 스킵/취소 로그에 표시합니다 |
| v2.4 | 2026-09-26 | **CPU 스캔에서 `isBusy()` 조건 제거**: AE2 는 **출력 막힘/재료 대기 상태에서 `isBusy=false`, `isActive=true`** 가 될 수 있어, 그때 그 품목이 CPU 안에 있는데도 감지가 안 되는 문제를 완화. 모든 CPU 의 `finalOutput`·3개 목록을 사이클당 1회 스냅샷으로 읽음. `skipIfAnyCpuBusy` 도 busy/active 둘 다 반영 |
| v2.3 | 2026-09-26 | **진행 정지 감지 → 자동 취소**: 요청 시점·직전 주기의 보관량을 기록해 매 주기 비교 → `stallCycles`(기본 2주기) 동안 생산량이 늘지 않으면 즉시 중단 + CPU 취소(예: 64개 요청 중 30개만 나오고 멈춘 경우). 화면에 `생산 30/64 · 정지 1/2주기` 표시. **중복 요청 방지 보강**: 상태 객체를 못 읽어도 기록된 CPU가 busy면 진행 중으로 간주, `skipIfAnyCpuBusy` 옵션 추가 |
| v2.2.1 | 2026-09-26 | **진단 강화**: `ae_maintainer diag` 가 CPU별 `finalOutput`/`activeItems`/`pendingItems`/`storedItems` 를 **이름·수량까지** 출력(OC로 CPU 작업 내용을 어디까지 읽을 수 있는지 바로 확인 가능) |
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

