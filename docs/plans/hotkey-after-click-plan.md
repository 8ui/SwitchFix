# Хоткей после клика/стрелки без набора: слово перед кареткой

Задача: `docs/tasks/2026-10-02-hotkey-reads-the-word-before-the-caret-after-a-click-or.md`.
Долг из `2026-09-30-hotkey-converts-the-word-before-the-caret-when-the-buffer-is`.

## Проблема

Хоткей при пустом буфере читает слово перед кареткой через AX, только если `ScreenSuffix` что-то
подтверждает: набранный с последней невидимой правки текст. После клика или стрелки суффикс
«неизвестен» (`needsTyping`), потому что:

1. `KeyboardMonitor.classifyKeyDown` смешивает в `.navigation` перемещения каретки (стрелки) и
   невидимые правки (Cmd+V, Cmd+X, Opt+Backspace, forward delete, Opt+буквы с модификатором);
   клик мышью — `.focusMayChange`, как Tab/Esc (Tab вставляет `\t`, Esc откатывает поле
   переименования).
2. Даже если различить, после клика/стрелки контекст меняется дважды: `process()` применяет
   новый epoch события (`updateContext`), потом разрешение фокуса (`resolveFocus` →
   `engine.updateContext`). Каждая смена контекста делает `screenSuffix.unknownEdit()`.

## Решение (после plan-review)

### Классификация (Core/CapturedInput, Core/KeyboardMonitor)

Новый `CapturedInput.Kind.caretMove(byClick: Bool)` — «каретку поставили, текст не менялся»:

- левый клик без Cmd/Ctrl/Opt/Shift и с `mouseEventClickState <= 1` → `.caretMove(byClick: true)`;
  правый/средний, клик с модификаторами (мультикурсор VS Code, Ctrl-клик = меню, Shift-клик =
  выделение), двойной/тройной клик — `.focusMayChange`, как раньше;
- ←/→/Home/End без Cmd/Ctrl/Opt/Shift, а также Cmd или Opt (без Ctrl/Shift) с ←/→ →
  `.caretMove(byClick: false)`. ↑/↓/PgUp/PgDn (комбобоксы, омнибокс, история шелла подставляют
  текст), Shift+что угодно, Ctrl+что угодно, forward delete, функциональные клавиши — `.navigation`.
  Флаги сравниваются только по маске Cmd/Ctrl/Opt/Shift (стрелки несут NumericPad/SecondaryFn).
- `.caretMove` везде рядом с `.navigation`/`.focusMayChange`: `invalidatesFocus`, `isPhysicalEdit`
  (CapturedInput), `invalidatesCaptureContext`, `recordsUserEdit` (InputEngine), `consume`.

### Автомат (Core/InputStateMachine)

- `.caretMove`: `invalidate(untilBoundary: false)`; `skipsAutomaticFlushUntilBoundary = true` только
  для `!byClick`; `screenSuffix.caretPlaced()` (`text = ""`, `needsTyping = false`). В `process()`
  `updateContext(input.context)` идёт до `consume`, поэтому `unknownEdit` → `caretPlaced` — порядок верный.
- `updateContext` не меняется (любая смена — `unknownEdit`). Два явных входа:
  - `focusResolved(context)` — `AppDelegate.publishFocusResolution`: суффикс сохраняется, если тот же
    epoch/PID/appAllowed/layout/inputSourceID и новый `secureFocus == .notSecure`;
  - `focusMoved(context)` — фокус AX сменился (`onFocusInvalidated` координатора, клик в другое поле):
    суффикс сохраняется, только если он «каретка поставлена» (ничего не было после `caretMove`) и
    PID/appAllowed/layout/inputSourceID те же. Secure Input и рестарт тапа идут прежним
    `updateContext` (клавиши могли потеряться).
  Буфер в обоих сбрасывается, как сейчас.

### Защита от отставания AX и терминалы (Core/InputEngine, AppDelegate)

Пустой суффикс (`screenSuffix == ""`) — экран не подтверждён набором, поэтому:

1. Читать только при `screenCheckMode == .enforce` и наличии `screenTextRequest`, и только если
   `readsScreenAfterCaretMove(pid)` (AppDelegate: не терминал из `fieldTextHidingBundleIdentifiers`
   — там каретка AX не курсор шелла, а ↑/→ подставляют историю/подсказку).
2. Первое чтение — не раньше `caretSettleNanoseconds` (200 мс) после последнего `caretMove`
   (uptime фиксируется в `process`); ожидание через `selectionQueue.asyncAfter`, staleness после
   ответа проверяется как сейчас.
3. Слово идёт в коррекцию с `screenVerified: false` — перед удалением независимая сверка поля
   (`verifyScreen`): выделение (`.selection`) и другое слово отменяют.

Остаточный риск: AX, отстающий дольше 200 мс + время сверки, на одинаково старой каретке. Описать в долге.

## Тесты (InputPipelineTestRunner)

- `classifyKeyDown`: ←/→/Home/End, Cmd+←, Opt+→ → caretMove; ↑, PgDn, Shift+←, Opt+↑, Ctrl+←,
  forward delete, Cmd+V, Opt+Backspace → `.navigation` (обновить утверждение `keyDown(123) == .navigation`).
- Автомат: caretMove → `""`; Backspace после него → nil; `.navigation`/`.focusMayChange` → nil;
  `focusResolved` сохраняет, `updateContext` с новым epoch — нет; `focusMoved` сохраняет только
  «каретку поставлена»; стрелка ставит skip, клик — нет.
- Пайплайн (с ScreenStub, enforce): клик → focusResolved → хоткей конвертирует; стрелка — так же;
  клик → focusMoved → focusResolved → конвертирует; сверка видит другое слово/выделение → ничего;
  `shadow`/без screenTextRequest → экран не читается; терминал (`readsScreenAfterCaretMove` false)
  → не читается; Tab/Esc/Cmd+V → не читается; Secure Input (`updateContext` новый epoch) после
  клика → не читается; откат Caps Lock после клика экран не читает.

## Шаги

Шаги 1–3 — один коммит (без промежуточного состояния без защиты от отставания).

### Step 1 Kind.caretMove + классификация + автомат (все exhaustive switch) + тесты
### Step 2 InputEngine: focusResolved/focusMoved, задержка, enforce-сверка, терминалы; AppDelegate
### Step 3 Тесты пайплайна
### Step 4 CI, ревью, документация (CLAUDE.md, долг исходной задачи)
