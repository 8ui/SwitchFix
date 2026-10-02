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

## Решение

### Классификация (Core/CapturedInput, Core/KeyboardMonitor)

Новый `CapturedInput.Kind.caretMove(byClick: Bool)` — «каретку поставили, текст не менялся»:

- левый клик мышью → `.caretMove(byClick: true)`; правый/средний — `.focusMayChange` (контекстное
  меню может вставить текст);
- клавиши каретки (стрелки 123–126, Home 115, End 119, PgUp 116, PgDn 121; не forward delete 117)
  → `.caretMove(byClick: false)`, если модификаторы (Cmd/Ctrl/Opt) пусты, либо Cmd или Opt (без Ctrl)
  со стрелкой влево/вправо. Shift допустим везде (выделение — хоткей прочтёт выделение).
  Opt/Cmd+↑↓ (VS Code переносит строку), Ctrl+что угодно, функциональные клавиши — `.navigation`.
- Хоткей и системные сочетания проверяются раньше, как сейчас.

`.caretMove` везде, где `.navigation`/`.focusMayChange`: `invalidatesFocus`, `isPhysicalEdit`
(CapturedInput), `invalidatesCaptureContext`, `recordsUserEdit` (InputEngine) — epoch, staleness
и отмена ожидающих коррекций не меняются.

### Автомат (Core/InputStateMachine)

- `.caretMove`: `invalidate(untilBoundary: false)`; `skipsAutomaticFlushUntilBoundary = true`,
  только если `!byClick` (клик по-прежнему не мешает автокоррекции следующего слова);
  `screenSuffix.caretPlaced()` — `text = ""`, `needsTyping = false`: экран не правился невидимо,
  верификация — пустая строка.
- `.navigation` и `.focusMayChange` — как сейчас (`unknownEdit`).
- `updateContext`: суффикс сохраняется, если новый контекст отличается от текущего только
  `secureFocus` (тот же epoch, PID, appAllowed, layout, inputSourceID) и он `.notSecure` — это
  разрешение фокуса того же epoch. Любая другая смена (новый epoch от Secure Input/рестарта тапа,
  смена приложения/раскладки) — `unknownEdit`. Буфер сбрасывается, как и раньше.

### Отставание AX (Core/InputEngine)

Пустой суффикс ничего не доказывает об актуальности AX (Chromium может ещё показывать старую
каретку). Когда `screenSuffix == ""`, ответ `.caret` подтверждается вторым чтением через
`caretConfirmDelay` (0.1 с) на `selectionQueue`; слово берётся, только если оба ответа равны
(`CaretContext: Equatable`). Проверка staleness (sequence, editGeneration, correctionEpoch, context)
— после второго ответа, как сейчас после первого. Выделение второго чтения не требует.

## Тесты (InputPipelineTestRunner)

- `classifyKeyDown`: стрелки/Home/End/PgUp/PgDn → `.caretMove(byClick: false)`; Shift+стрелка,
  Cmd+←, Opt+→ → caretMove; Opt+↑, Cmd+↓, Ctrl+←, forward delete, Cmd+V, Opt+Backspace → `.navigation`.
- Автомат: `.caretMove` → суффикс `""`; после него Backspace → nil; `.navigation` → nil;
  `updateContext` с тем же epoch и `.notSecure` сохраняет суффикс, с новым epoch — нет; стрелка
  ставит skip, клик — нет.
- Пайплайн: клик → resolveFocus → хоткей конвертирует слово перед кареткой (2 текстовых запроса);
  стрелка — так же; ответы двух чтений различаются → ничего; Tab/Esc (`.focusMayChange`) и Cmd+V
  (`.navigation`) → экран не читается; Secure Input (новый epoch через `invalidateFocus`) после
  клика → не читается; откат Caps Lock после клика экран не читает.

## Шаги

### Step 1 Классификация caretMove (Core) + тесты classifyKeyDown
### Step 2 ScreenSuffix.caretPlaced и updateContext в автомате + тесты
### Step 3 Подтверждающее чтение AX в InputEngine + тесты пайплайна
### Step 4 CI, ревью, документация (CLAUDE.md, долг исходной задачи)
