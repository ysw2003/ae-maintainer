# OpenComputers AE Maintainer (GTNH)

GTNH **2.9.0-beta-3 / AE2FC** 의 `ME Level Maintainer` 블록에 등록된 **아이템·유체 / 유지 수량 / 1회 제작량** 을
OpenComputers 어댑터로 읽어서, **내가 정한 주기마다** ME 네트워크에 크래프트 요청을 넣는 Lua 프로그램입니다.

| 항목 | 내용 |
|---|---|
| 읽는 값 | 품목(아이템/유체), 유지 수량(`quantity`), 1회 제작량(`batch`), 슬롯 사용여부, 작업 진행상태 |
| **다중 유지기** | 어댑터에 붙은 **모든 `ME Level Maintainer`** 를 자동 인식(주소순). 기본 화면 = **2대씩 슬롯 5줄 상세 + 자동 페이지 전환**, `summary` 로 한 줄 요약, `show <번호>` 로 1대 고정 |
| 하는 일 | 현재 보관량 조회 → 부족분 계산 → 지정 주기(초)마다 요청 (유지기 많을 땐 보관량을 사이클당 1회 일괄 조회) |
| 중복 요청 방지 | **AE CPU 작업에 같은 품목이 들어 있으면**(최종산출물·보관·대기·제작중, **사람이 요청한 것 포함**) 새 요청을 넣지 않음 + 유지기 자체 작업 중이어도 건너뜀 |
| 응답 없는 요청 | 요청 후 `requestTimeout`(기본 **60초**) 동안 **결과물이 나오지 않으면**(재고 미도달·작업 미완료) 요청 중단 + **그 작업의 CPU 취소**(요청 시 CPU 기록 → 재탐색 → 사용 중 CPU 1대면 그 CPU) |
| 화면 표시 | 다음 요청까지 남은 시간 + 진행 중 요청 경과/타임아웃을 **1초마다** 갱신 |
| 컴포넌트 | `level_maintainer` (어댑터 + ME Level Maintainer, 여러 대), `me_controller` 또는 `me_interface` |
| 검증 환경 | GTNH 2.9.0-beta-3 · `appliedenergistics2-rv3-beta-1050-GTNH` · `ae2fc-1.5.106-gtnh` · `OpenComputers-1.12.61-GTNH` |

> AE2 기본 모드에는 이 블록이 없고, **AE2FC(`ae2fc`)가 추가**합니다. AE2FC가 OpenComputers 드라이버를 내장하고 있어
> `level_maintainer` 컴포넌트로 유지기 설정을 그대로 읽을 수 있습니다.

## 1. 인게임 설치 (권장)

OC 컴퓨터에 **인터넷 카드(Internet Card)** 를 넣은 상태에서 아래 중 하나를 실행하세요.

### 방법 A — 설치 스크립트로 한 번에 (프로그램 + 설정)

```lua
wget -f https://raw.githubusercontent.com/ysw2003/ae-maintainer/main/ae_maintainer_setup.lua /home/ae_maintainer_setup.lua && ae_maintainer_setup
```

- `ae_maintainer.lua` 와 `ae_maintainer.cfg` 를 `/home` 에 함께 설치합니다.
- **이미 수정한 설정(cfg)은 건드리지 않습니다.** 최신 기본값으로 덮어쓰려면 `ae_maintainer_setup --force`.
- ⚠️ 이름이 `install` 이 아닌 이유: OpenOS 에는 **내장 `install` 명령**(`/bin/install.lua` — OS 디스크 설치)이 있고,
  PATH 순서가 `/bin:/usr/bin:/home/bin:.` 이라 `install` 로 실행하면 **OpenOS 설치 프로그램이 실행**됩니다.

### 방법 B — 파일 직접 받기

```lua
wget -f https://raw.githubusercontent.com/ysw2003/ae-maintainer/main/ae_maintainer.lua /home/ae_maintainer.lua
wget -f https://raw.githubusercontent.com/ysw2003/ae-maintainer/main/ae_maintainer.cfg /home/ae_maintainer.cfg
```

OpenOS 셸은 `&&` 연결을 지원하므로 한 줄로도 됩니다:

```lua
wget -f https://raw.githubusercontent.com/ysw2003/ae-maintainer/main/ae_maintainer.lua /home/ae_maintainer.lua && wget -f https://raw.githubusercontent.com/ysw2003/ae-maintainer/main/ae_maintainer.cfg /home/ae_maintainer.cfg
```

