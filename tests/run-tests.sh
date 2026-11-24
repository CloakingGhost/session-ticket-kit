#!/usr/bin/env bash
# Kit tests: installer (paths, safety, upgrade, uninstall), scripts, environment checks, PowerShell entry points.
# Runs in a temp folder and cleans it up. Nothing is installed outside it.   Usage: bash tests/run-tests.sh
set -u

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${TMPDIR:-/tmp}/cst-test.$$"
mkdir -p "$ROOT"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
has()   { grep -qF -- "$2" "$1" 2>/dev/null; }          # has FILE TEXT
hasre() { grep -qE -- "$2" "$1" 2>/dev/null; }          # hasre FILE REGEX
not()   { ! "$@"; }                                      # not has FILE TEXT
inst()  { bash "$KIT/install.sh" "$@"; }
HAVE_GIT=0; command -v git >/dev/null 2>&1 && HAVE_GIT=1
rc_of() { "$@" >/dev/null 2>&1; echo $?; }               # prints the exit code

echo "== installer: path forms"
P="$ROOT/내 프로젝트 dir"; mkdir -p "$P"
inst --target "$P" --yes --prefix AB --tz-offset +09:00 --master-effort high --test-command 'make test' > "$ROOT/o1.txt" 2>&1
check "install into a folder with spaces and Korean characters" test -f "$P/.claude/agents/dispatcher.md"
check "conf has the chosen prefix"       has "$P/.claude/dispatcher.conf" "TICKET_PREFIX=AB"
check "conf keeps a command with a space" has "$P/.claude/dispatcher.conf" "TEST_COMMAND=make test"
check "conf has effort and time zone"    grep -q "MASTER_EFFORT=high" "$P/.claude/dispatcher.conf"
check "manifest written"                 test -s "$P/.claude/dispatcher/manifest.txt"
check "shell scripts are executable"     test -x "$P/.claude/scripts/open-session.sh"
check "launchers created in the project" test -f "$P/open-master.sh"

P2="$ROOT/dry"; mkdir -p "$P2"
inst --target "$P2" --yes --dry-run > "$ROOT/o2.txt" 2>&1
check "dry-run exits 0"                  test "$?" -eq 0
check "dry-run creates nothing"          test -z "$(ls -A "$P2")"

if command -v cygpath >/dev/null 2>&1; then
  P3="$ROOT/winstyle dir"; mkdir -p "$P3"; W="$(cygpath -w "$P3")"
  inst --target "$W" --yes --prefix WN > "$ROOT/o3.txt" 2>&1
  check "Windows-style path (C:\\...) is accepted" test -f "$P3/.claude/dispatcher.conf"
  W2="$(cygpath -m "$P3")"; inst --target "$W2" --yes --dry-run > /dev/null 2>&1
  check "mixed-slash path (C:/...) is accepted" test "$?" -eq 0
fi

mkdir -p "$ROOT/rel proj"
( cd "$ROOT" && inst --target "./rel proj" --yes --prefix RL > "$ROOT/o4.txt" 2>&1 )
check "relative path" test -f "$ROOT/rel proj/.claude/dispatcher.conf"

mkdir -p "$ROOT/home/p"
HOME="$ROOT/home" inst --target "~/p" --yes --prefix TL > "$ROOT/o5.txt" 2>&1
check "~ is expanded" test -f "$ROOT/home/p/.claude/dispatcher.conf"

echo "== installer: refusals and validation"
check "refuses the home folder"        test "$(HOME="$ROOT/home" rc_of bash "$KIT/install.sh" --target "$ROOT/home" --yes --dry-run)" -eq 2
check "refuses a folder inside the kit" test "$(rc_of bash "$KIT/install.sh" --target "$KIT/payload" --yes --dry-run)" -eq 2
check "refuses a missing folder"       test "$(rc_of bash "$KIT/install.sh" --target "$ROOT/does-not-exist" --yes --dry-run)" -eq 2
check "--yes without --target fails"   test "$(rc_of bash "$KIT/install.sh" --yes --dry-run)" -eq 2
for spec in "--prefix 1x" "--prefix T" "--prefix TOOLONGPREFIX1" "--tz-offset +9" "--notion-data-source xyz" "--master-effort ultra" "--repo-dir ../x" "--github-repo bad" "--root-shims maybe"; do
  # shellcheck disable=SC2086
  check "rejects: $spec" test "$(rc_of bash "$KIT/install.sh" --target "$P2" --yes --dry-run $spec)" -eq 2
