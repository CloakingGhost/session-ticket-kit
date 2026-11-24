#!/usr/bin/env bash
# session-ticket-kit installer (macOS, Linux, Windows Git Bash).
#
# Copies the dispatcher agent, skills and scripts from this kit into <project>/.claude/ and writes
# <project>/.claude/dispatcher.conf from your answers. The kit folder can live anywhere; run this script from it.
# It does NOT touch settings.json, .gitignore, or any file that is not listed in the manifest it writes.
# Re-running it upgrades the kit-managed files (your dispatcher.conf is kept; edited files are backed up first).
#
#   ./install.sh                         interactive (asks for the project folder and settings)
#   ./install.sh --target ~/work/proj --yes --prefix TK     non-interactive
#   ./install.sh --target ~/work/proj --dry-run             show what would happen, change nothing
#   ./install.sh --target ~/work/proj --uninstall [--purge]
#
# Speed note: starting a process costs 0.3-0.5 s on Windows (Git Bash), so this script computes all checksums
# in one cksum call, copies files grouped by folder, and otherwise uses only bash built-ins.
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD="$KIT_DIR/payload"
VERSION="unknown"; read -r VERSION < "$KIT_DIR/VERSION" 2>/dev/null || true; VERSION="${VERSION%$'\r'}"

U='__unset__'   # "option not given"
TARGET="$U"; PREFIX="$U"; REPO_DIR="$U"; GITHUB="$U"; BASE="$U"; TESTCMD="$U"
NDS="$U"; NDB="$U"; TZOFF="$U"; MODEL="$U"; EFFORT="$U"; SHIMS="$U"
YES=0; DRY=0; UNINSTALL=0; PURGE=0

usage() {
  cat <<'EOF'
Usage: install.sh [options]
  --target DIR             project folder (the folder that will contain .claude/)
  --prefix XX              ticket prefix, 2-10 letters/digits starting with a letter (default: TK; Notion's Unique ID prefix needs 2-10 characters)
  --repo-dir DIR           git repository folder inside the project ('.' = the project itself, empty = none)
  --github-repo OWNER/NAME (default: read from the repository's origin remote)
  --base-branch NAME       (default: detected, else main)
  --test-command CMD       command that must pass before commits (default: empty)
  --notion-data-source ID  Notion data source ID; can be filled in later (default: empty)
  --notion-db-url URL      (default: empty)
  --tz-offset +HH:MM       used for progress-log timestamps (default: detected from this machine)
  --master-model NAME      (default: opus)
  --master-effort LEVEL    (default: empty = model default)
  --root-shims yes|no      create open-master.sh/.ps1/.cmd launchers in the project folder (default: yes)
  --yes, -y                do not prompt; use the options and detected defaults
  --dry-run                print what would happen; change nothing
  --uninstall              remove the files this kit installed (keeps dispatcher.conf and runtime data)
  --purge                  with --uninstall: also remove dispatcher.conf and .claude/dispatcher/
  -h, --help
If .claude/dispatcher.conf already exists, its values are kept and the value options are ignored.
EOF
}

say()  { printf '%s\n' "$*"; }
note() { printf '  %s\n' "$*"; }
die()  { printf 'install: %s\n' "$*" >&2; exit 2; }

# ---- arguments -------------------------------------------------------------
while [ $# -gt 0 ]; do
  opt="$1"
  case "$opt" in
    --yes|-y) YES=1; shift; continue ;;
    --dry-run) DRY=1; shift; continue ;;
    --uninstall) UNINSTALL=1; shift; continue ;;
    --purge) PURGE=1; shift; continue ;;
    -h|--help) usage; exit 0 ;;
    --target|--prefix|--repo-dir|--github-repo|--base-branch|--test-command|--notion-data-source|--notion-db-url|--tz-offset|--master-model|--master-effort|--root-shims)
      [ "$#" -ge 2 ] || die "option $opt needs a value"
      val="$2"; shift 2
      case "$opt" in
        --target) TARGET="$val" ;;            --prefix) PREFIX="$val" ;;
        --repo-dir) REPO_DIR="$val" ;;        --github-repo) GITHUB="$val" ;;
        --base-branch) BASE="$val" ;;         --test-command) TESTCMD="$val" ;;
        --notion-data-source) NDS="$val" ;;   --notion-db-url) NDB="$val" ;;
        --tz-offset) TZOFF="$val" ;;          --master-model) MODEL="$val" ;;
        --master-effort) EFFORT="$val" ;;     --root-shims) SHIMS="$val" ;;
      esac ;;
    *) die "unknown option: $opt (see --help)" ;;
  esac
