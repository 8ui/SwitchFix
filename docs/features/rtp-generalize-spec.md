# Спека: обобщить `rtp` (run-task-pipeline) — подзадача 1

Задача: `docs/tasks/2026-09-29-rtp-generalize.md`. Подзадача 2 (копия скилла в SwitchFix для
облачных сессий) — отдельная спека после завершения этой.

Пути ниже — относительно `~/.claude/skills/run-task-pipeline/`, если не указано иное.

## Проблема

Скилл (CLI `rtp`) написан под restoplace-frontend. В другом проекте он подсказывает чужие
команды, ревьюеров и примеры:

- `SKILL.md`: `npm run build` / `npm run lint` в примере verify (≈340); ревьюеры
  `frontend-invariants-reviewer`, `legacy-parity-auditor`, `caveman:cavecrew-reviewer` (≈34, 354, 456);
  раздел Delegation (`migration-module`, `openapi-codegen`, ≈63); «~10 worktree с общим
  `docs/tasks`» (≈177 — к тому же неверно: в restoplace `docs/tasks` отслеживается git отдельно
  в каждом worktree); «ahead/behind master» (≈383); `/debts-report` (≈366, 406);
  строка про `docs/migration/modules` (≈418); пример `fix-scheme-zoom` (≈224).
- `scripts/rtp.mjs`: примеры `fix-scheme-zoom` / `Konva` / `npm run lint` в общем `--help`
  (≈129–141); `npm run lint` в `rtp verify --help` (≈1362) и в подсказке фазы `review`
  (`nextActionFor`, ≈1163); «ahead/behind master» в `rtp handoff --help` (≈1213) и в тексте
  handoff (≈1259); `/debts-report` в `validate` (≈596, 701) и `debt --help` (≈884);
  комментарий про «~10 worktrees sharing» (≈1879).
- `scripts/lib.mjs:706` `gitContext`: `master...HEAD` зашит; поля `aheadOfMaster`/`behindMaster`.
- `templates/task.md:38` и `references/anti-rationalization.md:20`: `/debts-report`.

## Решение

### 1. Конфиг проекта `docs/tasks/.rtp.json`

Необязательный файл **в папке трекера той задачи, с которой работает команда**. Все поля
необязательны:

```json
{
  "baseBranch": "master",
  "verify": [
    "npm run build",
    { "run": "npm run test:remote -- --changed master", "timeout": 900 },
    { "record": "CI зелёный: <ссылка на ран>" }
  ],
  "reviewers": ["frontend-invariants-reviewer", "legacy-parity-auditor"]
}
```

- `baseBranch` — строка, ветка для ahead/behind в handoff.
- `verify` — массив. Элемент: строка (= `{run: <строка>}`), `{run, timeout?}` (`timeout` —
  положительное целое, сек.) или `{record}`. Порядок сохраняется.
- `reviewers` — массив непустых строк, `subagent_type` для ревью кода, в порядке предпочтения.
- Неизвестные поля игнорируются.

**Загрузка** — `loadProjectConfig(tasksDir)` в `lib.mjs`, возвращает нормализованный
`{ baseBranch?, verify: [], reviewers: [] }`:
- файла нет → пустой конфиг, без вывода;
- битый JSON / корень не объект → весь конфиг пуст; неверный тип поля → поле пусто;
  элемент `verify`/`reviewers` неверной формы → отброшен поштучно. В каждом случае — строка
  `rtp: <путь>/.rtp.json: <причина> — использую умолчания` в **stderr**. Никогда не бросает.

**Откуда берётся `tasksDir`**: всегда `dirname(<файл задачи>)`, не cwd и не `--tasks-dir`
напрямую. Задача может лежать в другом репо, чем cwd (SessionStart/Stop-хуки, `rtp handoff`
с абсолютным путём) — конфиг должен быть того проекта, которому принадлежит задача.

### 2. Подсказки verify и ревьюеров (только подсказки — `rtp` сам ничего не запускает)

