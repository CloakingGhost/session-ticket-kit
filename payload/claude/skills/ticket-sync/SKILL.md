---
name: ticket-sync
description: 마스터 세션(dispatcher 에이전트) 전용. 열린 티켓의 현황을 원천(gh, 세션 목록, 세션 로그, 경보)에서 읽어 Notion 티켓을 갱신하고 사용자에게 표로 보고한다. "현황", "어디까지", "병합됐나", "정리해줘" 같은 요청이나 하위 세션의 경보(done·error·attention)가 올 때 쓴다. 하위 세션(이름 앞에 번호 배지가 붙은 세션)은 쓰지 않는다.
allowed-tools:
  - Bash(bash .claude/scripts/now.sh)
  - Bash(bash .claude/scripts/watch-alerts.sh --once)
  - Bash(claude agents *)
  - Bash(claude logs *)
  - Bash(gh pr list *)
  - Bash(gh pr view *)
  - Bash(gh repo view *)
  - Bash(git -C * branch *)
  - Bash(git -C * worktree list *)
  - Bash(pwd)
  - mcp__claude_ai_Notion__notion-fetch
  - mcp__claude_ai_Notion__notion-update-page
  - mcp__claude_ai_Notion__notion-query-data-sources
  - mcp__notion__notion-fetch
  - mcp__notion__notion-update-page
  - mcp__notion__notion-query-data-sources
---

# ticket-sync — 원천에서 읽어 티켓을 갱신한다

나는 `dispatcher` 에이전트(마스터)인가? 아니면 멈춘다. `.claude/dispatcher.conf` 를 읽었는지 확인한다(`<PREFIX>`=`TICKET_PREFIX`, `<REPO_DIR>`, `<GITHUB_REPO>`, `<DATA_SOURCE>`=`NOTION_DATA_SOURCE_ID`).
**원칙: 값은 하위 세션의 자기 보고가 아니라 원천에서 읽는다.** 세션이 "PR 올렸다"고 해도 `gh` 로 확인되기 전에는 쓰지 않는다. GitHub 저장소 이름은 `<GITHUB_REPO>`, 비어 있으면 `gh repo view --json nameWithOwner -q .nameWithOwner` 를 `<REPO_DIR>` 안에서 실행해(`git -C` 가 아니라 해당 폴더에서) 얻는다. `<REPO_DIR>` 가 비어 있으면 PR 단계(4)는 건너뛴다.

## 1. 시각

`bash .claude/scripts/now.sh` 를 실행한다. `utc=…` 은 Notion 날짜 칸에, `local=…` 은 진행 기록 문장에 쓴다(Git Bash 의 `date` 는 UTC 라서 직접 `date` 를 쓰지 않는다).

## 2. 대상 티켓

`notion-query-data-sources` 로 `상태` 가 `진행`·`입력 대기`·`승인 대기` 인 티켓을 읽는다(data source `<DATA_SOURCE>`). 사용자가 특정 번호를 말했으면 그것만(번호로 찾는 방법은 `dispatcher` 의 '티켓 번호로 지목하면').
`승인 대기` 인데 세션 이름이 없고 하루 넘게 지났으면 `취소` 후보로 표시만 한다(바꾸는 것은 사용자에게 묻고 한다).

## 3. 세션 상태와 경보 (읽기만)

`claude agents --json --all --cwd <프로젝트 폴더>`(`pwd` 로 읽은 현재 폴더)에서 이름에 배지 `[<PREFIX>-n]` 이 들어 있는 세션을 찾는다(대괄호까지 맞춘다. `TK-1` 만으로 찾으면 `[TK-12]` 가 섞인다). 배지가 없는 예전 이름의 세션은 티켓의 `세션 이름` 값과 같은 이름으로 찾는다.

