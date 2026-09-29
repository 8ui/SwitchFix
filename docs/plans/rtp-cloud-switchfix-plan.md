# Пайплайн rtp в облаке SwitchFix — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** облачные сессии SwitchFix работают через пайплайн `rtp` так же, как локальные: копии
скиллов, хуки и шим в репо; локально хуки не срабатывают дважды.

**Architecture:** разовые копии `run-task-pipeline` и 10 скиллов superpowers в `.claude/skills/`;
`.claude/settings.json` вешает 4 хука на `.claude/rtp-hook.sh`, который молчит, если у
пользователя уже подключены глобальные хуки rtp; в облаке SessionStart кладёт `.claude/bin` на
PATH через `$CLAUDE_ENV_FILE`. Проектная специфика — `docs/tasks/.rtp.json` и CLAUDE.md.

**Tech Stack:** POSIX sh, Node ≥18 (ESM, без зависимостей), git, GitHub Actions (macos-15).

**Spec:** `docs/features/rtp-cloud-switchfix-spec.md`.

## Global Constraints

- Репо: `R=/Users/andrejsokolov/Desktop/projects/SwitchFix`, ветка `claude/rtp-cloud-pipeline`. Пушить только в `origin` (`8ui/SwitchFix`), никогда в `upstream`.
- Источники: `SK=~/.claude/skills/run-task-pipeline`, `SP=~/.claude/plugins/cache/claude-plugins-official/superpowers/6.3.0`. Их **не менять**.
- `C=$R/.claude/skills/run-task-pipeline` — копия rtp; регресс копии `sh $C/scripts/regress.sh` → exit 0 после каждого шага, где трогается копия.
- 10 скиллов: `brainstorming writing-plans executing-plans subagent-driven-development systematic-debugging verification-before-completion using-git-worktrees finishing-a-development-branch requesting-code-review test-driven-development`.
- Коммит после каждого шага (сообщения — conventional, с `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`).
- Трекер: после plan-review — `rtp steps 2026-09-29-rtp-generalize --from-plan docs/plans/rtp-cloud-switchfix-plan.md`, `rtp phase … --to impl`; каждый шаг заканчивается `rtp step … --done N` в том же ходе, что и коммит (иначе глобальный Stop-хук вернёт ход). После пуша — `rtp artifact … --branch claude/rtp-cloud-pipeline`, после PR — `--pr <url>`.
- «Пустой grep» проверять инверсией (`! grep …`), шаблоны `--include` — в кавычках (zsh иначе падает с `no matches found`, и пустой вывод выглядит зелёным).
- Временные папки — в scratchpad сессии, не голый `mktemp -d`. Блоки с `export` — одним вызовом Bash.

---

### Step 1: копии скиллов, лицензия, `.gitignore`

**Files:**
- Create: `$R/.claude/skills/run-task-pipeline/**` (копия `$SK`)
- Create: `$R/.claude/skills/<10 скиллов>/**` (копии из `$SP/skills`)
- Create: `$R/.claude/THIRD_PARTY/superpowers/LICENSE`, `NOTICE.md`
- Modify: `$R/.gitignore`

- [ ] **1.1 Копирование с сохранением режимов**

```sh
cd /Users/andrejsokolov/Desktop/projects/SwitchFix
SK=~/.claude/skills/run-task-pipeline; SP=~/.claude/plugins/cache/claude-plugins-official/superpowers/6.3.0
SKILLS="brainstorming writing-plans executing-plans subagent-driven-development systematic-debugging verification-before-completion using-git-worktrees finishing-a-development-branch requesting-code-review test-driven-development"
mkdir -p .claude/skills .claude/THIRD_PARTY/superpowers
cp -Rp "$SK" .claude/skills/run-task-pipeline
for s in $SKILLS; do cp -Rp "$SP/skills/$s" ".claude/skills/$s"; done
cp -p "$SP/LICENSE" .claude/THIRD_PARTY/superpowers/LICENSE
find .claude/skills -name .DS_Store -delete
```

- [ ] **1.2 `superpowers:X` → `X` в копиях superpowers**

