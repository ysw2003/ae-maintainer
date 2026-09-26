# AE Maintainer (GTNH OpenComputers) 사용 설명서

작성: 2026-09-26 · 대상 팩: **GTNH 2.9.0-beta-3** (`GTNH_Beta_3_GOG_Addon` 서버)
작업 폴더: `/home/ubuntu/github/ae-maintainer/`

```
~/github/ae-maintainer/
├── ae_maintainer.lua              OC 컴퓨터에 넣을 프로그램 (본체)
├── ae_maintainer.cfg.example      설정 예시 (게임에서는 ae_maintainer.cfg 로 복사)
├── AE_MAINTAINER.md               이 문서
└── tests/oc_mock_test.lua         OC 없이 서버에서 돌려보는 검증 하네스
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

### `me_controller` — ME Controller (OpenComputers의 AE2 통합)

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


---

## 4. 게임 내 배치 (필수)

```
[어댑터]  ← (6면 중 아무 면) ← ME Level Maintainer   → 필요: level_maintainer
[어댑터]  ←                 ← ME Controller         → 필요: me_controller (drive 모드)
[어댑터]  ←                 ← 화면(선택)            → 출력
어댑터와 컴퓨터/케이블을 연결 (어댑터 = 컴퓨터에 붙이는 '부품 상자' 블록)
```
- 어댑터에 **해당 블록을 직접 접촉**시켜야 컴포넌트가 잡힙니다(유지기·컨트롤러는 ME 네트워크에 연결되어 있어야 함).
- 컴퓨터에서 `lua` 실행 후 `component.list("level_maintainer")` 로 잡히는지 먼저 확인하세요.
  - 비어 있으면 컴포넌트 이름이 다르거나 배치가 잘못된 것입니다.

## 5. 파일을 컴퓨터에 넣는 방법

1. 이 폴더의 `ae_maintainer.lua` 내용을 복사 (`aecode` 별칭으로 바로 볼 수 있습니다)
2. OC 컴퓨터에서 `edit /usr/bin/ae_maintainer.lua` (또는 홈에 `edit ae_maintainer.lua`)
3. 터미널에서 붙여넣기 → `Ctrl+S` 저장 → `Ctrl+W` 종료
4. 실행: `ae_maintainer` (OpenOS는 `.lua` 확장자를 자동으로 찾습니다)

부팅 시 자동 실행: OpenOS 부팅 스크립트(`/home/.shrc` 등)에 `ae_maintainer &` 를 넣으면 됩니다.
(버전에 따라 다를 수 있으니 안 되면 부팅 후 수동 실행)

## 6. 사용법

| 명령 | 동작 |
|---|---|
| `ae_maintainer` | 설정대로 상시 실행 (기본 = drive / 60초) |
| `ae_maintainer monitor` | **읽기/표시만** (요청 안 함) — 먼저 이걸로 값을 확인하세요 |
| `ae_maintainer drive 30` | 30초 주기로 직접 요청 |
| `ae_maintainer once` | 1회만 계산해서 표시 (설정 변경 없음) |
| `ae_maintainer set 1 4096 512` | 1번 슬롯: 유지 4096, 1회 제작 512 로 변경 |
| `ae_maintainer help` | 도움말 |

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

### 매 주기 판단 순서

1. 슬롯 1~5 → 품목/유지수량/배치/사용여부 읽기
2. (drive 모드면) 사용 중인 슬롯의 유지기 자동요청을 끔
3. `me_controller` 로 현재 보관량 조회 (아이템=개수, 유체=mB)
4. `부족분 = 유지수량 - 보관량` → 0 이하면 "충족"
5. 부족하면 `batchMode` 규칙으로 요청량 계산 → 레시피(`getCraftables`) 검색 → `request(요청량)`
6. 내가 넣은 요청이 아직 진행 중(`isComputing`)이면 이번 주기는 건너뜀 (중복 요청 방지)

---

## 7. 검증 결과 (실제 실행)

`tests/oc_mock_test.lua` 하네스로 OC 런타임을 흉내 내어 5가지를 실제 실행했습니다(문법 검사 포함, Lua 5.3).
실행 방법: `aetest once` / `aetest drive 5` / `STRICT=1 aetest drive 5`

| 테스트 | 결과 |
|---|---|
| `luac5.3 -p ae_maintainer.lua` | 통과 (오류 없음) |
| `once` (monitor) | 5개 슬롯 읽기 정상, 아이템 부족 3,072 / 유체 부족 50,000 mB 계산, 요청 안 함 |
| `drive 5` | `setEnable(1,false)`, `setEnable(2,false)` → `request(512)`, `request(16000)` 실행 → 다음 주기 "이전 요청 진행 중" → 인터럽트 시 `setEnable(...,true)` **원상복구** |
| `drive 5` (STRICT=1, userdata self 미주입 규약) | 동일하게 정상 동작 (두 호출 규약 모두 대응 확인) |
| `set 2 250000 32000` | `setSlot(2, 250000, 32000)` 호출 / 반환 `true` 확인 |
| `help` | 정상 출력 |

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

