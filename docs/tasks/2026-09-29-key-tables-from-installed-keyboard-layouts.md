---
id: 2026-09-29-key-tables-from-installed-keyboard-layouts
title: Key tables from installed keyboard layouts
type: bug
pipeline: full
phase: done
created: 2026-09-29
updated: 2026-10-05
blocked_by: null
steps_done: 5
steps_total: 5
step_current: null
artifacts:
  spec: docs/features/key-tables-from-installed-layouts-spec.md
  plan: docs/plans/key-tables-from-installed-layouts-plan.md
  branch: null
  pr: null
---

## Context

_2-5 строк: что делаем и зачем. Задача этой секции — чтобы через N дней можно было восстановить контекст без чтения spec/plan._

## Progress

1. ✅ Task 1: KeyTable types и .pc
2. ✅ Task 2: KeyTableBuilder + sanity
3. ✅ Task 3: InputSourceManager per-source tables
4. ✅ Task 4: замена UkrainianKeyboardVariant
5. ✅ Task 5: docs, сборка, ручная проверка

## Log

- 2026-09-29: triage — pipeline `full`, reason: >5 файлов Core+App, влияет на детектор; статичные PC-таблицы неверны для mac Russian/Ukrainian, British-PC, Shift+цифр
- 2026-09-29: brainstorm: пользователь выбрал таблицы из системы, full, убрать UkrainianKeyboardVariant
- 2026-09-29: artifacts.spec = docs/features/key-tables-from-installed-layouts-spec.md
- 2026-09-29: spec drafted
- 2026-09-29: spec-review (general-purpose opus): 3 blocker/7 major/6 minor учтены в ревизии 2; вне объёма → debt
- 2026-09-29: artifacts.plan = docs/plans/key-tables-from-installed-layouts-plan.md
- 2026-09-29: plan drafted (5 tasks)
- 2026-09-29: plan-review (Plan opus): C1 crash dict literal, C2 internal PCLayoutData, H1-H4, M2-M4 учтены
- 2026-09-29: шаг 1 ✅ Task 1: KeyTable types и .pc — 290 passed; .pc == static convert для всех пар
- 2026-09-29: шаг 2 ✅ Task 2: KeyTableBuilder + sanity — 533 passed; найдено: ISO-клавиша 10 дублирует ё в RussianWin, mac Ukrainian = legacy
- 2026-09-29: шаг 3 ✅ Task 3: InputSourceManager per-source tables — 536 passed, app builds
- 2026-09-29: шаг 4 ✅ Task 4: замена UkrainianKeyboardVariant — 533+886 passed; eval без изменений (кроме таймингов), sweep идентичен
- 2026-09-29: verify: `Проверено пользователем на macOS (RussianWin+Australian, ISO kbd type 91)` → exit 0 ✅
- 2026-09-29: шаг 5 ✅ Task 5: docs, сборка, ручная проверка
- 2026-09-29: impl complete, manual verified; доп. фикс selectionSourceOrder для выделений без букв
- 2026-09-29: verify: `swift build -c release` → exit 0 ✅
- 2026-09-29: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-09-29: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-09-29: verify: `swift build -c release` → exit 0 ✅
- 2026-09-29: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-09-29: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-09-29: code-review (general-purpose opus): 2 medium исправлены (тавтологичный тест → эталон из старого кода; legacy-фолбэк uk), low #4 исправлен, #3/#5 → debt
- 2026-09-29: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36572313534` → exit 0 ✅
- 2026-09-29: pushed 83cc15c, CI green, manual verified, review addressed

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] Границы слова по физической клавише: № ? @ # $ % ^ & * обрывают слово — спека key-tables, вне объёма
- [x] Перестраивать таблицы при смене типа клавиатуры (LMGetKbdType) — спека key-tables, вне объёма — закрыто 2026-10-05: 2026-10-05-debt-batch-revert-shortcuts-keytables
- [ ] Report-only LayoutEval на реальных (не .pc) таблицах — спека key-tables M4
- [ ] Общий dependency-free таргет с ключевыми данными для Core и ModelTrainer — спека key-tables B2
- [ ] Автодетекция перебирает все таблицы исходной раскладки (US+Colemak/Dvorak): первая прошедшая порог побеждает — не измерено LayoutEval
- [ ] Выделение без букв (';5') при .pc-фолбэке источника (Phonetic, нечитаемый uchr) всё ещё идёт через English → 'ж5'; end-to-end теста ';5'→'$5' через движок нет — ревью key-tables, low
- [x] Тесты KeyTableBuilder: нет проверки пропуска dead keys; suite 'system tables agree' пропускает клавиши 10/50 целиком (ё/ґ на 50 не покрыты на ANSI) — ревью key-tables, low — закрыто 2026-10-05: 2026-10-05-debt-batch-revert-shortcuts-keytables

## Verification

- 2026-09-29 · `Проверено пользователем на macOS (RussianWin+Australian, ISO kbd type 91)` · exit 0 ✅

  ```
  "ьфшд+хоткей → @mail; выделение гыук"ьфшдюсщь → user@mail.com; №1 ;5 → #1 $5 и обратно; сценарий A (worktree, привет) с переключением раскладки
  ```

- 2026-09-29 · `swift build -c release` · exit 0 ✅

  ```
  Building for production...
  Build complete! (0,41 с)
  ```

- 2026-09-29 · `swift run -c release TestRunner` · exit 0 ✅

  ```
  | fix uk←en tech | 12/14 | пшерги (want github), згірув (want pushed) |
  | fix uk←en word-forms | 10/11 | сфеі (want cats) |
  | fix en←ru word-forms | 9/10 | pfdnhf→завтра (want завтра) |
  | fix en←ru slang-tech | 5/7 | ofc (want щас), rhby; (want кринж) |
  | fix en←uk word-forms | 6/6 |  |
  | fix en←uk slang-tech | 3/4 | yjhv→норм (want норм) |
  
  ========================================
  Results: 533 passed, 0 failed
  ALL TESTS PASSED
  
  Building for production...
  [1 / 9]
  Build complete! (0,32 с)
  ```

- 2026-09-29 · `swift run -c release InputPipelineTestRunner` · exit 0 ✅

  ```
  --- learning: reverting a forced hotkey conversion forgets the lesson ---
  --- learning: manual entries are not overwritten by reverts ---
  --- learning: forced hotkey target follows the last Cyrillic layout ---
  --- key tables: hotkey converts a shifted digit-row symbol through the key ---
  --- key tables: .pc keeps today's result for the same input ---
  --- learning: the revert hotkey's fallback conversion does not teach ---
  --- learning: one- and two-key hotkey conversions are not learned ---
  --- learning: trailing punctuation is not part of the learned word ---
  --- learning: merged multi-word corrections are not learned ---
  
  Input pipeline: 889 passed, 0 failed
  
  Building for production...
  Build complete! (0,19 с)
  ```

- 2026-09-29 · `swift build -c release` · exit 0 ✅

  ```
  Building for production...
  [2 / 12] SwitchFix_LanguageModel
  Build complete! (0,25 с)
  ```

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
  Results: 522 passed, 0 failed
  ALL TESTS PASSED
  
  Building for production...
  Build complete! (0,19 с)
  ```

- 2026-09-29 · `swift run -c release InputPipelineTestRunner` · exit 0 ✅

  ```
  --- learning: reverting a forced hotkey conversion forgets the lesson ---
  --- learning: manual entries are not overwritten by reverts ---
  --- learning: forced hotkey target follows the last Cyrillic layout ---
  --- key tables: hotkey converts a shifted digit-row symbol through the key ---
  --- key tables: .pc keeps today's result for the same input ---
  --- learning: the revert hotkey's fallback conversion does not teach ---
  --- learning: one- and two-key hotkey conversions are not learned ---
  --- learning: trailing punctuation is not part of the learned word ---
  --- learning: merged multi-word corrections are not learned ---
  
  Input pipeline: 889 passed, 0 failed
  
  Building for production...
  Build complete! (0,19 с)
  ```

- 2026-09-29 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36572313534` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