```sh
for s in $SKILLS; do
  grep -rl "superpowers:" ".claude/skills/$s" | while IFS= read -r f; do
    perl -pi -e 's/\bsuperpowers:([a-z][a-z-]*)/$1/g' "$f"
  done
done
! grep -rn "superpowers:" .claude/skills --include='*.md' | grep -v "^.claude/skills/run-task-pipeline/"
```
Expected: последняя команда — exit 0 (совпадений нет). `perl -pi` сохраняет режим файла.

- [ ] **1.2b Сразу скрыть копии локально** (иначе до конца работы в списке скиллов дубли):
  прочитать `.claude/settings.local.json`, добавить на верхний уровень (разрешения не трогать):

```json
"skillOverrides": {
  "brainstorming": "off", "writing-plans": "off", "executing-plans": "off",
  "subagent-driven-development": "off", "systematic-debugging": "off",
  "verification-before-completion": "off", "using-git-worktrees": "off",
  "finishing-a-development-branch": "off", "requesting-code-review": "off",
  "test-driven-development": "off"
}
```
`jq -e '.skillOverrides|length==10' .claude/settings.local.json`; `git check-ignore .claude/settings.local.json`
— путь выведен. `skillOverrides` — ключ из схемы настроек Claude Code (значения on / name-only /
user-invocable-only / off); действие проверяется вживую в Step 6.

- [ ] **1.3 NOTICE.md** — `.claude/THIRD_PARTY/superpowers/NOTICE.md`:

```md
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
three levels up and runs without a version when it is absent.
```

- [ ] **1.4 `.gitignore`** — добавить в блок «Local / temporary files and tooling»:

```
.superpowers/
```

- [ ] **1.5 Проверка режимов и `server.cjs`**

```sh
git add .claude/skills .claude/THIRD_PARTY .gitignore
git ls-files -s .claude/skills | awk '$1=="100755"{print $4}' | sort
```
Expected ровно:
```
.claude/skills/brainstorming/scripts/start-server.sh
.claude/skills/brainstorming/scripts/stop-server.sh
.claude/skills/subagent-driven-development/scripts/review-package
.claude/skills/subagent-driven-development/scripts/sdd-workspace
.claude/skills/subagent-driven-development/scripts/task-brief
.claude/skills/systematic-debugging/find-polluter.sh
```
(+ файлы копии rtp, если они `+x` в `$SK` — сверить: `find $SK -type f -perm +111`.)

`server.cjs` проверить запуском (спека требует): `T=<scratchpad>/bs; mkdir -p "$T"`,
`.claude/skills/brainstorming/scripts/start-server.sh --project-dir "$T"` → в выводе URL сервера
без ошибки про `package.json`; затем `.claude/skills/brainstorming/scripts/stop-server.sh "<session dir из вывода>"`
(точные аргументы — по `--help`/тексту скрипта). `rm -rf "$T"`.

- [ ] **1.6 Регресс копии как есть** — `sh .claude/skills/run-task-pipeline/scripts/regress.sh; echo exit=$?` → `exit=0`.

- [ ] **1.7 Коммит** — `chore(claude): vendor run-task-pipeline and superpowers skills for cloud sessions`.

---

### Step 2: фиксы копии rtp — путь с пробелом/кириллицей и кавычечная форма

**Files:**
- Modify: `$C/scripts/lib.mjs:1-7,27`
- Modify: `$C/scripts/rtp.mjs:1823-1832`
- Modify/Test: `$C/scripts/regress.sh`

- [ ] **2.1 Падающие кейсы** — в `$C/scripts/regress.sh` перед ПОСЛЕДНИМИ строками `echo ""` / `echo "итог (все секции)…"` (после определения `mk`/`stop` ≈311-325):