### 설정 파일이 없어도 됩니다

- `ae_maintainer.cfg` 가 없으면 **첫 실행 때 프로그램이 기본값 cfg 를 자동으로 만들어 줍니다.**
- 프로그램과 cfg 를 둘 다 안 받았어도, 최소한 `ae_maintainer.lua` 만 있으면 실행은 됩니다.

```lua
ae_maintainer monitor     -- 먼저 읽기 전용(monitor)으로 값이 제대로 읽히는지 확인
ae_maintainer drive 30    -- 30초 주기로 직접 요청
```

- OpenOS 의 PATH 는 `/bin:/usr/bin:/home/bin:.` 이므로 `/home` 에 받으면 이름만으로 실행됩니다.
  (`/bin/ae_maintainer.lua` 로 받아도 됩니다)
- 인터넷 카드가 없어 `wget` 을 못 쓰면: 이 페이지의 파일 내용을 복사해
  OC 컴퓨터에서 `edit /home/ae_maintainer.lua` → 붙여넣기 → `Ctrl+S`, `Ctrl+W`
- 부팅 시 자동 실행: `/home/.shrc` 에 `ae_maintainer &` 추가 (OpenOS 버전에 따라 다를 수 있음)

## 2. 게임 내 배치

```
[어댑터] ← ME Level Maintainer   → 컴포넌트 level_maintainer (설정/수량 읽기)  [필수]
[어댑터] ← ME Controller         → 컴포넌트 me_controller   (보관량 조회 + 요청)
   또는
[어댑터] ← ME Interface          → 컴포넌트 me_interface    (동일 기능, 대체 가능)
[어댑터] ← 화면(선택)            → 상태 표시
어댑터는 컴퓨터/케이블에 연결, 각 블록은 ME 네트워크에 연결
```

- `component.list("level_maintainer")`, `component.list("me_interface")` 로 잡히는지 먼저 확인하세요.
- ME Controller 가 없어도 **ME Interface 를 붙이면 됩니다**(두 드라이버가 같은 네트워크 API를 제공).

## 3. 사용법

| 명령 | 동작 |
|---|---|
| `ae_maintainer` | 설정대로 상시 실행 (**상세 보기: 2대씩 슬롯 5줄 + 자동 페이지 전환**) |
| `ae_maintainer monitor` | 읽기·표시만 (요청 안 함) |
| `ae_maintainer drive 30` | 30초 주기로 직접 요청 |
| `ae_maintainer summary` | **한 줄 요약 보기**로 전환 (`pageSize` 대씩) |
| `ae_maintainer detail` | **상세 보기**로 전환 (`detailPerPage` 대씩) |
| `ae_maintainer show 3` | **3번 유지기 1대만** 고정 상세(슬롯 5줄) |
| `ae_maintainer list` | 전체 유지기/슬롯 상세 **1회 출력** |
| `ae_maintainer once` | 1회만 계산/표시 |
| `ae_maintainer set 2 1 4096 512` | **2번 유지기** 1번 슬롯: 유지 4096, 1회 제작 512 |
| `ae_maintainer diag` | 진단 정보(모든 유지기 + 값 타입) 출력 |
| `ae_maintainer help` | 도움말 |

### 화면 예시 (기본: 상세 2대씩)

```
== AE Maintainer 2.1 | DRIVE | 상세 1~2 / 3대 | 1/2 페이지 | 다음 주기 42초 ==
 #1 aaaa0001 창고A   부족 1 · 요청 1 · 제작 0 · 진행 1
  1 I Machine Casing       유지 4,096   배치 512    보관 1,024   -> 요청 512  [요청 512 진행 12/60초]
  2 F water                유지 100,000 배치 16,000 보관 50,000  충족
  3 (빈 슬롯)  4 (빈 슬롯)  5 (빈 슬롯)
 #2 aaaa0002 -        부족 1 · 요청 0 · 제작 1 · 진행 0
  1 I Iron Ingot           유지 2,048   배치 256    보관 300     AE 제작 중(중복 요청 안 함)
  ...
 (10초마다 다음 2대로 넘어갑니다 · 1대 남음)
```
> 페이지 전환 간격은 `pageSeconds`, 한 페이지당 대수는 `detailPerPage` 로 조정합니다.

