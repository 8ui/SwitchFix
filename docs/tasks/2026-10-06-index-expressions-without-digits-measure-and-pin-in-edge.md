---
id: 2026-10-06-index-expressions-without-digits-measure-and-pin-in-edge
title: "Index expressions without digits: measure and pin in edge cases"
type: chore
pipeline: minimal
phase: done
created: 2026-10-06
updated: 2026-10-06
blocked_by: null
steps_done: 2
steps_total: 2
step_current: null
artifacts:
  spec: null
  plan: null
  branch: null
  pr: null
---

## Context

_2-5 строк: что делаем и зачем. Задача этой секции — чтобы через N дней можно было восстановить контекст без чтения spec/plan._

## Progress

1. ✅ Строки edge_cases
2. ✅ Проверки

## Log

- 2026-10-06: triage — pipeline `minimal`, reason: долг из 2026-10-02-digits-in-token-validation; только строки edge_cases.tsv + закрытие долга по замеру, кода нет
- 2026-10-06: замер: 13/13 keep (arr[i], dict["k"], m[i][j], data["name"], …) — модель их не трогает
- 2026-10-06: шаг 1 ✅ Строки edge_cases
- 2026-10-06: строки добавлены
- 2026-10-06: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-10-06: verify: `LayoutEval edge cases: keep en←en index-no-digit 13/13` → exit 0 ✅
- 2026-10-06: шаг 2 ✅ Проверки
- 2026-10-06: долг закрыт замером: модель сохраняет индексные выражения без цифр; 13 строк edge_cases как регрессия (ревью не нужно — только данные eval)

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

_Отложенное, упрощения, известные пробелы. Формат — чекбоксы (их считают индекс и отчёты по долгам):_
_- `- [ ] <что отложено> — <почему/контекст>` — открытый долг_
_- `- [x] <что было> — закрыто YYYY-MM-DD: <причина/ссылка на task>` — закрытый_
_Без `[ ]`/`[x]` пункт невидим для агрегатора и теряется через 2 недели._

## Verification

- 2026-10-06 · `swift run -c release TestRunner` · exit 0 ✅

  ```
  | fix en←ru word-forms | 9/10 | pfdnhf→завтра (want завтра) |
  | fix en←ru slang-tech | 5/7 | ofc (want щас), rhby; (want кринж) |
  | fix en←uk word-forms | 6/6 |  |
  | fix en←uk slang-tech | 3/4 | yjhv→норм (want норм) |
  | keep en←en backslash | 6/6 |  |
  | fix en←uk apostrophe | 6/6 |  |
  | keep en←en index-no-digit | 13/13 |  |
  
  ========================================
  Results: 1210 passed, 0 failed
  ALL TESTS PASSED
  
  Building for production...
  Build complete! (0,19 с)
  ```

- 2026-10-06 · `LayoutEval edge cases: keep en←en index-no-digit 13/13` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
