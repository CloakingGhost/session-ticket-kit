# 경보: 하위 세션이 마스터에게 보고하는 법

목표는 **마스터 세션만 보고 있다가, 문제가 생긴 하위 세션에만 들어가는 것**이다. 그래서 하위 세션이 막히거나 오류가 나면 마스터에게 올라오게 했다.

## 왜 `SendMessage` 가 아닌가
세션 사이 메시지(`SendMessage`)는 받는 쪽 사용자의 승인을 기다리며 **보류**될 수 있고, 보류 사실이 받는 쪽 화면에 뚜렷이 나타나지 않았다(실제로 겪음). 승인하지 않으면 일정 시간 뒤 **만료되어 사라지고**, 보낸 쪽에는 "승인되지 않아 전달되지 않았다"는 안내만 온다(2026-11-24 확인). 그래서 보고 통로로 쓰지 않는다. 이 키트는 모델이 아니라 **훅**(Claude Code 가 자동으로 실행하는 스크립트)과 **파일**로 보고한다.

## 흐름
```
하위 세션 ──훅──▶ alert.sh ──▶ .claude/dispatcher/alerts/*.txt ──▶ watch-alerts.sh(마스터의 Monitor)
                                                                       │ 한 줄 = 알림 하나
                                                                       ▼
                                       마스터: 티켓 상태 갱신 + 대화창 알림 + PushNotification
```
1. `open-session.sh` 가 하위 세션을 열 때 `--settings` 로 **그 세션 전용** 훅을 붙인다(프로젝트의 `settings.json` 은 건드리지 않는다).
2. 훅은 모델이나 권한 질문과 무관하게 실행된다. `alert.sh` 가 경보 파일을 쓴다.
3. 마스터는 시작할 때 Monitor 도구로 `watch-alerts.sh` 를 건다. 새 경보 파일이 생기면 한 줄을 출력하고, 그 한 줄이 마스터 대화창의 알림이 된다.
4. 마스터가 `ALERT_LEVELS` 에 든 등급은 즉시 알리고(`PushNotification`), 티켓 상태를 `입력 대기` 등으로 갱신한다. 사용자는 마스터만 보다가 `claude attach "[TK-12]"` 로 해당 세션에 들어간다.

## 훅 이벤트와 등급

| 훅 이벤트 | 언제 | 경보 level / type |
|---|---|---|
| `Notification` `permission_prompt` 등 | 권한 승인이나 질문에 막혀 약 6초 기다림 | `attention` |
| `StopFailure` | API 오류로 턴이 끝남(한도, 결제, 인증, 서버 오류 …) | `error` (type = 오류 종류) |
| `Stop` | 에이전트가 한 턴을 마침(끝났거나 질문을 남김). 본문에 마지막 메시지의 끝 300자 | `done` |
| `SessionEnd` | 세션 종료(`reason=other` 는 정상 종료도 포함) | `info` |

`idle_prompt` 는 `Stop` 경보와 겹쳐서 쓰지 않는다. 같은 티켓·이벤트·종류의 경보가 60초 안에 또 오면 건너뛴다.

## 설정
`.claude/dispatcher.conf`
- `ALERT_LEVELS=error,attention` — 마스터가 즉시 푸시 알림을 보낼 등급(`done` 을 넣으면 한 턴 끝날 때마다 알린다).
- `ALERTS=off` — 하위 세션에 훅을 붙이지 않는다.

## 경보 파일
`.claude/dispatcher/alerts/<epoch>-<접두어><번호>-<이벤트>-<pid>.txt`, `KEY=값` 줄들(level, ticket, event, type, time_utc, session_id, text). 마스터가 읽은 파일은 `alerts/seen/` 으로 옮겨진다. **본문은 로컬 파일에만** 남고 어디로도 보내지 않는다. 키·비밀값은 세션이 출력하지 않는 것이 전제다.

## 직접 시험
```
printf '%s' '{"hook_event_name":"Notification","message":"test","notification_type":"permission_prompt"}' | bash .claude/scripts/alert.sh 12 notification
bash .claude/scripts/watch-alerts.sh --once
```
두 번째 명령이 `ALERT level=attention ticket=TK-12 ...` 한 줄을 출력하면 파일 경로는 정상이다.