> `#번호` 는 **어댑터 주소 오름차순** 순서입니다. 매 주기 다시 확인하므로 유지기를 추가/제거해도 자동 반영됩니다.
> cfg 에 `name.<주소>=창고A` 를 넣으면 번호 옆에 이름이 표시됩니다(주소는 `list`/`diag` 로 확인).

### 설정 파일 (`ae_maintainer.cfg`)

프로그램을 실행한 폴더(=보통 `/home`)에 `ae_maintainer.cfg` 를 두면 값을 덮어씁니다.
예시는 `ae_maintainer.cfg.example` 참고.

| 키 | 기본 | 설명 |
|---|---|---|
| `mode` | `drive` | `drive`=OC가 요청 / `monitor`=읽기만 |
| `interval` | `60` | 요청 주기(초) |
| `takeover` | `true` | 관리 슬롯의 유지기 자체 자동요청을 꺼서 중복 요청 방지 |
| `batchMode` | `need` | `need`=min(배치,부족분) / `batch`=배치 고정 / `fill`=배치 단위 올림 |
| `dryRun` | `false` | 요청 없이 계산 결과만 표시 |
| `labelFallback` | `true` | 이름 매칭 실패 시 표시이름으로 재검색 |
| `autoRestore` | `true` | 종료(Ctrl+C) 시 유지기 슬롯 enable 상태 자동 복구 |
| `skipIfCrafting` | `true` | AE CPU 작업에 같은 품목이 있으면 새 요청 안 함 |
| `cpuSkipScope` | `any` | `any`=최종산출물·보관·대기·제작중 어디에든 있으면 스킵(사람 요청 포함) / `final`=최종 결과물만 |
| `skipIfMaintainer` | `true` | 유지기 자체가 그 슬롯을 작업 중(`isDone=false`)이면 건너뜀 |
| `requestTimeout` | `60` | 요청 후 이 초 안에 **결과물이 안 나오면** 중단(+CPU 취소 시도). `0`=끔 |
| `cancelOnTimeout` | `true` | 타임아웃 시 해당 품목을 제작 중인 CPU 의 작업을 취소 |
| `cancelFallback` | `single` | 취소 대상을 못 찾았을 때: `single`=사용 중 CPU 가 1대뿐이면 취소 / `none`=취소 안 함 |
| `timeoutCooldown` | `0` | 중단 후 그 슬롯을 다시 요청하지 않을 시간(초). `0`=즉시 재시도 |
| `countdown` | `true` | 화면에 다음 주기까지 남은 시간을 1초마다 표시 |
| `view` | `detail` | 기본 화면: `detail`=유지기별 상세(슬롯 5줄) / `summary`=한 줄 요약 |
| `detailPerPage` | `2` | **상세 화면 한 페이지에 보여줄 유지기 수** (2 → 2대씩) |
| `pageSize` | `10` | 요약 화면 한 페이지에 보여줄 유지기 수 |
| `pageSeconds` | `10` | 자동 페이지 전환 간격(초). `0`=전환 안 함 |
| `maxMaintainers` | `0` | `0`=모든 유지기, N=앞에서 N대만 사용 |
| `bulkQuery` | `true` | 보관량을 사이클당 1회 전체 조회(유지기가 많을 때 훨씬 빠름) |
| `name.<주소>` | (없음) | 유지기 별칭. 예: `name.36720bcd-…=창고A` |
| `maintainerAddress` | (없음) | 특정 유지기 **1대만** 쓸 때 어댑터 주소 지정 |

## 4. 파일 구성

```
ae_maintainer.lua            프로그램 본체 (OC 컴퓨터에 넣는 파일)
ae_maintainer.cfg            기본 설정 (인게임에서 그대로 내려받아 사용 / 수정해서 씀)
ae_maintainer_setup.lua      OC용 설치 스크립트 (프로그램 + 설정 한 번에 내려받기)
AE_MAINTAINER.md             상세 문서 (컴포넌트 API 표 · 검증 근거 · 주의사항 · 되돌리기)
tests/oc_mock_test.lua       프로그램 검증 하네스 (OC 없이 실행)
tests/oc_mock_setup.lua      설치 스크립트 검증 하네스
```

