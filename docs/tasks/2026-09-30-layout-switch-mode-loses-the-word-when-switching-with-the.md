---
id: 2026-09-30-layout-switch-mode-loses-the-word-when-switching-with-the
title: Layout-switch mode loses the word when switching with the Globe key
type: bug
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

- 2026-09-30: triage — pipeline `minimal`, reason: ручная проверка D2: keyCode 179 (🌐) приходит как ввод и инвалидирует буфер до kTISNotifySelectedKeyboardInputSourceChanged; handleLayoutChange видит пустой буфер

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

- **Задача:** `2026-09-30-layout-switch-mode-loses-the-word-when-switching-with-the` — Layout-switch mode loses the word when switching with the Globe key
- **Фаза:** triage (pipeline `minimal`, type `bug`)
- **Worktree:** `/Users/andrejsokolov/Desktop/projects/SwitchFix`
- **Ветка:** `claude/epic-galileo-zq47ec` — своих коммитов 43, отставание от origin/master 0
- **Незакоммиченного:** 3 файл(ов)

**Файлы в работе**

- `gitignore`
- `docs/tasks/index.md`
- `docs/tasks/2026-09-30-layout-switch-mode-loses-the-word-when-switching-with-the.md`

**git diff HEAD --stat**

```
.gitignore          | 2 ++
 docs/tasks/index.md | 3 ++-
 2 files changed, 4 insertions(+), 1 deletion(-)
```

**Последние коммиты**

- `edb677f docs(tasks): close key-tables task`
- `83cc15c docs(tasks): key-tables plan, review evidence; signing task`
- `b5890f6 fix(layout): address key-table review`

**Последние записи лога**

- 2026-09-30: triage — pipeline `minimal`, reason: ручная проверка D2: keyCode 179 (🌐) приходит как ввод и инвалидирует буфер до kTISNotifySelectedKeyboardInputSourceChanged; handleLayoutChange видит пустой буфер

**Следующее действие**

- реализовать → rtp phase 2026-09-30-layout-switch-mode-loses-the-word-when-switching-with-the --to impl

**Заметки агента** (не выводятся из кода — грабли, тупики, договорённости)

<!-- handoff-notes -->
- 2026-09-30: Лог 2026-09-30 16:36: набрано ghbdtn (seq 468-473, буфер наполнялся), затем input seq=474 keyCode=179 → 'buffer invalidated', через 20 мс 'layout changed old=english new=russian generated=false'; конверсии нет, логов handleLayoutChange нет. InputEngine.handleLayoutChange читает stateMachine.currentBuffer после инвалидации. Вероятно, до key-tables так же (путь не менялся). Отдельно: инструкция docs/testing/ngram-lexicon-manual-test.md §D.5 — пример 'ше цщкли' не склеивается ('ше' в ShortWordTable → 'it' сразу); нужен пример отложенного короткого слова.
<!-- /handoff-notes -->

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
