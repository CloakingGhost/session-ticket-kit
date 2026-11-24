# session-ticket-kit

> 비공식 프로젝트다. Anthropic 과 무관하게 만든 Claude Code 용 도구이며, "Claude" 는 Anthropic 의 상표다.

Claude Code 세션을 **티켓 번호로 관리**하는 키트. 마스터 세션 하나에만 요청하면, 마스터가 Notion 티켓을 발급하고, 열린 세션에 이관하거나 새 세션을 열고, 하위 세션의 오류·승인 대기를 대신 받아 알려 준다.

- **티켓**: 세션마다 `TK-12` 같은 번호를 발급하고 Notion DB 에 작업 요약, 브랜치, 부모 브랜치, PR 번호·상태, 병합 여부, 모델, effort 를 기록한다. PR·병합 값은 세션의 말이 아니라 `gh` 로 읽는다.
- **승인형 개설**: 새 세션은 마스터가 **첫 프롬프트 초안**을 보여 주고 사용자가 승인한 뒤에만 열린다. 모델·effort·권한 모드도 마스터가 정하고 사용자가 바꿀 수 있다.
- **번호로 지목**: 하위 세션 이름은 `[TK-12] 백업 CronJob`. 마스터에게 `TK-12 리뷰 반영해줘` 라고만 하면 된다.
- **경보**: 하위 세션이 권한 승인에서 멈추거나 API 오류가 나면 **훅**이 파일로 남기고 마스터가 즉시 알린다. 마스터만 보다가 필요한 세션에만 들어가면 된다.

## 요구 사항
- Claude Code CLI(`claude`): `--bg`, `--agent`, `--settings` 옵션과 `agents`·`logs`·`attach`·`stop`·`rm` 명령이 있는 버전(시험한 버전: 2.1.330~2.1.331)
- git, bash(Windows 는 Git for Windows 의 Git Bash), Notion 연결(claude.ai 의 Notion 커넥터 또는 이름이 `notion` 인 MCP 서버)
- `gh`(GitHub CLI): 티켓에 PR 상태를 채울 때만 필요하다(선택)

## 빠른 시작

키트는 아무 폴더에나 받는다. 설치 스크립트가 질문하고, 답한 프로젝트 폴더의 `.claude/` 에 적용한다.

| | Windows | macOS · Linux |
|---|---|---|
| 1. 받기 | `git clone https://github.com/CloakingGhost/session-ticket-kit.git <폴더>` | 같음 |
| 2. 점검 | `powershell -NoProfile -ExecutionPolicy Bypass -File check-env.ps1` | `sh check-env.sh` |
| 3. 설치 | `install.cmd` | `./install.sh` |
| 4. Notion DB | [docs/NOTION-SCHEMA.md](docs/NOTION-SCHEMA.md) 의 DDL 을 복사해 마스터에게 붙여 넣어 만들고, 나온 ID 를 `.claude/dispatcher.conf` 에 기입 | 같음 |
| 5. 마스터 열기 | `open-master.cmd` | `./open-master.sh` |
| 6. 확인 | 마스터에게 "현황" 이라고 말한다 | 같음 |

점검(2)은 읽기 전용이고 항목마다 `OK`/`WARN`/`FAIL` 과 고치는 방법을 한 줄씩 보여 준다. 자세한 순서, 경로 설정, 문제 해결은 **[docs/INSTALL.md](docs/INSTALL.md)**.

## 업그레이드와 제거
- **업그레이드**: 키트를 `git pull` 한 뒤 같은 설치 명령을 다시 실행한다. `dispatcher.conf` 의 값은 그대로 두고 빠진 키만 추가한다. 키트가 바꾼 파일은 갱신하고, **직접 고친 파일은 `.claude/dispatcher/backup/<시각>/` 에 백업한 뒤** 키트 버전으로 바꾼다.
- **제거**: `./install.sh --target <폴더> --uninstall` (설정과 실행 데이터까지 지우려면 `--purge`).
- **미리 보기**: `--dry-run` 은 아무것도 바꾸지 않고 무엇을 할지만 보여 준다. 설치는 `settings.json` 과 `.gitignore` 를 건드리지 않는다.

## 경보는 어떻게 올라오나
하위 세션이 마스터에게 보고하는 통로는 `SendMessage` 가 **아니다**. `SendMessage` 는 받는 쪽 사용자의 승인을 기다리며 보류되고, 승인하지 않으면 만료되어 사라진다. 대신 이렇게 한다.