## 점검 (경보가 안 올 때)
| 확인 | 방법 |
|---|---|
| 훅이 붙었나 | `DISPATCH_PRINT_SETTINGS=1 bash .claude/scripts/open-session.sh 1 x sonnet low plan </dev/null` 이 JSON 을 출력하는지 |
| Windows 에 Git Bash 가 있나 | `check-env.ps1` 의 bash 항목. 없으면 훅의 `bash` 명령이 돌지 않는다 |
| 마스터의 감시가 켜져 있나 | 마스터에게 "경보 감시 켜져 있어?" 라고 묻는다. 꺼졌으면 다시 걸게 한다(감시는 최대 30분마다 만료돼 다시 건다) |
| 파일은 생기는데 마스터가 모름 | `watch-alerts.sh --once` 를 직접 돌려 본다. 마스터가 `ticket-sync` 로 같은 일을 할 수 있다 |

## 알려진 한계
- 훅은 한 번에 약 2초(Windows 에서는 bash 시작 시간이 대부분) 걸리고 제한시간은 10초다.
- 마스터의 감시(Monitor)는 최대 30분마다 만료되므로 마스터가 다시 걸어야 한다(만료 알림이 온다). 감시가 꺼져 있는 동안 생긴 경보도 파일로 남으므로 마스터가 `ticket-sync` 로 읽을 수 있다.
- **확인한 것(Windows 11, 2026-11-23)**: 실제 백그라운드 세션(`claude --bg`)에서 `Stop` 훅이 `done` 경보를(마지막 메시지 본문 포함), `SessionEnd` 훅이 `info` 경보를 썼고, `--name` 에 대괄호·한글·공백이 든 이름도 받는다. 비대화 모드(`claude -p`)에서도 같다.
- **권한 승인 대기(`permission_prompt`) 경보도 확인했다(2026-11-24)**: `mkdir` 처럼 승인이 필요한 명령에서 멈춘 백그라운드 세션이 약 12초 뒤 `attention` 경보를 썼다. 같은 세션을 `claude agents --json` 은 `status: waiting`, `state: blocked` 로 보여 준다(훅 없이도 조회로 알 수 있고 `ticket-sync` 가 쓴다). `claude logs "[TK-n]"` 의 대괄호 부분 일치 조회도 동작한다. 참고: `echo` 같은 읽기 전용 명령은 권한 질문 없이 자동 실행되므로 이 경보 시험에는 쓸 수 없다.
- **API 오류(`StopFailure`) 경보도 확인했다(2026-11-24)**: 존재하지 않는 모델 이름으로 호출해 API 오류(`model_not_found`)를 일으키자 `StopFailure` 훅이 실제 페이로드(`error`, `last_assistant_message`)를 받았고 `error` 경보가 만들어졌다. 오류 때는 `Stop` 훅이 돌지 않고 `StopFailure` 만 돈다(문서와 같다). 비대화 모드(`claude -p`)에서 확인했다. 사용량 한도·결제·인증 오류도 같은 훅 이벤트를 쓰고 `error` 값만 다르다.
- **쉬고 있는 세션이 Monitor 알림으로 깨어나는 것도 확인했다(2026-11-24)**: 백그라운드 세션이 Monitor 를 걸고 턴을 끝내 쉬는 중에 감시 대상 파일이 생기자, 사람의 입력 없이 스스로 깨어나 알림을 처리했다(약 2초). 마스터와 같은 알림 메커니즘이다. 터미널에서 직접 여는 대화형 마스터는 조작할 수 없어 같은 방식으로는 확인하지 못했다.
- **Linux 실행을 확인했다(2026-11-24)**: 일회용 Debian 12 컨테이너(bash 5.2, `sh`=dash)와 macOS 기본 bash 와 같은 버전인 `bash:3.2` 컨테이너에서 키트 시험이 모두 통과했다(플랫폼에 해당하지 않는 시험은 건너뛴다). 이 컨테이너들은 GNU/busybox 유틸리티를 쓴다.
- **확인하지 못한 것**: macOS 실제 환경(BSD `date`·`sed`, `now.sh` 의 BSD 분기, zsh), Linux 에서 `claude` 를 실제로 띄운 세션(컨테이너에 Claude Code 를 설치하지 않았다), 대화형 터미널 마스터의 Monitor 깨움.
- 권한 승인에서 멈춘 세션을 풀어 주는 것은 사람이다. 경보는 "멈췄다"를 알릴 뿐이다.
