# superpowers — vendored copy

Source: `superpowers` plugin 6.3.0 (claude-plugins-official), https://github.com/obra/superpowers.
License: MIT © 2025 Jesse Vincent — see `LICENSE` in this directory.

Copied into `.claude/skills/` so that Claude Code cloud sessions (which do not install plugins)
can run the `run-task-pipeline` process: brainstorming, writing-plans, executing-plans,
subagent-driven-development, systematic-debugging, verification-before-completion,
using-git-worktrees, finishing-a-development-branch, requesting-code-review,
test-driven-development.

Changes: `superpowers:<name>` references rewritten to `<name>` (no plugin namespace in the cloud).
Nothing else changed. One-off copy — not synced with the plugin.

Known dangling references (accepted): `executing-plans` → `../using-superpowers/references/`;
`test-driven-development` → `writing-skills`; `using-superpowers` and the plugin's SessionStart
hook are not copied. `brainstorming/scripts/server.cjs` looks for the plugin `package.json`
three levels up and runs without a version when it is absent. `writing-plans` still says
`docs/superpowers/plans/`; in this repo the `run-task-pipeline` flow puts plans in `docs/plans/`.