done

[ -d "$PAYLOAD/claude" ] || die "payload folder not found next to install.sh ($PAYLOAD)"
command -v cksum >/dev/null 2>&1 || die "cksum not found (needed to track installed files)"

# ---- paths -----------------------------------------------------------------
# Prints the absolute POSIX-style path of an existing directory. Accepts: ~, ~/x, relative paths,
# C:\x\y, C:/x/y (Windows, via cygpath in Git Bash/MSYS/Cygwin), /c/x/y, paths with spaces or non-ASCII characters.
norm_path() {
  local p="${1:-}"
  [ -n "$p" ] || return 1
  p="${p%$'\r'}"
  case "$p" in "~") p="$HOME" ;; "~/"*) p="$HOME/${p#"~/"}" ;; esac
  if command -v cygpath >/dev/null 2>&1; then
    case "$p" in [A-Za-z]:*|*\\*) p="$(cygpath -u "$p" 2>/dev/null || printf '%s' "$p")" ;; esac
  fi
  [ -d "$p" ] || return 1
  ( cd "$p" 2>/dev/null && pwd )
}

# ---- prompts ---------------------------------------------------------------
ask() {   # ask "label" "default" -> reply (or default)
  local reply=""
  if [ -n "$2" ]; then printf '%s [%s]: ' "$1" "$2" >&2; else printf '%s (empty = none): ' "$1" >&2; fi
  IFS= read -r reply || reply=""
  reply="${reply%$'\r'}"
  if [ -n "$reply" ]; then printf '%s' "$reply"; else printf '%s' "$2"; fi
}
resolve() {   # resolve VAR "label" "default": if VAR was not given, prompt (or use the default with --yes)
  local var="$1" cur
  cur="${!var}"
  if [ "$cur" = "$U" ]; then
    if [ "$YES" -eq 1 ]; then printf -v "$var" '%s' "$3"; else printf -v "$var" '%s' "$(ask "$2" "$3")"; fi
  fi
}

if [ "$YES" -eq 0 ] && [ ! -t 0 ]; then die "no terminal for prompts: use --yes with --target (see --help)"; fi

# ---- target project --------------------------------------------------------
if [ "$TARGET" = "$U" ]; then
  [ "$YES" -eq 0 ] || die "--yes requires --target"
  say "Claude session tickets $VERSION"
  say "Kit folder: $KIT_DIR"
  say "Type the project folder to install into. It will get a .claude/ folder (project level, not your user-level ~/.claude)."
  say "Accepted forms: C:\\path, C:/path, /c/path, ~/path, a relative path; spaces and non-ASCII characters are fine."
  TARGET="$(ask "Project folder" "")"
fi
[ -n "$TARGET" ] || die "no project folder given"
tpath="$(norm_path "$TARGET")" || die "project folder not found (create it first): $TARGET"

home_path="$(norm_path "$HOME" || true)"
[ "$tpath" != "/" ] || die "refusing to install into the filesystem root"
if [ -n "$home_path" ] && [ "$tpath" = "$home_path" ]; then
  die "refusing to install into your home folder: <home>/.claude is your USER-level config shared by every project. Pick a project folder."
