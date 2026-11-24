#!/usr/bin/env bash
# 하위 세션의 훅이 부른다(open-session.sh 가 세션을 열 때 --settings 로 건다). 사람이 직접 부르는 스크립트가 아니다.
# 표준입력으로 Claude Code 훅 JSON 을 받아 경보 파일 하나를 쓴다. 마스터의 watch-alerts.sh 가 그 파일을 읽어 알린다.
#
# 사용: alert.sh <티켓번호> <notification|stop|stop_failure|session_end>
#
# - 훅은 세션을 막으면 안 되므로 항상 exit 0 하고, 표준출력에는 아무것도 쓰지 않는다.
# - 경보 파일: <프로젝트>/.claude/dispatcher/alerts/<epoch>-<접두어><번호>-<이벤트>-<pid>.txt  (KEY=값 줄들)
# - level: error(API 오류 등) / attention(권한 승인·질문 대기) / done(한 턴을 마침) / info(세션 종료)
# - 경보 본문은 로컬 파일에만 남는다(최대 300자). 키·비밀값은 세션이 출력하지 않는 것이 전제다.
# - 속도: Windows(Git Bash)에서는 프로세스 하나를 띄우는 데 0.3~0.5초가 걸리고 훅에는 제한시간이 있다.
#   그래서 grep/sed/cat 없이 bash 내장 기능만 쓰고, 띄우는 프로세스는 date·mv(·최초 mkdir)뿐이다.
set -u

main() {
  local num="${1:-}" event="${2:-}"
  [[ "$num" =~ ^[0-9]+$ ]] || return 0

  local here="${BASH_SOURCE[0]%/*}"
  [ "$here" = "${BASH_SOURCE[0]}" ] && here="."
  . "$here/lib-conf.sh"
  [ "$(conf_get ALERTS on)" = "off" ] && return 0
  local prefix dir
  prefix="$(conf_get TICKET_PREFIX TK)"
  dir="$here/../dispatcher/alerts"
  [ -d "$dir" ] || mkdir -p "$dir" || return 0

  local payload=""
  if [ ! -t 0 ]; then IFS= read -r -d '' payload || true; fi

  # 단순 JSON 문자열 필드 읽기(jq 없이): jstr KEY → REPLY. 같은 키가 여럿이면 첫 번째를 쓴다.
  local REPLY=""
  jstr() {
    REPLY=""
    local re='"'"$1"'":"(([^"\\]|\\.)*)"'
    if [[ "$payload" =~ $re ]]; then REPLY="${BASH_REMATCH[1]}"; fi
  }
  unesc() {  # JSON 이스케이프를 한 줄 평문으로
    local s="$1"
    s="${s//\\n/ }"; s="${s//\\r/}"; s="${s//\\t/ }"; s="${s//\\\"/\"}"; s="${s//\\\\/\\}"
    REPLY="$s"
  }

  local ntype err msg last reason sid level type text
  jstr notification_type; ntype="$REPLY"
  jstr error;             err="$REPLY"
  jstr message;           unesc "$REPLY"; msg="$REPLY"
  jstr last_assistant_message; unesc "$REPLY"; last="$REPLY"
  jstr reason;            reason="$REPLY"
  jstr session_id;        sid="$REPLY"

  case "$event" in
    notification)
      case "$ntype" in
        permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input|auth_storage_failure|quota_auto_resume_disabled|quota_auto_resume_stale)
          level=attention; type="$ntype"; text="$msg" ;;
        *) return 0 ;;   # idle_prompt 등은 Stop 경보와 겹치므로 쓰지 않는다
      esac ;;
    stop)         level=done;  type=turn_end; text="$last" ;;
    stop_failure) level=error; type="${err:-unknown}"; text="${last:-$err}" ;;
    session_end)  level=info;  type="${reason:-other}"; text="" ;;
    *) return 0 ;;
  esac

  # 결론과 질문은 끝에 있으므로 길면 끝 300자만 남긴다
  if [ "${#text}" -gt 300 ]; then text="…${text: -300}"; fi

  local now epoch utc
  now="$(date -u '+%s %Y-%m-%dT%H:%M:%SZ')"
  epoch="${now%% *}"; utc="${now#* }"

  # 같은 티켓·이벤트·종류의 경보가 60초 안에 또 오면 건너뛴다(이벤트별로 따로 기억한다)
  local lastf prev=0
  lastf="$dir/.last-$num-$event-${type//[^A-Za-z0-9_]/_}"
  if [ -f "$lastf" ]; then
    read -r prev < "$lastf" || true
    [[ "$prev" =~ ^[0-9]+$ ]] || prev=0
    if [ $(( epoch - prev )) -lt 60 ]; then return 0; fi
  fi
  printf '%s\n' "$epoch" > "$lastf"

  local fname tmp
  printf -v fname '%014d-%s%s-%s-%s.txt' "$epoch" "$prefix" "$num" "$event" "$$"
  tmp="$dir/.tmp-$$"
  printf 'level=%s\nticket=%s-%s\nevent=%s\ntype=%s\ntime_utc=%s\nsession_id=%s\ntext=%s\n' \
    "$level" "$prefix" "$num" "$event" "$type" "$utc" "$sid" "$text" > "$tmp" && mv "$tmp" "$dir/$fname"
  return 0
}

main "$@" 2>/dev/null || true
exit 0
