---
id: 2026-09-30-words-tab-live-match-counters-accessibility-labels-truncated
title: "Words tab: live match counters, accessibility labels, truncated headers"
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

- 2026-09-30: triage — pipeline `minimal`, reason: ручная проверка E 2026-09-30: счётчики не обновляются, у кнопок нет AX-подписей, заголовки обрезаны

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

- **Задача:** `2026-09-30-words-tab-live-match-counters-accessibility-labels-truncated` — Words tab: live match counters, accessibility labels, truncated headers
- **Фаза:** triage (pipeline `minimal`, type `bug`)
- **Worktree:** `/Users/andrejsokolov/Desktop/projects/SwitchFix`
- **Ветка:** `claude/epic-galileo-zq47ec` — своих коммитов 44, отставание от origin/master 0
- **Незакоммиченного:** 3 файл(ов)

**Файлы в работе**

- `gitignore`
- `docs/tasks/index.md`
- `docs/tasks/2026-09-30-words-tab-live-match-counters-accessibility-labels-truncated.md`

**git diff HEAD --stat**

```
.gitignore          | 2 ++
 docs/tasks/index.md | 3 ++-
 2 files changed, 4 insertions(+), 1 deletion(-)
```

**Последние коммиты**

- `6e14366 docs(tasks): layout-switch Globe key bug`
- `edb677f docs(tasks): close key-tables task`
- `83cc15c docs(tasks): key-tables plan, review evidence; signing task`

**Последние записи лога**

- 2026-09-30: triage — pipeline `minimal`, reason: ручная проверка E 2026-09-30: счётчики не обновляются, у кнопок нет AX-подписей, заголовки обрезаны

**Следующее действие**

- реализовать → rtp phase 2026-09-30-words-tab-live-match-counters-accessibility-labels-truncated --to impl

**Заметки агента** (не выводятся из кода — грабли, тупики, договорённости)

<!-- handoff-notes -->
- 2026-09-30: Найдено ручной проверкой E (2026-09-30, через System Events/AX). (1) Счётчик срабатываний: правило rehk.. сработало (лог 'lexicon: convert to russian'), PersonalLexicon.noteMatch увеличил matchCount в памяти (после quit в defaults matchCount=1), но вкладка «Слова» показывала 0 и после переключения вкладок и повторного открытия окна — LearnedWordsView модель перечитывает entries только по .personalLexiconDidChange, который постится при сохранении, а noteMatch сохранение не планирует. docs/testing/ngram-lexicon-manual-test.md §2 обещает актуальные значения из памяти. (2) Accessibility: кнопки +, −, «Изменить…» в AX — безымянные 'button', меню «…» — 'More' по-английски (VoiceOver). (3) Окно 520 pt: заголовки колонок обрезаны («Раскла…», «Сраб…»/«С…» при сортировке). Всё остальное в E работает: валидация (пусто, >64, чужие символы, дубликат), цели для кириллицы только EN, правка → «Вручную», подсказка «Последнее срабатывание», поиск/фильтры/сортировка, удаление −/⌫/контекстное меню/мультивыбор/скрытые поиском не удаляются, сброс выученных и удаление всех с подтверждением.
<!-- /handoff-notes -->

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
