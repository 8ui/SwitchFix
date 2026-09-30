---
id: 2026-09-30-check-upstream-develop-edge-cases-against-the-n-gram
title: Check upstream develop edge cases against the n-gram detector
type: bug
pipeline: no-spec
phase: done
created: 2026-09-30
updated: 2026-09-30
blocked_by: null
steps_done: 4
steps_total: 4
step_current: null
artifacts:
  spec: null
  plan: docs/plans/upstream-develop-edge-cases-plan.md
  branch: claude/upstream-develop-edge-cases
  pr: "https://github.com/8ui/SwitchFix/pull/5"
---

## Context

В `upstream/develop` (rundax, ветка устарела относительно форка: база 0df61fb, 2026-08-07) есть 8 коммитов, не перенесённых в master
(`origin/develop` удалена 2026-09-30, оригинал — `upstream/develop`). Вливать целиком нельзя: вернёт словарный движок и
конфликтует с переписанным пайплайном. Задача: воспроизвести их кейсы тестами на текущем n-gram детекторе / пайплайне
и портировать только то, что реально падает.

Кейсы по коммитам (`git show <sha>` в `upstream/develop`):
- `fb33eb9` — одиночные символы и флаги вида `-r` не конвертировать (LayoutDetector, TestRunner)
- `b1eb723` — не исправлять внутри слова (каретка посреди слова) и неоднозначные слова (InputStateMachine, LayoutDetector)
- `6224c8d` — не удалять текст при смешанном вводе en/ru в одном слове, синхронизация раскладки (InputEngine, TextCorrector)
- `bdee150` — deletion plans, boundary resets, выбор codesign identity (InputStateMachine, TextCorrector, build-app.sh, setup-codesign.sh)
- `6fa5577` — session tap + pacing для Chromium; вероятно, покрыто `AppPostMode`, проверить только отсутствие регрессии
- не применимо (словари удалены): `a90a53d`, словарная часть `119d6f1`; `5f0c10e` — сверить только скрипты

## Progress

1. ✅ A: флаги не исправляются автоматически
2. ✅ B: 3-буквенные в сильном контексте остаются
3. ✅ C: после стрелок нет автоисправления слова
4. ✅ Ревью

## Log

