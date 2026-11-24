#!/bin/sh
# Environment check for the dispatcher kit (POSIX sh: macOS, Linux, Windows Git Bash).
# READ-ONLY: it never installs or changes anything. It only runs version/help commands
# and (for the Notion check) `claude mcp list`, which makes a network health check.
#
# Usage: sh check-env.sh [--project DIR]
#   --project DIR  the project folder that contains .claude/ (default: auto-detect from this script's location)
# Output: one line per item: [OK] / [WARN] / [FAIL] name: detail, followed by "  fix: ..." for WARN and FAIL.
# Exit code: 1 if any FAIL, else 0. Tokens are never printed.

FAILS=0
WARNS=0
ok()   { printf '[OK]   %s: %s\n' "$1" "$2"; }
warn() { WARNS=$((WARNS + 1)); printf '[WARN] %s: %s\n       fix: %s\n' "$1" "$2" "$3"; }
fail() { FAILS=$((FAILS + 1)); printf '[FAIL] %s: %s\n       fix: %s\n' "$1" "$2" "$3"; }
have() { command -v "$1" >/dev/null 2>&1; }

PROJECT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -z "$PROJECT" ]; then
  # installed layout: <project>/.claude/scripts/check-env.sh. The folder above scripts/ must be named .claude;
  # in the kit it is payload/claude, which is not a project (a pre-install run then reports "no project", not FAILs).
  PARENT="$(cd "$SELF_DIR/.." && pwd)"
  case "$PARENT" in
    */.claude) PROJECT="$(cd "$PARENT/.." && pwd)" ;;
  esac
fi
if [ -n "$PROJECT" ]; then
  case "$PROJECT" in [A-Za-z]:*|*\\*) have cygpath && PROJECT="$(cygpath -u "$PROJECT")" ;; esac
  [ -d "$PROJECT" ] || { echo "project folder not found: $PROJECT" >&2; exit 2; }
  PROJECT="$(cd "$PROJECT" && pwd)"
fi

# --- 1. OS and shell -------------------------------------------------------
UNAME_S="$(uname -s 2>/dev/null || echo unknown)"
UNAME_M="$(uname -m 2>/dev/null || echo unknown)"
IS_WINDOWS=0
case "$UNAME_S" in
  MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=1; ok "os" "Windows ($UNAME_S $UNAME_M) via Git Bash/MSYS" ;;
  Darwin) ok "os" "macOS ($UNAME_M)" ;;
  Linux)
    if grep -qi microsoft /proc/version 2>/dev/null; then
      warn "os" "Linux inside WSL ($UNAME_M)" "Use the Claude Code installed inside WSL, not the Windows one; the two are separate installs and settings"
    else
      ok "os" "Linux ($UNAME_M)"
    fi ;;
  *) warn "os" "untested OS: $UNAME_S $UNAME_M" "Supported: Windows (Git Bash), macOS, Linux" ;;
esac

# --- 2. bash ---------------------------------------------------------------
if have bash; then
  BASH_PATH="$(command -v bash)"
  BASH_VER="$(bash -c 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"' 2>/dev/null)"
  BASH_MAJ="${BASH_VER%%.*}"; BASH_MIN="${BASH_VER#*.}"
  if [ "${BASH_MAJ:-0}" -gt 3 ] || { [ "${BASH_MAJ:-0}" -eq 3 ] && [ "${BASH_MIN:-0}" -ge 2 ]; }; then
    ok "bash" "$BASH_VER at $BASH_PATH"
  else
    fail "bash" "version $BASH_VER is too old (need 3.2+)" "Install a newer bash (e.g. 'brew install bash' on macOS)"
  fi
  case "$BASH_PATH" in
    *[Ss]ystem32*|*WindowsApps*) warn "bash" "bash resolves to the WSL launcher ($BASH_PATH), not Git Bash" "Put Git for Windows' bin folder before System32 in PATH, or run the scripts from Git Bash" ;;
  esac
else
  fail "bash" "not found" "Install bash (Windows: install Git for Windows, which includes Git Bash)"
fi

