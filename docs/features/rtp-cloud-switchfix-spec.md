# Спека: пайплайн `rtp` в облачных сессиях SwitchFix — подзадача 2

Задача: `docs/tasks/2026-09-29-rtp-generalize.md` (подзадача 1 — обобщение скилла — закрыта,
см. `docs/features/rtp-generalize-spec.md`). Ветка: `claude/rtp-cloud-pipeline`, PR в `8ui/SwitchFix`.

## Проблема

Облачная сессия Claude Code (claude.ai/code) клонирует только репозиторий. `~/.claude`
(скилл `run-task-pipeline`, шим `rtp`, хуки из `~/.claude/settings.json`, плагин `superpowers`)
туда не попадает, поэтому облачный агент работает вне пайплайна: без трекера задач, без
ревью-гейтов, без Stop-хука.

Что облако берёт из репо (docs: code.claude.com/docs/en/claude-code-on-the-web —
«What carries over»): `.claude/skills/`, `.claude/agents/`, `.claude/commands/`, хуки и
разрешения из `.claude/settings.json`, `CLAUDE.md`. Плагины из `enabledPlugins` /
`extraKnownMarketplaces` **не ставятся**. В облаке `CLAUDE_CODE_REMOTE=true`, локально — никогда.
Хукам доступны `$CLAUDE_PROJECT_DIR` и (для SessionStart) `$CLAUDE_ENV_FILE`: `export`-строки,
дописанные в него, действуют во всех последующих Bash-командах сессии (docs: hooks, SessionStart);
stdin с JSON события проходит в обёртку с `exec`; stdout SessionStart попадает в контекст.

## Решение

### 1. Копии скиллов (разовые, без скрипта синхронизации)

- `.claude/skills/run-task-pipeline/` — копия `~/.claude/skills/run-task-pipeline/`
  (`SKILL.md`, `scripts/`, `templates/`, `references/`) на момент подзадачи 1. Дальше живёт
  своей жизнью; расхождение с глобальной версией — принятое следствие решения «без sync».
- 10 скиллов `superpowers` 6.3.0 (из `~/.claude/plugins/cache/claude-plugins-official/superpowers/6.3.0/skills/`)
  целиком, с подпапками: `brainstorming`, `writing-plans`, `executing-plans`,
  `subagent-driven-development`, `systematic-debugging`, `verification-before-completion`,
  `using-git-worktrees`, `finishing-a-development-branch`, `requesting-code-review`,
  `test-driven-development` — замыкание ссылок `superpowers:*` из пайплайна.
  **Копировать `cp -Rp`** (сохранить `+x` у `brainstorming/scripts/*.sh`,
  `subagent-driven-development/scripts/*`, `systematic-debugging/find-polluter.sh`).
- Лицензия — вне папки скиллов: `.claude/THIRD_PARTY/superpowers/LICENSE` (MIT © 2025 Jesse
  Vincent, как есть) и `.claude/THIRD_PARTY/superpowers/NOTICE.md`: источник, версия 6.3.0,
  список скопированных скиллов, внесённые правки, известные висячие ссылки (ниже).
- Не копируем: `using-superpowers` и SessionStart-хук плагина (`hooks/hooks.json`,
  `${CLAUDE_PLUGIN_ROOT}`). В облаке дисциплину «вызывай скиллы» держит раздел «Процесс» в
  CLAUDE.md (§5) и описание скилла `run-task-pipeline`. Висячие ссылки, принятые как есть:
  `executing-plans` → `../using-superpowers/references/`, `test-driven-development` →
  `writing-skills`; `brainstorming/scripts/server.cjs` ищет `package.json` на три уровня выше —
  не находит и работает без версии (проверить запуском при реализации).

**Правки в копиях**:
- копии superpowers: все `superpowers:<name>` → `<name>`. Больше ничего не меняем.
- копия `run-task-pipeline/scripts/lib.mjs:27`: `SKILL_DIR` через
  `fileURLToPath(new URL('..', import.meta.url))` вместо `.pathname` — репо может лежать в
  пути с пробелами/кириллицей, а `.pathname` оставляет `%20`/`%D0%BF` и ломает `TEMPLATE_PATH`.
