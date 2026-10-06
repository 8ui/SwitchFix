---
id: 2026-10-06-keys-typed-between-a-correction-and-its-layout-switch-end-up
title: Keys typed between a correction and its layout switch end up in two layouts
type: bug
pipeline: minimal
phase: review
created: 2026-10-06
updated: 2026-10-06
blocked_by: null
steps_done: 2
steps_total: 3
step_current: 3
artifacts:
  spec: null
  plan: null
  branch: null
  pr: null
---

## Context

Telegram: в русской раскладке «слово ␣""» быстро → `"@`. После автокоррекции слова переключение раскладки ставится в очередь main; первая `"` (Shift+2) успевает уйти в старой раскладке, вторая — уже в английской (Shift+2 = @). `mayFinishLayoutSwitch` намеренно не отменял переключение при наборе (решение 2026-10-02-recheck-context-before-layout-switch).

## Progress

1. ✅ Отменять переключение при наборе после коррекции
2. ✅ Тест в InputPipelineTestRunner
3. ▶ Ревью и проверки

## Log

- 2026-10-06: triage — pipeline `minimal`, reason: одно условие в TextCorrector.mayFinishLayoutSwitch + тест в InputPipelineTestRunner; пересматривает решение из 2026-10-02-recheck-context-before-layout-switch
- 2026-10-06: brainstorm: Telegram, "" после пробела → "@ сразу; первая кавычка в старой раскладке, вторая после переключения; корень — mayFinishLayoutSwitch не отменяет переключение при наборе после коррекции
- 2026-10-06: шаг 1 ✅ Отменять переключение при наборе после коррекции
- 2026-10-06: шаг 2 ✅ Тест в InputPipelineTestRunner — 1461 passed
- 2026-10-06: impl complete
- 2026-10-06: verify: `swift build -c release` → exit 0 ✅
- 2026-10-06: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-10-06: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-10-06: verify: `swift build -c release` → exit 0 ✅
- 2026-10-06: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-10-06: spec-review: n/a; code-review: субагент general-purpose (opus) — дефектов нет; поправлены комментарий и лог пропуска
- 2026-10-06: ревью учтено

## Decisions

- Пересмотрено решение из 2026-10-02-recheck-context-before-layout-switch («следующие клавиши уже в новой раскладке»): клавиша, нажатая до переключения, набрана в старой раскладке; переключение после неё делит набираемый текст на две раскладки. Теперь любое физическое редактирование (editGeneration) после коррекции отменяет переключение; следующее слово проверяется в старой раскладке. Хоткеи editGeneration не двигают.

## Debt

- [ ] пропущенное из-за набора переключение не возвращает подтверждение низкоуверенного переключения (LayoutDetector сбросил счётчик): следующее такое слово снова требует двух подтверждений — как и при пропуске из-за смены фокуса; у быстрого набора теперь чаще — ревью
- [ ] гонка сужена, не закрыта: клавиша, которую приложение получило до переключения, а tap-колбэк обработал после, проходит проверку; в Telegram вживую не воспроизведено (баг ловился нерегулярно)

## Verification

- 2026-10-06 · `swift build -c release` · exit 0 ✅

  ```
  Building for production...
  [2 / 12]
  Build complete! (0,40 с)
  ```

- 2026-10-06 · `swift run -c release TestRunner` · exit 0 ✅

  ```
  | fix ru←en word-forms | 11/11 |  |
  | fix uk←en tech | 12/14 | пшерги (want github), згірув (want pushed) |
  | fix uk←en word-forms | 10/11 | сфеі (want cats) |
  | fix en←ru word-forms | 9/10 | pfdnhf→завтра (want завтра) |
  | fix en←ru slang-tech | 5/7 | ofc (want щас), rhby; (want кринж) |
  | fix en←uk word-forms | 6/6 |  |
  | fix en←uk slang-tech | 3/4 | yjhv→норм (want норм) |
  
  ========================================
  Results: 1176 passed, 0 failed
  ALL TESTS PASSED
  
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
  
  Input pipeline: 1461 passed, 0 failed
  
  Building for production...
  [1 / 9]
  Build complete! (0,33 с)
  ```

- 2026-10-06 · `swift build -c release` · exit 0 ✅

  ```
  /Users/andrejsokolov/Desktop/projects/SwitchFix/Sources/Core/InputEngine.swift:766:59: [1;33mwarning: [1;39m'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope[0;0m [#]8;;https://docs.swift.org/compiler/documentation/diagnostics/implicit-strong-cap… [обрезано 35 симв.]
   [0;36m763 |[0;0m         // suffix is compared, so a character cut at the window's start does not matter.
   [0;36m764 |[0;0m         let window = (check.word + check.boundary).utf16.count + 6
   [0;36m765 |[0;0m         selectionQueue.async {
       [0;36m|[0;0m                              |- [1;39mnote: [1;39m'self' implicitly strongly captured here[0;0m
       [0;36m|[0;0m                              `- [1;39mnote: [1;39madd 'self' as a capture list item to silence[0;0m
   [0;36m766 |[0;0m             query(check.pid, check.epoch, window) { [weak self] probe in
       [0;36m|[0;0m                                                           |- [1;33mwarning: [1;39m'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope[0;0m [#]8;;https://docs.swift.org/compiler/documentation/diagnostics/implicit-strong-capture\… [обрезано 29 симв.]
       [0;36m|[0;0m                                                           `- [1;39mnote: [1;39mexplicitly assign the capture list item to silence[0;0m
   [0;36m767 |[0;0m                 self?.inputQueue.async {
   [0;36m768 |[0;0m                     guard let self else { return }
  
  [#ImplicitStrongCapture]: <https://docs.swift.org/compiler/documentation/diagnostics/implicit-strong-capture>
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
  
  Input pipeline: 1461 passed, 0 failed
  
  Building for production...
  Build complete! (0,21 с)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