`nextActionFor(fm, cfg, { verbose = false } = {})`. Конфиг загружают по `dirname(file)`:
`buildStatusBlock(file)` (им пользуются `rtp status`, `rtp step`, SessionStart-хук),
`cmdNext`, `cmdHandoff`. Прочие фазы, кроме `review`, не меняются.

Фаза `review`, `verbose: true` (`rtp next`), многострочно:

```
rtp verify <id> --run '<cmd>' [--timeout N]      # по строке на каждый run
rtp verify <id> --record '<text>'                # по строке на каждый record
ревьюер: <r1> / <r2> (иначе general-purpose)     # только если reviewers непуст
затем rtp phase <id> --to done
```

- `verify` пуст → первая строка нейтральная:
  `rtp verify <id> --run '<команды проверки из CLAUDE.md проекта>'`. `reviewers` пуст →
  строка `ревьюер: субагент из списка агентов сессии (иначе general-purpose)`.
- Аргументы экранируются одинарными кавычками для sh (`'` → `'\''`), чтобы строку можно было
  вставить как есть.

Фаза `review`, `verbose: false` (`rtp status`, `rtp step`, SessionStart, `## Handoff`), одна строка:
- `verify` непуст: `rtp verify по командам проекта (rtp next <id>), затем ревью субагентом → rtp phase <id> --to done`;
- `verify` пуст: `rtp verify <id> --run "<команды проверки из CLAUDE.md проекта>", затем ревью субагентом → rtp phase <id> --to done`.

**Сознательное изменение для restoplace**: `rtp status`/handoff больше не показывают
`npm run lint` — конкретные команды только в `rtp next`. `rtp next` теперь подсказывает и
`test:remote` (~5.5 мин, удалённо) — это соответствует CLAUDE.md restoplace (стр. 85/95).

`--help`: общий — нейтральные примеры (`2026-01-10-fix-login-redirect`, `--run "make test"`,
заметка handoff без Konva); `rtp verify --help` — `--run "<команда из .rtp.json / CLAUDE.md проекта>"`;
`rtp handoff --help` — «ahead/behind базовой ветки».

### 3. Базовая ветка

`gitContext(cwd, preferredBase?)`. Порядок выбора:
1. `preferredBase` (из `.rtp.json`), если ref существует (`git rev-parse --verify --quiet <ref>`);
   если не существует — предупреждение в stderr и переход к п. 2;
2. `git symbolic-ref --short refs/remotes/origin/HEAD` → `origin/<x>`: локальная `<x>`, если
   есть, иначе `origin/<x>`;
3. первая существующая из `main`, `master`;
4. иначе `null`.

Поля переименовываются: `baseBranch`, `aheadOfBase`, `behindBase` (`aheadOfMaster` /
`behindMaster` уходят, все использования обновляются). `## Handoff`:
- база есть: `Ветка: \`<b>\` — своих коммитов N, отставание от <base> M`;
- `null`: `Ветка: \`<b>\` — базовая ветка не определена`.

### 4. Прочие правки в скрипте

- `/debts-report` в `validate` / `debt --help` → «невидим для индекса и отчётов по долгам».
- Комментарий ≈1879: «несколько параллельных сессий/worktree» без числа и без «sharing».
- **Stop-хук**: правка не-`.md` файла прямо в `docs/tasks/` (`.rtp.json`) — метаданные трекера:
  не код (не требует обновления задачи) и не называет задачу. PostEdit уже игнорирует не-`.md`.

### 5. SKILL.md, шаблон, references — нейтральные формулировки

- Ревьюеры: «специализированный ревьюер — из `reviewers` в `.rtp.json`, иначе подходящий из
  списка агентов сессии (например, из подключённого плагина); дефолт `general-purpose`».
  Конкретные имена агентов restoplace и `caveman:*` убрать отовсюду, включая таблицу в конце.
- Delegation: «если CLAUDE.md проекта называет более специфичный скилл для задачи — он».
- Worktree (≈177): «несколько параллельных сессий в соседних worktree; "последняя активная
  задача" регулярно принадлежит соседней» — без числа и без «общего `docs/tasks`».