- копия `run-task-pipeline/scripts/rtp.mjs` (≈1829-1832): регэкспы `RTP_MUTATING`, `RTP_NEW`,
  `RTP_VERIFY` и `RTP_TASK_ARG` принимают закрывающую кавычку после `rtp`/`rtp.mjs`
  (`rtp(?:\.mjs)?["']?\s+…`) — иначе Stop-хук не видит вызов
  `node "$CLAUDE_PROJECT_DIR/…/rtp.mjs" phase X` и требует завести задачу повторно.
- копия `run-task-pipeline/SKILL.md`:
  - ссылки на скиллы `superpowers:<name>` → `` `superpowers:<name>` (без плагина — `<name>`) ``
    в разделе «Cross-referenced skills» и первом упоминании в каждом шаге; остальные — `<name>`.
    Строка ≈37 про `superpowers:code-reviewer` («это СКИЛЛ, не `subagent_type`») остаётся —
    это предупреждение, не ссылка на скопированный скилл;
  - «Invocation forms»: шим `.claude/bin/rtp` (в облаке на PATH через SessionStart, §2);
    прямой вызов без кавычек `node .claude/skills/run-task-pipeline/scripts/rtp.mjs <sub>`
    из корня репо; форму `/rtp` убрать; рецепт пересоздания шима — проектный, без `$HOME`;
  - регресс: `sh .claude/skills/run-task-pipeline/scripts/regress.sh`;
  - упоминания `~/.claude` в описании поведения Stop-хука остаются (это поведение, не путь).
- `regress.sh` копии: `node "$RTP"` в кавычках везде; новые кейсы — путь скилла с пробелом и
  кириллицей (`rtp new` работает), кавычечная форма вызова засчитывается Stop-хуком.

### 2. Хуки: `.claude/settings.json` (в git) + `.claude/rtp-hook.sh`

`.claude/rtp-hook.sh`:
```sh
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
```

- После ревью кода реализация уточнена (итог — в `.claude/rtp-hook.sh`): гвард смотрит и `settings.local.json` и ловит `rtp(.mjs)? hook-` в любой записи; нет `node` → сообщение в stderr и exit 1; строка PATH пишется один раз и в одинарных кавычках. Шим разрешает симлинки.
- Гвард — «глобальные хуки rtp подключены в настройках пользователя», а не наличие папки
  скилла и не `CLAUDE_CODE_REMOTE`: у человека со скиллом, но без хуков, работают хуки копии;
  у склонировавшего репо без глобального скилла — тоже.
- Риск версий: у кого глобальные хуки подключены, тот гоняет свой (возможно, старый) `rtp`
  против этого репо. Принимаем, записываем в долг.

`.claude/settings.json` — только `hooks`, те же четыре события, что в глобальных настройках:
`SessionStart` → `hook-sessionstart`, `PostToolUse` (matcher `Edit|Write|MultiEdit`) →
`hook-postedit`, `PreCompact` → `hook-precompact`, `Stop` → `hook-stop`; каждая команда —
ровно `sh "${CLAUDE_PROJECT_DIR:-.}/.claude/rtp-hook.sh" <sub>` (с `:-.` команда не
превращается в `sh "/.claude/…"` при неустановленной переменной).

### 3. Шим `.claude/bin/rtp`

```sh
#!/bin/sh
# rtp is NOT an npm package: `npx rtp` fetches an unrelated registry package.
exec node "$(cd "$(dirname "$0")/.." && pwd)/skills/run-task-pipeline/scripts/rtp.mjs" "$@"
```
Режим `100755` в git.

### 4. `docs/tasks/.rtp.json` SwitchFix

```json
{
  "baseBranch": "origin/master",
  "verify": [
    "swift build -c release",
    { "run": "swift run -c release TestRunner", "timeout": 900 },
    { "run": "swift run -c release InputPipelineTestRunner", "timeout": 900 },
    { "record": "CI зелёный: <ссылка на ран GitHub Actions>" }
  ]
}
```
- `baseBranch: origin/master` — в облачном клоне на ветке `claude/*` локального `master` может
  не быть (иначе предупреждение на каждый handoff); локально `origin/master` тоже есть.
- `reviewers` не задаём — своих агентов у проекта нет, дефолт `general-purpose`.

### 5. CLAUDE.md SwitchFix — раздел «Процесс»

- Каждая задача с правкой кода — через скилл `run-task-pipeline` (triage выбирает пресет);
  скиллы процесса — `superpowers:*`, в облаке те же без префикса (копии в `.claude/skills/`).
- CLI — `rtp`, **никогда `npx rtp`**; если `rtp` не на PATH — из корня репо
  `node .claude/skills/run-task-pipeline/scripts/rtp.mjs <sub>` (без кавычек вокруг пути).
