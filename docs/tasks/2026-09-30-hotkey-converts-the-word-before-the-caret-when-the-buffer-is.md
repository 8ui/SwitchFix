---
id: 2026-09-30-hotkey-converts-the-word-before-the-caret-when-the-buffer-is
title: Hotkey converts the word before the caret when the buffer is suspended
type: feature
pipeline: minimal
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

_2-5 строк: что делаем и зачем. Задача этой секции — чтобы через N дней можно было восстановить контекст без чтения spec/plan._

## Progress

_Шаги не заданы. `rtp steps <id> --set "…"` или `--from-plan <файл>`._

## Log

- 2026-09-30: triage — pipeline `minimal`, reason: ручная проверка G: после Cmd+A→Backspace буфер выключен до пробела (invalidateUntilBoundary), хоткей без выделения ничего не делает

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
