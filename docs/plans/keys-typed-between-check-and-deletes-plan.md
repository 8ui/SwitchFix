# План: клавиши между последней проверкой и удалением коррекции

Задача: `docs/tasks/2026-10-06-keys-typed-between-the-last-staleness-check-and-the.md`.

## Где окно

- `KeyboardMonitor` — listen-only tap на main run loop. WindowServer не ждёт listen-only колбэк:
  физическое событие идёт в приложение, копия — в наш колбэк, который поднимает
  `latestPhysicalSequence` (`CaptureStateStore.capture`) с задержкой L.
- L замерен 2026-10-06 скриптом (listen-only session tap, событие в HID): ≈0,8 мс у простаивающего
  процесса; метки событий — наносекунды uptime (`DispatchTime.uptimeNanoseconds`), у ещё не
  отправленного `CGEvent` метка 0 (ставится при post).
- Последняя проверка перед удалением — `plan.isEligible` в `TextCorrector.apply`. Между ней и первым
  Backspace сейчас ещё `post()` резолвит маршрут: `NSRunningApplication(processIdentifier:)` (запрос
  в LaunchServices) и `AppPostMode.overrides()` (UserDefaults) — лишнее время в окне.
- Итог: клавиша, вошедшая в поток событий за L (+ работа между проверкой и post) до первого
  Backspace, проходит все проверки; в session/HID-режиме она стоит в очереди приложения раньше
  наших удалений и удаляется ими. Закрыть окно listen-only tap не может.

## Отвергнуто

- Пауза после последней клавиши / перед post: окно сдвигается, ширина остаётся L.
- Перепроверка между пачками (после удалений, до набора): текст уже испорчен, обрыв оставит
  удалённое слово без замены — хуже.
- Перечитать поле после удалений до набора: ещё один AX-круг (в Telegram ~20 мс), клавиши за это
  время ложатся в середину правки; починить испорченное по догадке — новая мутация по
  устаревшему контексту.
- Активный tap, придерживающий клавиши на время post: нарушает правило plan/003 (физический ввод
  не задерживается) и ставит наш колбэк на критический путь каждой клавиши.

## Ревизия после plan-review

- Окно — до последнего события пачки (deletes×2 + replacement×2), не до первого Backspace: лог
  гонки различает before / during / after.
- L под нагрузкой main не измерен: метрика задержки tap на каждое событие (notice выше 5 мс).
- Новое сужение: нажатие модификатора (Shift и т. п., не Caps Lock, не Fn/Globe, не клавиша
  tap-хоткея) после границы — сигнал устаревания в `isEligible`. Shift для `"`/заглавной идёт за
  единицы-десятки мс до символа — окно шире L; `editGeneration` и state machine не трогает.
- Путь выделения (`performSelectionCorrection`: проверка → копия буфера → Cmd+V) и склейка
  Unicode-событий — долг.
- AX-замена по диапазону (`AXSelectedTextRange` + `AXSelectedText`) — отвергнуто: Qt/Telegram и
  ещё один AX-круг.

## Шаги

## Фаза 1 — Метрика задержки tap

`KeyboardMonitor.handle`: `now − event.timestamp`, notice выше 5 мс.

## Фаза 2 — Сужение: маршрут до проверки и модификатор как сигнал

`TextCorrector`: маршрут резолвится до последней `isEligible` (apply и postUndo); инъекции
`postRoute`/`eventPoster` для тестов. `CaptureStateStore.noteModifierPress`, поле снапшота,
проверка в `isEligible`; `KeyboardMonitor` зовёт её на нажатие модификатора.

## Фаза 3 — Лог гонки

`TextCorrector` запоминает (boundarySequence, начало, конец post, маршрут); `InputEngine.process`
на первой физической клавише после границы классифицирует before/during/after (чистая функция)
и пишет `correction may have raced`.

## Фаза 4 — Тесты

InputPipelineTestRunner: (1) модификатор, нажатый между screen check и эмиссией, отменяет
коррекцию (падает до фазы 2); (2) настоящий `TextCorrector`, клавиша поймана во время резолва
маршрута — ничего не отправлено, для apply и postUndo (падает до фазы 2); (3) классификация гонки;
(4) клавиша между screen check и эмиссией — регрессионный страж.

## Фаза 5 — Решение и долг

Решение в задаче; долг: tap на main run loop — вынести на свой поток, если метрика покажет L ≫ 1 мс.