- 2026-09-30: triage — pipeline `no-spec`, reason: 8 коммитов upstream/develop не перенесены; проверить тестами -r/одиночные символы, исправление внутри слова, смешанный ввод; портировать только падающее
- 2026-09-30: brainstorm: spike одобрен — пробы 9 кейсов develop на текущем коде, затем bounded-фиксы
- 2026-09-30: spike (пробы откачены): БАГ ls/rm/cp/grep -r → -к и голое r → к (low-confidence short без switch заменяет текст; подавление только при ≥2 валидных словах контекста); БАГ еру → the даже в 'в нову еру' (len 3 > shortWordSuppressionLength 2); РИСК навигация стрелками посреди слова начинает новый буфер (фрагмент может исправиться); OK: keys/llm/llms/replaces/replaced, r dhfx → к врач, chars from -r, git log -r; консервативно by design: ⌫ на пустом буфере / через пробел → слово до границы не отслеживается (пропуск, не порча); N/A: identical text (нет ru↔uk), чанки Unicode (у нас пара событий на символ), session tap (AppPostMode), словарные коммиты
- 2026-09-30: artifacts.plan = docs/plans/upstream-develop-edge-cases-plan.md
- 2026-09-30: план: A латинские ≤2 всегда откладываются, B contextSuppressionLength 3, C skipsAutomaticFlushUntilBoundary (хоткей сохраняется); Cyrillic ше→it по 1ad2692 не трогаем
- 2026-09-30: verify: `baseline до правок: TestRunner 527/0, InputPipelineTestRunner 979/0; sentence eval: ru started on en 93.01% restored, uk 94.27%, en on ru 97.93%, en on uk 97.76%; FP ru 9, en 2; edge cases code/cli 35/36` → exit 0 ✅
- 2026-09-30: plan-review #1: 3 блокера (merge без проверки экрана при двойном пробеле/!/Cmd+Z/Enter; C сбрасывался резолвом фокуса; подряд идущие флаги). План rev.2 с согласия пользователя: без deferral — A′ флаги stateless, B′ keep без merge, C′ флаг только до границы; merge-риск 2-буквенного пути → отдельный долг
- 2026-09-30: plan-review #2 (rev.2): блокеров нет; приняты: сброс switch-счётчика в keep, флаг нейтрален к контексту, стоп если 'в нову' слабый контекст
- 2026-09-30: шаг 1 ▶ A: флаги не исправляются автоматически
- 2026-09-30: verify: `Task 1 (A): TestRunner 536/0 (новый suite 'command-line flags stay' до фикса 6 FAIL), InputPipelineTestRunner 979/0, eval идентичен baseline` → exit 0 ✅
- 2026-09-30: шаг 1 ✅ A: флаги не исправляются автоматически — eval без изменений
- 2026-09-30: шаг 2 ▶ B: 3-буквенные в сильном контексте остаются
- 2026-09-30: verify: `Task 2 (B): TestRunner 541/0 (suite до фикса 2 FAIL), InputPipelineTestRunner 979/0; eval vs baseline: mixed ru messages -1 (у меня дфп в игре → lag больше не восстанавливается), ru typed correctly FP 9→8, ru started on en FP after switch 6→5, restored % без изменений` → exit 0 ✅
- 2026-09-30: шаг 2 ✅ B: 3-буквенные в сильном контексте остаются — eval: -1 mixed (дфп), FP -1, FP after switch -1
- 2026-09-30: шаг 3 ▶ C: после стрелок нет автоисправления слова
- 2026-09-30: verify: `Task 3 (C): InputPipelineTestRunner 986/0 (2 новых теста до фикса FAIL: state machine и engine с resolveFocus), TestRunner 541/0` → exit 0 ✅
- 2026-09-30: шаг 3 ✅ C: после стрелок нет автоисправления слова
- 2026-09-30: шаг 4 ▶ Ревью
- 2026-09-30: impl complete: A f669661, B 21b11b9, C (последний коммит)
- 2026-09-30: verify: `swift build -c release` → exit 0 ✅
- 2026-09-30: verify: `ревью кода: блокеров нет; should-fix (Option+Backspace/Cmd+V выключали исправление следующего слова) исправлен — флаг только для caret-клавиш, сброс при смене приложения, флаг раньше acronym-правила; новые проверки на старом коде FAIL 2, после — InputPipelineTestRunner 988/0, TestRunner 542/0, eval = после B` → exit 0 ✅
- 2026-09-30: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-09-30: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-09-30: artifacts.branch = claude/upstream-develop-edge-cases; artifacts.pr = https://github.com/8ui/SwitchFix/pull/5
- 2026-09-30: PR https://github.com/8ui/SwitchFix/pull/5 открыт, CI в процессе; done — после зелёного CI и merge
- 2026-09-30: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36752606163 (PR #5)` → exit 0 ✅
- 2026-09-30: шаг 4 ✅ Ревью
- 2026-09-30: PR https://github.com/8ui/SwitchFix/pull/5 влит (38b48fb), CI зелёный

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [x] 2-буквенный merge (pendingSuppressedShort) удаляет 'отложенное + bridge + текущее' без проверки экрана: двойной пробел, '!' перед пробелом, Cmd+Z (.undo не сбрасывает детектор), Enter как bridge (перенабор \n отправит сообщение/выполнит команду) — отдельная задача: adjacency-флаг от InputStateMachine + bridge только пробел — закрыто 2026-09-30: 2026-09-30-merged-short-word-correction-deletes-text-without-checking
- [ ] C не покрывает клик мышью посреди слова (focusMayChange) — отключать исправление первого слова после клика слишком дорого
- [x] .navigation включает Cmd/Ctrl/Option-сочетания (Cmd+V, Option-символы, Ctrl+C): слово сразу после них без пробела не исправляется автоматически — осознанная цена C — закрыто 2026-09-30: сужено до caret-клавиш по ревью
- [ ] B теряет 3-буквенные английские слова внутри русской/украинской фразы (eval: 'у меня дфп в игре' → lag больше не восстанавливается)
- [ ] многобуквенные флаги (-rf, -la, -xzf) идут через модель; проверить eval-ом, не станет ли 'rm -rf' → 'rm -ка'
- [ ] B считает word.count с пунктуацией: 3-буквенное слово в кавычке/скобке (4 символа) не удерживается — редкий край

## Verification

- 2026-09-30 · `baseline до правок: TestRunner 527/0, InputPipelineTestRunner 979/0; sentence eval: ru started on en 93.01% restored, uk 94.27%, en on ru 97.93%, en on uk 97.76%; FP ru 9, en 2; edge cases code/cli 35/36` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-09-30 · `Task 1 (A): TestRunner 536/0 (новый suite 'command-line flags stay' до фикса 6 FAIL), InputPipelineTestRunner 979/0, eval идентичен baseline` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-09-30 · `Task 2 (B): TestRunner 541/0 (suite до фикса 2 FAIL), InputPipelineTestRunner 979/0; eval vs baseline: mixed ru messages -1 (у меня дфп в игре → lag больше не восстанавливается), ru typed correctly FP 9→8, ru started on en FP after switch 6→5, restored % без изменений` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-09-30 · `Task 3 (C): InputPipelineTestRunner 986/0 (2 новых теста до фикса FAIL: state machine и engine с resolveFocus), TestRunner 541/0` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-09-30 · `swift build -c release` · exit 0 ✅

  ```
  Building for production...
  [Pre-planning 1 / 269]
  [Planning deferred tasks]
  [2 / 13]
  [3 / 7] UI
  [5 / 9] UI
  [8 / 11] SwitchFixApp-product
  [9 / 12] SwitchFixApp-product
  [11 / 12] SwitchFixApp-product
  [12 / 12] SwitchFixApp-product
  Build complete! (4,57 с)
  ```

- 2026-09-30 · `ревью кода: блокеров нет; should-fix (Option+Backspace/Cmd+V выключали исправление следующего слова) исправлен — флаг только для caret-клавиш, сброс при смене приложения, флаг раньше acronym-правила; новые проверки на старом коде FAIL 2, после — InputPipelineTestRunner 988/0, TestRunner 542/0, eval = после B` · exit 0 ✅

  ```
  (без вывода)
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
  Results: 542 passed, 0 failed
  ALL TESTS PASSED
  
  Building for production...
  Build complete! (0,17 с)
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
  
  Input pipeline: 988 passed, 0 failed
  
  Building for production...
  Build complete! (0,18 с)
  ```

- 2026-09-30 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36752606163 (PR #5)` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

**Сгенерировано:** 2026-09-30 · `rtp handoff`

- **Задача:** `2026-09-30-check-upstream-develop-edge-cases-against-the-n-gram` — Check upstream develop edge cases against the n-gram detector
- **Фаза:** review (pipeline `no-spec`, type `bug`)
- **Прогресс:** 3/4 ▰▰▰▱
- **Worktree:** `/Users/andrejsokolov/Desktop/projects/SwitchFix`
- **Ветка:** `claude/upstream-develop-edge-cases` — своих коммитов 5, отставание от origin/master 0
- **Незакоммиченного:** 2 файл(ов)

**Шаги плана**

1. ✅ A: флаги не исправляются автоматически
2. ✅ B: 3-буквенные в сильном контексте остаются
3. ✅ C: после стрелок нет автоисправления слова
4. ▶ Ревью

**Файлы в работе**

- `ocs/tasks/2026-09-30-check-upstream-develop-edge-cases-against-the-n-gram.md`
- `docs/tasks/index.md`

**git diff HEAD --stat**

```
...stream-develop-edge-cases-against-the-n-gram.md | 40 ++++++++++++++++++++++
 docs/tasks/index.md                                |  2 +-
 2 files changed, 41 insertions(+), 1 deletion(-)
```

**Последние коммиты**

- `d5b8ba5 docs(tasks): edge-case task review notes`
- `b4caf8f fix(input): skip the automatic flush only after caret keys`
- `0c0d7a1 fix(input): no automatic correction for a word entered by arrow keys`

**Последние записи лога**

- 2026-09-30: impl complete: A f669661, B 21b11b9, C (последний коммит)
- 2026-09-30: verify: `swift build -c release` → exit 0 ✅
- 2026-09-30: verify: `ревью кода: блокеров нет; should-fix (Option+Backspace/Cmd+V выключали исправление следующего слова) исправлен — флаг только для caret-клавиш, сброс при смене приложения, флаг раньше acronym-правила; новые проверки на старом коде FAIL 2, после — InputPipelineTestRunner 988/0, TestRunner 542/0, eval = после B` → exit 0 ✅
- 2026-09-30: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-09-30: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅

**Открытые долги (5)**

- 2-буквенный merge (pendingSuppressedShort) удаляет 'отложенное + bridge + текущее' без проверки экрана: двойной пробел, '!' перед пробелом, Cmd+Z (.undo не сбрасывает детектор), Enter как bridge (перенабор \n отправит сообщение/выполнит команду) — отдельная задача: adjacency-флаг от InputStateMachine + bridge только пробел
- C не покрывает клик мышью посреди слова (focusMayChange) — отключать исправление первого слова после клика слишком дорого
- B теряет 3-буквенные английские слова внутри русской/украинской фразы (eval: 'у меня дфп в игре' → lag больше не восстанавливается)
- многобуквенные флаги (-rf, -la, -xzf) идут через модель; проверить eval-ом, не станет ли 'rm -rf' → 'rm -ка'
- B считает word.count с пунктуацией: 3-буквенное слово в кавычке/скобке (4 символа) не удерживается — редкий край

**Следующее действие**

- rtp verify по командам проекта (rtp next 2026-09-30-check-upstream-develop-edge-cases-against-the-n-gram), затем ревью субагентом → rtp phase 2026-09-30-check-upstream-develop-edge-cases-against-the-n-gram --to done

**Заметки агента** (не выводятся из кода — грабли, тупики, договорённости)

<!-- handoff-notes -->
- 2026-09-30: Не начата: только заведена по итогам разбора develop. Начать с brainstorming + плана; тесты — в TestRunner (детектор) и InputPipelineTestRunner (пайплайн).
- 2026-09-30: Работа в ветке claude/upstream-develop-edge-cases (запушена), master = origin/master. CI на ветку не стартовал: tip-коммит только docs/tasks (paths-ignore). Ждём решения пользователя: PR или прямой merge в master; CI запустится на PR/master.
<!-- /handoff-notes -->

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
