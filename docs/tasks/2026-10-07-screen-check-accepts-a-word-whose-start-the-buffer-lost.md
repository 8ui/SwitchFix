---
id: 2026-10-07-screen-check-accepts-a-word-whose-start-the-buffer-lost
title: Screen check accepts a word whose start the buffer lost
type: bug
pipeline: minimal
phase: review
created: 2026-10-07
updated: 2026-10-07
blocked_by: null
steps_done: 3
steps_total: 3
step_current: null
artifacts:
  spec: null
  plan: null
  branch: null
  pr: null
---

## Context

Продолжение 2026-10-06-keys-typed-between-the-last-staleness-check-and-the (PR #26): живой прогон master 1345f7b в Telegram (session, RussianWin) дал `рhello @` — проверяли, обгоняет ли клавиша пачку коррекции. Обгона не нашли (см. Decisions), зато в 450 прогонах настоящего SwitchFix нашлась другая порча: Telegram шлёт AXFocusedUIElementChanged, когда в поле начинают печатать → новая эпоха → `InputStateMachine.updateContext` обнуляет буфер посреди слова → детектор видит `уддщ`, удаляет 5 символов и пишет `ello` → `рello`. Проверка экрана давала `.match` по одному суффиксу. Исправление: `.match` требует, чтобы перед словом в поле не было буквы.

## Progress

1. ✅ Проверка начала слова в ScreenVerification
2. ✅ Тесты
3. ✅ Решения, долги, замеры

## Log

- 2026-10-07: triage — pipeline `minimal`, reason: One function in ScreenVerification + a pipeline test; known architecture, no new state
- 2026-10-07: brainstorm (из запроса и замеров): что — проверка экрана требует начала слова (перед словом в поле не буква); зачем — живой прогон Telegram: буфер сброшен посреди слова (AXFocusedUIElementChanged при наборе → новая эпоха), руддщ → рello, 3/150; готово — тест verdict + пайплайн-тест, проверки зелёные
- 2026-10-07: шаг 1 ✅ Проверка начала слова в ScreenVerification — startsWord в .match и в ветке скрытого пробела
- 2026-10-07: шаг 2 ✅ Тесты — verdict + пайплайн; мутация без фикса → 5 FAIL
- 2026-10-07: шаг 3 ✅ Решения, долги, замеры
- 2026-10-07: impl complete
- 2026-10-07: verify: `swift build -c release` → exit 0 ✅
- 2026-10-07: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-10-07: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-10-07: verify: `swift build -c release` → exit 0 ✅
- 2026-10-07: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-10-07: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-10-07: code-review (general-purpose, opus): Medium — откат коррекции выделения внутри слова (приdtn→привет) отказывал → requiresWordStart только для коррекций (kind == .correction), тест + мутация; Low — хоткей на слове, набранном внутри существующего слова, теперь отменяется (безопаснее, оставлено); Low — autocorrected с потерянным префиксом → долг; добавлены тесты NBSP, decomposed, selection accept/require

## Decisions

- Замеры 2026-10-07 (скрипты в scratchpad сессии): `CGEventPost` 24 событий возвращается за ~0,1 мс — `endedAt` = «отдано WindowServer», не «доставлено»; приложение получает первое событие через 1–6 мс и разбирает пачку 7–28 мс (NSTextView). Порядок при этом FIFO: HID-клавиша (из второго процесса, с Shift flagsChanged) через 0–4 мс после пачки ни разу её не обогнала — NSTextView 0/135 (session/hid/pid, с переключением TIS и занятым получателем), Telegram с эмулированной пачкой 0/76 (с AX-чтением перед пачкой и TIS через 5 мс). Гипотезы 1 (session доставляется позже HID) и 2 (Qt разбирает Unicode-события асинхронно) не подтвердились; 3 верна (Shift пользователя ушёл в ~.180, одновременно с пачкой — модификатор-гард его видеть не мог), но для FIFO-получателя такая клавиша и не обгоняет.
- Настоящий SwitchFix в Telegram, X=2..30, SL=3/20, по 150 прогонов на маршрут: «съеденной кавычки» нет ни разу. Порча: session 3/150 (`рello @@`, `уllo ""` — буфер сброшен посреди слова, лог: `focus resolved` между буквами, `word flushed <4 chars>`, deletes=5, verdict=match), hid 6/150 и pid 3/150 (`ддщ ""`/`дщ ""` — в поле нет первых букв, а SwitchFix ничего не слал: коррекция `keep` на 2 буквах; похоже на потерю клавиш самим Telegram в только что очищенном поле, механизм не установлен).
- Окно диагностики гонки за `endedAt` не расширяем: в FIFO-получателе клавиша после `endedAt` приходит после пачки, а доставка пачки длится 7–28 мс — расширение дало бы шум на обычном наборе. Маршрут Telegram не меняем: hid/pid не лучше session (у них больше аномалий).
- Слово с буквой прямо перед ним в поле — `.mismatch` (а не удаление всего слова с экрана): текст по устаревшему контексту не меняем (правило plan/003). Отменяет прежний тест «only the deleted tail matters» (`xghbdtn` → match): удаление было точным, но результат — искалеченное слово. Цифра, пунктуация, эмодзи перед словом — не буква, коррекция идёт; символ, обрезанный окном, не считается.
- Откат (`kind == .revert`) начало слова не требует (`requiresWordStart: false`): коррекция выделения может стоять внутри слова (`приdtn` → выделить `dtn` → `привет`), её откат удаляет только конвертированную часть. Хоткей на слове, набранном внутри существующего слова (`w|rld` + `ghb`), теперь отменяется — сознательно, безопаснее.
- Исходный `рhello @` пользователя (deletes=6, т. е. буфер видел все 5 букв) этим механизмом не объясняется и не воспроизведён — см. долг.

## Debt

- [ ] Telegram шлёт AXFocusedUIElementChanged при начале набора → буфер обнуляется посреди слова и коррекция теперь отменяется (раньше портила) — пропущенная коррекция; различать 'тот же элемент' (сравнить AXUIElement) и не сбрасывать буфер
- [ ] рhello @ из прогона 2026-10-06 (deletes=6, буфер полный) не объяснён и не воспроизведён в 450+58 прогонах; если повторится — снять log stream с input-логами и сравнить поле до/после
- [ ] hid/pid-маршрут в Telegram: 9/300 прогонов — в поле нет первых букв слова, SwitchFix ничего не слал; механизм (Telegram теряет клавиши в только что очищенном поле?) не установлен
- [ ] autocorrected() может принять слово с потерянным началом, если потерянный префикс начинается с той же буквы и укладывается в 2 правки (буфер ghbdtm, поле gghbdtn → .replaced(8)) — маловероятно, найдено ревью

## Verification

- 2026-10-07 · `swift build -c release` · exit 0 ✅

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

- 2026-10-07 · `swift run -c release TestRunner` · exit 0 ✅

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
  Build complete! (0,20 с)
  ```

- 2026-10-07 · `swift run -c release InputPipelineTestRunner` · exit 0 ✅

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
  
  Input pipeline: 1526 passed, 0 failed
  
  Building for production...
  Build complete! (0,20 с)
  ```

- 2026-10-07 · `swift build -c release` · exit 0 ✅

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

- 2026-10-07 · `swift run -c release TestRunner` · exit 0 ✅

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
  Build complete! (0,34 с)
  ```

- 2026-10-07 · `swift run -c release InputPipelineTestRunner` · exit 0 ✅

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
  
  Input pipeline: 1534 passed, 0 failed
  
  Building for production...
  Build complete! (0,19 с)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