```sh
echo "P1: скилл в пути с пробелом и кириллицей — rtp new находит шаблон"
SPD="$ROOT/my dir/проект/skill"; mkdir -p "$SPD"
cp -R "$(dirname "$RTP")" "$SPD/scripts"; cp -R "$(dirname "$RTP")/../templates" "$SPD/templates"
mkdir -p "$ROOT/sp/docs/tasks"
node "$SPD/scripts/rtp.mjs" new --title "Space path" --type chore --pipeline minimal --reason r --tasks-dir "$ROOT/sp/docs/tasks" >/dev/null 2>"$ROOT/p1.err" \
  && ls "$ROOT/sp/docs/tasks" | grep -q 'space-path' && ok "rtp new из пути с пробелом/кириллицей" || bad "rtp new упал: $(cat "$ROOT/p1.err")"

echo "P2: Stop засчитывает вызов rtp.mjs с путём в кавычках"
mk "$H/p2.jsonl" '[user("правлю"),asst(edit("u1",E.H+"/repo-b/src/x.ts")),res("u1","ok"),asst(bash("u2","node \"/x/.claude/skills/run-task-pipeline/scripts/rtp.mjs\" phase "+E.MINE+" --to impl --log s")),res("u2","ok")]'
OUT=$(stop "$H/repo-b" "$H/p2.jsonl" p2); RC=$?
[ $RC -eq 0 ] && ok "кавычечная форма засчитана" || bad "exit $RC: $OUT"
```

Проверить до этого, что `E.MINE` — задача из `$H/repo-b/docs/tasks` (см. кейс X13 ≈452: правка
`repo-b/src/x.ts` + `rtp verify E.MINE`). Если `MINE` лежит в другом репо — взять правку из
того же репо, что и `MINE`.

- [ ] **2.2 Прогнать** — `sh $C/scripts/regress.sh 2>&1 | sed -n '/^P1/,$p'` → P1 и P2 `FAIL`.

- [ ] **2.3 lib.mjs**: в импорты добавить `import { fileURLToPath } from 'node:url';`; строку 27:

```js
export const SKILL_DIR = resolve(fileURLToPath(new URL('..', import.meta.url)));
```

- [ ] **2.4 rtp.mjs**: в четырёх регэкспах `rtp(?:\.mjs)?\s+` → `rtp(?:\.mjs)?["']?\s+`:

```js
const RTP_TASK_ARG =
  /(?:^|[\s;&|(/])rtp(?:\.mjs)?["']?\s+(phase|artifact|steps|step|status|handoff|verify|debt|show|validate|next)\s+(?!-)(\S+)/g;
const RTP_MUTATING =
  /(?:^|[\s;&|(/])rtp(?:\.mjs)?["']?\s+(?:new|phase|artifact|steps|step|debt|verify|handoff)\b/;
const RTP_NEW = /(?:^|[\s;&|(/])rtp(?:\.mjs)?["']?\s+new\b/;
const RTP_VERIFY = /(?:^|[\s;&|(/])rtp(?:\.mjs)?["']?\s+verify\b/;
```

- [ ] **2.5 regress.sh**: все `node $RTP` → `node "$RTP"` (`sed -i '' 's/node \$RTP /node "$RTP" /g' $C/scripts/regress.sh`), проверить `grep -c 'node \$RTP ' ` → 0.

- [ ] **2.6 Регресс** — `exit=0`, P1/P2 `ok`.

- [ ] **2.7 Коммит** — `fix(rtp): skill dir via fileURLToPath; Stop hook counts quoted rtp.mjs calls`.
  В `## Decisions` задачи: «побочный эффект: `grep "rtp" …` с кавычкой после `rtp` теперь тоже
  считается мутирующим вызовом — как и раньше без кавычки; принято».

---

### Step 3: SKILL.md копии rtp

**Files:** Modify `$C/SKILL.md` (≈104-133 Tooling/invocation, ≈37, шаги 1/4a/5/6, «Cross-referenced skills» ≈455-470)

- [ ] **3.1 Invocation forms** — блок `Invocation forms (pick one — all three work):` … до рецепта шима включительно заменить на:

````md
Invocation forms (из корня репо):

```bash
# Шим проекта — .claude/bin/rtp. В облаке SessionStart-хук кладёт .claude/bin на PATH;
# локально rtp обычно уже есть в PATH (глобальный шим).
rtp <subcommand> [args]

# Прямой вызов — путь БЕЗ кавычек, иначе Stop-хук старых версий не узнает вызов
node .claude/skills/run-task-pipeline/scripts/rtp.mjs <subcommand> [args]
```

