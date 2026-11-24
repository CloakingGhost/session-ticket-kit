---
name: dispatch
description: 마스터 세션(dispatcher 에이전트) 전용. 사용자가 새 작업을 맡기거나 열린 작업의 후속을 요청할 때 쓴다. Notion 티켓 발급, 열린 세션에 이관 또는 새 세션 개설(모델·effort·권한 모드 선택), 첫 프롬프트 승인까지 처리한다. 하위 세션(이름 앞에 번호 배지가 붙은 세션)은 이 스킬을 쓰지 않는다.
allowed-tools:
  - Bash(bash .claude/scripts/open-session.sh *)
  - Bash(bash .claude/scripts/now.sh)
  - Bash(claude agents *)
  - Bash(claude logs *)
  - Bash(git -C * fetch *)
  - Bash(git -C * branch --show-current)
  - Bash(git -C * status *)
  - Bash(git -C * rev-parse *)
  - Bash(git -C * rev-list *)
  - Bash(pwd)
  - SendMessage
  - mcp__claude_ai_Notion__notion-fetch
  - mcp__claude_ai_Notion__notion-create-pages
  - mcp__claude_ai_Notion__notion-update-page
  - mcp__claude_ai_Notion__notion-query-data-sources
  - mcp__notion__notion-fetch
  - mcp__notion__notion-create-pages
  - mcp__notion__notion-update-page
  - mcp__notion__notion-query-data-sources
---

# dispatch — 요청 접수, 티켓 발급, 세션 라우팅

시작하기 전에 확인한다.
- 나는 `dispatcher` 에이전트(마스터)인가? 아니면(세션 이름이 `[접두어-번호]` 배지로 시작하는 하위 세션이면) 이 스킬을 쓰지 않고 멈춘다.
- `.claude/dispatcher.conf` 를 읽었는가? 읽지 않았으면 읽는다. 아래의 `<…>` 는 그 설정 값이다: `<PREFIX>`=`TICKET_PREFIX`, `<REPO_DIR>`, `<GITHUB_REPO>`, `<BASE_BRANCH>`, `<TEST_COMMAND>`, `<DATA_SOURCE>`=`NOTION_DATA_SOURCE_ID`. `NOTION_DATA_SOURCE_ID` 가 비어 있으면 티켓을 만들 수 없으니, 키트의 docs/NOTION-SCHEMA.md 로 DB 를 먼저 만들게 안내하고 멈춘다.

Notion 페이지를 만들 때 parent 는 `{"type":"data_source_id","data_source_id":"<DATA_SOURCE>"}` 이다.
속성: `작업 요약`(제목), `상태`, `세션 이름`, `모델`, `Effort`, `권한 모드`, `브랜치`, `부모 브랜치`, `PR 번호`, `PR 상태`, `마지막 동기화`(날짜). `티켓`(`<PREFIX>-n`), `생성일`, `PR 작성 여부`, `병합 여부` 는 자동이라 쓰지 않는다.

## 1. 요청을 정리한다

한 문장으로 목적을 적는다. 목적이 둘 이상이면 나눠서 티켓을 따로 만든다(한 세션 한 목적). 목적이 모호하면 질문을 모아 한 번에 묻는다(AskUserQuestion).

저장소의 `CLAUDE.md` 절대 규칙과 부딪히는 요청이면 티켓을 만들지 않고 어떤 규칙인지 알린 뒤 멈춘다.

## 2. 열린 작업과 비교한다 (이관할지, 새로 열지)

1. `ListAgents` 와 `claude agents --json --cwd <프로젝트 폴더>`(`pwd` 로 읽은 현재 폴더)로 열린 세션을 본다(`name`, `kind`, `status`, `state`).
2. Notion 에서 `상태` 가 `진행`·`입력 대기`·`승인 대기` 인 티켓을 조회한다(`notion-query-data-sources`, SQL 에는 `"상태" IN (...)`).
3. **이관(기존 세션에 보낸다)은 아래를 모두 만족할 때만 한다.**
   - 요청이 그 티켓의 목적과 같은 일의 연장이다(리뷰 반영, 같은 브랜치에 추가, 방향 수정).
   - 그 세션이 `idle` 이다(`busy` 면 사용자에게 알리고, 끝나면 경보가 온다).
   - 세션 이름에 그 티켓의 배지 `[<PREFIX>-n]` 이 있다(`dispatcher` 의 '티켓 번호로 지목하면' 순서로 찾는다. 사용자가 번호를 말했으면 그 티켓이 후보다).
   하나라도 아니면 새 티켓·새 세션이다.
