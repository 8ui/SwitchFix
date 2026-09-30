# План: сверка текста поля перед удалением (correction-verifies-field-text-before-deleting)

## Проблема

`prepareCorrection` удаляет `originalWord.count + boundary.count` символов, доверяя буферу. Поле может
изменить текст между нашим буфером и эмиссией, и тогда Backspace удаляет не то:

- inline-автодополнение (омнибокс Chrome/Safari, Spotlight, Raycast): подсказка — выделение после каретки,
  первый Backspace гасит её, остаётся лишняя буква (`gпривет`);
- inline predictive text (macOS 14+) и автокоррекция/Text Replacements срабатывают на том же пробеле,
  которым мы делаем flush: в поле уже другое слово.

Staleness-guards (`isEligible`) видят только наши счётчики и контекст, не содержимое поля.

## Решение (после plan-review)

Перед эмиссией (после существующих guards, до `correctionQueue`) прочитать через AX текст перед
кареткой и эмитировать, только если последние `deleteCount` символов поля — это то, что мы удаляем.

**Принцип вердикта:** удаление вредно, только когда последние N символов поля не наши **по количеству
или позиции**. Изменения той же длины безопасны для Backspace и принимаются:
- регистр (автокапитализация `ghbdtn` → `Ghbdtn`);
- кавычки: `'` ≈ `‘ ’ ‚ ‹ ›`, `"` ≈ `“ ” „ « »` (умные кавычки: `'nj` = «это»);
- пробелы: U+00A0, U+202F, U+2007 ≈ пробел (contenteditable хранит пробел как NBSP, в т. ч. внутри
  склеенной пары) — нормализуется вся строка.
Сравнение посимвольно по `Character` (Swift-равенство учитывает каноническую эквивалентность).

Проба (новый тип, не `CaretContext`): `FieldTextProbe { text(before: String), selection(length: Int),
unavailable(transient: Bool) }`, читается отдельной функцией без побочных эффектов:
`focusedElement` + обязательный `exposesText`, **без AXManualAccessibility и без продления его таймера**;
сначала `AXSelectedTextRange` — `length > 0` → `selection`; окно `expected.utf16.count + 2` UTF-16
единиц; fallback на `AXValue` только до 4 000 символов. Structural unavailable (нет текстового элемента,
атрибут не поддерживается) vs transient (таймаут `.cannotComplete`, caret > total, длина
`AXStringForRange` не совпала). Ответ — без хопа на main.

Вердикт `ScreenVerification.verdict(expected:word:probe:final:)`:

| Проба | Вердикт |
|---|---|
| `text`, хвост ≈ `word + boundary` | `match` → эмиссия |
| `text`, хвост ≈ непустой собственный префикс `expected` (приложение ещё не обработало клавиши) | `lagging` → повтор |
| `text`, иначе (автокоррекция `teh ` → `the `, predictions `helo ` → `hello `) | `mismatch` → отмена сразу |
| `selection` (inline-подсказка омнибокса/Spotlight) | `mismatch` → отмена сразу |
| `unavailable(transient)`, до дедлайна | повтор |
| `unavailable(structural)` или transient на дедлайне | `unknown` → эмиссия (fail-open, как сейчас) |
| на дедлайне `lagging`, при этом поле ≈ `word` и граница — пробельная | `match` (редакторы, не отдающие хвостовой пробел; трансформация по пробелу уже изменила бы слово) |
| на дедлайне прочее `lagging` | `mismatch` → отмена |

Дедлайн — по времени (150 мс от первого запроса, интервал ≥ 20 мс), не по числу попыток: одна попытка —
до 5 AX-вызовов по 50 мс. Перед каждым повтором (на `inputQueue`) перепроверяются sequence / generation /
correction epoch / context, после каждого ответа — тоже; эмиссия по-прежнему через `correctionQueue` +
`plan.isEligible`.

**Режим** `SwitchFix_fieldTextCheck` (`defaults write`, читается при запуске, как `logTypedText`):
`off` / `shadow` (по умолчанию: вердикт, попытки, мс, pid пишутся в лог — длины, без текста, — но
коррекция идёт как раньше) / `enforce`. Проверить в облаке на реальных приложениях нельзя, поэтому
`enforce` включается по умолчанию только после локальной матрицы (последний шаг).
**Обход по bundle id** (Terminal, iTerm2, Warp, kitty, Alacritty, WezTerm, Ghostty): AppDelegate
отвечает `unavailable(structural)` сразу — AX терминала отдаёт весь буфер с кареткой не шелла.