**Never `npx rtp`.** `rtp` is not an npm package: npx resolves an unrelated
registry package (`rtp@0.1.0`, no `bin` field) and dies with
`npm error could not determine executable to run`. The error reads like
"binary missing", but npx actually downloaded someone else's library.
The shim exists precisely so the bare `rtp` never falls through to npx —
if `.claude/bin/rtp` is missing, recreate it:

```bash
printf '#!/bin/sh\nexec node "$(cd "$(dirname "$0")/.." && pwd)/skills/run-task-pipeline/scripts/rtp.mjs" "$@"\n' > .claude/bin/rtp && chmod +x .claude/bin/rtp
```
````

- [ ] **3.2 Регресс-путь**: `` `sh ~/.claude/skills/run-task-pipeline/scripts/regress.sh` `` → `` `sh .claude/skills/run-task-pipeline/scripts/regress.sh` ``.

- [ ] **3.3 Ссылки на скиллы** — во всём файле `superpowers:<name>` для 10 скопированных имён:
  в разделе «Cross-referenced skills» и **первое упоминание каждого имени** внутри каждого из шагов
  1, 4a, 5, 6 и раздела Invariants → `` `superpowers:<name>` (без плагина — `<name>`) ``; прочие → `` `<name>` ``.
  Строку про `superpowers:code-reviewer` (≈37) не трогать.

- [ ] **3.4 Проверки**

```sh
! grep -nE "~/\.claude/(skills|bin)|\\\$HOME/\.claude" .claude/skills/run-task-pipeline/SKILL.md   # exit 0
grep -n "superpowers:" .claude/skills/run-task-pipeline/SKILL.md   # каждая строка — с «без плагина» или code-reviewer
```

- [ ] **3.5 Коммит** — `docs(rtp): project-local invocation and plugin-less skill names in the vendored SKILL.md`.

---

### Step 4: хуки и шим

**Files:** Create `$R/.claude/rtp-hook.sh`, `$R/.claude/settings.json`, `$R/.claude/bin/rtp`

- [ ] **4.1 `.claude/rtp-hook.sh`** — ровно текст из спеки §2.
- [ ] **4.2 `.claude/bin/rtp`** — текст из спеки §3; `chmod +x .claude/bin/rtp .claude/rtp-hook.sh`.
- [ ] **4.3 `.claude/settings.json`**:

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "sh \"${CLAUDE_PROJECT_DIR:-.}/.claude/rtp-hook.sh\" hook-sessionstart" }] }
    ],
    "PostToolUse": [
      { "matcher": "Edit|Write|MultiEdit", "hooks": [{ "type": "command", "command": "sh \"${CLAUDE_PROJECT_DIR:-.}/.claude/rtp-hook.sh\" hook-postedit" }] }
    ],
    "PreCompact": [
      { "hooks": [{ "type": "command", "command": "sh \"${CLAUDE_PROJECT_DIR:-.}/.claude/rtp-hook.sh\" hook-precompact" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "sh \"${CLAUDE_PROJECT_DIR:-.}/.claude/rtp-hook.sh\" hook-stop" }] }
    ]
  }
}
```

- [ ] **4.4 Критерий 6 (jq)**

```sh
jq -e '(.hooks|keys)==["PostToolUse","PreCompact","SessionStart","Stop"]
  and .hooks.PostToolUse[0].matcher=="Edit|Write|MultiEdit"
  and ([.hooks|to_entries|sort_by(.key)[]|.value[0].hooks[0].command] ==
       ["sh \"${CLAUDE_PROJECT_DIR:-.}/.claude/rtp-hook.sh\" hook-postedit",
        "sh \"${CLAUDE_PROJECT_DIR:-.}/.claude/rtp-hook.sh\" hook-precompact",
        "sh \"${CLAUDE_PROJECT_DIR:-.}/.claude/rtp-hook.sh\" hook-sessionstart",
        "sh \"${CLAUDE_PROJECT_DIR:-.}/.claude/rtp-hook.sh\" hook-stop"])' .claude/settings.json