4. 이관하면: `SendMessage` 로 `to` = 세션 전체 이름(ListAgents 에 보이는 그대로, 예: `[TK-12] 백업 CronJob`), 본문 첫 줄에 `[티켓 <PREFIX>-n 후속]` 과 한 줄 요약을 쓰고, 이어서 필요한 내용을 쓴다. 티켓 `진행 기록` 에 한 줄 추가하고(`notion-update-page`, `insert_content`) 사용자에게 알린다. 여기서 끝난다.
   - **메시지는 받는 쪽 사용자의 승인을 기다리며 보류될 수 있고**(권한 모드가 다르면), 승인하지 않으면 일정 시간 뒤 만료되어 사라진다. 보류 안내가 오면 전달됐다고 말하지 말고 사용자에게 알린 뒤 `claude attach "[<PREFIX>-n]"` 로 붙어 승인하게 한다. 같은 메시지를 다시 보내지 않는다.

## 3. 새 세션이면 티켓을 먼저 만든다

`notion-create-pages` 로 `상태` = `승인 대기` 티켓을 만든다. 속성은 `작업 요약`, `모델`, `Effort`, `권한 모드`, `부모 브랜치`(코드 작업이면). 본문에는 `## 첫 프롬프트(초안)` 와 `## 진행 기록` 두 제목을 둔다. 만든 페이지를 `notion-fetch` 로 읽어 `티켓` 번호(`<PREFIX>-n`)를 얻는다.

## 4. 모델·effort·권한 모드를 고른다

| 작업 종류 | 모델 | effort | 권한 모드 |
|---|---|---|---|
| 질문·조사·정리·문서 | sonnet | low~medium | plan(조사) / acceptEdits(문서) |
| 구현·테스트·디버깅 | sonnet | high | manual |
| 계획·설계(모호함이 크다) | opus | high | plan |
| 리뷰·위험한 변경 검토 | opus | high | plan |

- 값은 사용자가 승인 단계에서 바꿀 수 있다. 근거를 한 줄로 적는다("모호한 설계라 opus").
- 여러 세션은 같은 사용 한도를 함께 쓴다. 열린 `busy` 세션이 둘 이상이면 사용자에게 알린다.
- 어떤 모델은 요금제나 사용 크레딧이 있어야 열린다(실패하면 모델을 바꿔 다시 제안한다).
- **세션 이름은 `[<PREFIX>-<번호>] <이름>`** 이다(예: `[TK-12] 백업 CronJob`). `<이름>` 은 작업 요약에서 딴 짧은 한글·영문 라벨(20자 안팎)이고 `[ ] / \ : * ? " < > |` 같은 특수문자는 쓰지 않는다. 배지는 `open-session.sh` 가 붙이므로 직접 쓰지 않는다. 사용자가 `<PREFIX>-12` 만 말해도 찾을 수 있게 하려는 규칙이다.

## 5. 코드를 바꾸는 작업이면 선행 조건을 확인한다

`<REPO_DIR>` 가 비어 있으면 이 단계와 worktree 규칙은 건너뛴다. 아니면 그 저장소가 `<BASE_BRANCH>` 이고 `origin/<BASE_BRANCH>` 와 같은지 본다(`git -C <REPO_DIR> fetch origin <BASE_BRANCH>`, `branch --show-current`, `rev-list --count HEAD..origin/<BASE_BRANCH>`, `status -sb`). 다르면 세션을 열지 말고 사용자에게 알린다. 새 세션이 읽는 저장소 규칙(`CLAUDE.md`)이 옛 것이 되지 않게 하려는 확인이다.
브랜치 이름은 `type/short-description`(feat, fix, chore, docs; 저장소가 다른 규칙을 쓰면 그것). 부모는 `<BASE_BRANCH>`.
같은 시각에 `진행` 중인 다른 코드 티켓의 요약과 영역이 겹치면 알린다(병합 충돌 가능). 각 세션은 자기 worktree 에서 일하므로 동시 작업 자체는 막지 않는다.

## 6. 첫 프롬프트 초안을 쓴다 (아래 템플릿)

초안은 티켓 본문 `첫 프롬프트(초안)` 아래에도 저장한다.
**첫 프롬프트에 배지 문자열 `[<PREFIX>-n]`(대괄호 포함)을 쓰지 않는다.** `claude attach`·`logs` 가 이름 일부로 세션을 찾을 때 이름뿐 아니라 첫 프롬프트 문구도 보기 때문에, 프롬프트 안에 배지가 있으면 다른 세션이 함께 걸린다. 번호는 `<PREFIX>-n` 처럼 대괄호 없이 쓴다.