```
하위 세션 ─훅─▶ alert.sh ─▶ .claude/dispatcher/alerts/*.txt ─▶ watch-alerts.sh (마스터의 Monitor) ─▶ 마스터의 알림·티켓 갱신
```
- `open-session.sh` 가 세션을 열 때 그 세션 전용 훅(`Notification`·`Stop`·`StopFailure`·`SessionEnd`)을 `--settings` 로 붙인다. 프로젝트의 설정 파일은 건드리지 않는다.
- 등급: `error`(API 오류), `attention`(권한 승인·질문 대기), `done`(한 턴 끝), `info`(세션 종료). `dispatcher.conf` 의 `ALERT_LEVELS` 에 든 등급만 마스터가 즉시 푸시 알림으로 알린다.
- `claude agents` 가 막힌 세션을 `waiting`(JSON 의 `state` 는 `blocked`)으로 보여 주므로 마스터는 조회로도 알 수 있다.
- 원리, 점검 방법, 알려진 한계는 [docs/ALERTS.md](docs/ALERTS.md).

## OS별 차이 (요약)
| 항목 | Windows | macOS | Linux |
|---|---|---|---|
| 필요한 셸 | PowerShell + **Git for Windows(Git Bash)**. 스크립트·훅은 Git Bash 로 돈다 | zsh/bash 기본 | bash |
| bash 버전 | Git Bash 의 5.x | 기본 3.2 로 충분 | 3.2 이상 |
| 시각 | Git Bash `date` 는 UTC → `TIMEZONE_OFFSET` 설정 필수 | `now.sh` 가 BSD 도 처리 | GNU date |
| 줄 끝 | `.sh` 는 **LF** 여야 함(`.gitattributes` 가 지정) | LF | LF |
| 따옴표 | `claude attach "[TK-12]"` | zsh/bash 는 따옴표 **필수**(없으면 글롭) | 같음 |
| WSL | WSL 안의 Claude Code 는 Windows 쪽과 별개 설치. WSL 에서 쓰려면 WSL 안에서 설치 | - | - |

전체 표는 [docs/INSTALL.md](docs/INSTALL.md).

## 구성
```
install.sh / install.ps1 / install.cmd    설치(프롬프트로 묻고 프로젝트의 .claude/ 에 적용, 업그레이드·제거·--dry-run 포함)
check-env.sh / check-env.ps1              환경 점검(읽기 전용, OK/WARN/FAIL)
payload/
  claude/                                 프로젝트의 .claude/ 로 복사된다
    agents/dispatcher.md                    마스터 에이전트
    skills/dispatch, skills/ticket-sync     요청 접수·세션 개설 / 현황 갱신
    scripts/                                open-session, alert, watch-alerts, now, check-env, lib-conf
    dispatcher.conf.example                 값이 빈 설정 예시
  root/                                   프로젝트 폴더에 놓는 open-master.sh / .ps1 / .cmd
docs/                                     INSTALL, NOTION-SCHEMA, ALERTS
tests/run-tests.sh                        설치·스크립트·점검 시험
VERSION  LICENSE  .gitattributes          버전, MIT, 줄 끝 규칙(.sh 는 LF, .cmd 는 CRLF)
```

## 문서
- [INSTALL.md](docs/INSTALL.md) — OS별 설치 절차, 경로 설정, 업그레이드, 문제 해결
- [NOTION-SCHEMA.md](docs/NOTION-SCHEMA.md) — 티켓 DB 스키마(DDL)
- [ALERTS.md](docs/ALERTS.md) — 하위 세션 → 마스터 보고(경보)의 원리와 점검

## 상태와 한계
- 시험한 환경: Windows 11(Git Bash 5.2, Windows PowerShell 5.1), Debian 12 컨테이너(bash 5.2, `sh`=dash), `bash:3.2` 컨테이너(macOS 기본 bash 와 같은 버전). **macOS 실제 환경은 확인하지 못했다**(BSD `date`·`sed`, zsh 의 글롭 처리). 컨테이너에는 Claude Code 를 설치하지 않았으므로 Linux 에서 실제 `claude` 세션을 띄우는 부분도 확인되지 않았다.
- 경보는 실제 백그라운드 세션에서 `Stop`·`SessionEnd`·권한 승인 대기(`permission_prompt`)를, 비대화 모드에서 API 오류(`StopFailure`)를 확인했고, 쉬고 있는 백그라운드 세션이 Monitor 알림으로 깨어나는 것도 확인했다. 터미널의 대화형 마스터에 대한 깨움은 직접 확인하지 못했다(자세히는 [ALERTS.md](docs/ALERTS.md)).
- 키·토큰은 어디에도 저장하지 않는다. 설정 파일(`dispatcher.conf`)에는 개인 값(Notion ID 등)만 들어가며 저장소에 올리지 않는다.
- 시험: `bash tests/run-tests.sh` (임시 폴더에서 돌고 정리한다). Linux 와 bash 3.2 는 Docker 로 돌릴 수 있다(키트 폴더에서):
  ```
  docker run --rm -v "$PWD:/kit:ro" debian:bookworm-slim bash -c 'apt-get update -qq && apt-get install -y -qq git && cp -r /kit /work && cd /work && bash tests/run-tests.sh'
  docker run --rm -v "$PWD:/kit:ro" bash:3.2 bash -c 'cp -r /kit /work && cd /work && bash tests/run-tests.sh'
  ```
- 라이선스: [MIT](LICENSE).
