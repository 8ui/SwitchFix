---
id: 2026-10-06-a-word-ended-by-enter-in-the-wrong-layout-does-not-switch
title: A word ended by Enter in the wrong layout does not switch the layout
type: bug
pipeline: minimal
phase: review
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

1. ✅ Переключение раскладки на слове, законченном Enter
2. ✅ Тест в харнессе
3. ✅ Ревью и проверки

## Log

- 2026-10-06: triage — pipeline `minimal`, reason: одна ветка в InputEngine.prepareCorrection (Enter: без перенабора, только переключение через TextCorrector.finishLayoutSwitch) + тест в харнессе; долг из 2026-09-30-automatic-correction-retypes-the-enter-that-ended-the-word
- 2026-10-06: brainstorm: Enter уже отправил текст — перенабор нельзя; переключение раскладки безопасно (следующее сообщение в верной раскладке); Shift+Return не выделяем — в терминалах тоже выполняет
- 2026-10-06: шаг 1 ✅ Переключение раскладки на слове, законченном Enter
- 2026-10-06: шаг 2 ✅ Тест в харнессе — 1475 passed
- 2026-10-06: impl complete
- 2026-10-06: verify: `swift build -c release` → exit 0 ✅
- 2026-10-06: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-10-06: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-10-06: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-10-06: шаг 3 ✅ Ревью и проверки — ревью general-purpose (opus): дефектов нет; UX-риск — в долг
- 2026-10-06: verify: `swift build -c release` → exit 0 ✅
- 2026-10-06: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-10-06: доработка: переключение после Enter только для слов от 4 букв (короткие — основной источник ложных; Caps Lock-отмена после Enter была бы случайной); тест с мутационной проверкой

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] ложное переключение после Enter не откатывается хоткеем отмены и не учит лексикон — сознательно: отмена по умолчанию на Caps Lock, его жмут для заглавной в начале следующего сообщения; риск снижен порогом ≥4 букв (InputEngine.minimumLettersForEnterSwitch) — переформулировано 2026-10-06
- [ ] переключение после Enter идёт без сверки текста поля (enforce) — текст не меняется, риск только лишнего переключения (ревью, low)
- [ ] Shift+Return не отличается от Return: в чатах он перевод строки, но в терминалах выполняет — слово перед ним тоже не перенабирается

## Verification

- 2026-10-06 · `swift build -c release` · exit 0 ✅

  ```
  Building for production...
  [2 / 12]
  Build complete! (0,54 с)
  ```

- 2026-10-06 · `swift run -c release TestRunner` · exit 0 ✅

  ```
  | fix en←ru word-forms | 9/10 | pfdnhf→завтра (want завтра) |
  | fix en←ru slang-tech | 5/7 | ofc (want щас), rhby; (want кринж) |
  | fix en←uk word-forms | 6/6 |  |
  | fix en←uk slang-tech | 3/4 | yjhv→норм (want норм) |
  | keep en←en backslash | 6/6 |  |
  | fix en←uk apostrophe | 6/6 |  |
  
  ========================================
  Results: 1210 passed, 0 failed
  ALL TESTS PASSED
  
  Building for production...
  [1 / 9]
  Build complete! (0,34 с)
  ```

- 2026-10-06 · `swift run -c release InputPipelineTestRunner` · exit 0 ✅

  ```
  --- layout switch after a correction: rechecked on main ---
  --- layout switch after a correction: queued, rechecked and superseded ---
  --- revert screen check: a hotkey correction (no boundary) ---
  --- key-down classification: input-source shortcuts act like the Globe key ---
  --- key-down classification: other keys as before ---
  --- key-down classification: caret moves and unseen edits ---
  --- mouse-down classification ---
  --- input-source shortcuts from com.apple.symbolichotkeys ---
  --- input-source shortcuts: re-read at most once per interval unless forced ---
  
  Input pipeline: 1475 passed, 0 failed
  
  Building for production...
  Build complete! (0,21 с)
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
  [1 / 1]
  Build complete! (0,32 с)
  ```

- 2026-10-06 · `swift build -c release` · exit 0 ✅

  ```
  /Users/andrejsokolov/Desktop/projects/SwitchFix/Sources/Core/InputEngine.swift:800:59: [1;33mwarning: [1;39m'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope[0;0m [#]8;;https://docs.swift.org/compiler/documentation/diagnostics/implicit-strong-cap… [обрезано 35 симв.]
   [0;36m797 |[0;0m         // suffix is compared, so a character cut at the window's start does not matter.
   [0;36m798 |[0;0m         let window = (check.word + check.boundary).utf16.count + 6
   [0;36m799 |[0;0m         selectionQueue.async {
       [0;36m|[0;0m                              |- [1;39mnote: [1;39m'self' implicitly strongly captured here[0;0m
       [0;36m|[0;0m                              `- [1;39mnote: [1;39madd 'self' as a capture list item to silence[0;0m
   [0;36m800 |[0;0m             query(check.pid, check.epoch, window) { [weak self] probe in
       [0;36m|[0;0m                                                           |- [1;33mwarning: [1;39m'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope[0;0m [#]8;;https://docs.swift.org/compiler/documentation/diagnostics/implicit-strong-capture\… [обрезано 29 симв.]
       [0;36m|[0;0m                                                           `- [1;39mnote: [1;39mexplicitly assign the capture list item to silence[0;0m
   [0;36m801 |[0;0m                 self?.inputQueue.async {
   [0;36m802 |[0;0m                     guard let self else { return }
  
  [#ImplicitStrongCapture]: <https://docs.swift.org/compiler/documentation/diagnostics/implicit-strong-capture>
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
  
  Input pipeline: 1477 passed, 0 failed
  
  Building for production...
  [1 / 9]
  Build complete! (0,24 с)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
