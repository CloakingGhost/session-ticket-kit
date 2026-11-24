#!/bin/sh
# Environment check you can run BEFORE installing (macOS, Linux, Git Bash). Read-only.
# After installing, use <project>/.claude/scripts/check-env.sh instead (it also checks the project's config).
# Usage: sh check-env.sh [--project DIR]
exec sh "$(dirname "$0")/payload/claude/scripts/check-env.sh" "$@"
