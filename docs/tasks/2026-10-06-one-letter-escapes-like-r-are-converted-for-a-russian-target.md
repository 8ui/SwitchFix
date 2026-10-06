---
id: 2026-10-06-one-letter-escapes-like-r-are-converted-for-a-russian-target
title: One-letter escapes like \r are converted for a Russian target
type: bug
pipeline: minimal
phase: review
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

1. ✅ Условие и тесты
2. ✅ Ревью

## Log

- 2026-10-06: triage — pipeline `minimal`, reason: одно условие в LayoutDetector.backslashFits + строки теста; долг из 2026-10-06-ukrainian-apostrophe
- 2026-10-06: ревью апострофа: \r→\к, \b→\и при русской цели
- 2026-10-06: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-10-06: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-10-06: verify: `swift build -c release` → exit 0 ✅
- 2026-10-06: шаг 1 ✅ Условие и тесты
- 2026-10-06: шаг 2 ✅ Ревью — ревью general-purpose (sonnet): дефектов нет
- 2026-10-06: impl+review: дефектов нет; z\ (я\) больше не исправляется — принято

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] однобуквенное русское слово вплотную к \ (z\ → я\) больше не исправляется автоматически — неотличимо от escape (ревью, принято)

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
  Build complete! (0,22 с)
  ```

- 2026-10-06 · `swift run -c release InputPipelineTestRunner` · exit 0 ✅

  ```
  --- layout switch after a correction: queued, rechecked and superseded ---
  --- revert screen check: a hotkey correction (no boundary) ---
  --- key-down classification: input-source shortcuts act like the Globe key ---
  --- key-down classification: other keys as before ---
  --- key-down classification: caret moves and unseen edits ---
  --- mouse-down classification ---
  --- input-source shortcuts from com.apple.symbolichotkeys ---
  --- input-source shortcuts: re-read at most once per interval unless forced ---
  
  Input pipeline: 1476 passed, 0 failed
  
  Building for production...
  [1 / 9]
  Build complete! (0,33 с)
  ```

- 2026-10-06 · `swift build -c release` · exit 0 ✅

  ```
  Building for production...
  [1 / 5] LanguageModel
  Build complete! (0,24 с)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
