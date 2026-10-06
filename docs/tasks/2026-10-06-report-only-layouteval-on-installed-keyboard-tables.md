---
id: 2026-10-06-report-only-layouteval-on-installed-keyboard-tables
title: Report-only LayoutEval on installed keyboard tables
type: chore
pipeline: minimal
phase: done
created: 2026-10-06
updated: 2026-10-06
blocked_by: null
steps_done: 3
steps_total: 3
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

1. ✅ evalTables + флаг --layout-eval-real-tables
2. ✅ Замер и бенчмарк
3. ✅ Ревью и проверки

## Log

- 2026-10-06: triage — pipeline `minimal`, reason: долг key-tables M4; только TestRunner (LayoutEval.swift + main.swift флаг), отчётный режим, .pc-числа не меняются
- 2026-10-06: brainstorm: долг key-tables M4 — сравнить eval на реальных таблицах; отчётный флаг
- 2026-10-06: шаг 1 ✅ evalTables + флаг --layout-eval-real-tables
- 2026-10-06: шаг 2 ✅ Замер и бенчмарк — совпадает с .pc строка в строку; plan/benchmarks/real_tables.md
- 2026-10-06: impl complete
- 2026-10-06: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-10-06: verify: `swift run -c release TestRunner --layout-eval-real-tables` → exit 0 ✅
- 2026-10-06: шаг 3 ✅ Ревью и проверки — ревью general-purpose (sonnet): дефектов нет
- 2026-10-06: отчётный режим --layout-eval-real-tables; на стандартной тройке совпадает с .pc; ревью без дефектов

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
  Results: 1214 passed, 0 failed
  ALL TESTS PASSED
  
  Building for production...
  Build complete! (0,19 с)
  ```

- 2026-10-06 · `swift run -c release TestRunner --layout-eval-real-tables` · exit 0 ✅

  ```
  | fix uk←en word-forms | 10/11 | сфеі (want cats) |
  | fix en←ru word-forms | 9/10 | pfdnhf→завтра (want завтра) |
  | fix en←ru slang-tech | 5/7 | ofc (want щас), rhby; (want кринж) |
  | fix en←uk word-forms | 6/6 |  |
  | fix en←uk slang-tech | 3/4 | yjhv→норм (want норм) |
  | keep en←en backslash | 6/6 |  |
  | fix en←uk apostrophe | 6/6 |  |
  | keep en←en index-no-digit | 13/13 |  |
  
  ========================================
  Results: 15 passed, 0 failed
  
  Building for production...
  Build complete! (0,19 с)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
