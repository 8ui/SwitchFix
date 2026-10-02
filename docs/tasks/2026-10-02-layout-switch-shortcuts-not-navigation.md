---
id: 2026-10-02-layout-switch-shortcuts-not-navigation
title: Ctrl-Space and other layout-switch shortcuts are classified as navigation
type: bug
pipeline: no-spec
phase: review
created: 2026-10-02
updated: 2026-10-02
blocked_by: null
steps_done: 3
steps_total: 4
step_current: null
artifacts:
  spec: null
  plan: docs/plans/layout-switch-shortcuts-not-navigation-plan.md
  branch: null
  pr: null
---

## Context

`KeyboardMonitor.classify` приватный и без тестов; особый случай смены раскладки есть только для Globe (keyCode 179). Ctrl-Space / Ctrl-Option-Space и другие системные хоткеи смены источника классифицируются как навигация, поэтому режим «по переключению» теряет слово (долг из 2026-09-30-layout-switch-mode-loses-the-word…), а регресс 179 пройдёт незаметно.
Готово, когда: classify — чистая тестируемая функция, системные хоткеи смены источника (из symbolic hotkeys или Ctrl-Space по умолчанию) не сбрасывают слово как навигация; тесты в InputPipelineTestRunner.

## Progress

1. ✅ classifyKeyDown — чистая функция + тесты
2. ✅ Чтение symbolichotkeys 60/61 + тесты парсера
3. ⛔ Ручная проверка на Mac (пользователь): ⌃Space, удержание ⌃, стрелка+⌃Space
4. ✅ Ревью и CI

## Log

- 2026-10-02: triage — pipeline `no-spec`, reason: вынести KeyboardMonitor.classify в чистую тестируемую функцию + распознавать системные хоткеи смены источника; KeyboardMonitor + тесты
- 2026-10-02: brainstorm: пользователь одобрил чтение symbolichotkeys 60/61 → .inputSourceKey и вынос ветки keyDown в чистую функцию
- 2026-10-02: artifacts.plan = docs/plans/layout-switch-shortcuts-not-navigation-plan.md
- 2026-10-02: plan drafted
- 2026-10-02: plan-review: блокер — нужна ручная проверка на Mac (шаг 3, пользователь); should-fix S1–S6 в rev.2
- 2026-10-02: шаг 1 ✅ classifyKeyDown — чистая функция + тесты — classifyKeyDown + тесты
- 2026-10-02: шаг 2 ✅ Чтение symbolichotkeys 60/61 + тесты парсера — inputSourceShortcuts(from:selectableSourceCount:) + CFPreferences + тесты
- 2026-10-02: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36993040417 (push bb9e34b; TestRunner 613/0, InputPipelineTestRunner 1215/0; 3 новых сьюта classifyKeyDown/парсер)` → exit 0 ✅
- 2026-10-02: verify: `CI зелёный после правок код-ревью: https://github.com/8ui/SwitchFix/actions/runs/36994039723 (push 3b3512a; TestRunner 632/0, InputPipelineTestRunner 1223/0)` → exit 0 ✅
- 2026-10-02: verify: `код-ревью субагентом: блокеров нет; should-fix (порядок в тесте) и нитпики исправлены в 3b3512a` → exit 0 ✅
- 2026-10-02: шаг 3 ⛔ Ручная проверка на Mac (пользователь): ⌃Space, удержание ⌃, стрелка+⌃Space — ручная проверка на Mac (⌃Space, удержание ⌃ >500 мс, стрелка+⌃Space) — только у пользователя локально
- 2026-10-02: шаг 4 ✅ Ревью и CI
- 2026-10-02: impl + ревью + CI; ждёт ручной проверки на Mac (шаг 3) и merge

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] повторное нажатие ⌃⌥Space (перебор 3+ источников) или автоповтор теряет слово, как и Globe — безопасно (текст не меняется)
- [ ] Caps Lock как переключатель раскладки (настройка macOS, flagsChanged) и сторонние переключатели (Karabiner, Punto) не распознаются
- [ ] refreshInputSourceShortcuts на main при каждой активации и смене источника (CFPreferencesAppSynchronize + TIS) без троттлинга; коррекция со сменой раскладки обновляет дважды

## Verification

- 2026-10-02 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36993040417 (push bb9e34b; TestRunner 613/0, InputPipelineTestRunner 1215/0; 3 новых сьюта classifyKeyDown/парсер)` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-10-02 · `CI зелёный после правок код-ревью: https://github.com/8ui/SwitchFix/actions/runs/36994039723 (push 3b3512a; TestRunner 632/0, InputPipelineTestRunner 1223/0)` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-10-02 · `код-ревью субагентом: блокеров нет; should-fix (порядок в тесте) и нитпики исправлены в 3b3512a` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

- 2026-10-02: шаг 3 — ручная проверка на Mac (⌃Space, удержание ⌃ >500 мс, стрелка+⌃Space) — только у пользователя локально

