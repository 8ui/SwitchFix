---
id: 2026-09-30-merged-short-word-correction-deletes-text-without-checking
title: Merged short-word correction deletes text without checking the screen
type: bug
pipeline: no-spec
phase: review
created: 2026-09-30
updated: 2026-09-30
blocked_by: null
steps_done: 3
steps_total: 4
step_current: 4
artifacts:
  spec: null
  plan: null
  branch: null
  pr: null
---

## Context

`LayoutDetector` откладывает короткое неуверенное слово (≤2 символа) в сильном контексте текущего языка
(`pendingSuppressedShort`) и, если следующее слово подтверждает ту же раскладку, выдаёт одну коррекцию
`originalWord = отложенное + bridge + текущее`. `InputEngine.prepareCorrection` удаляет
`originalWord.count + boundary.count` символов, не проверяя, что экран между словами не менялся.
Найдено ревью плана в задаче `2026-09-30-check-upstream-develop-edge-cases-against-the-n-gram` (PR 8ui/SwitchFix#5).

Сценарии порчи (воспроизвести тестами до фикса):
- двойной пробел `ше␠␠цщкли␠`: второй пробел при пустом буфере даёт `[]` (`InputStateMachine` `.boundary`),
  bridge остаётся `" "` → удаляется на символ меньше, остаётся мусор;
- пунктуация `ше!␠цщкли␠` — то же;
- Cmd+Z между словами: `.undo` даёт только `.nativeUndo`, детектор не сбрасывается → склейка с чужим текстом;
- Enter как bridge (`boundaryAfterWord = "\n"`): перенабор `\n` отправляет сообщение / выполняет команду в терминале.

Идея фикса (из ревью): (a) хранить отложенное слово только при bridge ровно `" "`; (b) флаг смежности —
`InputStateMachine` ставит его при `.flush` и снимает на любом событии, кроме `.character` и `.delete`
внутри буфера; передавать в детектор (`flushBuffer(..., continuesPrevious:)`), склеивать только при true,
иначе сбрасывать отложенное. Проще: `.invalidate` на `.undo` и на границе при пустом буфере.
Тесты — на уровне детектора и пайплайна (`LearningHarness`).

## Progress

1. ✅ Детектор: continuesPreviousWord + bridge только пробел
2. ✅ Автомат и движок: признак смежности
3. ✅ Тесты сценариев на уровне движка
4. ▶ Ревью

## Log

- 2026-09-30: triage — pipeline `no-spec`, reason: pendingSuppressedShort merge удаляет 'отложенное + bridge + текущее' без проверки, что экран не менялся; Enter-bridge может отправить сообщение/выполнить команду; затрагивает LayoutDetector + InputStateMachine/InputEngine
- 2026-09-30: brainstorm (bounded): дизайн одобрен в чате — признак смежности в .flush/DetectionRequest/flushBuffer(continuesPreviousWord:), откладывание только при bridge ' '; план-документ не пишется (bounded)
- 2026-09-30: шаг 1 ▶ Детектор: continuesPreviousWord + bridge только пробел
- 2026-09-30: verify: `4 сценария (двойной пробел, '!'+пробел, Cmd+Z, Enter) на старом Core: 4 FAIL; после фикса InputPipelineTestRunner 1002/0, TestRunner 545/0, eval идентичен` → exit 0 ✅
- 2026-09-30: шаг 1 ✅ Детектор: continuesPreviousWord + bridge только пробел
- 2026-09-30: шаг 2 ✅ Автомат и движок: признак смежности
- 2026-09-30: шаг 3 ✅ Тесты сценариев на уровне движка
- 2026-09-30: шаг 4 ▶ Ревью
- 2026-09-30: impl complete (ветка claude/merged-short-word-safety)
- 2026-09-30: verify: `swift build -c release` → exit 0 ✅
- 2026-09-30: verify: `ревью: блокеров нет; should-fix (отложенное слово переживало сброс из одних символов '^!') исправлен — забирается в начале каждого flushBuffer; тест до фикса FAIL; arrow-кейс заменён на hotkey; TestRunner 546/0, InputPipelineTestRunner 1002/0, eval идентичен` → exit 0 ✅

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] unit-тест смежности в InputStateMachine не покрывает punctuation boundary, focusMayChange, revertHotkey, inputSourceKey, tapReset, queueOverflow, stale context, updateContext, delete на пустом буфере — сейчас корректно за счёт общего сброса, но не зафиксировано
- [ ] updatePreferences сбрасывает смежность только при выключении SwitchFix, не при смене режима — на практике недостижимо (смена настроек требует клика)

## Verification

- 2026-09-30 · `4 сценария (двойной пробел, '!'+пробел, Cmd+Z, Enter) на старом Core: 4 FAIL; после фикса InputPipelineTestRunner 1002/0, TestRunner 545/0, eval идентичен` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-09-30 · `swift build -c release` · exit 0 ✅

  ```
  Building for production...
  [Using on-disk description]
  [2 / 13]
  [3 / 7] UI
  [5 / 9] UI
  [8 / 11] SwitchFixApp-product
  [9 / 12] SwitchFixApp-product
  [11 / 12] SwitchFixApp-product
  [12 / 12] SwitchFixApp-product
  Build complete! (8,36 с)
  ```

- 2026-09-30 · `ревью: блокеров нет; should-fix (отложенное слово переживало сброс из одних символов '^!') исправлен — забирается в начале каждого flushBuffer; тест до фикса FAIL; arrow-кейс заменён на hotkey; TestRunner 546/0, InputPipelineTestRunner 1002/0, eval идентичен` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

**Сгенерировано:** 2026-09-30 · `rtp handoff`

- **Задача:** `2026-09-30-merged-short-word-correction-deletes-text-without-checking` — Merged short-word correction deletes text without checking the screen
- **Фаза:** triage (pipeline `no-spec`, type `bug`)
- **Worktree:** `/Users/andrejsokolov/Desktop/projects/SwitchFix`
- **Ветка:** `master` — своих коммитов 0, отставание от origin/master 0
- **Незакоммиченного:** 3 файл(ов)

**Файлы в работе**

- `ocs/tasks/2026-09-30-check-upstream-develop-edge-cases-against-the-n-gram.md`
- `docs/tasks/index.md`
- `docs/tasks/2026-09-30-merged-short-word-correction-deletes-text-without-checking.md`

**git diff HEAD --stat**

```
...stream-develop-edge-cases-against-the-n-gram.md | 25 ++++++++++++++++------
 docs/tasks/index.md                                |  6 +++---
 2 files changed, 21 insertions(+), 10 deletions(-)
```

**Последние коммиты**

- `38b48fb Merge pull request #5 from 8ui/claude/upstream-develop-edge-cases`
- `ee1527d docs(tasks): edge-case task verification`
- `d5b8ba5 docs(tasks): edge-case task review notes`

**Последние записи лога**

- 2026-09-30: triage — pipeline `no-spec`, reason: pendingSuppressedShort merge удаляет 'отложенное + bridge + текущее' без проверки, что экран не менялся; Enter-bridge может отправить сообщение/выполнить команду; затрагивает LayoutDetector + InputStateMachine/InputEngine

**Следующее действие**

- написать план → rtp phase 2026-09-30-merged-short-word-correction-deletes-text-without-checking --to plan-review

**Заметки агента** (не выводятся из кода — грабли, тупики, договорённости)

<!-- handoff-notes -->
- 2026-09-30: Не начата. Начать с brainstorming; сначала падающие тесты на 4 сценария из Context.
<!-- /handoff-notes -->

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
