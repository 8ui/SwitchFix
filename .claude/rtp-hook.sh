#!/bin/sh
# Project copy of the rtp hooks. Where the user's own settings already wire the
# global rtp hooks (a local machine), those run — do nothing here.
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
grep -qs 'run-task-pipeline/scripts/rtp.mjs hook-' "$CFG" && exit 0
DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
if [ "$1" = "hook-sessionstart" ] && [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$DIR/.claude/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi
exec node "$DIR/.claude/skills/run-task-pipeline/scripts/rtp.mjs" "$@"
