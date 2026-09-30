---
id: 2026-09-30-words-tab-live-match-counters-accessibility-labels-truncated
title: "Words tab: live match counters, accessibility labels, truncated headers"
type: bug
pipeline: minimal
phase: done
created: 2026-09-30
updated: 2026-09-30
blocked_by: null
steps_done: 5
steps_total: 5
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

1. ✅ Живые счётчики: noteMatch уведомляет вкладку без сохранения
2. ✅ AX-подписи кнопок +/−/Изменить/…
3. ✅ Вкладка «Слова» шире (~640 pt), ширины колонок по замерам
4. ✅ Сборка, тесты, ревью
5. ✅ Проверка на Mac через AX

## Log

- 2026-09-30: triage — pipeline `minimal`, reason: ручная проверка E 2026-09-30: счётчики не обновляются, у кнопок нет AX-подписей, заголовки обрезаны
- 2026-09-30: причины: (1) noteMatch меняет счётчики только в памяти и не постит personalLexiconDidChange; (2) у кнопок-иконок и Menu нет accessibilityLabel; (3) заголовки RU шире колонок (Раскладка 57+22 pt при 55, Срабатываний 80+22 при 45). Решение пользователя: вкладка «Слова» шире (~640 pt), остальные 520
- 2026-09-30: шаг 1 ✅ Живые счётчики: noteMatch уведомляет вкладку без сохранения — TestRunner: red → 526 passed
- 2026-09-30: шаг 2 ✅ AX-подписи кнопок +/−/Изменить/…
- 2026-09-30: шаг 3 ✅ Вкладка «Слова» шире (~640 pt), ширины колонок по замерам — Word ~170 pt, колонки 80/125/80/105
- 2026-09-30: verify: `swift build -c release` → exit 0 ✅
- 2026-09-30: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-09-30: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-09-30: verify: `AX-проверка на Mac после ./install.sh (AXUIElement)` → exit 0 ✅
- 2026-09-30: шаг 4 ✅ Сборка, тесты, ревью — ревью: 0 blocker; учтены тест повторного уведомления, Раскладка 88 pt, центрирование окна; меню — подпись на Image
- 2026-09-30: шаг 5 ✅ Проверка на Mac через AX
- 2026-09-30: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36737689687` → exit 0 ✅
- 2026-09-30: исправлено: живые счётчики, AX-подписи, вкладка 640 pt; AX и скриншот на Mac, CI зелёный; живой счётчик вживую не проверен (debt)

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] Живой счётчик «Срабатываний» не проверен вживую на Mac (лексикон пуст; нужен набор с клавиатуры) — покрыт тестом PersonalLexicon: a counter update notifies observers
- [ ] Форма «Изменить» показывает снимок matchCount; сохранение формы может перезаписать срабатывание, пришедшее между reload и Save (гонка существовала и раньше; замечание ревью)

## Verification

- 2026-09-30 · `swift build -c release` · exit 0 ✅

  ```
  Building for production...
  [Using on-disk description]
  Build complete! (0,36 с)
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
  [1 / 6] Utils
  Build complete! (0,27 с)
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
  
  Input pipeline: 927 passed, 0 failed
  
  Building for production...
  [1 / 6] LanguageModel
  Build complete! (0,27 с)
  ```

- 2026-09-30 · `AX-проверка на Mac после ./install.sh (AXUIElement)` · exit 0 ✅

  ```
  Окно «Слова» 640×497. + desc=Новое слово, − desc=Удалить, Изменить… desc=Изменить…, меню title=Другие действия (было More). Скриншот: заголовки Слово/Раскладка/Правило/Источник/Срабатываний полностью, ~19 pt запаса у Раскладка и Срабатываний. Живой счётчик на Mac не проверен: лексикон пуст, набор через System Events ненадёжен — покрыт TestRunner.
  ```

- 2026-09-30 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36737689687` · exit 0 ✅

  ```
  (без вывода)
  ```

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
