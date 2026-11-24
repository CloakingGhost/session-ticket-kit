# 설치 안내

키트 폴더는 **아무 곳에나** 두면 된다. 설치 스크립트를 실행하면 질문에 답한 값으로 **프로젝트 폴더의 `.claude/`** 에 파일이 복사되고 설정 파일이 만들어진다. 설치 뒤에는 키트 폴더가 없어도 동작한다(업그레이드할 때 다시 쓴다).

## 1. OS별 차이

| 항목 | Windows 10/11 | macOS | Linux |
|---|---|---|---|
| 필요한 셸 | PowerShell(또는 cmd) + **Git for Windows(Git Bash)**. 스크립트와 경보 훅은 Git Bash 로 돈다 | zsh/bash 기본 | bash |
| bash 버전 | Git Bash 의 bash 5.x | 기본 3.2 로 충분(3.2 문법만 쓴다) | 3.2 이상 |
| 설치 실행 | `install.cmd`(실행/더블클릭) 또는 `powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1`, 또는 Git Bash 에서 `./install.sh` | `./install.sh` (실행 권한이 없으면 `bash install.sh`) | 같음 |
| 환경 점검 | 설치 전 `check-env.ps1`(키트 폴더), 설치 후 `<프로젝트>\.claude\scripts\check-env.ps1` | `sh check-env.sh` | 같음 |
| 마스터 열기 | `open-master.cmd`(내부에서 `.ps1` 호출), 또는 Git Bash 의 `./open-master.sh` | `./open-master.sh` | 같음 |
| 현재 시각 | Git Bash `date` 는 `TZ` 를 무시하고 UTC 를 보여 준다 → `TIMEZONE_OFFSET` 설정이 필수 | `date` 가 BSD 라 옵션이 다르다. `now.sh` 가 GNU/BSD 를 모두 처리한다 | GNU date |
| 줄 끝 | `.sh` 는 **LF** 여야 한다. 메모장 등으로 저장하면 CRLF 가 되어 macOS/Linux 에서 깨진다. 키트의 `.gitattributes` 가 LF 를 지정한다 | LF | LF |
| 따옴표 | PowerShell·cmd: `claude attach "[TK-12]"` | zsh/bash 는 **반드시 따옴표**(없으면 `[TK-12]` 가 파일 글롭이라 zsh 는 `no matches found`) | 같음 |
| 경보 훅이 도는 셸 | Git Bash(없으면 PowerShell 로 떨어져 `bash` 훅이 돌지 않는다 → Git for Windows 설치) | sh | sh |
| 경로 입력 | `C:\Users\me\proj`, `C:/Users/me/proj`, `/c/Users/me/proj` 모두 가능 | `/Users/me/proj`, `~/proj` | `/home/me/proj`, `~/proj` |
| WSL | WSL 안의 Claude Code 는 Windows 쪽과 **별개 설치·별개 설정**이다. WSL 에서 쓰려면 WSL 안에서 키트를 받아 설치한다 | - | - |

> 시험한 환경: Windows 11(Git Bash 5.2, Windows PowerShell 5.1), Debian 12 컨테이너(bash 5.2, `sh`=dash), `bash:3.2` 컨테이너(macOS 기본 bash 와 같은 버전). **macOS 실제 환경과 Linux 에서 `claude` 를 실제로 띄우는 부분은 확인되지 않았다.** 막히면 이슈로 알려 달라.

## 2. 설치 순서

### 0) 필요한 것
- Claude Code CLI(`claude`) — `--bg`, `--agent`, `--settings` 옵션과 `agents`/`logs`/`attach`/`stop`/`rm` 명령이 있는 버전(시험한 버전: 2.1.330~2.1.331)
- git, bash(위 표), **Notion 연결**(claude.ai 설정의 Connectors 에서 Notion 을 연결하거나, 이름이 `notion` 인 MCP 서버를 추가)
- `gh`(GitHub CLI, 선택): 티켓에 PR 상태를 채울 때만 필요하다. `gh auth login` 으로 로그인한다.

### 1) 키트 받기
```
git clone https://github.com/CloakingGhost/session-ticket-kit.git <원하는 폴더>
```

### 2) 환경 점검 (설치 전, 읽기 전용)
| OS | 명령 (키트 폴더에서) |
|---|---|
| macOS·Linux·Git Bash | `sh check-env.sh` |
| Windows PowerShell | `powershell -NoProfile -ExecutionPolicy Bypass -File check-env.ps1` |

항목마다 `[OK]`/`[WARN]`/`[FAIL]` 한 줄과 고치는 방법(`fix:`) 한 줄이 나온다. `FAIL` 을 먼저 고친다. 점검은 아무것도 설치하거나 바꾸지 않는다(Notion 확인에 `claude mcp list` 를 부르므로 몇 초 걸리고 네트워크를 쓴다).