## 7. 사용자 승인 (한 번의 턴 안에서 끝낸다)

먼저 초안 전문을 채팅에 보여 준다. 이어서 `AskUserQuestion` 한 번으로 묻는다.

- 질문: `[<PREFIX>-n] <이름>` 을 이 설정으로 열까요? (모델 / effort / 권한 모드 / 브랜치·부모 한 줄)
- 선택지: `승인하고 열기`(preview 에 첫 프롬프트 전문), `수정`, `취소`.
- `수정`: 사용자가 고칠 점을 말하면 반영해 7번을 다시 한다. `취소`: 티켓 `상태` 를 `취소` 로 바꾸고 끝낸다.

## 8. 승인되면 연다

```
bash .claude/scripts/open-session.sh 12 "백업 CronJob" sonnet high manual <<'EOF'
(승인된 첫 프롬프트 전문)
EOF
```

- 인자는 순서대로 티켓 번호(숫자만), 이름, 모델, effort, 권한 모드다. 스크립트가 세션 이름을 `[<PREFIX>-12] 백업 CronJob` 으로 만들어 열고, 경보 훅을 함께 붙인다.
- 실패하면(종료 코드 ≠ 0) 티켓은 `승인 대기` 로 두고 오류 한 줄을 사용자에게 보여 준다. 같은 명령을 반복하지 않는다.
- 성공하면 티켓을 갱신한다: `상태`=`진행`, `세션 이름`(배지 포함 전체 이름), `모델`, `Effort`, `권한 모드`, `브랜치`(코드 작업이면 승인된 이름), `PR 상태`=`없음`, `마지막 동기화`=`bash .claude/scripts/now.sh` 의 `utc`(`date:마지막 동기화:start`, `is_datetime`=1), `진행 기록` 에 `local 시각 · 세션 열림 · <모델>/<effort>/<권한>` 한 줄.

## 9. 사용자에게 보고한다 (짧게)

티켓 번호와 링크(`NOTION_DB_URL` 이 있으면), 세션 이름, `claude attach "[<PREFIX>-n]"`(읽기만 하려면 `claude logs "[<PREFIX>-n]"`, 대괄호가 있어 따옴표가 필요하고 이름 일부로 찾는다), "마스터에게는 `<PREFIX>-n` 이라고만 말하면 된다"는 안내, 모델·effort·권한 모드, 브랜치·부모, 그리고 "이 세션이 권한 승인에서 멈추거나 오류가 나면 경보가 마스터로 올라오니 마스터만 보면 된다"는 안내. 거기서 멈춘다.

## 첫 프롬프트 템플릿

```
[티켓 <PREFIX>-n] 이 세션의 목적은 한 가지다: <한 문장>.

## 먼저 읽을 것
- 프로젝트의 CLAUDE.md (자동으로 읽힌다)
- <관련 파일·문서 경로>

## 선행 조건 (하나라도 다르면 멈추고 사용자에게 묻는다)
- <REPO_DIR> 가 <BASE_BRANCH> 이고 origin/<BASE_BRANCH> 와 같다. (REPO_DIR 이 비어 있으면 이 줄 생략)
- <이 작업이 쓰는 데이터·설정의 출처>

## 할 일
1. ...
2. ...

## 하지 않을 것
- 푸시, PR 생성, 병합은 사용자 승인 뒤에 한다. 이 세션이 임의로 하지 않는다.
- <범위 밖인 것>

## 작업 규칙
- 코드·문서를 바꾸는 작업이면 편집 전에 worktree 를 만들고 들어간다:
  git -C <REPO_DIR> worktree add .claude/worktrees/<브랜치에서 type/ 를 뺀 이름> -b <브랜치> <부모 브랜치>
  그다음 EnterWorktree(path) 로 들어가 그 안에서만 편집한다. 브랜치 <type/short>, 부모 <BASE_BRANCH>.
- 커밋 전에 <TEST_COMMAND> 가 통과해야 한다. (TEST_COMMAND 가 비어 있으면 이 줄 생략) 커밋은 저장소 안에서 한다.
- Notion 티켓 <PREFIX>-n 은 마스터가 갱신한다. 이 세션은 Notion 을 건드리지 않는다.
- 막히면 20분 안에 실패한 테스트·로그를 붙여 질문으로 바꾼다.
- 끝나면 마지막 메시지에 아래를 적는다(마스터가 경보로 이 메시지의 끝 300자를 받는다):
  branch: <브랜치 또는 없음>
  pr: <번호 또는 없음>
  한 일 / 남은 일 / 사용자가 확인할 것

## 완료 기준
- <테스트로 확인할 수 있는 끝>
```
