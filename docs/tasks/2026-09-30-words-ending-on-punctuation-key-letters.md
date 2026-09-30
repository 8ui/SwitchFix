---
id: 2026-09-30-words-ending-on-punctuation-key-letters
title: Words ending in letters on punctuation keys (х ъ ж э б ю ё) may be cut as trailing punctuation
type: bug
pipeline: minimal
phase: review
created: 2026-09-30
updated: 2026-09-30
blocked_by: null
steps_done: 4
steps_total: 4
step_current: null
artifacts:
  spec: null
  plan: null
  branch: null
  pr: null
---

## Context

В RuSwitcher массово не конвертировались слова, у которых последняя буква в EN-раскладке — знак препинания:
х `[`, ъ `]`, ж `;`, э `'`, б `,`, ю `.`, ё `` ` `` (`их`→`bx[`, `ещё`, `знаю`→`pyf.`, `наших`, `ghbdtn,`) —
детектор отрезал хвост как пунктуацию (rashn/RuSwitcher #35, #15, #33; xneur #2, #59: `будет`→`,eltn`). В Russian–PC
`,` и `.` стоят на `/?`, в Ukrainian legacy/PC пунктуация на других клавишах, апостроф внутри `п'ять` — не граница.
У нас `LayoutDetector.splitTrailingBoundary` отрезает хвост по `boundaryCharacterSet` (LayoutDetector.swift:894),
и `lexiconWord(from:)` на нём же — проверить, что `bx[`, `pyf.`, ``tot` `` (ещё), `ghbdtn,`, `,eltn` конвертируются, а
настоящая точка/запятая после английского слова — нет (KeySwitch решает это отдельной «моделью границы слова»
и откладывает решение при сомнении). Сначала — тесты в TestRunner на все семь букв в конце и в начале слова,
для KeyboardTables.pc и для Russian–PC/Ukrainian-legacy таблиц.

## Progress

1. ✅ Воспроизвести тестами в TestRunner
2. ✅ Найти корневую причину
3. ✅ Исправить
4. ✅ Ревью

## Log

- 2026-09-30: triage — pipeline `minimal`, reason: исследование: RuSwitcher #35/#15/#33 массово не конвертировал их/ещё/знаю/ghbdtn,; проверить splitTrailingBoundary
- 2026-09-30: brainstorm: критерий — тесты на х ъ ж э б ю ё в конце/начале слова конвертируются, настоящая пунктуация после EN-слова нет
- 2026-09-30: шаг 1 ✅ Воспроизвести тестами в TestRunner — 5 падений: ё (`) на краях, э (') и ю (.) в начале
- 2026-09-30: шаг 2 ✅ Найти корневую причину — typedCore для margin и короткой таблицы обрезал края, ставшие буквами: EN-сторона считалась по меньшему числу символов
- 2026-09-30: шаг 3 ✅ Исправить — typedScoringSpan: края, ставшие буквами, платят штраф модели; бесплатны обычный хвост ,.;:'" и обрамление [x] `x`
- 2026-09-30: impl complete: LayoutEval primary ru 95.02→96.20%, uk 96.83→98.25%, uk сообщения 92.08→95.05%, FP без изменений
- 2026-09-30: verify: `swift build -c release` → exit 0 ✅
- 2026-09-30: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-09-30: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-09-30: verify: `swift build -c release` → exit 0 ✅
- 2026-09-30: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-09-30: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-09-30: ревью: штраф −12 за краевой символ давал FP (here]→рукуї, `git→ёпше, 'em); переделано на фиксированную цену 4 за краевую клавишу-букву, откалибровано перебором 0–6 (6 → FP ps']); добавлен набор на 17358 EN-токенов с краевыми символами: FP 1 (to`→ещё, целевой)
- 2026-09-30: verify: `swift build -c release` → exit 0 ✅
- 2026-09-30: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-09-30: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-09-30: шаг 4 ✅ Ревью — 2 ревью: FP от штрафа −12 → цена 4; парность закрывающей скобки внутри слова (see[1])
- 2026-09-30: ревью 2: see[1]/fig[1] получали бонус за ']' — закрывающая скобка с открывающей внутри токена не буква; набор FP строгий (0 сверх to`); 603/0; ждёт коммита и CI

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] en+ru+uk без истории раскладки: wrong conversion для uk 4-5 букв 169→207 (1157→1195 всего) вместе с ростом restored — слова с ї/є на краю (] ') теперь конвертируются, часть в русский; вторичный сценарий LayoutEval secondary, ru не изменился — переформулировано 2026-09-30
- [ ] Индексы 'w[1]' конвертировались и до этой задачи (HEAD: 209/1105 слов en.txt на ru, 194 на uk; 'obj[0]', 'x[0]' → ...) — splitTokenForValidation считает цифры частью слова; отдельная задача

## Verification

- 2026-09-30 · `swift build -c release` · exit 0 ✅

  ```
  Building for production...
  [2 / 13]
  [4 / 10] InputPipelineTestRunner-product
  [6 / 12] InputPipelineTestRunner-product
  [8 / 12] UI
  [12 / 14] SwitchFixApp-product
  [16 / 19] SwitchFixApp-product
  [18 / 19] SwitchFixApp-product
  [19 / 19] SwitchFixApp-product
  Build complete! (4,05 с)
  ```

- 2026-09-30 · `swift run -c release TestRunner` · exit 0 ✅

  ```
  | fix ru←en word-forms | 11/11 |  |
  | fix uk←en tech | 12/14 | пшерги (want github), згірув (want pushed) |
  | fix uk←en word-forms | 10/11 | сфеі (want cats) |
  | fix en←ru word-forms | 9/10 | pfdnhf→завтра (want завтра) |
  | fix en←ru slang-tech | 5/7 | ofc (want щас), rhby; (want кринж) |
  | fix en←uk word-forms | 6/6 |  |
  | fix en←uk slang-tech | 3/4 | yjhv→норм (want норм) |
  
  ========================================
  Results: 582 passed, 0 failed
  ALL TESTS PASSED
  
  Building for production...
  Build complete! (0,19 с)
  ```

- 2026-09-30 · `swift run -c release InputPipelineTestRunner` · exit 0 ✅

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
  
  Input pipeline: 1002 passed, 0 failed
  
  Building for production...
  Build complete! (0,19 с)
  ```

- 2026-09-30 · `swift build -c release` · exit 0 ✅

  ```
  /Users/andrejsokolov/Desktop/projects/SwitchFix/Sources/Core/InputEngine.swift:211:82: [1;33mwarning: [1;39m'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope[0;0m [#]8;;https://docs.swift.org/compiler/documentation/diagnostics/implicit-strong-cap… [обрезано 35 симв.]
  [0;36m208 |[0;0m                 return
  [0;36m209 |[0;0m             }
  [0;36m210 |[0;0m             self.selectionQueue.async {
      [0;36m|[0;0m                                       |- [1;39mnote: [1;39m'self' implicitly strongly captured here[0;0m
      [0;36m|[0;0m                                       `- [1;39mnote: [1;39madd 'self' as a capture list item to silence[0;0m
  [0;36m211 |[0;0m                 selectedTextRequest(context.frontmostPID, context.epoch) { [weak self] selectedText in
      [0;36m|[0;0m                                                                                  |- [1;33mwarning: [1;39m'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope[0;0m [#]8;;https://docs.swift.org/compiler/documentation/diagnostics/imp… [обрезано 51 симв.]
      [0;36m|[0;0m                                                                                  `- [1;39mnote: [1;39mexplicitly assign the capture list item to silence[0;0m
  [0;36m212 |[0;0m                     guard let self else { return }
  [0;36m213 |[0;0m                     self.inputQueue.async {
  
  [#ImplicitStrongCapture]: <https://docs.swift.org/compiler/documentation/diagnostics/implicit-strong-capture>
  ```

- 2026-09-30 · `swift run -c release TestRunner` · exit 0 ✅

  ```
  | fix uk←en tech | 12/14 | пшерги (want github), згірув (want pushed) |
  | fix uk←en word-forms | 10/11 | сфеі (want cats) |
  | fix en←ru word-forms | 9/10 | pfdnhf→завтра (want завтра) |
  | fix en←ru slang-tech | 5/7 | ofc (want щас), rhby; (want кринж) |
  | fix en←uk word-forms | 6/6 |  |
  | fix en←uk slang-tech | 3/4 | yjhv→норм (want норм) |
  
  ========================================
  Results: 598 passed, 0 failed
  ALL TESTS PASSED
  
  Building for production...
  [1 / 9]
  Build complete! (0,32 с)
  ```

- 2026-09-30 · `swift run -c release InputPipelineTestRunner` · exit 0 ✅

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
  
  Input pipeline: 1002 passed, 0 failed
  
  Building for production...
  Build complete! (0,18 с)
  ```

- 2026-09-30 · `swift build -c release` · exit 0 ✅

  ```
  Building for production...
  [2 / 13]
  [4 / 10] InputPipelineTestRunner-product
  [6 / 12] InputPipelineTestRunner-product
  [8 / 12] UI
  [11 / 14] InputPipelineTestRunner-product
  [13 / 15] InputPipelineTestRunner-product
  [16 / 19] SwitchFixApp-product
  [18 / 19] SwitchFixApp-product
  [19 / 19] SwitchFixApp-product
  Build complete! (3,74 с)
  ```

- 2026-09-30 · `swift run -c release TestRunner` · exit 0 ✅

  ```
  | fix uk←en tech | 12/14 | пшерги (want github), згірув (want pushed) |
  | fix uk←en word-forms | 10/11 | сфеі (want cats) |
  | fix en←ru word-forms | 9/10 | pfdnhf→завтра (want завтра) |
  | fix en←ru slang-tech | 5/7 | ofc (want щас), rhby; (want кринж) |
  | fix en←uk word-forms | 6/6 |  |
  | fix en←uk slang-tech | 3/4 | yjhv→норм (want норм) |
  
  ========================================
  Results: 603 passed, 0 failed
  ALL TESTS PASSED
  
  Building for production...
  [1 / 9]
  Build complete! (0,32 с)
  ```

- 2026-09-30 · `swift run -c release InputPipelineTestRunner` · exit 0 ✅

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
  
  Input pipeline: 1002 passed, 0 failed
  
  Building for production...
  Build complete! (0,19 с)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
