---
id: 2026-09-30-layout-switch-mode-loses-the-word-when-switching-with-the
title: Layout-switch mode loses the word when switching with the Globe key
type: bug
pipeline: minimal
phase: done
created: 2026-09-30
updated: 2026-10-02
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

_2-5 строк: что делаем и зачем. Задача этой секции — чтобы через N дней можно было восстановить контекст без чтения spec/plan._

## Progress

1. ✅ Падающий тест в InputPipelineTestRunner
2. ✅ Вид ввода inputSourceKey для keyCode 179, слово откладывается для handleLayoutChange
3. ✅ Сборка, тесты, ревью
4. ✅ Проверка на Mac (./install.sh, 🌐 в режиме переключения)

## Log

- 2026-09-30: triage — pipeline `minimal`, reason: ручная проверка D2: keyCode 179 (🌐) приходит как ввод и инвалидирует буфер до kTISNotifySelectedKeyboardInputSourceChanged; handleLayoutChange видит пустой буфер
- 2026-09-30: root cause: keyCode 179 → .navigation (нет в таблице перевода) → буфер очищен И фокус инвалидирован (secureFocus unknown) → handleLayoutChange видит пустой буфер и не проходит guard secureFocus; фикс: отдельный kind, не трогающий фокус, слово откладывается до следующего ввода
- 2026-09-30: шаг 1 ▶ Падающий тест в InputPipelineTestRunner
- 2026-09-30: шаг 1 ✅ Падающий тест в InputPipelineTestRunner — red без фикса: 3 FAIL (0 plans)
- 2026-09-30: шаг 2 ✅ Вид ввода inputSourceKey для keyCode 179, слово откладывается для handleLayoutChange — InputPipelineTestRunner 896 passed
- 2026-09-30: impl: CapturedInput.Kind.inputSourceKey для keyCode 179 (не сбрасывает фокус, слово откладывается в InputStateMachine.layoutSwitchWord до следующего ввода), handleLayoutChange берёт его
- 2026-09-30: verify: `swift build -c release` → exit 0 ✅
- 2026-09-30: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-09-30: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-09-30: verify: `swift build -c release` → exit 0 ✅
- 2026-09-30: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-09-30: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-09-30: шаг 3 ✅ Сборка, тесты, ревью — ревью: 0 blocker; учтены окно 500 мс, reason inputSourceKey, тесты без маскировки фокусом, доп. сценарии; 927 passed
- 2026-09-30: review-фиксы: окно 500 мс (диктовка по 🌐), InputInvalidationReason.inputSourceKey, тесты: notSecure-контекст, клик/стрелка/ввод/смена приложения/выключение/позднее уведомление, проверка wait; мутация окна → красный
- 2026-09-30: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36735042858` → exit 0 ✅
- 2026-09-30: verify: `Ручная проверка на Mac 2026-09-30 после ./install.sh, режим «При смене раскладки»` → exit 0 ✅
- 2026-09-30: шаг 4 ✅ Проверка на Mac (./install.sh, 🌐 в режиме переключения) — лог: коррекция при 🌐 применена; после стрелки — нет
- 2026-09-30: исправлено и проверено на Mac; CI зелёный; открытые debts: Control-Space, тест классификации keyCode 179

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [x] Control-Space и другие сочетания с модификатором для смены раскладки всё ещё классифицируются как navigation (буфер и фокус сбрасываются) — режим «по переключению» теряет слово; проверить на Mac, нужен ли тот же подход без сброса фокуса — закрыто 2026-10-02: 2026-10-02-layout-switch-shortcuts-not-navigation
- [x] KeyboardMonitor.classify приватный и не покрыт тестом: регресс классификации keyCode 179 → .inputSourceKey вернёт баг незаметно (замечание ревью) — закрыто 2026-10-02: 2026-10-02-layout-switch-shortcuts-not-navigation

## Verification

- 2026-09-30 · `swift build -c release` · exit 0 ✅

  ```
  Building for production...
  [2 / 9] UI
  [4 / 10] TestRunner-product
  [7 / 12] UI
  [10 / 15] SwitchFixApp-product
  [11 / 16] SwitchFixApp-product
  [13 / 16] SwitchFixApp-product
  [14 / 16] SwitchFixApp-product
  [17 / 19] TestRunner-product
  [19 / 19] TestRunner-product
  [20 / 21] TestRunner-product
  Build complete! (4,83 с)
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
  Results: 522 passed, 0 failed
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
  
  Input pipeline: 896 passed, 0 failed
  
  Building for production...
  Build complete! (0,19 с)
  ```

- 2026-09-30 · `swift build -c release` · exit 0 ✅

  ```
  /Users/andrejsokolov/Desktop/projects/SwitchFix/Sources/Core/InputEngine.swift:201:82: [1;33mwarning: [1;39m'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope[0;0m [#]8;;https://docs.swift.org/compiler/documentation/diagnostics/implicit-strong-cap… [обрезано 35 симв.]
  [0;36m198 |[0;0m                 return
  [0;36m199 |[0;0m             }
  [0;36m200 |[0;0m             self.selectionQueue.async {
      [0;36m|[0;0m                                       |- [1;39mnote: [1;39m'self' implicitly strongly captured here[0;0m
      [0;36m|[0;0m                                       `- [1;39mnote: [1;39madd 'self' as a capture list item to silence[0;0m
  [0;36m201 |[0;0m                 selectedTextRequest(context.frontmostPID, context.epoch) { [weak self] selectedText in
      [0;36m|[0;0m                                                                                  |- [1;33mwarning: [1;39m'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope[0;0m [#]8;;https://docs.swift.org/compiler/documentation/diagnostics/imp… [обрезано 51 симв.]
      [0;36m|[0;0m                                                                                  `- [1;39mnote: [1;39mexplicitly assign the capture list item to silence[0;0m
  [0;36m202 |[0;0m                     guard let self else { return }
  [0;36m203 |[0;0m                     self.inputQueue.async {
  
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
  Results: 522 passed, 0 failed
  ALL TESTS PASSED
  
  Building for production...
  [1 / 9]
  Build complete! (0,33 с)
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
  
  Input pipeline: 927 passed, 0 failed
  
  Building for production...
  Build complete! (0,19 с)
  ```

- 2026-09-30 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36735042858` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-09-30 · `Ручная проверка на Mac 2026-09-30 после ./install.sh, режим «При смене раскладки»` · exit 0 ✅

  ```
  ghbdtn (seq 34-39) → 🌐 keyCode=179 seq 40 → layout changed english→russian через 18 мс → correction planned deletes=6 → APPLIED. ghbdtn → ← (123) → 🌐: layout changed, коррекции нет (дважды, seq 46-54 и 63-70). Режим возвращён в automatic.
  ```

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