```
(`keys` сортирует, `to_entries` — нет, поэтому `sort_by(.key)`.)

- [ ] **4.5 Критерий 4 (гвард локально)** — `PATH=/usr/bin:/bin /bin/sh .claude/rtp-hook.sh hook-stop </dev/null; echo "exit=$?"` → `exit=0`, без вывода. `node` лежит только в `~/.nvm/…`, поэтому при несработавшем гварде был бы exit 127 (проверить заранее: `PATH=/usr/bin:/bin command -v node` — пусто).

- [ ] **4.6 Критерий 5 (без глобальных хуков)** — один вызов Bash, `SPAD` = scratchpad сессии:

```sh
R=$PWD; T="$SPAD/c5"; rm -rf "$T"; mkdir -p "$T/cfg"
export CLAUDE_CONFIG_DIR="$T/cfg" CLAUDE_PROJECT_DIR="$R"
# a) PATH через CLAUDE_ENV_FILE
echo '{"source":"startup","cwd":"'"$R"'"}' | CLAUDE_ENV_FILE="$T/env" sh .claude/rtp-hook.sh hook-sessionstart >/dev/null
grep -qF "export PATH=\"$R/.claude/bin:" "$T/env" && echo "OK-a" || echo "FAIL-a"
# b) Stop: t1 — правка Sources без rtp → 2 и просьба завести задачу; t2 — затем кавычечный rtp.mjs phase → 0
gen() { node -e '
const fs=require("fs");const [f,r,withRtp]=process.argv.slice(1);
const L=[{type:"user",message:{content:"правлю"}},
 {type:"assistant",message:{content:[{type:"tool_use",id:"u1",name:"Edit",input:{file_path:r+"/Sources/x.swift"}}]}},
 {type:"user",message:{content:[{type:"tool_result",tool_use_id:"u1",content:"ok"}]}}];
if(withRtp==="1")L.push({type:"assistant",message:{content:[{type:"tool_use",id:"u2",name:"Bash",input:{command:"node \""+r+"/.claude/skills/run-task-pipeline/scripts/rtp.mjs\" phase 2026-09-29-rtp-generalize --to impl --log s"}}]}},
 {type:"user",message:{content:[{type:"tool_result",tool_use_id:"u2",content:"ok"}]}});
fs.writeFileSync(f,L.map(o=>JSON.stringify(o)).join("\n")+"\n");' "$1" "$R" "$2"; }
gen "$T/t1.jsonl" 0; gen "$T/t2.jsonl" 1
echo '{"cwd":"'"$R"'","transcript_path":"'"$T/t1.jsonl"'","session_id":"s1","stop_hook_active":false}' | sh .claude/rtp-hook.sh hook-stop >"$T/o1" 2>&1; echo "t1 exit=$?"
grep -q "задачи в этой сессии нет" "$T/o1" && echo "OK-b1" || { echo "FAIL-b1"; cat "$T/o1"; }
echo '{"cwd":"'"$R"'","transcript_path":"'"$T/t2.jsonl"'","session_id":"s2","stop_hook_active":false}' | sh .claude/rtp-hook.sh hook-stop >/dev/null 2>&1; echo "t2 exit=$?"
# c) шим
.claude/bin/rtp list | head -3
unset CLAUDE_CONFIG_DIR CLAUDE_PROJECT_DIR; rm -rf "$T"
```
Expected: `OK-a`, `t1 exit=2`, `OK-b1`, `t2 exit=0`, таблица задач. Файл `Sources/x.swift` не создаётся —
хук читает транскрипт. Вывод сохранить для `rtp verify --record` (Step 7).

- [ ] **4.7 Коммит** — `feat(claude): project hooks and rtp shim for cloud sessions, guarded against double-firing`;
  затем `git ls-files -s .claude/bin/rtp .claude/rtp-hook.sh` — оба `100755`.

---

### Step 5: `.rtp.json` и CLAUDE.md

**Files:** Create `$R/docs/tasks/.rtp.json`; Modify `$R/CLAUDE.md` (новый раздел `## Process` перед `## Debugging`)

- [ ] **5.1 `.rtp.json`** — ровно из спеки §4. Проверка на пробной задаче в scratchpad
  (`mkdir -p $SPAD/p/docs/tasks; cp docs/tasks/.rtp.json $SPAD/p/docs/tasks/`, `rtp new … --tasks-dir`,
  `rtp phase … --to review`, `rtp next … --tasks-dir`): 3 строки `--run` и 1 `--record`.
- [ ] **5.2 CLAUDE.md**:

```md
## Process

- Every code change goes through the `run-task-pipeline` skill (its triage picks the preset). Process
  skills are `superpowers:*`; in cloud sessions the same skills exist without the prefix (vendored in
  `.claude/skills/`, one-off copies — edit `rtp` there and run its `scripts/regress.sh`).
- Task tracker: `docs/tasks/`. CLI: `rtp`, **never `npx rtp`** (an unrelated npm package). If `rtp` is not
  on PATH, from the repo root: `node .claude/skills/run-task-pipeline/scripts/rtp.mjs <sub>` (no quotes
  around the path). `rtp next <id>` in the review phase prints this project's checks from `docs/tasks/.rtp.json`.
- Cloud sessions (`CLAUDE_CODE_REMOTE=true`, Ubuntu) have no Swift: do not run the swift commands; push the
  branch and record the green CI run (`.github/workflows/ci.yml` runs on `claude/**`):
  `rtp verify <id> --record "CI зелёный: <run url>"`.
- Cloud sessions cannot push tags: a release there = bump the version in `Resources/Info.plist` on master;
  the `v*` tag and the GitHub release are made locally.
- Never push to `upstream` (`rundax/SwitchFix`).
```

- [ ] **5.3 Коммит** — `docs(claude): pipeline process and cloud limits; rtp project config`.

---

### Step 6: проверка дублей скиллов вживую

**Files:** `docs/tasks/2026-09-29-rtp-generalize.md` (`## Decisions`, правка Edit-ом)

- [ ] **6.1** Посмотреть список скиллов, который сессия видит после Steps 1–5 (обновлённое
  напоминание о доступных скиллах): видны ли `superpowers:brainstorming` и прочие, скрыты ли
  копии без префикса; сколько `run-task-pipeline` и какой (личные скиллы должны быть приоритетнее
  проектных). Если в текущей сессии список не обновился — попросить пользователя открыть новую
  локальную сессию в SwitchFix и прислать вывод `/skills`.
- [ ] **6.2** Итог — строками в `## Decisions` задачи.

### Step 7: PR, CI, доказательства

- [ ] **7.1** Полный регресс копии — `rtp verify 2026-09-29-rtp-generalize --run "sh .claude/skills/run-task-pipeline/scripts/regress.sh" --timeout 300`.
- [ ] **7.2** Критерии 2, 3, 6, 7 — `rtp verify … --run "<команда>"` по одной (grep-критерии — в форме `! grep …`); критерии 4 и 5 — `rtp verify … --record "<что проверено>" --out "<вывод из 4.5/4.6>"`.
- [ ] **7.3** `git push -u origin claude/rtp-cloud-pipeline`; `gh pr create --repo 8ui/SwitchFix --base master` (тело: что, зачем, как проверить в облаке; в конце `🤖 Generated with [Claude Code](https://claude.com/claude-code)`).
- [ ] **7.4** Дождаться CI (ccd_pr tools) → `rtp verify … --record "CI зелёный: <url>"`.
- [ ] **7.5** Ревьюер-субагент по diff ветки против master + спеке.

---

### Step 8: облачная проверка (пользователь) и закрытие

- [ ] **8.1** Пользователь запускает облачную сессию на `claude/rtp-cloud-pipeline` с маленькой
  задачей; проверить: `command -v rtp` → `.claude/bin/rtp`; задача заведена в `docs/tasks`; после
  правки без `rtp` Stop возвращает ход. Итог — `rtp verify … --record "облако: …"`.
- [ ] **8.2** Долги: перенос `fileURLToPath` и кавычечной формы в глобальный скилл; риск версий
  глобальных хуков; гвард не видит хуки rtp, подключённые в `settings.local.json` или managed settings. Мерж PR — по решению пользователя; `rtp phase … --to done`.
