#!/usr/bin/env bash
# Opens the master (dispatcher) session. Works on macOS, Linux and Windows Git Bash.
# Model and effort come from .claude/dispatcher.conf (MASTER_MODEL, MASTER_EFFORT; empty effort = model default).
set -eu
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/.claude/scripts/lib-conf.sh"
model="$(conf_get MASTER_MODEL opus)"
effort="$(conf_get MASTER_EFFORT)"
cd "$here"
args=(--agent dispatcher --model "$model" --name master)
if [ -n "$effort" ]; then args+=(--effort "$effort"); fi
exec claude "${args[@]}" "Master start: arm the alert monitor and summarize the open tickets in one line."