- Трекер — `docs/tasks/`; команды проверки печатает `rtp next <id>` в фазе review.
- Облако (`CLAUDE_CODE_REMOTE=true`, Ubuntu): Swift нет → swift-команды не запускать;
  доказательство — `rtp verify <id> --record "CI зелёный: <url рана>"` после пуша ветки
  (CI `.github/workflows/ci.yml` запускается на `claude/**`).
- Облако не пушит теги: релиз = облако поднимает версию в `Resources/Info.plist` в master;
  тег `v*` и GitHub release — локально.
- `upstream` (`rundax/SwitchFix`) — не пушить.
- Копии скиллов в `.claude/skills/` разовые; правки `rtp` — в копии, с её регрессом.

### 6. Прочее в репо

- `.gitignore`: `.superpowers/` (визуальный компаньон brainstorming пишет туда сессии).

### 7. Локальные настройки (не в git)

`.claude/settings.local.json`: к существующему содержимому (разрешения пользователя —
сохранить как есть) добавить `skillOverrides` = `"off"` для 10 копий superpowers.

Проверить вживую (записать в `## Decisions`):
- `brainstorming: "off"` не скрывает `superpowers:brainstorming`;
- одноимённый `run-task-pipeline` (глобальный + копия): какой виден/вызывается. Если копия —
  допустимо (её SKILL.md работает и с плагином). Если оба — долг, не скрывать (по имени может
  скрыться и глобальный).

## Критерии приёмки

1. `sh .claude/skills/run-task-pipeline/scripts/regress.sh` — exit 0, включая новые кейсы
   (путь с пробелом/кириллицей; кавычечная форма вызова засчитана Stop-хуком).
2. `! grep -rn "superpowers:" .claude/skills --include='*.md' | grep -v "^.claude/skills/run-task-pipeline/"` — exit 0;
   в копии rtp каждое `superpowers:X` — с пометкой «без плагина — `X`», кроме строки про
   `superpowers:code-reviewer` (предупреждение «не subagent_type»).
3. `! grep -nE "~/\.claude/(skills|bin)|\\\$HOME/\.claude" .claude/skills/run-task-pipeline/SKILL.md` — exit 0.
4. Локально (глобальные хуки подключены): `PATH=/usr/bin:/bin /bin/sh .claude/rtp-hook.sh hook-stop </dev/null` —
   exit 0 и пустой вывод (`node` вне `/usr/bin:/bin`, так что без гварда был бы exit 127).
5. Без глобальных хуков (`CLAUDE_CONFIG_DIR` на пустую временную папку, `CLAUDE_PROJECT_DIR` = репо):
   - `hook-sessionstart` с `CLAUDE_ENV_FILE` дописывает `export PATH="<репо>/.claude/bin:$PATH"`;
   - `hook-stop` на транскрипте с правкой `<репо>/Sources/x.swift` без `rtp` — exit 2 и просьба
     завести задачу; с последующим `node "<репо>/.claude/…/rtp.mjs" phase <id> …` — exit 0;
   - `.claude/bin/rtp list` — печатает задачи `docs/tasks`.
6. `jq` по `.claude/settings.json`: ровно ключи `PostToolUse, PreCompact, SessionStart, Stop`;
   matcher PostToolUse = `Edit|Write|MultiEdit`; каждая команда =
   `sh "${CLAUDE_PROJECT_DIR:-.}/.claude/rtp-hook.sh" <sub>` с верным `<sub>`.
7. `git ls-files -s` — `100755` у `.claude/bin/rtp` и у исполняемых скриптов копий superpowers
   (тех же, что `100755`/`+x` в плагине).
8. CI на ветке зелёный (Swift-сборка не затронута).
9. **До мержа** — облачная сессия на ветке `claude/rtp-cloud-pipeline` (запускает пользователь):
   `rtp` на PATH, маленькая задача → `docs/tasks/<id>.md`, фазы двигаются, Stop-хук возвращает
   ход, если после правки кода фаза не обновлена. Результат — `rtp verify --record`.
10. Локальные проверки дублей записаны в `## Decisions` задачи.

## Вне рамок

- Скрипт синхронизации копий — отвергнут (разовая копия).
- Setup-скрипт облачного окружения — не нужен, всё ставится из репо.
- Перенос фиксов `fileURLToPath` и кавычечной формы в глобальный скилл — долг.
