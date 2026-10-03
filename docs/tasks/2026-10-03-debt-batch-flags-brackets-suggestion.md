---
id: 2026-10-03-debt-batch-flags-brackets-suggestion
title: "Debt batch: transparent long flags, bracketed short word in context, inline suggestion for automatic correction and revert"
type: chore
pipeline: minimal
phase: impl
created: 2026-10-03
updated: 2026-10-03
blocked_by: null
steps_done: 4
steps_total: 5
step_current: 5
artifacts:
  spec: null
  plan: null
  branch: null
  pr: null
---

## Context

Пачка открытых долгов из соседних задач:
1. 2026-10-03-debt-batch-flags-counters-adjacency: многобуквенные флаги (-la, -rf, --force) держит модель — они не прозрачны ('yf -la yf' не переключает).
2. 2026-09-30-check-upstream-develop-edge-cases-against-the-n-gram: правило B считает word.count с пунктуацией — 3-буквенное слово в скобке не удерживается контекстом.
3. 2026-10-02-hotkey-and-layout-switch-convert-an-inline-autocomplete: автоматическая коррекция при выделенной inline-подсказке отменяется — применить то же правило (стереть подсказку лишним Backspace).
4. Там же: откат после коррекции с подсказкой отказывает (сверка видит выделение) — принять с deleteCount+1.
Готово, когда: правки + тесты, CI зелёный на push-ране, LayoutEval сравнён с базой, долги в исходных задачах закрыты со ссылкой на эту.

## Progress

1. ✅ Прозрачные многобуквенные флаги
2. ✅ Короткое слово в скобке в контексте
3. ✅ Подсказка при автоматической коррекции
4. ✅ Подсказка при откате
5. ▶ Ревью, CI, eval

## Log

- 2026-10-03: triage — pipeline `minimal`, reason: четыре независимых долга: 2 правила детектора (LayoutDetector) и 2 режима выделения в сверке (InputEngine); известная архитектура, 2-3 файла кода + тесты; ревью субагентом, CI, LayoutEval против базы
- 2026-10-03: brainstorm: что — 4 долга (см. Context); зачем — пользователь попросил закрыть следующую пачку; готово — тесты + CI + eval vs база + закрытые долги
- 2026-10-03: шаг 1 ✅ Прозрачные многобуквенные флаги — код + тесты (a0a3417), ждёт CI
- 2026-10-03: шаг 2 ✅ Короткое слово в скобке в контексте — код + тесты (a0a3417), ждёт CI
- 2026-10-03: шаг 3 ✅ Подсказка при автоматической коррекции — код + тесты (a0a3417), ждёт CI
- 2026-10-03: шаг 4 ✅ Подсказка при откате — код + тесты (a0a3417), ждёт CI
- 2026-10-03: шаг 5 ▶ Ревью, CI, eval
- 2026-10-03: verify: `CI красный: https://github.com/8ui/SwitchFix/actions/runs/37130078051 (push a0a3417) — TestRunner зелёный, InputPipelineTestRunner 1435/1: 'timeouts are read again' (тайминг: 3 чтения не влезли в 150 мс, путь .unavailable не затронут) — тесту дан свой дедлайн 600 мс` → exit 1 ❌
- 2026-10-03: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/37130269102 (push 01fb8e9; TestRunner 687/0, InputPipelineTestRunner 1436/0, build-app); LayoutEval и threshold sweep (172 SWEEP-строки) совпадают с базой 37129456647 (e211b47 = master), кроме таймингов` → exit 0 ✅

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

_Отложенное, упрощения, известные пробелы. Формат — чекбоксы (их считают индекс и отчёты по долгам):_
_- `- [ ] <что отложено> — <почему/контекст>` — открытый долг_
_- `- [x] <что было> — закрыто YYYY-MM-DD: <причина/ссылка на task>` — закрытый_
_Без `[ ]`/`[x]` пункт невидим для агрегатора и теряется через 2 недели._

## Verification

- 2026-10-03 · `CI красный: https://github.com/8ui/SwitchFix/actions/runs/37130078051 (push a0a3417) — TestRunner зелёный, InputPipelineTestRunner 1435/1: 'timeouts are read again' (тайминг: 3 чтения не влезли в 150 мс, путь .unavailable не затронут) — тесту дан свой дедлайн 600 мс` · exit 1 ❌

  ```
  (без вывода)
  ```

- 2026-10-03 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/37130269102 (push 01fb8e9; TestRunner 687/0, InputPipelineTestRunner 1436/0, build-app); LayoutEval и threshold sweep (172 SWEEP-строки) совпадают с базой 37129456647 (e211b47 = master), кроме таймингов` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