fi
case "$tpath" in "$KIT_DIR"|"$KIT_DIR"/*) die "the project folder is inside the kit folder: $tpath" ;; esac
[ ! -e "$tpath/.claude" ] || [ -d "$tpath/.claude" ] || die "$tpath/.claude exists but is not a folder"

claude_dir="$tpath/.claude"
data_dir="$claude_dir/dispatcher"
manifest="$data_dir/manifest.txt"
conf="$claude_dir/dispatcher.conf"

# ---- uninstall -------------------------------------------------------------
if [ "$UNINSTALL" -eq 1 ]; then
  [ -f "$manifest" ] || die "no manifest at $manifest: nothing installed by this kit here"
  say "Uninstall from: $tpath"
  UN_PATHS=(); UN_SUMS=()
  while read -r crc size path; do
    case "$crc" in ''|'#'*) continue ;; esac
    case "$path" in /*|*..*) note "skip (unsafe path in manifest): $path"; continue ;; esac
    [ -f "$tpath/$path" ] || continue
    UN_PATHS+=("$path"); UN_SUMS+=("$crc $size")
  done < "$manifest"
  if [ "${#UN_PATHS[@]}" -gt 0 ]; then
    i=0
    while read -r crc size path; do
      if [ "$crc $size" = "${UN_SUMS[$i]}" ]; then
        note "remove  ${UN_PATHS[$i]}"
        if [ "$DRY" -eq 0 ]; then rm -f "$tpath/${UN_PATHS[$i]}"; fi
      else
        note "keep (modified since install)  ${UN_PATHS[$i]}"
      fi
      i=$((i + 1))
    done < <(cd "$tpath" && cksum "${UN_PATHS[@]}")
  fi
  if [ "$DRY" -eq 0 ]; then
    for d in .claude/agents .claude/skills/dispatch .claude/skills/ticket-sync .claude/skills .claude/scripts; do rmdir "$tpath/$d" 2>/dev/null || true; done
  fi
  if [ "$PURGE" -eq 1 ]; then
    go=1
    if [ "$YES" -eq 0 ]; then
      printf 'Also delete dispatcher.conf and .claude/dispatcher/ (alerts, prompt records, backups)? [y/N]: ' >&2
      IFS= read -r ans || ans=""; case "${ans%$'\r'}" in y|Y|yes) go=1 ;; *) go=0 ;; esac
    fi
    if [ "$go" -eq 1 ]; then
      note "purge  .claude/dispatcher.conf and .claude/dispatcher/"
      if [ "$DRY" -eq 0 ]; then rm -f "${conf:?}"; rm -rf "${data_dir:?}"; rmdir "$claude_dir" 2>/dev/null || true; fi
    fi
  else
    note "kept .claude/dispatcher.conf and .claude/dispatcher/ (use --purge to remove them)"
  fi
  [ "$DRY" -eq 0 ] || say "(dry run: nothing was changed)"
  exit 0
fi

# ---- values ----------------------------------------------------------------
detect_repo_dir() {
  if [ -e "$tpath/.git" ]; then printf '.'; return 0; fi
  local d n=0 first=""
  for d in "$tpath"/*/; do
    [ -e "${d}.git" ] || continue
    n=$((n + 1)); d="${d%/}"; [ -n "$first" ] || first="${d##*/}"
  done
  if [ "$n" -eq 1 ]; then printf '%s' "$first"; fi
  return 0
}
detect_github() {
  [ -n "$repo_path" ] || return 0
  local url s
  url="$(git -C "$repo_path" remote get-url origin 2>/dev/null || true)"
  case "$url" in
    *github.com[:/]*) s="${url#*github.com[:/]}"; s="${s%.git}"; s="${s%/}"; printf '%s' "$s" ;;
  esac
  return 0
}
detect_base() {
  local b=""
  if [ -n "$repo_path" ]; then
    b="$(git -C "$repo_path" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"; b="${b#origin/}"
    [ -n "$b" ] || b="$(git -C "$repo_path" branch --show-current 2>/dev/null || true)"
  fi
  [ -n "$b" ] || b="main"
  printf '%s' "$b"
}
detect_tz() {
  local z
  z="$(date +%z 2>/dev/null || true)"
  if [[ "$z" =~ ^[+-][0-9]{4}$ ]]; then printf '%s:%s' "${z:0:3}" "${z:3:2}"; else printf '+00:00'; fi
}