| 목록의 값 | 뜻 |
|---|---|
| `status: busy` / `state: working` | 일하는 중 |
| `status: waiting` / `state: blocked` | 권한 승인이나 질문에 막혀 **사람을 기다림**(2026-11-24 시험에서 확인. 훅 경보 없이도 이 조회로 알 수 있다) → `입력 대기` |
| `status: idle` | 한 턴을 끝내고 쉬는 중. 끝났을 수도, 입력(권한 승인 포함)을 기다릴 수도 있다 |
| 목록에 없음 | 종료됨 |

아직 처리하지 않은 경보가 있으면 `bash .claude/scripts/watch-alerts.sh --once` 로 읽는다. 마스터의 Monitor 가 이미 처리했다면 비어 있다. 경보는 `dispatcher` 의 '경보' 표대로 반영한다(`attention`·`error` → `입력 대기`).
idle 세션이 일을 끝냈는지 입력을 기다리는지는 경보와 `claude logs "[<PREFIX>-n]"` 의 마지막 부분으로 판단한다(마지막 출력이 질문이나 권한 요청인지). 로그는 요약만 쓰고 원문을 티켓에 붙이지 않는다. 키·계좌번호처럼 보이는 문자열은 쓰지 않는다.

## 4. PR 상태 (gh)

브랜치가 있는 티켓마다:

```
gh pr list --repo <GITHUB_REPO> --head <브랜치> --state all --json number,isDraft,state,baseRefName,mergedAt
```

| 결과 | `PR 상태` | 비고 |
|---|---|---|
| 비어 있음 | 없음 | `PR 번호` 비움 |
| state OPEN, isDraft true | draft | |
| state OPEN, isDraft false | open | |
| state MERGED | merged | `상태` 를 `완료` 로 바꾼다 |
| state CLOSED | closed | `상태` 는 `입력 대기` 로 두고 사용자에게 알린다 |

`PR 번호` 에는 `number`, `부모 브랜치` 에는 `baseRefName` 을 덮어쓴다. 같은 브랜치에 PR 이 둘 이상이면 가장 최근 것을 쓰고 사용자에게 알린다.
브랜치가 실제로 존재하는지 `git -C <REPO_DIR> branch --list <브랜치>` 로 확인한다(아직 없으면 그대로 두고 "브랜치 미생성"으로 보고).

## 5. 상태 판정

- PR merged → `완료`.
- 세션이 목록에 없고 merged 가 아님 → `입력 대기`(끝났는지 중단됐는지 사용자 확인 필요)로 두고 알린다.
- 경보가 `attention`·`error`, 세션이 `state: blocked`, 또는 세션이 idle 이고 로그 끝이 질문·권한 요청 → `입력 대기`.
- 그 밖에 일하는 중이거나 한 턴을 마친 idle → `진행`.

## 6. Notion 갱신

티켓마다 `notion-update-page`:
- `update_properties`: `상태`, `PR 번호`, `PR 상태`, `부모 브랜치`, `date:마지막 동기화:start`(1번의 `utc`), `date:마지막 동기화:is_datetime`=1. 바뀐 것만 보낸다.
- `insert_content`(끝에 추가): `local 시각 · <상태> · <한 줄 요약(경보·로그에서 읽은 한 일/다음)>`. 같은 내용을 반복해서 쓰지 않는다(직전 줄과 같으면 건너뛴다).
- `PR 작성 여부`, `병합 여부` 는 수식이라 쓰지 않는다.

## 7. 보고

표로 보여 준다: 티켓, 세션 이름, 상태, 세션(busy/idle/종료), 브랜치, PR(번호·상태), 부모, 한 줄 요약. 그다음 사용자가 할 일을 나열한다(입력 대기 세션에 `claude attach "[<PREFIX>-n]"`, merged 세션 정리 제안).
`완료` 가 된 티켓의 세션은 `claude stop <id>`·`claude rm <id>` 정리를 **제안만** 하고 사용자 승인 뒤에 한다. worktree 정리도 마찬가지다.