검증 하네스 (Lua 5.3 설치된 PC에서):
```bash
lua5.3 tests/oc_mock_test.lua once               # 읽기 경로
lua5.3 tests/oc_mock_test.lua drive 5            # 요청 + 카운트다운 + 원상복구
lua5.3 tests/oc_mock_test.lua diag               # 진단 출력
lua5.3 tests/oc_mock_test.lua list               # 전체 유지기 상세
MAINTAINER_COUNT=3 lua5.3 tests/oc_mock_test.lua drive 10      # 다중 유지기(3대)
CPU_BUSY_MATCH=1 lua5.3 tests/oc_mock_test.lua drive 30        # 중복 요청 방지
CFG_EXTRA=$'requestTimeout=3' MAX_SLEEPS=8 lua5.3 tests/oc_mock_test.lua drive   # 타임아웃+CPU 취소
TARGET_DIR=/tmp/ocinstall lua5.3 tests/oc_mock_setup.lua       # 설치 스크립트
```
> 하네스는 실제 환경을 그대로 흉내 냅니다: ① `component`/`computer`/`term` 은 전역이 아니라 모듈,
> ② 값(userdata)은 프록시 테이블 + 메서드는 **호출 가능한 테이블**, ③ 인터넷 핸들의 `close()` 는 호출 불가.

## 5. 문제 해결

| 증상 | 원인 / 해결 |
|---|---|
| `attempt to index a nil value (global 'component')` 로 즉시 종료 | **v1.0 버그**(v1.1에서 수정). OpenOS는 `component`/`computer`/`term` 을 전역으로 주지 않고 모듈로만 줍니다. 아래 명령으로 **v1.1 이상을 다시 받으세요**: `wget -f <raw URL> /home/ae_maintainer.lua` |
| 슬롯마다 `ME 조회 불가(me_controller/me_interface 없음)` | 어댑터를 **ME Controller 또는 ME Interface** 블록에 붙이세요 |
| 슬롯이 모두 `(빈 슬롯)` | 유지기 GUI에서 슬롯에 품목이 등록됐는지 확인 |
| `레시피 없음(Not Found)` | 해당 품목의 AE2 패턴이 없거나, CPU/재료 부족 |
| `wget: This program requires an internet card to run.` | 컴퓨터에 **인터넷 카드**를 꽂으세요 |
| `install` 을 입력했더니 OS 설치(디스크 선택) 화면이 나옴 | OpenOS **내장 명령**입니다. 이 프로젝트는 `ae_maintainer_setup` 을 사용하세요(이름이 겹치지 않게 바꿨습니다) |
| `요청 실패: request 호출 실패(table)` (v1.3 이하) | v1.4에서 수정. OC는 값(userdata)의 메서드를 **호출 가능한 테이블**로 노출합니다(함수가 아님). v1.4는 타입을 따지지 않고 호출합니다 |
| **타임아웃인데 CPU 취소가 안 됨** (v2.1 이하) | v2.2에서 수정. 이제 ① 요청 직후 CPU를 기억 ② 품목 포함 CPU 재탐색 ③ `cancelFallback=single`(사용 중 CPU 1대) 순으로 취소하고, 결과를 로그에 표시합니다 |
| 사람이 요청한 작업과 겹쳐서 유지기가 안 움직임 | **의도된 동작**(`cpuSkipScope=any`). 최종 결과물만 기준으로 삼으려면 `cpuSkipScope=final` 로 설정 |
| 설치 중 `attempt to call a table value (field 'close')` (setup v1.1 이하) | v1.2(setup)에서 수정. 이 환경에서는 `handle.close()` 를 호출할 수 없어(연쇄 `__call` 미지원) 호출하지 않습니다(EOF에서 자동 종료) |
| 그래도 원인을 모르겠음 | **`ae_maintainer diag`** 실행 후 출력을 보내주세요 (값 타입·메서드 호출 가능 여부가 나옵니다) |

## 6. 주의사항

- **컴퓨터가 꺼져 있으면 아무 것도 유지되지 않습니다.** `takeover=true` 는 유지기 자체 기능을 끄므로,
  끄기 전에 `Ctrl+C` 로 종료(자동 복구)하는 편이 안전합니다.
- 주기만 바꾸고 싶다면 OC 없이 `config/ae2fc.cfg` 의 `levelmaintainer { minTick, maxTick }` 를 조정하는 방법이 더 안전합니다.
- 유체 단위는 **mB** 입니다. 화면 폭 계산 문제로 한글 표시이름의 열이 조금 어긋날 수 있습니다(동작에는 영향 없음).

자세한 API 표와 실측 근거는 [`AE_MAINTAINER.md`](AE_MAINTAINER.md) 를 참고하세요.
