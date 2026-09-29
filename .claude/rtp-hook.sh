#!/bin/sh
# Project copy of the rtp hooks. Where the user's own settings already wire the
# global rtp hooks (a local machine), those run — do nothing here.
CFG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
grep -qsE "rtp(\.mjs)?[\"']? +hook-" "$CFG_DIR/settings.json" "$CFG_DIR/settings.local.json" && exit 0
command -v node >/dev/null 2>&1 || { echo "rtp: node not found — rtp hooks disabled" >&2; exit 1; }
DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
if [ "$1" = "hook-sessionstart" ] && [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  # SessionStart also fires on resume/clear/compact — add the line once.
  # Single-quoted path: a checkout under a path with ", $ or ` must not break sourcing.
  if ! grep -qsF "$DIR/.claude/bin" "$CLAUDE_ENV_FILE"; then
    q=$(printf '%s' "$DIR/.claude/bin" | sed "s/'/'\\\\''/g")
    printf "export PATH='%s':\"\$PATH\"\n" "$q" >> "$CLAUDE_ENV_FILE"
  fi
fi
exec node "$DIR/.claude/skills/run-task-pipeline/scripts/rtp.mjs" "$@"