done
inst --target "$P2" --yes --dry-run --notion-data-source "collection://00000000-0000-4000-8000-000000000000" > "$ROOT/o6.txt" 2>&1
check "collection:// prefix is stripped from the data source ID" test "$?" -eq 0

echo "== installer: repository detection"
P4="$ROOT/withrepo"; mkdir -p "$P4/myrepo"
if [ "$HAVE_GIT" -eq 1 ]; then
  git init -q -b main "$P4/myrepo" 2>/dev/null && git -C "$P4/myrepo" remote add origin https://github.com/acme/widgets.git 2>/dev/null
fi
inst --target "$P4" --yes > "$ROOT/o7.txt" 2>&1
if [ "$HAVE_GIT" -eq 1 ]; then
  check "detects REPO_DIR"    grep -q '^REPO_DIR=myrepo$' "$P4/.claude/dispatcher.conf"
  check "detects GITHUB_REPO" grep -q '^GITHUB_REPO=acme/widgets$' "$P4/.claude/dispatcher.conf"
  check "detects BASE_BRANCH" grep -q '^BASE_BRANCH=main$' "$P4/.claude/dispatcher.conf"
  # a project that is itself the git repository
  P7="$ROOT/selfrepo"; mkdir -p "$P7"; git init -q -b main "$P7" 2>/dev/null
  inst --target "$P7" --yes > "$ROOT/o13.txt" 2>&1
  check "a project that is itself a git repo gets REPO_DIR=." grep -q '^REPO_DIR=\.$' "$P7/.claude/dispatcher.conf"
  sh "$P7/.claude/scripts/check-env.sh" > "$ROOT/ce3.txt" 2>&1
  check "check-env accepts REPO_DIR=. as a git repository" grep -q 'config REPO_DIR: \. is a git repository' "$ROOT/ce3.txt"
else
  echo "skip  repository detection (git not installed)"
fi

echo "== installer: upgrade, backup, keep, uninstall"
echo "# my local edit" >> "$P/.claude/skills/dispatch/SKILL.md"
sed -i.bak '/^ALERTS=/d' "$P/.claude/dispatcher.conf" && rm -f "$P/.claude/dispatcher.conf.bak"
inst --target "$P" --yes > "$ROOT/o8.txt" 2>&1
check "edited file is reported as replaced"      hasre "$ROOT/o8.txt" 'replace +\.claude/skills/dispatch/SKILL\.md'
check "edited file was backed up"                test -n "$(find "$P/.claude/dispatcher/backup" -name SKILL.md 2>/dev/null | head -n 1)"
check "edited file is restored to the kit version" cmp -s "$P/.claude/skills/dispatch/SKILL.md" "$KIT/payload/claude/skills/dispatch/SKILL.md"
check "conf values are kept"                     has "$P/.claude/dispatcher.conf" "TICKET_PREFIX=AB"
check "missing conf key is added back"           has "$P/.claude/dispatcher.conf" "ALERTS=on"

cp -r "$KIT" "$ROOT/kit2" && echo "# v2" >> "$ROOT/kit2/payload/claude/scripts/now.sh"
bash "$ROOT/kit2/install.sh" --target "$P" --yes > "$ROOT/o9.txt" 2>&1
check "kit update is applied as 'update' (no backup needed)" hasre "$ROOT/o9.txt" 'update +\.claude/scripts/now\.sh'
check "kit update content arrived"               has "$P/.claude/scripts/now.sh" "# v2"

P5="$ROOT/keepme"; mkdir -p "$P5"; printf 'my own launcher\n' > "$P5/open-master.cmd"
inst --target "$P5" --yes > "$ROOT/o10.txt" 2>&1
check "a different existing launcher is kept"    has "$P5/open-master.cmd" "my own launcher"
check "...and reported as kept"                  hasre "$ROOT/o10.txt" 'keep +open-master\.cmd'

echo "# edited" >> "$P4/.claude/scripts/now.sh"
inst --target "$P4" --yes --uninstall > "$ROOT/o11.txt" 2>&1
check "uninstall removes unmodified files"       test ! -e "$P4/.claude/agents/dispatcher.md"
check "uninstall keeps modified files"           test -f "$P4/.claude/scripts/now.sh"
check "uninstall keeps dispatcher.conf"          test -f "$P4/.claude/dispatcher.conf"
inst --target "$P4" --yes --uninstall --purge > "$ROOT/o12.txt" 2>&1
check "uninstall --purge removes conf and runtime data" test ! -e "$P4/.claude/dispatcher.conf" -a ! -e "$P4/.claude/dispatcher"

