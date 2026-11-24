#!/usr/bin/env bash
# 경보 파일을 읽어 한 줄씩 출력한다. 출력 한 줄이 마스터 세션의 알림 하나가 된다.
# 마스터가 Monitor 도구로 건다(timeout 최대 30분, 끝나면 다시 건다). 읽은 파일은 alerts/seen/ 으로 옮긴다.
#
# 사용: watch-alerts.sh           계속 감시한다(Monitor 의 timeout 이 끝낼 때까지)
#       watch-alerts.sh --once    지금 쌓인 경보만 출력하고 끝낸다(ticket-sync·시험용)
set -u
here="${BASH_SOURCE[0]%/*}"
[ "$here" = "${BASH_SOURCE[0]}" ] && here="."
dir="$here/../dispatcher/alerts"
[ -d "$dir/seen" ] || mkdir -p "$dir/seen"

emit() {
  local f="$1" line k v level="" ticket="" event="" type="" time="" text=""
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"; k="${line%%=*}"; v="${line#*=}"
    case "$k" in level) level="$v" ;; ticket) ticket="$v" ;; event) event="$v" ;; type) type="$v" ;; time_utc) time="$v" ;; text) text="$v" ;; esac
  done < "$f"
  printf 'ALERT level=%s ticket=%s event=%s type=%s time=%s text="%s"\n' "$level" "$ticket" "$event" "$type" "$time" "$text"
  mv "$f" "$dir/seen/" 2>/dev/null || rm -f "$f"
}

while :; do
  for f in "$dir"/*.txt; do
    [ -e "$f" ] || continue
    emit "$f"
  done
  [ "${1:-}" = "--once" ] && break
  sleep 1
done