Где действует: коррекции из буфера через `prepareCorrection` (automatic, hotkey, hotkeyForced,
layoutSwitch). Не проверяется: hotkey по слову, прочитанному с экрана (`caretWord` — только что сверено
со `screenSuffix`; флаг `screenVerified` в `DetectionRequest`), и выделение
(`performSelectionCorrection`). Отмена hotkey/layoutSwitch логируется на уровне `notice`.

Честные ограничения (в README/задачу):
- Chrome/Electron без дерева: фокус — контейнер → `unavailable` → fail-open; омнибокс Chrome может
  остаться непокрытым (и «покрытым» 30 с после хоткея, включившего AXManualAccessibility). Локальная
  матрица фиксирует вердикт по приложениям; альтернатива для Chromium (выделение Shift+← как в OpenKey) —
  отдельная задача.
- Автокоррекция WebKit, применённая позже нашего чтения, не ловится (best-effort, не хуже, чем сейчас).
- Вне задачи: undo/revert (`TextCorrector.undo`) удаляет без сверки; hotkey/layoutSwitch при выделенной
  inline-подсказке конвертируют подсказку (ветка `.selection`).

## Шаги

### Step 1: ScreenVerification (Core) + чистые тесты вердикта

`Sources/Core/ScreenVerification.swift`: `FieldTextProbe` (в Utils рядом с `CaretContext`, т. к. его
отдаёт координатор), `ScreenVerdict`, эквивалентность символов, `verdict(...)`. Тесты в
`InputPipelineTestRunner`: совпадение, регистр, умные кавычки, NBSP (в т. ч. внутри пары), составной
`é` vs прекомпозированный, эмодзи перед словом, выделение, автокоррекция, predictions, lagging, дедлайн
с/без хвостового пробела, transient/structural.

### Step 2: InputEngine — стадия сверки

`ScreenTextRequest = (pid_t, UInt64, Int, @escaping (FieldTextProbe) -> Void) -> Void`,
`init(..., screenTextRequest: nil, screenCheckMode: .enforce)`; nil = без сверки (существующие тесты не
меняются). Извлечь `emit(plan)`; `verifyScreen` с дедлайном; логи вердикта. `DetectionRequest.screenVerified`.

### Step 3: Coordinator + AppDelegate

`AccessibilityFocusCoordinator.requestFieldText(pid:length:completion:)` — отдельная статическая функция
без побочных эффектов; `ScreenCheckMode` из UserDefaults; обход терминалов по bundle id; проводка в
`InputEngine`.

### Step 4: Тесты пайплайна

`ScreenStub` (очередь ответов, счётчик запросов, запрошенные длины окна): окно ≥ `expected.utf16.count`;
guard отменил раньше (`word-ended-by-enter`) → запроса нет; selection/mismatch → ровно 1 запрос;
lagging → match → эмиссия; transient → match → эмиссия; структурный unavailable → эмиссия; печать во
время повтора → запросов ≤ 2 и нет эмиссии; умные кавычки и капитализация → эмиссия; склеенное короткое
слово; hotkey (boundary "") и layoutSwitch — по одному запросу; hotkey по `caretWord` — без запроса;
`shadow` → эмиссия при mismatch.

### Step 5: Документация + ревью

CLAUDE.md (пайплайн, п. 5; Debugging — ключ режима), README (раздел форка), долг
`merged-short-word-…` про незахваченную вставку — переформулировать как частично закрытый.
Ревью субагентом, CI.

### Step 6: Локальная матрица и включение enforce (macOS)

TextEdit, Notes (умные кавычки, капитализация, автокоррекция), Chrome/Safari (омнибокс, textarea,
contenteditable), Telegram, Slack, VS Code, Terminal/iTerm2: вердикты по логу в `shadow`, затем
`enforce` по умолчанию.

## Риски

- Ложные отмены в приложениях с неверным AX — поэтому `shadow` по умолчанию и обход терминалов.
- Задержка коррекции на время AX-запроса → больше отмен у быстро печатающих; замер по логу (мс).