echo "== scripts in an installed project"
S="$P/.claude/scripts"
DISPATCH_DRY_RUN=1 bash "$S/open-session.sh" 12 "백업 CronJob" sonnet high manual <<< "prompt" > "$ROOT/os1.txt" 2>&1
check "session name uses the badge format"       has "$ROOT/os1.txt" '--name "[AB-12] 백업 CronJob"'
check "prompt record is named by ticket number"   has "$ROOT/os1.txt" "prompts/AB-12.md"
check "label with a bracket is rejected"          test "$(rc_of bash "$S/open-session.sh" 12 "a[1]" sonnet high manual <<< x)" -eq 2
check "bad permission mode is rejected"           test "$(rc_of bash "$S/open-session.sh" 12 ok sonnet high default <<< x)" -eq 2
DISPATCH_PRINT_SETTINGS=1 bash "$S/open-session.sh" 12 "x" sonnet high plan > "$ROOT/os2.txt" 2>&1 < /dev/null
check "alert hooks JSON has a Stop hook"          grep -q '"Stop"' "$ROOT/os2.txt"
check "alert hooks JSON has a Notification hook"  grep -q '"Notification"' "$ROOT/os2.txt"
check "alert hooks JSON has a StopFailure hook"   grep -q '"StopFailure"' "$ROOT/os2.txt"
check "alert hooks JSON points at alert.sh"        has "$ROOT/os2.txt" "alert.sh"
bash "$S/now.sh" > "$ROOT/now.txt" 2>&1
check "now.sh prints utc and local (+09:00)"      grep -qE '^utc=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$' "$ROOT/now.txt"
check "now.sh local uses the configured offset"   grep -qE '^local=.*\+09:00$' "$ROOT/now.txt"
printf '%s' '{"hook_event_name":"Notification","message":"Claude needs your permission to use Bash","notification_type":"permission_prompt"}' | bash "$S/alert.sh" 12 notification
bash "$S/watch-alerts.sh" --once > "$ROOT/w1.txt" 2>&1
check "alert -> watch-alerts line"                 grep -q 'ALERT level=attention ticket=AB-12 event=notification type=permission_prompt' "$ROOT/w1.txt"
bash "$S/watch-alerts.sh" --once > "$ROOT/w2.txt" 2>&1
check "alert is delivered only once"               test ! -s "$ROOT/w2.txt"
# a StopFailure payload shaped like the real one (captured from an API error: model_not_found)
printf '%s' '{"session_id":"x","hook_event_name":"StopFailure","error":"model_not_found","last_assistant_message":"There'"'"'s an issue with the selected model (x). It may not exist."}' | bash "$S/alert.sh" 13 stop_failure
bash "$S/watch-alerts.sh" --once > "$ROOT/w3.txt" 2>&1
check "StopFailure payload -> level=error type=model_not_found" grep -q 'ALERT level=error ticket=AB-13 event=stop_failure type=model_not_found' "$ROOT/w3.txt"

echo "== environment checks"
sh "$S/check-env.sh" > "$ROOT/ce1.txt" 2>&1
check "check-env.sh prints a summary"               grep -q '^Summary:' "$ROOT/ce1.txt"
check "check-env.sh: kit files OK"                  grep -q '^\[OK\]   kit files' "$ROOT/ce1.txt"
check "check-env.sh: line endings OK"               grep -q '^\[OK\]   line endings' "$ROOT/ce1.txt"
check "check-env.sh: no token in conf"              grep -q '^\[OK\]   config secrets' "$ROOT/ce1.txt"
# the documented pre-install run from the kit root must not treat the kit as a project
sh "$KIT/check-env.sh" > "$ROOT/ce4.txt" 2>&1
check "pre-install check-env (kit root) does not report FAILs about project files or config" not hasre "$ROOT/ce4.txt" '^\[FAIL\] (file|config)'
check "pre-install check-env (kit root) says no project was given"                          hasre "$ROOT/ce4.txt" '^\[WARN\] project'
cp -r "$P" "$ROOT/bad proj"
printf '\r\n' >> "$ROOT/bad proj/.claude/scripts/now.sh"
printf 'NOTION_TOKEN=ntn_abcdefghijklmnopqrstuvwxyz\n' >> "$ROOT/bad proj/.claude/dispatcher.conf"
sh "$ROOT/bad proj/.claude/scripts/check-env.sh" > "$ROOT/ce2.txt" 2>&1
check "check-env.sh catches CR in a script"         grep -q '^\[FAIL\] line endings' "$ROOT/ce2.txt"
check "check-env.sh catches a token in the conf"    grep -q '^\[FAIL\] config secrets' "$ROOT/ce2.txt"
check "check-env.sh exits 1 when something FAILs"   test "$(rc_of sh "$ROOT/bad proj/.claude/scripts/check-env.sh")" -eq 1
check "check-env.sh never prints a token value"     not has "$ROOT/ce2.txt" "ntn_abcdefghijklmnop"

