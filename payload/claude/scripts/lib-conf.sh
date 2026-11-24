#!/usr/bin/env bash
# dispatcher.conf 읽기 도우미. 다른 스크립트가 source 해서 쓴다:
#   . "$(dirname "${BASH_SOURCE[0]}")/lib-conf.sh"; conf_get KEY [기본값]
#
# 설정 파일은 KEY=값 형식(한 줄에 하나, '#' 으로 시작하는 줄은 주석, 줄 끝의 CR 은 무시)이다.
# 값을 실행하지 않는다(source 하지 않는다). 비밀값은 두지 않는다. 같은 키가 여러 번 있으면 마지막 것을 쓴다.
# 위치: $DISPATCH_CONF 가 있으면 그것, 없으면 <이 스크립트 폴더>/../dispatcher.conf
#
# 프로세스를 새로 띄우지 않고 bash 내장 기능만 쓴다. Windows(Git Bash)에서는 프로세스 하나를 띄우는 데
# 0.3~0.5초가 걸려서, 훅처럼 제한시간이 있는 곳에서 grep/sed 를 여러 번 부르면 시간 안에 끝나지 않는다.

if [ -z "${DISPATCH_CONF:-}" ]; then
  _dispatch_d="${BASH_SOURCE[0]%/*}"
  [ "$_dispatch_d" = "${BASH_SOURCE[0]}" ] && _dispatch_d="."
  DISPATCH_CONF="$_dispatch_d/../dispatcher.conf"
fi

conf_get() {  # conf_get KEY [DEFAULT]  -> 값을 출력한다(없거나 비었으면 DEFAULT)
  local key="${1:-}" def="${2:-}" val="" line k
  case "$key" in ""|*[!A-Za-z0-9_]*) return 2 ;; esac
  if [ -f "$DISPATCH_CONF" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%$'\r'}"
      line="${line#"${line%%[![:space:]]*}"}"          # 앞 공백 제거
      case "$line" in ''|'#'*) continue ;; esac
      case "$line" in *=*) ;; *) continue ;; esac
      k="${line%%=*}"
      k="${k%"${k##*[![:space:]]}"}"                    # 키 뒤 공백 제거
      if [ "$k" = "$key" ]; then val="${line#*=}"; fi
    done < "$DISPATCH_CONF"
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    case "$val" in
      \"*\") val="${val#\"}"; val="${val%\"}" ;;
      \'*\') val="${val#\'}"; val="${val%\'}" ;;
    esac
  fi
  if [ -n "$val" ]; then printf '%s' "$val"; else printf '%s' "$def"; fi
}