# --- 3. claude CLI ---------------------------------------------------------
if have claude; then
  CLAUDE_VER="$(claude --version 2>&1 | head -n 1)"
  ok "claude" "$CLAUDE_VER"
  CLAUDE_HELP="$(claude --help 2>&1)"
  F0="$FAILS"
  for opt in --bg --agent --name --model --effort --settings --permission-mode; do
    case "$CLAUDE_HELP" in *"$opt"*) ;; *) fail "claude option $opt" "this Claude Code version does not list $opt" "Update Claude Code (claude update)" ;; esac
  done
  for sub in agents logs attach stop rm; do
    if claude "$sub" --help >/dev/null 2>&1; then :; else fail "claude $sub" "subcommand not available" "Update Claude Code (claude update)"; fi
  done
  [ "$FAILS" -eq "$F0" ] && ok "claude features" "--bg, --agent, --settings and agents/logs/attach/stop/rm are available"
else
  fail "claude" "not found on PATH" "Install Claude Code (see https://code.claude.com/docs) and make sure 'claude' works in this shell"
fi

# --- 4. git ----------------------------------------------------------------
if have git; then ok "git" "$(git --version | head -n 1)"; else fail "git" "not found" "Install git (Windows: Git for Windows)"; fi

# --- 5. gh -----------------------------------------------------------------
if have gh; then
  if gh auth status >/dev/null 2>&1; then ok "gh" "$(gh --version | head -n 1), logged in"
  else warn "gh" "installed but not logged in" "Run 'gh auth login' (needed only for PR status in ticket-sync)"; fi
else
  warn "gh" "not found" "Install GitHub CLI and run 'gh auth login' (needed only for PR status in ticket-sync)"
fi

# --- 6. time ---------------------------------------------------------------
if NOW_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" && [ -n "$NOW_UTC" ]; then
  OFFSET_SYS="$(date +%z 2>/dev/null)"
  ok "time" "UTC $NOW_UTC, system offset ${OFFSET_SYS:-unknown}"
  if [ "$IS_WINDOWS" -eq 1 ]; then
    warn "time zone" "Git Bash 'date' ignores TZ and shows UTC" "Set TIMEZONE_OFFSET (e.g. +09:00) in .claude/dispatcher.conf; scripts compute local time from it"
  fi
else
  fail "time" "'date -u' failed" "Use a POSIX-compatible date (Windows: Git Bash)"
fi

# --- 7. project files ------------------------------------------------------
if [ -z "$PROJECT" ]; then
  warn "project" "no project folder given or detected (kit not installed yet?)" "Run install first, then 'sh .claude/scripts/check-env.sh', or pass --project DIR"