echo "== static portability scans (macOS bash 3.2 and POSIX)"
BASH4='declare -A|mapfile|readarray|\$\{[A-Za-z_]+(,,|\^\^)|&>>|\|&|coproc|local -n|;&|;;&'
check "no bash-4-only syntax in kit scripts" test "$(grep -rEl "$BASH4" "$KIT/install.sh" "$KIT/payload" --include='*.sh' 2>/dev/null | wc -l | tr -d ' ')" -eq 0
check "check-env.sh uses no bash-only syntax" test "$(grep -cE '\[\[ |BASH_SOURCE|\$\{![A-Za-z]|<\(' "$KIT/payload/claude/scripts/check-env.sh" | tr -d ' ')" -eq 0
CRBAD=0; for f in "$KIT"/*.sh "$KIT"/payload/claude/scripts/*.sh "$KIT"/payload/root/*.sh "$KIT"/tests/*.sh; do
  [ -f "$f" ] || continue; n="$(tr -cd '\r' < "$f" | wc -c | tr -d ' ')"; [ "${n:-0}" -gt 0 ] && { CRBAD=$((CRBAD + 1)); echo "      CR in $f"; }; done
check "all kit shell scripts use LF" test "$CRBAD" -eq 0

echo "== PowerShell entry points (Windows only)"
if command -v powershell.exe >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then   # cygpath = Git Bash/MSYS only (WSL has powershell.exe via interop but no cygpath)
  P6="$ROOT/ps dir"; mkdir -p "$P6"
  PW6="$(cygpath -w "$P6" 2>/dev/null || echo "$P6")"; PWK="$(cygpath -w "$KIT")"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PWK\\install.ps1" --target "$PW6" --yes --prefix PS --dry-run > "$ROOT/ps1.txt" 2>&1
  check "install.ps1 -> Git Bash -> install.sh (dry-run)" has "$ROOT/ps1.txt" "Dry run:"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PWK\\install.ps1" --target "$PW6" --yes --prefix PS > "$ROOT/ps2.txt" 2>&1
  check "install.ps1 installs into a path with a space" test -f "$P6/.claude/dispatcher.conf"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PW6\\.claude\\scripts\\check-env.ps1" > "$ROOT/ps3.txt" 2>&1
  check "check-env.ps1 prints a summary"               grep -q 'Summary:' "$ROOT/ps3.txt"
  check "check-env.ps1: kit files OK"                  grep -q '\[OK\]   kit files' "$ROOT/ps3.txt"
  check "check-env.ps1: line endings OK"               grep -q '\[OK\]   line endings' "$ROOT/ps3.txt"
  check "check-env.ps1: bash version is a plain number" grep -qE '\[OK\]   bash: Git Bash [0-9]+\.[0-9]+ at' "$ROOT/ps3.txt"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PWK\\check-env.ps1" > "$ROOT/ps5.txt" 2>&1
  check "pre-install check-env.ps1 (kit root) does not report FAILs about project files or config" not hasre "$ROOT/ps5.txt" '^\[FAIL\] (file|config)'
  check "pre-install check-env.ps1 (kit root) says no project was given"                          grep -q '\[WARN\] project' "$ROOT/ps5.txt"
  check "check-env.ps1: config TICKET_PREFIX OK"       grep -q '\[OK\]   config TICKET_PREFIX: PS' "$ROOT/ps3.txt"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ". '$PW6\\.claude\\scripts\\lib-conf.ps1'; \$env:DISPATCH_CONF='$PW6\\.claude\\dispatcher.conf'; Get-DispatchConf 'MASTER_MODEL' 'x'" > "$ROOT/ps4.txt" 2>&1
  check "lib-conf.ps1 reads dispatcher.conf"           grep -q '^opus' "$ROOT/ps4.txt"
else
  echo "skip  (powershell.exe not found)"
fi

echo
printf 'Result: %s passed, %s failed\n' "$PASS" "$FAIL"
case "$ROOT" in */cst-test.*) rm -rf "$ROOT" ;; esac
[ "$FAIL" -eq 0 ]
