---
id: 2026-10-06-keys-typed-between-the-last-staleness-check-and-the
title: "Keys typed between the last staleness check and the correction's deletes are deleted"
type: bug
pipeline: no-spec
phase: review
created: 2026-10-06
updated: 2026-10-06
blocked_by: null
steps_done: 5
steps_total: 5
step_current: null
artifacts:
  spec: null
  plan: docs/plans/keys-typed-between-check-and-deletes-plan.md
  branch: null
  pr: null
---

## Context

Живой тест 2026-10-06 (Telegram, post mode `session`, RussianWin): `руддщ`, пробел, через ~16 мс Shift+2 дважды → в поле `рhello "`: первая `"` дошла до Telegram раньше 6 Backspace и была удалена вместе с пробелом и `уддщ` (1 из 18 прогонов). Клавиша попала в очередь движка ~в момент post, после всех проверок устаревания. Нарушает правило plan/003 (текст не меняется по устаревшему контексту). Тот же класс, что долг «гонка сужена, не закрыта» в 2026-10-06-keys-typed-between-a-correction-and-its-layout-switch-end-up, но для самого удаления.

## Progress

1. ✅ Метрика задержки tap
2. ✅ Сужение: маршрут до проверки и модификатор как сигнал
3. ✅ Лог гонки
4. ✅ Тесты
5. ✅ Решение и долг

## Log

