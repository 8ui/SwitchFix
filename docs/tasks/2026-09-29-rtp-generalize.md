---
id: 2026-09-29-rtp-generalize
title: Обобщить rtp и перенести в SwitchFix
type: refactor
pipeline: full
phase: review
created: 2026-09-29
updated: 2026-09-29
blocked_by: null
steps_done: 7
steps_total: 8
step_current: 8
artifacts:
  spec: docs/features/rtp-cloud-switchfix-spec.md
  plan: docs/plans/rtp-cloud-switchfix-plan.md
  branch: claude/rtp-cloud-pipeline
  pr: "https://github.com/8ui/SwitchFix/pull/4"
---

## Context

Скилл `run-task-pipeline` (CLI `rtp`) был написан под restoplace. Подзадача 1: проектная
специфика вынесена в `docs/tasks/.rtp.json` + CLAUDE.md проекта (глобальный скилл в `~/.claude`,
restoplace `ae27627e9`). Подзадача 2: облачные сессии SwitchFix получают только репо, поэтому
копии скилла, 10 скиллов superpowers, хуки с гвардом и шим `rtp` положены в `.claude/` репо
(ветка `claude/rtp-cloud-pipeline`, PR в `8ui/SwitchFix`).

## Progress

1. ✅ копии скиллов, лицензия, `.gitignore`
2. ✅ фиксы копии rtp — путь с пробелом/кириллицей и кавычечная форма
3. ✅ SKILL.md копии rtp
4. ✅ хуки и шим
5. ✅ `.rtp.json` и CLAUDE.md
6. ✅ проверка дублей скиллов вживую
7. ✅ PR, CI, доказательства
8. ▶ облачная проверка (пользователь) и закрытие

## Log