- Step 6: пример `rtp verify` — «команды из `.rtp.json` (их печатает `rtp next <id>`), иначе
  из CLAUDE.md»; абзац «проект может предписывать удалённый прогон» оставить.
- `/debts-report` → «отчёты по долгам» (SKILL.md, `templates/task.md`, anti-rationalization).
  Строку про `docs/migration/modules` убрать. «ahead/behind master» → «базовой ветки».
- Новый короткий раздел «Конфиг проекта `.rtp.json`» со схемой и правилом загрузки.
- `~/.claude/commands/rtp.md` — привязок нет, не трогаем.

### 6. restoplace-frontend

- `docs/tasks/.rtp.json`: `baseBranch: master`; verify `npm run build`, `npm run lint`,
  `{run: "npm run test:remote -- --changed master", timeout: 900}`; reviewers
  `frontend-invariants-reviewer`, `legacy-parity-auditor`. `caveman:cavecrew-reviewer` не
  включаем — плагин `caveman` в `~/.claude/settings.json` выключен.
- CLAUDE.md, раздел про `run-task-pipeline`: делегирование (`migration-module` для
  `docs/migration/modules/<id>.md`, `openapi-codegen` для генерации типов API); `/debts-report`
  собирает `- [ ]` из `## Debt`; тот же формат долгов — в `docs/migration/modules/<id>.md`.
- Коммит в restoplace — только с согласия пользователя. `docs/tasks` там отслеживается git
  в каждом worktree отдельно: остальные worktree увидят `.rtp.json` после мержа master. До этого
  они на умолчаниях — база всё равно резолвится в `master` (`origin/HEAD` → `origin/master`),
  команды есть в их CLAUDE.md.

## Критерии приёмки

1. `sh scripts/regress.sh` завершается с exit 0 (строка 665: `[ "$FAIL" -eq 0 ]`). Новая секция:
   - `rtp next` в review с конфигом печатает строки `--run`/`--record`/`--timeout` и ревьюеров;
   - только `reviewers` без `verify` → нейтральная verify-строка + ревьюеры;
   - без конфига — нейтральные строки, в выводе нет `npm`;
   - команда с `"` и `$` напечатана в одинарных кавычках и исполняется `sh -c` без искажений;
   - битый JSON → `rtp status`/`next` exit 0, предупреждение в stderr;
   - элемент `verify` неверной формы отброшен, остальные напечатаны;
   - конфиг читается по папке задачи: `rtp status <абс. путь к задаче>` из чужого cwd берёт её конфиг;
   - handoff: репо `git init -b main` + коммит (`-c user.name=t -c user.email=t@t`), без конфига → `main`;
     с `baseBranch` на существующую ветку → она; с несуществующей → предупреждение и `main`;
   - `.rtp.json` не ломает `rtp index`, `rtp validate --all`, `rtp find rtp`;
   - Stop-хук: ход с единственной правкой `docs/tasks/.rtp.json` не блокируется.
2. `grep -riE "restoplace|test:remote|frontend-invariants|legacy-parity|caveman|openapi|migration-module|debts-report|npm run|konva|scheme-zoom|master\b" SKILL.md scripts/rtp.mjs scripts/lib.mjs scripts/build-index.mjs templates references`
   — пусто, кроме строк, где `master` — один из кандидатов автоопределения (`main`, `master`)
   или пример значения `baseBranch` в разделе про конфиг.
3. restoplace-frontend: `rtp next <id>` на задаче в фазе review печатает `npm run build`,
   `npm run lint`, `test:remote` и оба ревьюера; `rtp list` и `rtp show <id>` работают как раньше;
   `rtp handoff <id> --print-only` показывает отставание от `master`.
4. Бэкап `~/.claude/skills-backup-run-task-pipeline-2026-09-29` существует до первой правки (сделан).

## Вне рамок

- Запуск проверок самим `rtp` (`--check <name>`) — отвергнуто, только подсказки.
- Копия в SwitchFix, хуки с гвардом, облако — подзадача 2.
- Настраиваемые security-ключевые слова и пресеты триажа.

## Deferred

- (пусто)