- 2026-10-06: triage — pipeline `no-spec`, reason: Correction pipeline logic in TextCorrector + InputEngine + pipeline test (3 code files), known architecture; the fix is a narrowing whose shape needs a short plan
- 2026-10-06: brainstorm: из запроса — что: сузить/закрыть окно между последней проверкой и удалением + тест; зачем: нарушение правила plan/003 (рuddщ→рhello "); готово: решение записано, тест в InputPipelineTestRunner, проверки зелёные
- 2026-10-06: artifacts.plan = docs/plans/keys-typed-between-check-and-deletes-plan.md
- 2026-10-06: plan drafted (окно = задержка listen-only tap ≈0,8 мс + резолв маршрута после проверки)
- 2026-10-06: plan-review (Plan, opus): окно до конца пачки, нет метрики L, модификатор как сигнал, инъекция резолвера, postUndo, путь выделения → долг; план исправлен
- 2026-10-06: шаг 1 ✅ Метрика задержки tap — tap latency notice > 5 ms
- 2026-10-06: шаг 2 ✅ Сужение: маршрут до проверки и модификатор как сигнал — маршрут до проверки (apply, postUndo); модификатор в isEligible
- 2026-10-06: шаг 3 ✅ Лог гонки — correction may have raced: before/during, route
- 2026-10-06: шаг 4 ✅ Тесты — 5 сьютов, 1508 passed; мутации (без модификатора, маршрут после проверки) → 5 FAIL
- 2026-10-06: шаг 5 ✅ Решение и долг — решение в Decisions, 4 долга
- 2026-10-06: impl complete
- 2026-10-06: verify: `swift build -c release` → exit 0 ✅
- 2026-10-06: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-10-06: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-10-06: verify: `swift build -c release` → exit 0 ✅
- 2026-10-06: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-10-06: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-10-06: code-review (general-purpose, opus): исправлено — модификатор, отпущенный без клавиши, снимает сигнал (Karabiner-переключатели); биты стороны вместо общей маски; переключение раскладки после post не считает модификатор; запись post до последней проверки; 'input' в логе. Тест 'клавиша между проверкой и эмиссией' — регрессионный страж (проходил и до фикса)

## Decisions

- Окно: `KeyboardMonitor` — listen-only tap на main run loop; WindowServer не ждёт его колбэк, событие идёт в приложение, а `latestPhysicalSequence` растёт с задержкой L. Замер 2026-10-06 (скрипт, listen-only session tap): L ≈ 0,8 мс у простаивающего процесса; `CGEvent.timestamp` — uptime в нс (как `DispatchTime`), у неотправленного события 0. Последняя проверка — `isEligible` в `TextCorrector.apply`; после неё ещё шёл резолв маршрута (`NSRunningApplication`, `AppPostMode.overrides`), и окно тянется до конца пачки событий.
- Закрыть окно с listen-only tap нельзя: клавиша, вошедшая в поток за L до первого Backspace, проверке не видна. Сужено: (1) резолв маршрута до последней проверки (apply и postUndo); (2) нажатие Shift/Control/Option/Command после границы (не Caps Lock, не Fn/Globe, не модификатор tap-хоткея) делает коррекцию устаревшей (`CaptureStateStore.noteModifierPress` → `isEligible`): для `"` и заглавных Shift идёт за единицы-десятки мс до символа, это окно шире L; `editGeneration`, sequence и state machine не трогает. Отпускание всех учитываемых модификаторов без клавиши между ними снимает сигнал (иначе модификатор-переключатель раскладки — Karabiner «Cmd отдельно» — всегда отменял бы коррекцию в режиме layout-switch); нажатие/отпускание считается по биту стороны (0x2/0x4 Shift и т. д.); проверка после post перед переключением раскладки модификатор не считает. Синтетический прогон пользователя мог слать Shift+2 без отдельного flagsChanged — там помогает только (1).
- Измерения: `tap latency ms=…` (notice, колбэк позже события на > 5 мс) и `correction may have raced: key seq=… made before|during the post …, route=…` — первая физическая клавиша после отправленной коррекции/отката, сделанная до конца пачки (в режиме pid возможны ложные: событие из WindowServer может прийти после наших).
- Отвергнуто: пауза после последней клавиши/перед post (сдвигает окно, ширина та же L); перепроверка между удалениями и набором (текст уже испорчен, обрыв хуже); перечитать поле после удалений (ещё AX-круг ~20 мс в Telegram, «починка» по догадке — новая мутация по устаревшему контексту); активный tap, придерживающий клавиши на время post (нарушает правило plan/003, колбэк на критическом пути каждой клавиши); AX-замена по диапазону (Qt/Telegram, лишний AX-круг).

## Debt

- [ ] tap на main run loop: задержка listen-only колбэка растёт под нагрузкой main (TIS-переключение, AX-колбэки, SwiftUI) — вынести tap на свой поток, если 'tap latency' в логах часто > 5 мс
- [ ] путь выделения (performSelectionCorrection): проверка → копия всех элементов буфера → Cmd+V; клавиша в этом окне (мс при большом буфере) заменит выделение — перепроверять прямо перед postPaste
- [ ] пачка событий коррекции (deletes×2 + replacement×2) — тоже окно: клавиша внутри неё ложится между удалениями и заменой; склейка замены в одно Unicode-событие (до 20 UTF-16) сократит пачку — проверить в Qt/Telegram
- [ ] гонка сужена, не закрыта: клавиша без нажатия модификатора, вошедшая в поток за ~1 мс (L) до первого Backspace, всё ещё удаляется — для listen-only tap неустранимо (см. Decisions)

## Verification

- 2026-10-06 · `swift build -c release` · exit 0 ✅

  ```
  /Users/andrejsokolov/Desktop/projects/SwitchFix/Sources/Core/InputEngine.swift:810:59: [1;33mwarning: [1;39m'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope[0;0m [#]8;;https://docs.swift.org/compiler/documentation/diagnostics/implicit-strong-cap… [обрезано 35 симв.]
   [0;36m807 |[0;0m         // suffix is compared, so a character cut at the window's start does not matter.
   [0;36m808 |[0;0m         let window = (check.word + check.boundary).utf16.count + 6
   [0;36m809 |[0;0m         selectionQueue.async {
       [0;36m|[0;0m                              |- [1;39mnote: [1;39m'self' implicitly strongly captured here[0;0m
       [0;36m|[0;0m                              `- [1;39mnote: [1;39madd 'self' as a capture list item to silence[0;0m
   [0;36m810 |[0;0m             query(check.pid, check.epoch, window) { [weak self] probe in
       [0;36m|[0;0m                                                           |- [1;33mwarning: [1;39m'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope[0;0m [#]8;;https://docs.swift.org/compiler/documentation/diagnostics/implicit-strong-capture\… [обрезано 29 симв.]
       [0;36m|[0;0m                                                           `- [1;39mnote: [1;39mexplicitly assign the capture list item to silence[0;0m
   [0;36m811 |[0;0m                 self?.inputQueue.async {
   [0;36m812 |[0;0m                     guard let self else { return }
  
  [#ImplicitStrongCapture]: <https://docs.swift.org/compiler/documentation/diagnostics/implicit-strong-capture>
  ```

- 2026-10-06 · `swift run -c release TestRunner` · exit 0 ✅

  ```
  | fix en←ru word-forms | 9/10 | pfdnhf→завтра (want завтра) |
  | fix en←ru slang-tech | 5/7 | ofc (want щас), rhby; (want кринж) |
  | fix en←uk word-forms | 6/6 |  |
  | fix en←uk slang-tech | 3/4 | yjhv→норм (want норм) |
  | keep en←en backslash | 6/6 |  |
  | fix en←uk apostrophe | 6/6 |  |
  | keep en←en index-no-digit | 13/13 |  |
  
  ========================================
  Results: 1214 passed, 0 failed
  ALL TESTS PASSED
  
  Building for production...
  Build complete! (0,22 с)
  ```

- 2026-10-06 · `swift run -c release InputPipelineTestRunner` · exit 0 ✅

  ```
  --- key-down classification: caret moves and unseen edits ---
  --- mouse-down classification ---
  --- input-source shortcuts from com.apple.symbolichotkeys ---
  --- input-source shortcuts: re-read at most once per interval unless forced ---
  --- correction race: a key between the screen check and the emission cancels it ---
  --- correction race: a modifier pressed while the field is read cancels it ---
  --- correction race: modifier presses that count ---
  --- correction race: the last check runs after the post route is resolved ---
  --- correction race: a key made before or during the post is reported once ---
  
  Input pipeline: 1508 passed, 0 failed
  
  Building for production...
  Build complete! (0,20 с)
  ```

- 2026-10-06 · `swift build -c release` · exit 0 ✅

  ```
  /Users/andrejsokolov/Desktop/projects/SwitchFix/Sources/Core/InputEngine.swift:810:59: [1;33mwarning: [1;39m'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope[0;0m [#]8;;https://docs.swift.org/compiler/documentation/diagnostics/implicit-strong-cap… [обрезано 35 симв.]
   [0;36m807 |[0;0m         // suffix is compared, so a character cut at the window's start does not matter.
   [0;36m808 |[0;0m         let window = (check.word + check.boundary).utf16.count + 6
   [0;36m809 |[0;0m         selectionQueue.async {
       [0;36m|[0;0m                              |- [1;39mnote: [1;39m'self' implicitly strongly captured here[0;0m
       [0;36m|[0;0m                              `- [1;39mnote: [1;39madd 'self' as a capture list item to silence[0;0m
   [0;36m810 |[0;0m             query(check.pid, check.epoch, window) { [weak self] probe in
       [0;36m|[0;0m                                                           |- [1;33mwarning: [1;39m'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope[0;0m [#]8;;https://docs.swift.org/compiler/documentation/diagnostics/implicit-strong-capture\… [обрезано 29 симв.]
       [0;36m|[0;0m                                                           `- [1;39mnote: [1;39mexplicitly assign the capture list item to silence[0;0m
   [0;36m811 |[0;0m                 self?.inputQueue.async {
   [0;36m812 |[0;0m                     guard let self else { return }
  
  [#ImplicitStrongCapture]: <https://docs.swift.org/compiler/documentation/diagnostics/implicit-strong-capture>
  ```

- 2026-10-06 · `swift run -c release TestRunner` · exit 0 ✅

  ```
  | fix en←ru slang-tech | 5/7 | ofc (want щас), rhby; (want кринж) |
  | fix en←uk word-forms | 6/6 |  |
  | fix en←uk slang-tech | 3/4 | yjhv→норм (want норм) |
  | keep en←en backslash | 6/6 |  |
  | fix en←uk apostrophe | 6/6 |  |
  | keep en←en index-no-digit | 13/13 |  |
  
  ========================================
  Results: 1214 passed, 0 failed
  ALL TESTS PASSED
  
  Building for production...
  [1 / 9]
  Build complete! (0,35 с)
  ```

- 2026-10-06 · `swift run -c release InputPipelineTestRunner` · exit 0 ✅

  ```
  --- mouse-down classification ---
  --- input-source shortcuts from com.apple.symbolichotkeys ---
  --- input-source shortcuts: re-read at most once per interval unless forced ---
  --- correction race: a key between the screen check and the emission cancels it ---
  --- correction race: a modifier pressed while the field is read cancels it ---
  --- correction race: modifier presses that count ---
  --- correction race: the last check runs after the post route is resolved ---
  --- correction race: Shift pressed during the post keeps the layout switch ---
  --- correction race: a key made before or during the post is reported once ---
  
  Input pipeline: 1517 passed, 0 failed
  
  Building for production...
  Build complete! (0,19 с)
  ```

## Handoff

**Сгенерировано:** 2026-10-06 · `rtp handoff`

- **Задача:** `2026-10-06-keys-typed-between-the-last-staleness-check-and-the` — Keys typed between the last staleness check and the correction's deletes are deleted
- **Фаза:** review (pipeline `no-spec`, type `bug`)
- **Прогресс:** 5/5 ▰▰▰▰▰
- **Worktree:** `/Users/andrejsokolov/Desktop/projects/SwitchFix`
- **Ветка:** `claude/correction-race` — своих коммитов 0, отставание от origin/master 0
- **Незакоммиченного:** 9 файл(ов)

**Шаги плана**

1. ✅ Метрика задержки tap
2. ✅ Сужение: маршрут до проверки и модификатор как сигнал
3. ✅ Лог гонки
4. ✅ Тесты
5. ✅ Решение и долг

**Файлы в работе**

- `LAUDE.md`
- `Sources/Core/CapturedInput.swift`
- `Sources/Core/InputEngine.swift`
- `Sources/Core/KeyboardMonitor.swift`
- `Sources/Core/TextCorrector.swift`
- `Sources/InputPipelineTestRunner/main.swift`
- `docs/tasks/index.md`
- `docs/plans/keys-typed-between-check-and-deletes-plan.md`
- `docs/tasks/2026-10-06-keys-typed-between-the-last-staleness-check-and-the.md`

**git diff HEAD --stat**

```
CLAUDE.md                                  |   2 +-
 Sources/Core/CapturedInput.swift           |  27 +++-
 Sources/Core/InputEngine.swift             |  10 ++
 Sources/Core/KeyboardMonitor.swift         |  61 ++++++++
 Sources/Core/TextCorrector.swift           | 148 ++++++++++++++++---
 Sources/InputPipelineTestRunner/main.swift | 227 +++++++++++++++++++++++++++++
 docs/tasks/index.md                        |   6 +-
 7 files changed, 459 insertions(+), 22 deletions(-)
```

**Последние коммиты**

- `f9ee54d Merge pull request #25 from 8ui/claude/wave-3`
- `f7906e9 Merge pull request #24 from 8ui/claude/wave-2`
- `86d3a79 Merge pull request #23 from 8ui/claude/wave-1`

**Последние записи лога**

- 2026-10-06: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-10-06: verify: `swift build -c release` → exit 0 ✅
- 2026-10-06: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-10-06: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-10-06: code-review (general-purpose, opus): исправлено — модификатор, отпущенный без клавиши, снимает сигнал (Karabiner-переключатели); биты стороны вместо общей маски; переключение раскладки после post не считает модификатор; запись post до последней проверки; 'input' в логе. Тест 'клавиша между проверкой и эмиссией' — регрессионный страж (проходил и до фикса)

**Открытые долги (4)**

- tap на main run loop: задержка listen-only колбэка растёт под нагрузкой main (TIS-переключение, AX-колбэки, SwiftUI) — вынести tap на свой поток, если 'tap latency' в логах часто > 5 мс
- путь выделения (performSelectionCorrection): проверка → копия всех элементов буфера → Cmd+V; клавиша в этом окне (мс при большом буфере) заменит выделение — перепроверять прямо перед postPaste
- пачка событий коррекции (deletes×2 + replacement×2) — тоже окно: клавиша внутри неё ложится между удалениями и заменой; склейка замены в одно Unicode-событие (до 20 UTF-16) сократит пачку — проверить в Qt/Telegram
- гонка сужена, не закрыта: клавиша без нажатия модификатора, вошедшая в поток за ~1 мс (L) до первого Backspace, всё ещё удаляется — для listen-only tap неустранимо (см. Decisions)

**Следующее действие**

- rtp verify по командам проекта (rtp next 2026-10-06-keys-typed-between-the-last-staleness-check-and-the), затем ревью субагентом → rtp phase 2026-10-06-keys-typed-between-the-last-staleness-check-and-the --to done

**Заметки агента** (не выводятся из кода — грабли, тупики, договорённости)

<!-- handoff-notes -->
- 2026-10-06: Правки не закоммичены, ветка claude/correction-race от master (f9ee54d). Осталось: коммит + push → CI → rtp verify --record. Живой повтор в Telegram не делался: смотреть 'tap latency' и 'correction may have raced' в log stream.
<!-- /handoff-notes -->

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