- 2026-09-29: triage — pipeline `full`, reason: меняется интерфейс скилла (конфиг .rtp.json, baseBranch), >5 файлов, два репо + ~/.claude; подзадача 1 — обобщение, 2 — копия в SwitchFix для облака
- 2026-09-29: artifacts.spec = docs/features/rtp-generalize-spec.md
- 2026-09-29: brainstorm: конфиг docs/tasks/.rtp.json + CLAUDE.md, verify только подсказки; бэкап скилла сделан
- 2026-09-29: spec drafted
- 2026-09-29: spec-review (general-purpose/opus): 2 blocker + 5 major + 5 minor — все учтены в спеке (конфиг по dirname задачи, verbose next, частичный конфиг, экранирование, Stop-хук и .rtp.json, пропущенные места)
- 2026-09-29: spec approved by user
- 2026-09-29: artifacts.plan = docs/plans/rtp-generalize-plan.md
- 2026-09-29: plan drafted (8 steps)
- 2026-09-29: plan-review (Plan/opus): 0 blocker, 2 major (grep-ожидания, ID из rtp list) + 7 minor — учтены в плане
- 2026-09-29: шаг 1 ✅ `loadProjectConfig` и `shQuote` в lib.mjs — C1 зелёный, регресс 135/0
- 2026-09-29: шаг 2 ✅ базовая ветка в `gitContext` и handoff — C2 зелёный, 139/0
- 2026-09-29: шаг 3 ✅ подсказки verify/ревьюеров в `nextActionFor` — C3 зелёный, 149/0
- 2026-09-29: шаг 4 ✅ Stop-хук не считает `.rtp.json` кодом — C4 зелёный, 150/0
- 2026-09-29: шаг 5 ✅ нейтральные тексты в rtp.mjs — grep чистый (кроме автоопределения main/master), 150/0
- 2026-09-29: шаг 6 ✅ SKILL.md, шаблон, references — grep: остались только упоминания автоопределения main/master
- 2026-09-29: шаг 7 ✅ restoplace-frontend — конфиг и CLAUDE.md — restoplace: .rtp.json + CLAUDE.md, list/show/handoff/next проверены; коммит ждёт согласия
- 2026-09-29: impl complete (шаги 1-7)
- 2026-09-29: verify: `sh /Users/andrejsokolov/.claude/skills/run-task-pipeline/scripts/regress.sh` → exit 0 ✅
- 2026-09-29: verify: `grep -rniE 'restoplace|test:remote|frontend-invariants|legacy-parity|caveman|openapi|migration-module|debts-report|npm run|konva|scheme-zoom|master\b' /Users/andrejsokolov/.claude/skills/run-task-pipeline/SKILL.md /Users/andrejsokolov/.claude/skills/run-task-pipeline/scripts/rtp.mjs /Users/andrejsokolov/.claude/skills/run-task-pipeline/scripts/lib.mjs /Users/andrejsokolov/.claude/skills/run-task-pipeline/scripts/build-index.mjs /Users/andrejsokolov/.claude/skills/run-task-pipeline/templates /Users/andrejsokolov/.claude/skills/run-task-pipeline/references` → exit 0 ✅
- 2026-09-29: verify: `restoplace: rtp list/show/handoff (отставание от master) и rtp next на задаче в review — npm run build, npm run lint, test:remote --timeout 900, оба ревьюера` → exit 0 ✅
- 2026-09-29: verify: `sh /Users/andrejsokolov/.claude/skills/run-task-pipeline/scripts/regress.sh` → exit 0 ✅
- 2026-09-29: code-review (general-purpose/opus): 0 blocker, 7 minor; исправлены 1-4,6 (узкое исключение .rtp.json, переводы строк, BOM, контроль в C4), 5 и 7 — в долг; регресс 154/0
- 2026-09-29: шаг 8 ✅ итоговая проверка и доказательства — регресс 154/0, grep чист, restoplace проверен, код-ревью учтено
- 2026-09-29: подзадача 1 закрыта (restoplace ae27627e9, SwitchFix 6b3f8c0); старт подзадачи 2 — копия скилла в SwitchFix для облака
- 2026-09-29: artifacts.spec = docs/features/rtp-cloud-switchfix-spec.md
- 2026-09-29: подзадача 2: spec drafted (решения: разовая копия, 10 скиллов superpowers, скрыть дубли локально, гвард по глобальному скиллу); ветка claude/rtp-cloud-pipeline
- 2026-09-29: spec-review подзадачи 2 (general-purpose/opus): 0 blocker, 4 major (кавычечная форма rtp в Stop, гвард по хукам а не папке, fileURLToPath, облачная проверка до мержа) + 9 minor — учтены
- 2026-09-29: spec подзадачи 2 одобрена
- 2026-09-29: artifacts.plan = docs/plans/rtp-cloud-switchfix-plan.md
- 2026-09-29: plan подзадачи 2 drafted (8 steps)
- 2026-09-29: plan-review подзадачи 2 (Plan/opus): 2 blocker (PATH= ломает grep в гварде; jq to_entries не сортирует) + 4 major + 7 minor — учтены
- 2026-09-29: plan-review passed, старт реализации подзадачи 2
- 2026-09-29: шаг 1 ✅ копии скиллов, лицензия, `.gitignore` — копии + лицензия, режимы 100755 сохранены, server.cjs запускается, регресс копии 154/0
- 2026-09-29: шаг 2 ✅ фиксы копии rtp — путь с пробелом/кириллицей и кавычечная форма — P1/P2 зелёные, регресс копии 156/0
- 2026-09-29: шаг 3 ✅ SKILL.md копии rtp — критерий 3 exit 0; 13 ссылок с пометкой «без плагина», code-reviewer оставлен
- 2026-09-29: шаг 4 ✅ хуки и шим — критерии 4,5,6 зелёные; 100755 у шима и rtp-hook.sh
- 2026-09-29: шаг 5 ✅ `.rtp.json` и CLAUDE.md — rtp next печатает 3 --run и 1 --record
- 2026-09-29: шаг 6 ✅ проверка дублей скиллов вживую — предварительно: копии скрыты; какой run-task-pipeline виден — подтвердить /skills в новой сессии
- 2026-09-29: impl подзадачи 2 завершён (шаги 1-6)
- 2026-09-29: verify: `sh .claude/skills/run-task-pipeline/scripts/regress.sh` → exit 0 ✅
- 2026-09-29: verify: `! grep -rn 'superpowers:' .claude/skills --include='*.md' | grep -v '^.claude/skills/run-task-pipeline/'` → exit 0 ✅
- 2026-09-29: verify: `! grep -nE '~/\.claude/(skills|bin)|\$HOME/\.claude' .claude/skills/run-task-pipeline/SKILL.md` → exit 0 ✅
- 2026-09-29: verify: `jq -e '(.hooks|keys)==["PostToolUse","PreCompact","SessionStart","Stop"] and .hooks.PostToolUse[0].matcher=="Edit|Write|MultiEdit" and ([.hooks|to_entries|sort_by(.key)[]|.value[0].hooks[0].command|capture("hook-(?<s>[a-z]+)$").s]==["postedit","precompact","sessionstart","stop"])' .claude/settings.json` → exit 0 ✅
- 2026-09-29: verify: `git ls-files -s .claude | awk '$1=="100755"{print $4}'` → exit 0 ✅
- 2026-09-29: verify: `критерий 4: гвард локально — PATH=/usr/bin:/bin sh .claude/rtp-hook.sh hook-stop` → exit 0 ✅
- 2026-09-29: verify: `критерий 5: без глобальных хуков (CLAUDE_CONFIG_DIR пуст)` → exit 0 ✅
- 2026-09-29: artifacts.branch = claude/rtp-cloud-pipeline; artifacts.pr = https://github.com/8ui/SwitchFix/pull/4
- 2026-09-29: code-review ветки (general-purpose/opus): 0 blocker/major, 6 minor; исправлены 1-5 (симлинк шима, кавычки в env-строке, нет node, шире гвард, без дублей PATH), 6 — в NOTICE
- 2026-09-29: verify: `повторная проверка rtp-hook.sh/шима после ревью` → exit 0 ✅
- 2026-09-29: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36546484268 (pull_request, b8e8154) и /runs/36546460611 (push)` → exit 0 ✅
- 2026-09-29: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36547719023 (pull_request, c022bce)` → exit 0 ✅
- 2026-09-29: шаг 7 ✅ PR, CI, доказательства — PR #4, CI зелёный на c022bce, код-ревью учтено
- 2026-09-29: verify: `облако: пайплайн rtp пройден целиком на задаче 2026-09-29-ru-en-special-chars-test` → exit 0 ✅
- 2026-09-29: по отчёту облака: фиксы 1-3 ($0 в рецепте шима, verify.only local/cloud, paths-ignore docs/tasks в CI); тест облака остаётся в PR
- 2026-09-29: verify: `sh .claude/skills/run-task-pipeline/scripts/regress.sh` → exit 0 ✅
- 2026-09-29: verify: `! grep -nE '\$[0-9@#*]|\$ARGUMENTS' .claude/skills/run-task-pipeline/SKILL.md` → exit 0 ✅
- 2026-09-29: фиксы по отчёту облака: рецепт шима без $0, verify.only local/cloud (C6), paths-ignore docs/tasks для push в CI; b75a889
- 2026-09-29: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36549828578 (push, b75a889)` → exit 0 ✅

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

- Подзадача 1: проектная специфика rtp — в `docs/tasks/.rtp.json` (baseBranch/verify/reviewers) + CLAUDE.md; rtp только печатает подсказки, ничего не запускает.
- Подзадача 2: копии скиллов в SwitchFix разовые, без sync; 10 скиллов superpowers (замыкание ссылок); локально копии скрыты через `skillOverrides` в settings.local.json.
- Подзадача 2: гвард хуков копии — «глобальные хуки rtp подключены в settings.json пользователя», а не наличие папки скилла и не `CLAUDE_CODE_REMOTE`.
- Подзадача 2: регэкспы Stop-хука копии принимают кавычку после `rtp.mjs`; побочный эффект — `grep "rtp" …` с кавычкой теперь тоже считается мутирующим вызовом, как и раньше без кавычки. Принято.
- Подзадача 2, дубли локально (предварительно, в сессии, где копии появились на лету): обновлённый список скиллов показал один `run-task-pipeline` и ни одной копии superpowers без префикса — `skillOverrides: off` скрывает копии. Какой из двух `run-task-pipeline` виден, из сессии не различить (описания одинаковые) — подтвердить `/skills` в новой локальной сессии.

## Debt

- [ ] verify-элемент с timeout неверного типа отбрасывается целиком вместе с командой — мягче было бы сохранить run и предупредить только про timeout (ревью кода, п.5)
- [ ] команда verify, начинающаяся с '--', ломает подсказку: parseArgs примет значение --run за флаг; печатать --run=<quoted> (ревью кода, п.7, маловероятно)
- [ ] перенести в глобальный скилл фиксы копии: SKILL_DIR через fileURLToPath и кавычечную форму rtp.mjs в регэкспах Stop-хука (подзадача 2)
- [ ] гвард rtp-hook.sh ищет глобальные хуки только в settings.json — хуки из settings.local.json/managed settings не видит, копия сработает вдвое; и риск версий: подключённые глобальные хуки гоняют свой rtp против репо
- [ ] облачная проверка до мержа (пользователь): rtp на PATH, задача заводится, Stop возвращает ход — критерий 9 спеки подзадачи 2
- [ ] перенести в глобальный скилл поле verify.only (local/cloud) из копии SwitchFix — глобальный rtp его игнорирует и показывает все проверки

## Verification

- 2026-09-29 · `sh /Users/andrejsokolov/.claude/skills/run-task-pipeline/scripts/regress.sh` · exit 0 ✅

  ```
    ok   — без конфига — нейтральная подсказка без npm
    ok   — next печатает команды и ревьюеров
    ok   — мусорный элемент verify отброшен с предупреждением
    ok   — только reviewers → нейтральный verify + ревьюер
    ok   — команда с " и $ вставляется как есть
    ok   — битый JSON: status/next exit 0 + предупреждение
    ok   — status из чужого cwd берёт конфиг задачи
    ok   — index игнорирует .rtp.json
    ok   — validate --all игнорирует .rtp.json
    ok   — find игнорирует .rtp.json
  C4: Stop — правка docs/tasks/.rtp.json не требует обновления задачи
    ok   — ход с правкой .rtp.json не блокируется
  
  итог (все секции): PASS=150 FAIL=0
  ```

- 2026-09-29 · `grep -rniE 'restoplace|test:remote|frontend-invariants|legacy-parity|caveman|openapi|migration-module|debts-report|npm run|konva|scheme-zoom|master\b' /Users/andrejsokolov/.claude/skills/run-task-pipeline/SKILL.md /Users/andrejsokolov/.claude/skills/run-task-pipeline/scripts/rtp.mjs /Users/andrejsokolov/.claude/skills/run-task-pipeline/scripts/lib.mjs /Users/andrejsokolov/.claude/skills/run-task-pipeline/scripts/build-index.mjs /Users/andrejsokolov/.claude/skills/run-task-pipeline/templates /Users/andrejsokolov/.claude/skills/run-task-pipeline/references` · exit 0 ✅

  ```
  /Users/andrejsokolov/.claude/skills/run-task-pipeline/SKILL.md:159:- База для ahead/behind в handoff: `baseBranch` → `origin/HEAD` → `main`/`master`.
  /Users/andrejsokolov/.claude/skills/run-task-pipeline/SKILL.md:402:Собирает автоматически: фаза + шаг, **worktree и ветка**, ahead/behind базовой ветки (`.rtp.json` → `origin/HEAD` → `main`/`master`),
  /Users/andrejsokolov/.claude/skills/run-task-pipeline/scripts/rtp.mjs:1246:  (.rtp.json baseBranch → origin/HEAD → main/master), dirty files,
  /Users/andrejsokolov/.claude/skills/run-task-pipeline/scripts/lib.mjs:778:// Base for ahead/behind: config → origin/HEAD → main/master → null.
  /Users/andrejsokolov/.claude/skills/run-task-pipeline/scripts/lib.mjs:790:  for (const b of ['main', 'master']) if (await refExists(b, cwd)) return b;
  ```

- 2026-09-29 · `restoplace: rtp list/show/handoff (отставание от master) и rtp next на задаче в review — npm run build, npm run lint, test:remote --timeout 900, оба ревьюера` · exit 0 ✅

  ```
  см. вывод в сессии 2026-09-29; до коммита в restoplace остальные worktree на умолчаниях
  ```

- 2026-09-29 · `sh /Users/andrejsokolov/.claude/skills/run-task-pipeline/scripts/regress.sh` · exit 0 ✅

  ```
    ok   — битый JSON: status/next exit 0 + предупреждение
    ok   — status из чужого cwd берёт конфиг задачи
    ok   — index игнорирует .rtp.json
    ok   — validate --all игнорирует .rtp.json
    ok   — find игнорирует .rtp.json
  C4: Stop — правка docs/tasks/.rtp.json не требует обновления задачи
    ok   — ход с правкой .rtp.json не блокируется
    ok   — контроль: правка кода рядом блокируется
    ok   — код в папке с именем docs/tasks — всё ещё код
  C5: .rtp.json — BOM и переводы строк
    ok   — BOM не ломает JSON
    ok   — многострочные run/record отброшены
  
  итог (все секции): PASS=154 FAIL=0
  ```

- 2026-09-29 · `sh .claude/skills/run-task-pipeline/scripts/regress.sh` · exit 0 ✅

  ```
    ok   — find игнорирует .rtp.json
  C4: Stop — правка docs/tasks/.rtp.json не требует обновления задачи
    ok   — ход с правкой .rtp.json не блокируется
    ok   — контроль: правка кода рядом блокируется
    ok   — код в папке с именем docs/tasks — всё ещё код
  C5: .rtp.json — BOM и переводы строк
    ok   — BOM не ломает JSON
    ok   — многострочные run/record отброшены
  P1: скилл в пути с пробелом и кириллицей — rtp new находит шаблон
    ok   — rtp new из пути с пробелом/кириллицей
  P2: Stop засчитывает вызов rtp.mjs с путём в кавычках
    ok   — кавычечная форма засчитана
  
  итог (все секции): PASS=156 FAIL=0
  ```

- 2026-09-29 · `! grep -rn 'superpowers:' .claude/skills --include='*.md' | grep -v '^.claude/skills/run-task-pipeline/'` · exit 0 ✅

  ```
  (пустой вывод)
  ```

- 2026-09-29 · `! grep -nE '~/\.claude/(skills|bin)|\$HOME/\.claude' .claude/skills/run-task-pipeline/SKILL.md` · exit 0 ✅

  ```
  (пустой вывод)
  ```

- 2026-09-29 · `jq -e '(.hooks|keys)==["PostToolUse","PreCompact","SessionStart","Stop"] and .hooks.PostToolUse[0].matcher=="Edit|Write|MultiEdit" and ([.hooks|to_entries|sort_by(.key)[]|.value[0].hooks[0].command|capture("hook-(?<s>[a-z]+)$").s]==["postedit","precompact","sessionstart","stop"])' .claude/settings.json` · exit 0 ✅

  ```
  true
  ```

- 2026-09-29 · `git ls-files -s .claude | awk '$1=="100755"{print $4}'` · exit 0 ✅

  ```
  .claude/bin/rtp
  .claude/rtp-hook.sh
  .claude/skills/brainstorming/scripts/start-server.sh
  .claude/skills/brainstorming/scripts/stop-server.sh
  .claude/skills/subagent-driven-development/scripts/review-package
  .claude/skills/subagent-driven-development/scripts/sdd-workspace
  .claude/skills/subagent-driven-development/scripts/task-brief
  .claude/skills/systematic-debugging/find-polluter.sh
  ```

- 2026-09-29 · `критерий 4: гвард локально — PATH=/usr/bin:/bin sh .claude/rtp-hook.sh hook-stop` · exit 0 ✅

  ```
  exit 0, пустой вывод; node вне /usr/bin:/bin (command -v пусто)
  ```

- 2026-09-29 · `критерий 5: без глобальных хуков (CLAUDE_CONFIG_DIR пуст)` · exit 0 ✅

  ```
  SessionStart дописал export PATH=<repo>/.claude/bin; Stop t1 (правка Sources без rtp) exit 2 + «задачи в этой сессии нет»; t2 (+ node "…/rtp.mjs" phase) exit 0; .claude/bin/rtp list печатает задачи
  ```

- 2026-09-29 · `повторная проверка rtp-hook.sh/шима после ревью` · exit 0 ✅

  ```
  гвард локально exit 0; env-строка одна, source даёт .claude/bin/rtp; без node — сообщение + exit 1; шим через симлинк работает; Stop без транскрипта exit 0
  ```

- 2026-09-29 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36546484268 (pull_request, b8e8154) и /runs/36546460611 (push)` · exit 0 ✅

  ```
  Build and test (macos-15): swift build, TestRunner, InputPipelineTestRunner, build-app.sh — success
  ```

