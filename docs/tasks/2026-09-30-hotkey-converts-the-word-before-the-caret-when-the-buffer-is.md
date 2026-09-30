---
id: 2026-09-30-hotkey-converts-the-word-before-the-caret-when-the-buffer-is
title: Hotkey converts the word before the caret when the buffer is suspended
type: feature
pipeline: minimal
phase: done
created: 2026-09-30
updated: 2026-09-30
blocked_by: null
steps_done: 6
steps_total: 6
step_current: null
artifacts:
  spec: null
  plan: docs/plans/hotkey-word-before-caret-plan.md
  branch: null
  pr: null
---

## Context

_2-5 строк: что делаем и зачем. Задача этой секции — чтобы через N дней можно было восстановить контекст без чтения spec/plan._

## Progress

1. ✅ Извлечение слова (Core) + тесты
2. ✅ `unverifiedTail` в InputStateMachine + тесты
3. ✅ `requestCaretContext` (Utils)
4. ✅ InputEngine + AppDelegate
5. ✅ Тесты пайплайна
6. ✅ Сборка, тесты, ревью, проверка на Mac

## Log

- 2026-09-30: triage — pipeline `minimal`, reason: ручная проверка G: после Cmd+A→Backspace буфер выключен до пробела (invalidateUntilBoundary), хоткей без выделения ничего не делает
- 2026-09-30: brainstorm: пользователь выбрал «слово перед кареткой через AX»; 4+ файла (Utils/Core/App/тесты) → эскалация до no-spec
- 2026-09-30: artifacts.plan = docs/plans/hotkey-word-before-caret-plan.md
- 2026-09-30: plan drafted
- 2026-09-30: plan-review (Plan, opus): 2 blocker (обучение на AX-слове, отстающий AX) и should-fix учтены в плане: teaches:false, unverifiedTail, один запрос caretContext, проверка символа после каретки, BMP+маппинг, проверка длины AXStringForRange, лимит AXValue, allowCaretRead:false для отката
- 2026-09-30: шаг 1 ▶ Извлечение слова (Core) + тесты
- 2026-09-30: шаг 1 ✅ Извлечение слова (Core) + тесты — 944 passed
- 2026-09-30: шаг 2 ▶ `unverifiedTail` в InputStateMachine + тесты
- 2026-09-30: шаг 2 ✅ `unverifiedTail` в InputStateMachine + тесты
- 2026-09-30: шаг 3 ✅ `requestCaretContext` (Utils)
- 2026-09-30: шаг 4 ✅ InputEngine + AppDelegate
- 2026-09-30: шаг 5 ✅ Тесты пайплайна
- 2026-09-30: impl: CaretWordExtractor + WordBoundary (общие границы с KeyboardMonitor), InputStateMachine typedTail, AccessibilityFocusCoordinator.requestCaretContext (один запрос, проверка длины AXStringForRange, лимит AXValue 20k), InputEngine caretContextRequest (teaches:false для слова с экрана, suffix-проверка, откат без чтения экрана); 965 passed; мутации suffix/teaches → красные
- 2026-09-30: verify: `swift build -c release` → exit 0 ✅
- 2026-09-30: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-09-30: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-09-30: verify: `Проверка на Mac 2026-09-30 после ./install.sh: TextEdit, текст задан через AppleScript, одиночный Option — настоящий CGEvent flagsChanged` → exit 0 ✅
- 2026-09-30: verify: `Проверка на Mac после исправлений ревью (./install.sh < /dev/null), TextEdit, CGEvent-нажатия` → exit 0 ✅
- 2026-09-30: verify: `swift build -c release` → exit 0 ✅
- 2026-09-30: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-09-30: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-09-30: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36742447947` → exit 0 ✅
- 2026-09-30: шаг 6 ✅ Сборка, тесты, ревью, проверка на Mac — ревью кода: 4 should-fix + повторное ревью (click-путь) учтены; Mac: TextEdit Cmd+A→Backspace→набор→Option
- 2026-09-30: готово: хоткей конвертирует слово перед кареткой через AX при пустом буфере; проверено в TextEdit, CI зелёный; клик без набора — отдельный долг

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] Хоткей после клика/стрелки без набора не читает экран: фокус заменяет контекст, а Cmd+V/Cmd+X/Opt+Backspace/Opt-буквы/forward delete классифицируются как navigation — нужно разделить «каретка поставлена» и «невидимая правка» в KeyboardMonitor.classify, тогда разрешить пустой суффикс после клика/стрелок
- [ ] Автоматическая коррекция не сбрасывает ScreenSuffix (экран меняется вне потока событий): хоткей после неё просто не сработает (не портит текст) — ревью nit
- [ ] Chromium/Electron не проверены вживую (первый хоткей в Chrome может прийти до построения AX-дерева); install.sh ждёт ответ на read при открытом stdin — запускать с < /dev/null

## Verification

- 2026-09-30 · `swift build -c release` · exit 0 ✅

  ```
  Building for production...
  [Using on-disk description]
  [4 / 5] TestRunner-product
  [4 / 5] SwitchFixApp-product
  [5 / 5] SwitchFixApp-product
  [7 / 8] TestRunner-product
  Build complete! (1,18 с)
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
  Results: 527 passed, 0 failed
  ALL TESTS PASSED
  
  Building for production...
  [2 / 5] SwitchFix_LanguageModel
  Build complete! (0,28 с)
  ```

- 2026-09-30 · `swift run -c release InputPipelineTestRunner` · exit 0 ✅

  ```
  --- learning: manual entries are not overwritten by reverts ---
  --- learning: forced hotkey target follows the last Cyrillic layout ---
  --- key tables: hotkey converts a shifted digit-row symbol through the key ---
  --- key tables: .pc keeps today's result for the same input ---
  --- learning: the revert hotkey's fallback conversion does not teach ---
  --- learning: one- and two-key hotkey conversions are not learned ---
  --- learning: trailing punctuation is not part of the learned word ---
  --- learning: merged multi-word corrections are not learned ---
  
  Input pipeline: 965 passed, 0 failed
  
  Building for production...
  [1 / 6] Core
  Build complete! (0,28 с)
  ```

- 2026-09-30 · `Проверка на Mac 2026-09-30 после ./install.sh: TextEdit, текст задан через AppleScript, одиночный Option — настоящий CGEvent flagsChanged` · exit 0 ✅

  ```
  «старое ujnjdj», каретка в конце, буфер пуст → manual: selectionLen=-1 caretWordLen=6 → detect ujnjdj→готово → APPLIED deletes=6 → «старое готово». Каретка внутри слова (ujnj|dj) → caretWordLen=-1, текст не изменён. Chromium/Electron не проверены.
  ```

- 2026-09-30 · `Проверка на Mac после исправлений ревью (./install.sh < /dev/null), TextEdit, CGEvent-нажатия` · exit 0 ✅

  ```
  Cmd+A → пауза 0.4 с → Backspace → клавиши h e l l o в русской раскладке («руддщ») → одиночный Option: manual: bufferLen=0 → selectionLen=-1 caretWordLen=5 → detect руддщ→hello → APPLIED deletes=5 → в документе «hello». Без паузы Backspace приходит до разрешения фокуса и буфер не выключается (bufferLen=5) — путь буфера, тоже «hello».
  ```

- 2026-09-30 · `swift build -c release` · exit 0 ✅

  ```
  Building for production...
  Build complete! (0,21 с)
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
  Results: 527 passed, 0 failed
  ALL TESTS PASSED
  
  Building for production...
  Build complete! (0,18 с)
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
  
  Input pipeline: 979 passed, 0 failed
  
  Building for production...
  Build complete! (0,17 с)
  ```

- 2026-09-30 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36742447947` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

