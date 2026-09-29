---
id: 2026-09-29-australian-and-other-english-qwerty-layouts-not-recognized
title: Australian and other English QWERTY layouts not recognized as English
type: bug
pipeline: minimal
phase: done
created: 2026-09-29
updated: 2026-09-29
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

1. ✅ Тест + фикс
2. ✅ Проверка в приложении
3. ✅ Ревью

## Log

- 2026-09-29: triage — pipeline `minimal`, reason: 1-2 файла (LayoutMapper.inputSourceIDs + тест), причина найдена по логу ручной проверки
- 2026-09-29: root cause: Layout.inputSourceIDs whitelist lacks Australian; failing test added
- 2026-09-29: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-09-29: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-09-29: шаг 1 ✅ Тест + фикс — 246/882 зелёные, установлено в /Applications
- 2026-09-29: verify: `Проверено на macOS пользователем с раскладками RussianWin+Australian` → exit 0 ✅
- 2026-09-29: шаг 2 ✅ Проверка в приложении
- 2026-09-29: impl complete, verified in app
- 2026-09-29: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-09-29: шаг 3 ✅ Ревью
- 2026-09-29: commit 126f5f3, verified in app, review addressed

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] Colemak/Dvorak в списке English, хотя LayoutMapper считает позиции QWERTY — конверсия на них неверна (было до фикса, ревью)
- [ ] British-PC/ISO British/Irish: Shift-символы (@ на Shift+', ~ на клавише #) расходятся с таблицами LayoutMapper — затрагивает Э/Є/Ё/Ґ; учесть в задаче про Shift+цифры

## Verification

- 2026-09-29 · `swift run -c release TestRunner` · exit 0 ✅

  ```
  | fix ru←en word-forms | 11/11 |  |
  | fix uk←en tech | 12/14 | пшерги (want github), згірув (want pushed) |
  | fix uk←en word-forms | 10/11 | сфеі (want cats) |
  | fix en←ru word-forms | 9/10 | pfdnhf→завтра (want завтра) |
  | fix en←ru slang-tech | 5/7 | ofc (want щас), rhby; (want кринж) |
  | fix en←uk word-forms | 6/6 |  |
  | fix en←uk slang-tech | 3/4 | yjhv→норм (want норм) |
  
  ========================================
  Results: 246 passed, 0 failed
  ALL TESTS PASSED
  
  Building for production...
  Build complete! (0,18 с)
  ```

- 2026-09-29 · `swift run -c release InputPipelineTestRunner` · exit 0 ✅

  ```
  --- learning: revert of an automatic correction teaches neverCorrect ---
  --- learning: forced hotkey conversion teaches alwaysCorrect ---
  --- learning: reverting a forced hotkey conversion forgets the lesson ---
  --- learning: manual entries are not overwritten by reverts ---
  --- learning: forced hotkey target follows the last Cyrillic layout ---
  --- learning: the revert hotkey's fallback conversion does not teach ---
  --- learning: one- and two-key hotkey conversions are not learned ---
  --- learning: trailing punctuation is not part of the learned word ---
  --- learning: merged multi-word corrections are not learned ---
  
  Input pipeline: 882 passed, 0 failed
  
  Building for production...
  Build complete! (0,18 с)
  ```

- 2026-09-29 · `Проверено на macOS пользователем с раскладками RussianWin+Australian` · exit 0 ✅

  ```
  цщклекуу → worktree (margin=34.7), layout switched to english (com.apple.keylayout.Australian); хоткей на 'как' переключает раскладку
  ```

- 2026-09-29 · `swift run -c release TestRunner` · exit 0 ✅

  ```
  | fix en←ru slang-tech | 5/7 | ofc (want щас), rhby; (want кринж) |
  | fix en←uk word-forms | 6/6 |  |
  | fix en←uk slang-tech | 3/4 | yjhv→норм (want норм) |
  
  ========================================
  Results: 247 passed, 0 failed
  ALL TESTS PASSED
  
  Building for production...
  [3 / 6] TestRunner-product
  [5 / 7] TestRunner-product
  [7 / 7] TestRunner-product
  [8 / 9] TestRunner-product
  Build complete! (4,77 с)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
