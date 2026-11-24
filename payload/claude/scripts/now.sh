#!/usr/bin/env bash
# 현재 시각을 UTC 와 설정된 시간대(TIMEZONE_OFFSET)로 출력한다. PowerShell 없이 어디서나 쓴다.
# Git Bash 의 date 는 TZ 를 무시하고 UTC 를 보여 주므로(실제로 겪은 문제), 시간대는 설정 파일의 오프셋으로 계산한다.
# 출력 예:
#   utc=2026-11-23T01:02:03Z
#   local=2026-11-23T10:02:03+09:00
set -eu
. "$(dirname "${BASH_SOURCE[0]}")/lib-conf.sh"

off="$(conf_get TIMEZONE_OFFSET +00:00)"
case "$off" in
  [+-][0-9][0-9]:[0-9][0-9]) ;;
  *) echo "now: bad TIMEZONE_OFFSET '$off' (use +09:00 style)" >&2; exit 2 ;;
esac
sign="${off:0:1}"; hh="${off:1:2}"; mm="${off:4:2}"
secs=$(( 10#$hh * 3600 + 10#$mm * 60 ))
[ "$sign" = "-" ] && secs=$(( -secs ))

epoch="$(date -u +%s)"
fmt() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -r "$1" +%Y-%m-%dT%H:%M:%S; }  # GNU || BSD(macOS)

echo "utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "local=$(fmt $(( epoch + secs )))$off"