**Сгенерировано:** 2026-09-30 · `rtp handoff`

- **Задача:** `2026-09-30-hotkey-converts-the-word-before-the-caret-when-the-buffer-is` — Hotkey converts the word before the caret when the buffer is suspended
- **Фаза:** triage (pipeline `minimal`, type `feature`)
- **Worktree:** `/Users/andrejsokolov/Desktop/projects/SwitchFix`
- **Ветка:** `claude/epic-galileo-zq47ec` — своих коммитов 45, отставание от origin/master 0
- **Незакоммиченного:** 5 файл(ов)

**Файлы в работе**

- `gitignore`
- `docs/tasks/2026-09-29-ngram-only-learning-ui.md`
- `docs/tasks/index.md`
- `docs/testing/ngram-lexicon-manual-test.md`
- `docs/tasks/2026-09-30-hotkey-converts-the-word-before-the-caret-when-the-buffer-is.md`

**git diff HEAD --stat**

```
.gitignore                                      |  2 ++
 docs/tasks/2026-09-29-ngram-only-learning-ui.md | 12 ++++++--
 docs/tasks/index.md                             |  5 ++--
 docs/testing/ngram-lexicon-manual-test.md       | 40 ++++++++++++++++++++++---
 4 files changed, 51 insertions(+), 8 deletions(-)
```

**Последние коммиты**

- `b15ebf8 docs(tasks): Words tab findings from manual test E`
- `6e14366 docs(tasks): layout-switch Globe key bug`
- `edb677f docs(tasks): close key-tables task`

**Последние записи лога**

- 2026-09-30: triage — pipeline `minimal`, reason: ручная проверка G: после Cmd+A→Backspace буфер выключен до пробела (invalidateUntilBoundary), хоткей без выделения ничего не делает

**Следующее действие**

- реализовать → rtp phase 2026-09-30-hotkey-converts-the-word-before-the-caret-when-the-buffer-is --to impl

**Заметки агента** (не выводятся из кода — грабли, тупики, договорённости)

<!-- handoff-notes -->
- 2026-09-30: Лог 2026-09-30 17:56:53–55: Cmd+A (keyCode 0, navigation), Backspace (51) при пустом буфере → InputStateMachine .delete → invalidate(untilBoundary: true); набранные ujnjdj в буфер не попали (нет строк buffer '…'), ⌥ Option → manual: bufferLen=0 selectionLen=-1 → ничего. Идея: при пустом/выключенном буфере и отсутствии выделения читать через AX слово перед кареткой (AXValue + AXSelectedTextRange, как selectedText в AccessibilityFocusCoordinator) и конвертировать его, сохраняя staleness guards plan/003. Альтернатива дешевле: считать поле пустым, если AX говорит, что значение пустое после Backspace. Проверить Electron/Chrome (AXManualAccessibility).
<!-- /handoff-notes -->

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