### 3) 설치 실행
| OS | 명령 (키트 폴더에서) |
|---|---|
| macOS·Linux·Git Bash | `./install.sh` |
| Windows | `install.cmd` |

프롬프트가 순서대로 묻는다. 엔터를 누르면 `[대괄호]` 안의 기본값을 쓴다.

| 질문 | 뜻 |
|---|---|
| Project folder | `.claude/` 를 받을 **프로젝트 폴더** (아래 '경로 설정') |
| Ticket prefix | 티켓 접두어. 티켓은 `TK-12`, 세션 이름은 `[TK-12] 이름` 이 된다 |
| Git repository folder | 프로젝트 폴더 안의 git 저장소 폴더. 프로젝트 자체가 저장소면 `.`, 저장소가 없으면 비운다 |
| GitHub repository / Base branch / Test command | `owner/name`(저장소의 origin 에서 읽어 기본값으로 보여 준다) / 작업 브랜치의 부모 / 커밋 전에 통과해야 하는 명령 |
| Notion data source ID / URL | 아직 DB 가 없으면 비워 둔다(4단계에서 채운다) |
| Time zone offset | `+09:00` 형식. 이 PC 에서 읽은 값이 기본값이다(Git Bash 는 UTC 로 읽힐 수 있으니 확인) |
| Master model / effort | 마스터 세션의 모델과 effort(비우면 모델 기본값) |
| open-master launchers | 프로젝트 폴더에 `open-master.sh/.ps1/.cmd` 를 만들지 |

묻지 않고 설치하려면: `./install.sh --target <폴더> --yes --prefix TK ...`(`--help` 로 옵션 전체). 바꾸지 않고 미리 보려면 `--dry-run`.

### 4) Notion DB 만들기
[NOTION-SCHEMA.md](NOTION-SCHEMA.md) 를 따라 DB 를 만들고, 나온 data source ID 를 `<프로젝트>/.claude/dispatcher.conf` 의 `NOTION_DATA_SOURCE_ID` 에 적는다.

### 5) 설치 뒤 점검
`<프로젝트>/.claude/scripts/check-env.sh`(Windows: `check-env.ps1`)를 다시 돌린다. 이번에는 설정 파일 값(접두어, 저장소 폴더, 시간대, Notion ID)과 설치된 파일, 줄 끝까지 확인한다.

### 6) 마스터 열기
프로젝트 폴더에서 `./open-master.sh`(Windows: `open-master.cmd`). 열리면 마스터가 스스로 경보 감시를 켜고 진행 중인 티켓을 요약한다. 처음 한 번 도구 권한을 묻는 창이 뜰 수 있다.

### 7) 동작 확인
마스터에게 "현황"이라고 말한다. 티켓이 없다고 답하면 정상이다. 이어서 작은 일을 하나 맡겨 본다: 마스터가 티켓을 만들고, 모델·effort·권한 모드와 **첫 프롬프트 초안**을 보여 주며 승인을 묻는다. 승인하면 `[TK-1] 이름` 세션이 백그라운드로 열린다. 그 세션에는 `claude attach "[TK-1]"` 로 붙는다.

## 3. 경로 설정

설치 스크립트가 경로를 이렇게 처리한다.

| 입력 | 처리 |
|---|---|
| `C:\Users\me\my proj`, `C:/Users/me/my proj` | Git Bash 에서 `cygpath` 로 `/c/Users/me/my proj` 형태로 바꾼다 |
| `~/work/proj` | 홈 폴더로 펼친다 |
| `./proj`, `../proj` | 현재 폴더 기준 절대 경로로 바꾼다 |
| 공백·한글이 든 경로 | 모든 곳에서 따옴표로 다룬다 |

**거부하는 대상**(안전장치)
- 홈 폴더 자체: `<홈>/.claude` 는 모든 프로젝트가 공유하는 **사용자 수준** 설정이라 여기에 깔면 모든 세션에 영향을 준다.
- 키트 폴더 안, 파일시스템 루트, 존재하지 않는 폴더(먼저 만든다).

**저장소 폴더(`REPO_DIR`)** 는 프로젝트 폴더 기준 상대 경로다. 두 배치를 지원한다.
- 프로젝트 폴더 안에 저장소가 하나 들어 있는 배치(`REPO_DIR=myrepo`) — 시험했다.
- 프로젝트 폴더가 곧 저장소인 배치(`REPO_DIR=.`) — 설치(자동 감지)와 `check-env` 는 시험했지만, 이 배치로 실제 세션을 운영하는 것은 **확인되지 않았다.** 이때 `.claude/dispatcher.conf`·`.claude/dispatcher/` 는 `.gitignore` 에 넣는 것을 권한다.

설치된 스크립트는 자기 위치에서 프로젝트 폴더를 구하므로(`<프로젝트>/.claude/scripts/`) 절대 경로가 설정 파일에 들어가지 않는다. 프로젝트 폴더를 옮겨도 그대로 동작한다.