CONF_EXISTS=0
if [ -f "$conf" ]; then
  CONF_EXISTS=1
  say "Found existing $conf: keeping its values (value options are ignored; edit the file to change them)."
  # shellcheck disable=SC1090
  . "$PAYLOAD/claude/scripts/lib-conf.sh"
  DISPATCH_CONF="$conf"
  PREFIX="$(conf_get TICKET_PREFIX TK)"; REPO_DIR="$(conf_get REPO_DIR)"; GITHUB="$(conf_get GITHUB_REPO)"
  BASE="$(conf_get BASE_BRANCH main)"; TESTCMD="$(conf_get TEST_COMMAND)"; NDS="$(conf_get NOTION_DATA_SOURCE_ID)"
  NDB="$(conf_get NOTION_DB_URL)"; TZOFF="$(conf_get TIMEZONE_OFFSET +00:00)"; MODEL="$(conf_get MASTER_MODEL opus)"
  EFFORT="$(conf_get MASTER_EFFORT)"
  [ "$SHIMS" != "$U" ] || SHIMS="yes"
else
  say "Claude session tickets $VERSION -> $tpath"
  resolve PREFIX "Ticket prefix (2-10 letters, e.g. TK)" "TK"
  repo_path=""
  resolve REPO_DIR "Git repository folder inside the project ('.' = the project itself)" "$(detect_repo_dir)"
  case "$REPO_DIR" in
    "") repo_path="" ;;
    ".") repo_path="$tpath" ;;
    /*|*..*|[A-Za-z]:*|*\\*) die "--repo-dir must be a relative folder inside the project (got '$REPO_DIR')" ;;
    *) repo_path="$tpath/$REPO_DIR" ;;
  esac
  resolve GITHUB "GitHub repository (owner/name)" "$(detect_github)"
  resolve BASE "Base branch for new work" "$(detect_base)"
  resolve TESTCMD "Test command that must pass before commits" ""
  resolve NDS "Notion data source ID (create the database first; can be filled in later)" ""
  resolve NDB "Notion database URL" ""
  resolve TZOFF "Time zone offset for log timestamps" "$(detect_tz)"
  resolve MODEL "Master session model" "opus"
  resolve EFFORT "Master session effort (low|medium|high|xhigh|max)" ""
  resolve SHIMS "Create open-master launchers in the project folder? (yes/no)" "yes"
fi

# ---- validate --------------------------------------------------------------
NDS="${NDS#collection://}"
case "$SHIMS" in y|Y|yes|YES|Yes) SHIMS="yes" ;; n|N|no|NO|No) SHIMS="no" ;; *) die "--root-shims must be yes or no" ;; esac
for v in "$PREFIX" "$REPO_DIR" "$GITHUB" "$BASE" "$TESTCMD" "$NDS" "$NDB" "$TZOFF" "$MODEL" "$EFFORT"; do
  if [[ "$v" =~ [[:cntrl:]] ]]; then die "values must not contain control characters or line breaks"; fi
done
[[ "$PREFIX" =~ ^[A-Za-z][A-Za-z0-9]{1,9}$ ]] || die "ticket prefix must be 2-10 letters/digits starting with a letter (got '$PREFIX')"
[[ -z "$GITHUB" || "$GITHUB" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "GitHub repository must look like owner/name (got '$GITHUB')"
[[ "$BASE" =~ ^[A-Za-z0-9._/-]+$ ]] || die "base branch has unexpected characters (got '$BASE')"
[[ -z "$NDS" || "$NDS" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || die "Notion data source ID must be a UUID (got '$NDS'); use the part after collection://"
[[ -z "$NDB" || "$NDB" =~ ^https:// ]] || die "Notion database URL must start with https://"
[[ "$TZOFF" =~ ^[+-][0-9]{2}:[0-9]{2}$ ]] || die "time zone offset must look like +09:00 (got '$TZOFF')"
[[ "$MODEL" =~ ^[A-Za-z0-9._-]+$ ]] || die "model name has unexpected characters (got '$MODEL')"
case "$EFFORT" in ""|low|medium|high|xhigh|max) ;; *) die "effort must be low|medium|high|xhigh|max or empty (got '$EFFORT')" ;; esac
case "$REPO_DIR" in ""|".") ;; /*|*..*|[A-Za-z]:*|*\\*) die "repo dir must be a relative folder inside the project (got '$REPO_DIR')" ;; esac
if [ -n "$REPO_DIR" ] && [ "$REPO_DIR" != "." ] && [ ! -d "$tpath/$REPO_DIR" ]; then
  note "warning: $tpath/$REPO_DIR does not exist yet (check-env will report it)"
fi

# ---- plan ------------------------------------------------------------------
say ""
say "Plan:"
note "project folder : $tpath"
note "installs into  : $claude_dir  (and launchers in the project folder: $SHIMS)"
if [ "$CONF_EXISTS" -eq 1 ]; then note "settings       : existing dispatcher.conf kept"; else
  note "ticket prefix  : $PREFIX"
  note "repository     : ${REPO_DIR:-<none>}   github: ${GITHUB:-<none>}   base: $BASE"
  note "test command   : ${TESTCMD:-<none>}"
  note "notion         : ${NDS:-<not set yet>}"
  note "time zone      : $TZOFF   master: $MODEL${EFFORT:+ / $EFFORT}"
fi
if [ "$DRY" -eq 0 ] && [ "$YES" -eq 0 ]; then
  printf 'Proceed? [Y/n]: ' >&2
  IFS= read -r ans || ans=""; case "${ans%$'\r'}" in ""|y|Y|yes) ;; *) say "Cancelled."; exit 1 ;; esac
fi

# ---- collect payload files and checksums (one find + one cksum per payload tree) -------------
DST=(); NEWSUM=()
while read -r crc size p; do
  DST+=(".claude/${p#./}"); NEWSUM+=("$crc $size")
done < <(cd "$PAYLOAD/claude" && find . -type f -exec cksum {} + | LC_ALL=C sort -k3)
if [ "$SHIMS" = "yes" ] && [ -d "$PAYLOAD/root" ]; then
  while read -r crc size p; do
    DST+=("${p#./}"); NEWSUM+=("$crc $size")
  done < <(cd "$PAYLOAD/root" && find . -type f -exec cksum {} + | LC_ALL=C sort -k3)
fi
N="${#DST[@]}"
[ "$N" -gt 0 ] || die "payload is empty"

# checksums of the files that already exist in the project (one cksum call)
EX_NAME=(); EX_SUM=(); existing=()
for ((i = 0; i < N; i++)); do [ -e "$tpath/${DST[$i]}" ] && existing+=("${DST[$i]}"); done
if [ "${#existing[@]}" -gt 0 ]; then
  while read -r crc size p; do EX_NAME+=("$p"); EX_SUM+=("$crc $size"); done < <(cd "$tpath" && cksum "${existing[@]}")
fi

# what the previous install recorded
MF_NAME=(); MF_SUM=()
if [ -f "$manifest" ]; then
  while read -r crc size p; do
    case "$crc" in ''|'#'*) continue ;; esac
    MF_NAME+=("$p"); MF_SUM+=("$crc $size")
  done < "$manifest"
fi

TS="$(date -u +%Y%m%dT%H%M%SZ)"
new_manifest=""
n_new=0; n_upd=0; n_same=0; n_rep=0; n_keep=0
COPY_DST=(); REPL_DST=()

say ""
say "Files:"
for ((i = 0; i < N; i++)); do
  dst="${DST[$i]}"; new="${NEWSUM[$i]}"
  cur=""; for ((j = 0; j < ${#EX_NAME[@]}; j++)); do [ "${EX_NAME[$j]}" = "$dst" ] && { cur="${EX_SUM[$j]}"; break; }; done
  prev=""; for ((j = 0; j < ${#MF_NAME[@]}; j++)); do [ "${MF_NAME[$j]}" = "$dst" ] && { prev="${MF_SUM[$j]}"; break; }; done
  if [ -z "$cur" ]; then act="new"
  elif [ "$cur" = "$new" ]; then act="same"
  elif [ -n "$prev" ] && [ "$prev" = "$cur" ]; then act="update"
  else
    case "$dst" in .claude/*) act="replace" ;; *) act="keep" ;; esac   # a differing launcher in the project root is the user's: keep it
  fi
  case "$act" in
    new)     n_new=$((n_new + 1));   COPY_DST+=("$dst") ;;
    update)  n_upd=$((n_upd + 1));   COPY_DST+=("$dst") ;;
    replace) n_rep=$((n_rep + 1));   COPY_DST+=("$dst"); REPL_DST+=("$dst") ;;
    same)    n_same=$((n_same + 1)) ;;
    keep)    n_keep=$((n_keep + 1)) ;;
  esac
  case "$act" in
    replace) printf '  %-8s%s  (the existing file is backed up to .claude/dispatcher/backup/%s/)\n' "$act" "$dst" "$TS" ;;
    keep)    printf '  %-8s%s  (a different file already exists; not overwritten)\n' "$act" "$dst" ;;
    *)       printf '  %-8s%s\n' "$act" "$dst" ;;
  esac
  if [ "$act" != "keep" ]; then new_manifest="${new_manifest}${new} ${dst}"$'\n'; fi
done

src_of() { case "$1" in .claude/*) REPLY="$PAYLOAD/claude/${1#.claude/}" ;; *) REPLY="$PAYLOAD/root/$1" ;; esac; }

if [ "$DRY" -eq 0 ] && [ "${#COPY_DST[@]}" -gt 0 ]; then
  # back up files we are about to replace
  for dst in ${REPL_DST[@]+"${REPL_DST[@]}"}; do
    d="${dst%/*}"; [ "$d" = "$dst" ] && d="."
    mkdir -p "$data_dir/backup/$TS/$d"; cp "$tpath/$dst" "$data_dir/backup/$TS/$dst"
  done
  # copy grouped by destination folder (one mkdir, then one cp per folder)
  dirs=""; mk=()
  for dst in "${COPY_DST[@]}"; do
    d="${dst%/*}"; [ "$d" = "$dst" ] && d="."
    case $'\n'"$dirs" in *$'\n'"$d"$'\n'*) ;; *) dirs="$dirs$d"$'\n'; mk+=("$tpath/$d") ;; esac
  done
  mkdir -p "${mk[@]}"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    srcs=()
    for dst in "${COPY_DST[@]}"; do
      dd="${dst%/*}"; [ "$dd" = "$dst" ] && dd="."
      if [ "$dd" = "$d" ]; then src_of "$dst"; srcs+=("$REPLY"); fi
    done
    cp "${srcs[@]}" "$tpath/$d/"
  done <<< "$dirs"
  chmod +x "$claude_dir"/scripts/*.sh "$tpath"/open-master.sh 2>/dev/null || true
fi

# ---- dispatcher.conf -------------------------------------------------------
conf_default() {
  case "$1" in
    TICKET_PREFIX) printf 'TK' ;; BASE_BRANCH) printf 'main' ;; TIMEZONE_OFFSET) printf '+00:00' ;;
    MASTER_MODEL) printf 'opus' ;; ALERT_LEVELS) printf 'error,attention' ;; ALERTS) printf 'on' ;; *) printf '' ;;
  esac
}
ALL_KEYS="TICKET_PREFIX REPO_DIR GITHUB_REPO BASE_BRANCH TEST_COMMAND NOTION_DATA_SOURCE_ID NOTION_DB_URL TIMEZONE_OFFSET MASTER_MODEL MASTER_EFFORT ALERT_LEVELS ALERTS"

say ""
if [ "$CONF_EXISTS" -eq 1 ]; then
  # which keys does the file already define? (read it once; no grep per key)
  present=" "
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"; line="${line#"${line%%[![:space:]]*}"}"
    case "$line" in ''|'#'*) continue ;; *=*) k="${line%%=*}"; k="${k%"${k##*[![:space:]]}"}"; present="$present$k " ;; esac
  done < "$conf"
  added=""
  for k in $ALL_KEYS; do
    case "$present" in
      *" $k "*) ;;
      *) added="$added $k"
         if [ "$DRY" -eq 0 ]; then printf '%s=%s\n' "$k" "$(conf_default "$k")" >> "$conf"; fi ;;
    esac
  done
  say "Config: kept $conf${added:+ (added missing keys:$added)}"
else
  say "Config: writing $conf"
  if [ "$DRY" -eq 0 ]; then
    mkdir -p "$claude_dir"
    {
      printf '%s\n' "# dispatcher.conf - settings for the dispatcher agent, skills and scripts (KEY=value, one per line)."
      printf '%s\n' "# Written by session-ticket-kit $VERSION. NO keys, tokens or passwords here. Lines starting with # are comments."
      printf '%s\n' "# Safe to edit. Re-running the installer keeps your values and only adds missing keys."
      printf '\n%s\n' "# Ticket prefix: tickets are PREFIX-12 and session names start with [PREFIX-12]. Must match the Notion Unique ID prefix."
      printf 'TICKET_PREFIX=%s\n' "$PREFIX"
      printf '\n%s\n' "# Git repository folder relative to the project ('.' = the project itself, empty = no code/PR features)."
      printf 'REPO_DIR=%s\n' "$REPO_DIR"
      printf '%s\n' "# owner/name on GitHub. Empty = read from the repository's origin remote with gh."
      printf 'GITHUB_REPO=%s\n' "$GITHUB"
      printf 'BASE_BRANCH=%s\n' "$BASE"
      printf '%s\n' "# Command that must pass before commits (empty = none)."
      printf 'TEST_COMMAND=%s\n' "$TESTCMD"
      printf '\n%s\n' "# Notion ticket database: data source ID (UUID, without the collection:// prefix) and its URL. See docs/NOTION-SCHEMA.md in the kit."
      printf 'NOTION_DATA_SOURCE_ID=%s\n' "$NDS"
      printf 'NOTION_DB_URL=%s\n' "$NDB"
      printf '\n%s\n' "# Time zone offset for progress-log timestamps, +HH:MM. (Git Bash 'date' ignores TZ, so it is set here.)"
      printf 'TIMEZONE_OFFSET=%s\n' "$TZOFF"
      printf '\n%s\n' "# Master session: model and effort (empty effort = model default). Some models need a plan or usage credits."
      printf 'MASTER_MODEL=%s\n' "$MODEL"
      printf 'MASTER_EFFORT=%s\n' "$EFFORT"
      printf '\n%s\n' "# Alerts from sub-sessions: levels pushed to you at once (error, attention, done), and a global on/off switch."
      printf 'ALERT_LEVELS=%s\n' "error,attention"
      printf 'ALERTS=%s\n' "on"
    } > "$conf"
  fi
fi

# ---- manifest --------------------------------------------------------------
if [ "$DRY" -eq 0 ]; then
  mkdir -p "$data_dir"
  { printf '# session-ticket-kit %s installed %s\n' "$VERSION" "$TS"; printf '%s' "$new_manifest"; } > "$manifest.tmp" && mv "$manifest.tmp" "$manifest"
fi

# ---- summary ---------------------------------------------------------------
say ""
if [ "$DRY" -eq 1 ]; then
  say "Dry run: $n_new new, $n_upd updated, $n_rep replaced (backed up), $n_same unchanged, $n_keep kept. Nothing was changed."
  exit 0
fi
say "Done: $n_new new, $n_upd updated, $n_rep replaced (backed up), $n_same unchanged, $n_keep kept."
say ""
say "Next steps:"
note "1) Check the environment:   sh \"$claude_dir/scripts/check-env.sh\"     (Windows PowerShell: powershell -NoProfile -ExecutionPolicy Bypass -File \"$claude_dir\\scripts\\check-env.ps1\")"
if [ -z "$NDS" ]; then
  note "2) Create the Notion database (kit docs/NOTION-SCHEMA.md), then put its data source ID in $conf"
else
  note "2) Notion data source is set in $conf"
fi
note "3) Open the master session from the project folder:  ./open-master.sh   (Windows: open-master.cmd)"
note "4) In the master, say: status    (it summarizes tickets and arms the alert monitor)"
if [ -e "$tpath/.git" ] || git -C "$tpath" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  say ""
  say "This folder is inside a git work tree. Consider adding to .gitignore (personal values and runtime data):"
  note ".claude/dispatcher.conf"
  note ".claude/dispatcher/"
  say "and to .gitattributes (CR characters break the shell scripts on macOS/Linux):"
  note ".claude/scripts/*.sh text eol=lf"
  note "open-master.sh text eol=lf"
fi