- 2026-09-29 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36547719023 (pull_request, c022bce)` · exit 0 ✅

  ```
  Build and test (macos-15) — success
  ```

- 2026-09-29 · `облако: пайплайн rtp пройден целиком на задаче 2026-09-29-ru-en-special-chars-test` · exit 0 ✅

  ```
  rtp на PATH (/home/user/SwitchFix/.claude/bin/rtp), хуки сработали (индекс обновлялся), new/steps/step/phase/validate/status/verify --record работают, CI run 36548587047 зелёный; замечания: $0 в SKILL.md, swift в rtp next в облаке, коммит трекера отменяет CI
  ```

- 2026-09-29 · `sh .claude/skills/run-task-pipeline/scripts/regress.sh` · exit 0 ✅

  ```
    ok   — BOM не ломает JSON
    ok   — многострочные run/record отброшены
  C6: verify.only — local/cloud по CLAUDE_CODE_REMOTE
    ok   — only нормализован, неизвестное значение отброшено
    ok   — предупреждение про only: mars
    ok   — локально: local-элемент и общий показаны
    ok   — в облаке: local-элемент скрыт
    ok   — в облаке без подходящих элементов — нейтральная подсказка
  P1: скилл в пути с пробелом и кириллицей — rtp new находит шаблон
    ok   — rtp new из пути с пробелом/кириллицей
  P2: Stop засчитывает вызов rtp.mjs с путём в кавычках
    ok   — кавычечная форма засчитана
  
  итог (все секции): PASS=161 FAIL=0
  ```

- 2026-09-29 · `! grep -nE '\$[0-9@#*]|\$ARGUMENTS' .claude/skills/run-task-pipeline/SKILL.md` · exit 0 ✅

  ```
  (пустой вывод)
  ```

- 2026-09-29 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36549828578 (push, b75a889)` · exit 0 ✅

  ```
  Build and test (macos-15) — success
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