else
  C="$PROJECT/.claude"
  for f in agents/dispatcher.md skills/dispatch/SKILL.md skills/ticket-sync/SKILL.md scripts/open-session.sh scripts/alert.sh scripts/watch-alerts.sh scripts/now.sh scripts/lib-conf.sh; do
    if [ -f "$C/$f" ]; then :; else fail "file .claude/$f" "missing" "Re-run the installer for this project"; fi
  done
  [ -f "$C/agents/dispatcher.md" ] && ok "kit files" "agent, skills and scripts present under $C"

  # line endings: a CR in a .sh file breaks bash on macOS/Linux ('grep $\r' gives false hits on MSYS, so count with tr)
  CRBAD=""
  for f in "$C"/scripts/*.sh "$PROJECT"/open-master.sh; do
    [ -f "$f" ] || continue
    n="$(tr -cd '\r' < "$f" | wc -c | tr -d ' ')"
    [ "${n:-0}" -gt 0 ] && CRBAD="$CRBAD $(basename "$f")"
  done
  if [ -n "$CRBAD" ]; then
    fail "line endings" "CR characters found in:$CRBAD" "Convert to LF (e.g. 'sed -i.bak \"s/\\r\$//\" FILE'), and keep .sh files as eol=lf in git (.gitattributes)"
  else
    ok "line endings" "shell scripts use LF"
  fi

  # --- 8. config ---------------------------------------------------------
  CONF="$C/dispatcher.conf"
  if [ ! -f "$CONF" ]; then
    fail "config" "$CONF not found" "Re-run the installer, or copy dispatcher.conf.example to .claude/dispatcher.conf and fill it in"
  else
    # POSIX re-implementation of conf_get (lib-conf.sh is bash-only; this script must run under plain sh)
    getc() {
      v="$( { grep -E "^[[:space:]]*$1[[:space:]]*=" "$CONF" || true; } | tail -n 1 \
        | sed -e 's/^[^=]*=//' -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
              -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/")"
      if [ -n "$v" ]; then printf '%s' "$v"; else printf '%s' "${2:-}"; fi
    }
    if grep -qE '(ntn_|secret_|ghp_|gho_|github_pat_|sk-ant-|xox[bp]-)[A-Za-z0-9_-]{8,}' "$CONF"; then
      fail "config secrets" "dispatcher.conf contains something that looks like a token" "Remove it. This file must not hold keys or tokens; auth is handled by claude, gh and the Notion connector"
    else
      ok "config secrets" "no token-like values"
    fi
    P="$(getc TICKET_PREFIX)"
    case "$P" in
      "") fail "config TICKET_PREFIX" "empty" "Set a 2-10 letter prefix, e.g. TK" ;;
      [A-Za-z]*) if printf '%s' "$P" | grep -qE '^[A-Za-z][A-Za-z0-9]{1,9}$'; then ok "config TICKET_PREFIX" "$P"; else fail "config TICKET_PREFIX" "'$P' is invalid" "Use 2-10 letters/digits starting with a letter (Notion's Unique ID prefix needs 2-10 characters)"; fi ;;
      *) fail "config TICKET_PREFIX" "'$P' is invalid" "Use 2-10 letters/digits starting with a letter" ;;
    esac
    TZO="$(getc TIMEZONE_OFFSET)"
    if printf '%s' "$TZO" | grep -qE '^[+-][0-9]{2}:[0-9]{2}$'; then ok "config TIMEZONE_OFFSET" "$TZO"; else fail "config TIMEZONE_OFFSET" "'${TZO}' is not +HH:MM" "Set e.g. +09:00 (used for progress-log timestamps)"; fi
    RD="$(getc REPO_DIR)"
    if [ -z "$RD" ]; then
      warn "config REPO_DIR" "empty: PR/branch features are off" "Set it to the git repository folder relative to the project ('.' if the project itself is the repo)"
    else
      case "$RD" in /*|*..*|[A-Za-z]:*) fail "config REPO_DIR" "'$RD' must be a relative folder inside the project" "Use e.g. 'myrepo' or '.'" ;;
        *) if git -C "$PROJECT/$RD" rev-parse --git-dir >/dev/null 2>&1; then ok "config REPO_DIR" "$RD is a git repository"; else fail "config REPO_DIR" "$PROJECT/$RD is not a git repository" "Fix REPO_DIR or run git init/clone there"; fi ;;
      esac
    fi
    NDS="$(getc NOTION_DATA_SOURCE_ID)"
    if [ -z "$NDS" ]; then
      warn "config NOTION_DATA_SOURCE_ID" "empty" "Create the Notion database (docs/NOTION-SCHEMA.md in the kit) and paste its data source ID here"
    elif printf '%s' "$NDS" | grep -qiE '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
      ok "config NOTION_DATA_SOURCE_ID" "set (UUID format)"
    else
      fail "config NOTION_DATA_SOURCE_ID" "not a UUID" "Use the ID from the 'collection://...' URL, without the 'collection://' prefix"
    fi
    MM="$(getc MASTER_MODEL opus)"
    ok "config MASTER_MODEL" "$MM (note: some models need a plan or usage credits; test with 'claude --model $MM')"
  fi
fi

# --- 9. Notion MCP (as far as it can be checked) ----------------------------
if have claude; then
  TMP="${TMPDIR:-/tmp}/check-env-mcp.$$"
  claude mcp list >"$TMP" 2>&1 &
  PID=$!
  i=0
  while kill -0 "$PID" 2>/dev/null && [ "$i" -lt 30 ]; do sleep 1; i=$((i + 1)); done
  if kill -0 "$PID" 2>/dev/null; then kill "$PID" 2>/dev/null; fi
  wait "$PID" 2>/dev/null
  if grep -i notion "$TMP" >/dev/null 2>&1; then
    if grep -i notion "$TMP" | grep -qi 'connected'; then ok "notion mcp" "a Notion MCP server is listed and connected"
    else warn "notion mcp" "a Notion MCP server is listed but not connected" "Reconnect it (claude.ai Settings > Connectors, or 'claude mcp' / /mcp inside a session)"; fi
  else
    warn "notion mcp" "no Notion MCP server found in 'claude mcp list'" "Connect Notion: claude.ai Settings > Connectors > Notion (or add a local MCP server named notion). This check cannot see every setup"
  fi
  rm -f "$TMP"
fi

printf '\nSummary: %s FAIL, %s WARN\n' "$FAILS" "$WARNS"
[ "$FAILS" -eq 0 ]
