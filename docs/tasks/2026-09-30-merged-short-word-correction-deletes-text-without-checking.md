---
id: 2026-09-30-merged-short-word-correction-deletes-text-without-checking
title: Merged short-word correction deletes text without checking the screen
type: bug
pipeline: no-spec
phase: triage
created: 2026-09-30
updated: 2026-09-30
blocked_by: null
steps_done: 0
steps_total: 0
step_current: null
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

_Шаги не заданы. `rtp steps <id> --set "…"` или `--from-plan <файл>`._

## Log

- 2026-09-30: triage — pipeline `no-spec`, reason: pendingSuppressedShort merge удаляет 'отложенное + bridge + текущее' без проверки, что экран не менялся; Enter-bridge может отправить сообщение/выполнить команду; затрагивает LayoutDetector + InputStateMachine/InputEngine

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

_Отложенное, упрощения, известные пробелы. Формат — чекбоксы (их считают индекс и отчёты по долгам):_
_- `- [ ] <что отложено> — <почему/контекст>` — открытый долг_
_- `- [x] <что было> — закрыто YYYY-MM-DD: <причина/ссылка на task>` — закрытый_
_Без `[ ]`/`[x]` пункт невидим для агрегатора и теряется через 2 недели._

## Verification

_Доказательства, а не утверждения. Заполняется `rtp verify <id> --run "<команда>"`: команда, exit code, хвост вывода._

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
