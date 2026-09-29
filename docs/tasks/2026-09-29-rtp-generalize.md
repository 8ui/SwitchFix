---
id: 2026-09-29-rtp-generalize
title: Обобщить rtp и перенести в SwitchFix
type: refactor
pipeline: full
phase: review
created: 2026-09-29
updated: 2026-09-29
blocked_by: null
steps_done: 8
steps_total: 8
step_current: null
artifacts:
  spec: docs/features/rtp-generalize-spec.md
  plan: docs/plans/rtp-generalize-plan.md
  branch: null
  pr: null
---

## Context

_2-5 строк: что делаем и зачем. Задача этой секции — чтобы через N дней можно было восстановить контекст без чтения spec/plan._

## Progress

1. ✅ `loadProjectConfig` и `shQuote` в lib.mjs
2. ✅ базовая ветка в `gitContext` и handoff
3. ✅ подсказки verify/ревьюеров в `nextActionFor`
4. ✅ Stop-хук не считает `.rtp.json` кодом
5. ✅ нейтральные тексты в rtp.mjs
6. ✅ SKILL.md, шаблон, references
7. ✅ restoplace-frontend — конфиг и CLAUDE.md
8. ✅ итоговая проверка и доказательства

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

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] verify-элемент с timeout неверного типа отбрасывается целиком вместе с командой — мягче было бы сохранить run и предупредить только про timeout (ревью кода, п.5)
- [ ] команда verify, начинающаяся с '--', ломает подсказку: parseArgs примет значение --run за флаг; печатать --run=<quoted> (ревью кода, п.7, маловероятно)

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

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
