#!/usr/bin/env bash
# 하위 세션을 백그라운드로 연다. 마스터(dispatcher)가 사용자 승인을 받은 뒤에만 부른다.
# 첫 프롬프트는 표준입력으로 받는다(따옴표·줄바꿈 문제를 피하려고 인자로 받지 않는다).
#
# 사용:
#   bash .claude/scripts/open-session.sh <티켓번호> "<이름>" <모델> <effort> <권한모드> <<'EOF'
#   (첫 프롬프트)
#   EOF
#
# 세션 표시 이름은 이 스크립트가 "[<접두어>-<번호>] <이름>" 으로 만든다(접두어는 dispatcher.conf 의 TICKET_PREFIX).
#   예) open-session.sh 12 "백업 CronJob" sonnet high manual  →  세션 이름 "[TK-12] 백업 CronJob"
# 사용자는 'TK-12' 만 말해도 마스터가 이름의 배지 "[TK-12]" 로 세션을 찾는다.
#
# 티켓번호: 숫자만
# 이름: 1~80자의 짧은 라벨(한글·영문). [ ] / \ : * ? " < > | ` $ 와 제어문자는 쓸 수 없다
# 모델: sonnet | opus | haiku | fable
# effort: low | medium | high | xhigh | max
# 권한모드: plan | manual | acceptEdits
#
# 환경변수: DISPATCH_DRY_RUN=1 이면 세션을 열지 않고 열려던 명령만 출력한다(파일도 쓰지 않는다).
#           DISPATCH_PRINT_SETTINGS=1 이면 세션에 줄 훅 JSON 만 출력하고 끝낸다(시험용).
#
# 경보 훅: 세션마다 --settings 로 훅(Notification·Stop·StopFailure·SessionEnd)을 붙여, 세션이 권한 승인에서 멈추거나
#   API 오류로 끝나거나 한 턴을 마치면 alert.sh 가 경보 파일을 쓴다(마스터가 감시한다). 프로젝트의 settings.json 은 건드리지 않는다.
#   dispatcher.conf 에 ALERTS=off 이면 훅을 붙이지 않는다.
#
# 이 스크립트는 자기 프로세스 안에서만 cd 한다. 부른 셸의 작업 폴더는 바뀌지 않는다.
set -euo pipefail

fail() { echo "open-session: $*" >&2; exit 2; }

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # <프로젝트>/.claude/scripts
. "$here/lib-conf.sh"
claude_dir="$(cd "$here/.." && pwd)"                    # <프로젝트>/.claude
root="$(cd "$claude_dir/.." && pwd)"                    # <프로젝트>

prefix="$(conf_get TICKET_PREFIX TK)"
[[ "$prefix" =~ ^[A-Za-z][A-Za-z0-9]{1,9}$ ]] || fail "TICKET_PREFIX in dispatcher.conf must be 2-10 letters/digits starting with a letter"

num="${1:-}"; label="${2:-}"; model="${3:-}"; effort="${4:-}"; mode="${5:-}"

[[ "$num" =~ ^[0-9]+$ ]] || fail "ticket number must be digits only (12 for ${prefix}-12)"
num=$((10#$num))   # 앞의 0 을 떼고 10진수로 본다(012 → 12)

# 앞뒤 공백을 지운다
label="${label#"${label%%[![:space:]]*}"}"
label="${label%"${label##*[![:space:]]}"}"
[ -n "$label" ] || fail "label is empty"
[ "${#label}" -le 80 ] || fail "label too long (max 80)"
case "$label" in
  *'['*|*']'*|*'/'*|*'\'*|*':'*|*'*'*|*'?'*|*'"'*|*'<'*|*'>'*|*'|'*|*'`'*|*'$'*)
    fail 'label must not contain [ ] / \ : * ? " < > | ` $' ;;
esac
if [[ "$label" =~ [[:cntrl:]] ]]; then fail "label must not contain control characters"; fi

case "$model"  in sonnet|opus|haiku|fable) ;; *) fail "model must be sonnet|opus|haiku|fable" ;; esac
case "$effort" in low|medium|high|xhigh|max) ;; *) fail "effort must be low|medium|high|xhigh|max" ;; esac
case "$mode"   in plan|manual|acceptEdits) ;; *) fail "permission mode must be plan|manual|acceptEdits" ;; esac

name="[${prefix}-$num] $label"

# 경보 훅 JSON (세션 전용, --settings 로 준다)
settings=""
alert="$here/alert.sh"
if [ "$(conf_get ALERTS on)" != "off" ] && [ -f "$alert" ]; then
  case "$alert" in
    *'"'*|*'$'*|*'`'*) echo "open-session: warning: script path has quote/\$/backtick; alert hooks disabled for this session" >&2 ;;
    *)
      esc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
      hook() { printf '[{"hooks":[{"type":"command","command":"bash \\"%s\\" %s %s","timeout":10}]}]' "$(esc "$alert")" "$num" "$1"; }
      settings="{\"hooks\":{\"Notification\":$(hook notification),\"Stop\":$(hook stop),\"StopFailure\":$(hook stop_failure),\"SessionEnd\":$(hook session_end)}}"
      ;;
  esac
fi

if [ "${DISPATCH_PRINT_SETTINGS:-}" = "1" ]; then printf '%s\n' "$settings"; exit 0; fi

[ -t 0 ] && fail "first prompt must be piped on stdin"
prompt="$(cat)"
[ -n "${prompt//[[:space:]]/}" ] || fail "first prompt is empty"

# 파일 이름은 이름 라벨이 아니라 티켓 번호로만 만든다(특수문자·한글 파일명 문제를 피한다)
record="$claude_dir/dispatcher/prompts/${prefix}-$num.md"

if [ "${DISPATCH_DRY_RUN:-}" = "1" ]; then
  echo "DRY RUN: would run in $root"
  echo "  claude --bg --name \"$name\" --model $model --effort $effort --permission-mode $mode ${settings:+--settings <alert hooks>} <prompt: ${#prompt} chars>"
  if [ -n "$settings" ]; then echo "  alert hooks: on (DISPATCH_PRINT_SETTINGS=1 prints the JSON)"; else echo "  alert hooks: off"; fi
  echo "  would save the prompt to $record"
  exit 0
fi

[ ! -e "$record" ] || fail "prompt record already exists ($record): ticket number reused?"
mkdir -p "$claude_dir/dispatcher/prompts"
printf '%s\n' "$prompt" > "$record"

cd "$root"
export MSYS2_ARG_CONV_EXCL='*'   # Git Bash 가 인자 속 경로를 멋대로 바꾸지 못하게 한다(다른 OS 에서는 무해)
args=(--bg --name "$name" --model "$model" --effort "$effort" --permission-mode "$mode")
if [ -n "$settings" ]; then args+=(--settings "$settings"); fi
claude "${args[@]}" "$prompt"
echo "opened: $name  (attach: claude attach \"[${prefix}-$num]\")"
