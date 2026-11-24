# Notion 티켓 DB 만들기

마스터와 스킬은 아래 스키마의 Notion DB 를 전제로 한다. **속성 이름은 한글로 고정**이다(스킬이 이 이름으로 읽고 쓴다).

## 준비
- Notion 이 Claude Code 에 연결돼 있어야 한다(`check-env` 의 notion mcp 항목).
- DB 를 둘 **부모 페이지**를 Notion 에서 만들어 두고, 연결한 Notion 계정이 그 페이지를 편집할 수 있어야 한다.
- 티켓 접두어는 설치 때 정한 `TICKET_PREFIX` 와 **같아야** 한다. Notion 의 `UNIQUE_ID` 접두어는 워크스페이스에서 **한 번만** 쓸 수 있다(2~10자, 첫 글자는 영문자).

## 방법 A: Claude 에게 시키기 (권장)
마스터(또는 Notion 이 연결된 아무 Claude 세션)에게 이렇게 말한다. `XX` 는 접두어, 부모 페이지는 주소를 붙인다.

> Notion 의 <부모 페이지 주소> 아래에 "세션 티켓" DB 를 만들어 줘. 아래 DDL 로 만들되 접두어 XX 는 <내 접두어> 로 바꿔. 다 만들면 data source ID(collection:// 뒤의 UUID)를 알려 줘.
> (여기에 아래 'DDL' 절의 코드 블록을 붙여 넣는다)

마스터가 도는 프로젝트에는 키트 문서가 설치되지 않으므로 마스터는 이 파일을 볼 수 없다. **DDL 코드 블록을 복사해서 메시지에 직접 붙여 넣어야 한다.**

Claude 가 Notion 의 `notion-create-database` 도구로 아래 DDL 을 실행한다. 결과에 나오는 `collection://<UUID>` 에서 **UUID 만** `.claude/dispatcher.conf` 의 `NOTION_DATA_SOURCE_ID` 에 적고, DB 주소를 `NOTION_DB_URL` 에 적는다.

## DDL
`XX` 를 접두어로 바꿔서 쓴다.

```sql
CREATE TABLE (
  "작업 요약" TITLE,
  "티켓" UNIQUE_ID PREFIX 'XX',
  "상태" STATUS('승인 대기':gray:to_do, '진행':blue:in_progress, '입력 대기':yellow:in_progress, '완료':green:complete, '취소':red:complete),
  "세션 이름" RICH_TEXT,
  "모델" SELECT('sonnet':blue, 'opus':purple, 'haiku':green, 'fable':pink),
  "Effort" SELECT('low':gray, 'medium':blue, 'high':orange, 'xhigh':red, 'max':red),
  "권한 모드" SELECT('plan':gray, 'manual':blue, 'acceptEdits':green),
  "브랜치" RICH_TEXT,
  "부모 브랜치" RICH_TEXT,
  "PR 번호" NUMBER,
  "PR 상태" SELECT('없음':gray, 'draft':yellow, 'open':blue, 'merged':green, 'closed':red),
  "PR 작성 여부" FORMULA('prop("PR 번호") > 0'),
  "병합 여부" FORMULA('prop("PR 상태") == "merged"'),
  "생성일" CREATED_TIME,
  "마지막 동기화" DATE
)
```

## 방법 B: Notion 화면에서 직접
새 DB 를 만들고 아래 속성을 같은 **이름·종류**로 추가한다. 선택지 이름도 그대로 쓴다.

| 속성 | 종류 | 값(선택지) |
|---|---|---|
| 작업 요약 | 제목 | 마스터가 쓰는 한 줄 요약 |
| 티켓 | 고유 ID | 접두어 = `TICKET_PREFIX` |
| 상태 | 상태 | 승인 대기(To-do), 진행·입력 대기(In progress), 완료·취소(Complete) |
| 세션 이름 | 텍스트 | `[TK-12] 이름` 형식의 전체 이름 |
| 모델 | 선택 | sonnet, opus, haiku, fable |
| Effort | 선택 | low, medium, high, xhigh, max |
| 권한 모드 | 선택 | plan, manual, acceptEdits |
| 브랜치, 부모 브랜치 | 텍스트 | |
| PR 번호 | 숫자 | |
| PR 상태 | 선택 | 없음, draft, open, merged, closed |
| PR 작성 여부 | 수식 | `prop("PR 번호") > 0` |
| 병합 여부 | 수식 | `prop("PR 상태") == "merged"` |
| 생성일 | 생성 일시 | |
| 마지막 동기화 | 날짜 | |

## 참고
- **권한 모드 `manual`**: Claude Code CLI 의 `--permission-mode` 는 `default` 가 아니라 `manual` 을 받는다(`claude --help`). 그래서 선택지도 `manual` 이다.
- **값의 출처**: PR 번호·PR 상태·부모 브랜치는 하위 세션의 보고가 아니라 `gh` 로 읽어 채운다. `PR 작성 여부`·`병합 여부` 는 수식이라 직접 쓰지 않는다.
- **날짜**: `마지막 동기화` 는 UTC 로 쓴다. Notion 이 보는 사람의 시간대로 보여 준다.
- 수식 문법과 `UNIQUE_ID` 는 Notion 의 요금제·버전에 따라 다를 수 있다. 만들기가 실패하면 오류 문구를 그대로 마스터에게 붙여 넣어 방법 B 로 대신한다.