## 4. 무엇이 어디에 깔리나

```
<프로젝트>/
├─ open-master.sh / .ps1 / .cmd         마스터 실행 파일(이미 다른 내용의 파일이 있으면 덮어쓰지 않는다)
└─ .claude/
   ├─ agents/dispatcher.md              마스터 에이전트
   ├─ skills/dispatch/SKILL.md          요청 접수·티켓 발급·세션 개설
   ├─ skills/ticket-sync/SKILL.md       현황 갱신
   ├─ scripts/                          open-session.sh, alert.sh, watch-alerts.sh, now.sh, check-env.*, lib-conf.*
   ├─ dispatcher.conf                   이 프로젝트의 설정(개인 값. 공유하지 않는다)
   ├─ dispatcher.conf.example           값이 빈 설정 예시
   └─ dispatcher/                       실행 중 생기는 데이터: manifest.txt, prompts/, alerts/, backup/
```
설치는 `settings.json`, `.gitignore`, 위 목록 밖의 파일을 건드리지 않는다.

## 5. 업그레이드와 제거

- **업그레이드**: 키트를 `git pull` 한 뒤 같은 프로젝트로 `install` 을 다시 실행한다. `dispatcher.conf` 의 값은 그대로 두고 빠진 키만 추가한다. 키트가 바꾼 파일은 갱신하고, **직접 고친 파일은 `.claude/dispatcher/backup/<시각>/` 에 백업한 뒤** 키트 버전으로 바꾼다.
- **제거**: `./install.sh --target <폴더> --uninstall`. 설치 때 기록한 목록(manifest)의 파일 중 수정하지 않은 것만 지우고, 설정과 실행 데이터는 남긴다. `--purge` 를 더하면 그것까지 지운다.

## 6. 문제 해결

| 증상 | 원인 | 해결 |
|---|---|---|
| `claude: command not found` | PATH 에 없음 | Claude Code 설치 후 **새 터미널**을 연다. Windows 는 Git Bash 에서도 `claude` 가 보여야 한다 |
| `$'\r': command not found` | `.sh` 가 CRLF | LF 로 바꾼다. `check-env` 의 line endings 항목이 알려 준다 |
| `zsh: no matches found: [TK-12]` | 따옴표 없는 대괄호 | `claude attach "[TK-12]"` 처럼 따옴표를 쓴다 |
| 마스터가 "설치가 끝나지 않았다" | `dispatcher.conf` 가 없거나 `TICKET_PREFIX` 가 빔 | 설치를 다시 실행하거나 파일을 채운다 |
| 마스터가 "Notion data source 가 비었다" | `NOTION_DATA_SOURCE_ID` 가 빔 | [NOTION-SCHEMA.md](NOTION-SCHEMA.md) 로 DB 를 만들고 ID 를 적는다 |
| DB 만들기에서 prefix 오류 | Notion `UNIQUE_ID` 접두어는 **워크스페이스에서 한 번만** 쓸 수 있다 | 다른 접두어로 DB 를 만들고 `TICKET_PREFIX` 도 같게 바꾼다 |
| 마스터를 여는데 모델 오류(`requires usage credits` 등) | 그 모델은 요금제나 사용 크레딧이 있어야 한다 | `dispatcher.conf` 의 `MASTER_MODEL` 을 쓸 수 있는 모델로 바꾼다 |
| 경보가 마스터에 안 온다 | Git Bash 가 없어 훅이 안 돎 / `ALERTS=off` / 마스터의 감시가 꺼짐 | [ALERTS.md](ALERTS.md) 의 '점검' 을 본다 |
| 시각이 9시간 어긋남 | Git Bash `date` 는 UTC | `TIMEZONE_OFFSET` 을 설정한다 |
| 마스터→하위 세션 메시지가 전달 안 됨 | 받는 세션이 권한 모드가 달라 메시지를 보류했다. 승인하지 않으면 일정 시간 뒤 만료되어 사라진다 | `claude attach "[TK-n]"` 으로 붙어 승인한다. 하위→마스터 보고는 `SendMessage` 가 아니라 경보 훅을 쓰므로 영향이 없다 |
| 하위 세션이 멈춘 것 같은데 경보가 없다 | 경보 훅이 안 돌았거나 마스터의 감시가 꺼져 있다 | `claude agents` 에서 그 세션이 `waiting`(JSON 의 `state` 는 `blocked`)이면 권한 승인·질문 대기다. `claude attach "[TK-n]"` 으로 붙어 답한다 |

## 7. 공유할 때 주의
`.claude/dispatcher.conf`(Notion ID 등 개인 값), `.claude/dispatcher/`(경보·프롬프트 기록)는 저장소에 올리지 않는다. 이 파일들에는 키·토큰을 넣지 않게 설계했고 `check-env` 가 토큰 모양 값을 찾아 `FAIL` 로 알린다.
