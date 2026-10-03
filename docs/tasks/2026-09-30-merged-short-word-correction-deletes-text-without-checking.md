---
id: 2026-09-30-merged-short-word-correction-deletes-text-without-checking
title: Merged short-word correction deletes text without checking the screen
type: bug
pipeline: no-spec
phase: done
created: 2026-09-30
updated: 2026-10-03
blocked_by: null
steps_done: 4
steps_total: 4
step_current: null
artifacts:
  spec: null
  plan: null
  branch: null
  pr: "https://github.com/8ui/SwitchFix/pull/6"
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
4. ✅ Ревью

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
- 2026-09-30: artifacts.pr = https://github.com/8ui/SwitchFix/pull/6
- 2026-09-30: verify: `/code-review PR #6: 5 ревьюеров, 4 кандидата, оценки 75/0/0 (<80) → комментарий в PR не публикуется; 75 (незахваченная вставка текста) — остаточный риск, в долг; doc-комментарий flushBuffer уточнён` → exit 0 ✅
- 2026-09-30: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36755218914 (231b373)` → exit 0 ✅
- 2026-09-30: шаг 4 ✅ Ревью
- 2026-09-30: PR https://github.com/8ui/SwitchFix/pull/6 влит (a72bd84), CI зелёный

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [x] unit-тест смежности в InputStateMachine не покрывает punctuation boundary, focusMayChange, revertHotkey, inputSourceKey, tapReset, queueOverflow, stale context, updateContext, delete на пустом буфере — сейчас корректно за счёт общего сброса, но не зафиксировано — закрыто 2026-10-02: 2026-10-02-debt-batch-rtp-l10n-terminals-tests
- [x] updatePreferences сбрасывает смежность только при выключении SwitchFix, не при смене режима — на практике недостижимо (смена настроек требует клика) — закрыто 2026-10-03: 2026-10-03-debt-batch-flags-counters-adjacency
- [ ] смежность видит только захваченные события: вставка без key event между словами не снимает признак; частично закрыто сверкой текста поля (2026-09-30-correction-verifies-field-text-before-deleting) — но только в режиме enforce и где AX читается (иначе fail-open) — переформулировано 2026-09-30

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

- 2026-09-30 · `/code-review PR #6: 5 ревьюеров, 4 кандидата, оценки 75/0/0 (<80) → комментарий в PR не публикуется; 75 (незахваченная вставка текста) — остаточный риск, в долг; doc-комментарий flushBuffer уточнён` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-09-30 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36755218914 (231b373)` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

**Сгенерировано:** 2026-09-30 · `rtp handoff`

- **Задача:** `2026-09-30-merged-short-word-correction-deletes-text-without-checking` — Merged short-word correction deletes text without checking the screen
- **Фаза:** review (pipeline `no-spec`, type `bug`)
- **Прогресс:** 3/4 ▰▰▰▱
- **Worktree:** `/Users/andrejsokolov/Desktop/projects/SwitchFix`
- **Ветка:** `claude/merged-short-word-safety` — своих коммитов 4, отставание от origin/master 0
- **Незакоммиченного:** 0 файл(ов)

**Шаги плана**

1. ✅ Детектор: continuesPreviousWord + bridge только пробел
2. ✅ Автомат и движок: признак смежности
3. ✅ Тесты сценариев на уровне движка
4. ▶ Ревью

**Последние коммиты**

- `231b373 docs(detector): precise continuesPreviousWord contract`
- `20de4f3 docs(tasks): merge-safety review notes, Enter retype task`
- `7b1cde7 fix(detector): every flush consumes the deferred short word`

**Последние записи лога**

- 2026-09-30: impl complete (ветка claude/merged-short-word-safety)
- 2026-09-30: verify: `swift build -c release` → exit 0 ✅
- 2026-09-30: verify: `ревью: блокеров нет; should-fix (отложенное слово переживало сброс из одних символов '^!') исправлен — забирается в начале каждого flushBuffer; тест до фикса FAIL; arrow-кейс заменён на hotkey; TestRunner 546/0, InputPipelineTestRunner 1002/0, eval идентичен` → exit 0 ✅
- 2026-09-30: artifacts.pr = https://github.com/8ui/SwitchFix/pull/6
- 2026-09-30: verify: `/code-review PR #6: 5 ревьюеров, 4 кандидата, оценки 75/0/0 (<80) → комментарий в PR не публикуется; 75 (незахваченная вставка текста) — остаточный риск, в долг; doc-комментарий flushBuffer уточнён` → exit 0 ✅

**Открытые долги (3)**

- unit-тест смежности в InputStateMachine не покрывает punctuation boundary, focusMayChange, revertHotkey, inputSourceKey, tapReset, queueOverflow, stale context, updateContext, delete на пустом буфере — сейчас корректно за счёт общего сброса, но не зафиксировано
- updatePreferences сбрасывает смежность только при выключении SwitchFix, не при смене режима — на практике недостижимо (смена настроек требует клика)
- смежность видит только захваченные события: текст, вставленный без key event (диктовка, emoji-панель, Edit > Paste мышью, drag-and-drop, text expander) между отложенным и текущим словом, не снимает признак → склейка может стереть вставленное. До PR было хуже (без проверки вообще). Ограничение по времени не подходит (ломает склейку при паузе); вариант — сверка с AX-текстом у каретки перед склеенной коррекцией

**Следующее действие**

- rtp verify по командам проекта (rtp next 2026-09-30-merged-short-word-correction-deletes-text-without-checking), затем ревью субагентом → rtp phase 2026-09-30-merged-short-word-correction-deletes-text-without-checking --to done

**Заметки агента** (не выводятся из кода — грабли, тупики, договорённости)

<!-- handoff-notes -->
- 2026-09-30: Не начата. Начать с brainstorming; сначала падающие тесты на 4 сценария из Context.
- 2026-09-30: PR #6 готов к merge (merge-коммитом, --delete-branch) после зелёного CI на 231b373; auto-merge в репо запрещён. После merge: git switch master, pull, rtp phase done. Следующая задача — 2026-09-30-automatic-correction-retypes-the-enter-that-ended-the-word.
<!-- /handoff-notes -->

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
