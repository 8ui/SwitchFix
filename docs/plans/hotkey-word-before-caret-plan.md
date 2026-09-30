# Хоткей: слово перед кареткой через AX, когда буфера нет

Задача: `docs/tasks/2026-09-30-hotkey-converts-the-word-before-the-caret-when-the-buffer-is.md`.

## Проблема

Cmd+A → Backspace: Backspace при пустом буфере даёт `invalidate(untilBoundary: true)` (правильно: неизвестно,
что стёрто), набранное слово в буфер не попадает, хоткей получает `word: nil`, выделения нет → ничего.
То же после клика или стрелок в середину текста.

## Решение (выбрано пользователем)

Когда хоткей пришёл с пустым буфером и выделения нет, прочитать через AX текст вокруг каретки, взять слово
перед ней и конвертировать как ручной хоткей (`runDetection(..., forceConversion: true, teaches: false)`:
удалить `word.count` символов, напечатать конверсию). Буфер приоритетнее; непустое выделение — как сейчас.

## Инварианты и решения после plan-review

- Физический ввод не задерживается: AX-запрос на `queryQueue`, ответ обрабатывается на `inputQueue`.
- **Один AX-запрос** `requestCaretContext` вместо двух (выделение, потом текст): одна проверка staleness
  (sequence, editGeneration, correctionEpoch, context) после ответа, дальше `prepareCorrection`/`isEligible`.
- **Не учить лексикон** на слове из AX (`teaches: false` → provenance `.hotkey`): слово могло быть вставлено
  или набрано давно; двойное нажатие иначе выучило бы «всегда исправлять» настоящее слово.
- **Отстающий AX (Chromium/Electron)** — после code-review: `InputStateMachine.ScreenSuffix` — набранные
  символы и границы с последней правки, которую SwitchFix не видел (отмена, коррекция, клик/стрелка,
  сочетания с модификаторами, 🌐, смена контекста); Backspace убирает последний символ, Backspace при пустом
  суффиксе — «неизвестно». Текст перед кареткой должен оканчиваться на суффикс; пустой суффикс после
  невидимой правки — экран не читается. Следствие: «клик → хоткей без набора» не работает (фокус после клика
  всё равно заменяет контекст, а Cmd+V/Opt+Backspace классифицируются как navigation) — отдельная задача.
- **Каретка внутри слова** («hel|lo») — ничего: запрашиваем и символ после каретки.
- **Единицы**: слово принимается, только если каждый Character — один BMP-скаляр, который `LayoutMapper`
  знает в исходной раскладке (`KeyboardTables`). Тогда UTF-16 = Character = число Backspace.
  Обрезка окна: слово дошло до начала окна, а окно начинается не с 0 → nil.
- **AX-ответ проверяется**: `AXSelectedTextRange` → CFRange, length 0; `AXStringForRange` должен вернуть
  ровно запрошенную длину. Без `AXStringForRange` — `AXValue` только если `AXNumberOfCharacters` ≤ 20 000.
- **Откат (Caps Lock) без отмены** вызывает ручную коррекцию — там AX не читаем (`allowCaretRead: false`).
- Не цель: «ghbdtn |» (пробел перед кареткой) не конвертируется — как и путь буфера.
- Состояние автомата хоткей по AX не меняет (`isInvalidUntilBoundary` остаётся — консервативно).
- В логах только длины (`manual: caretWordLen=…`).

## Шаги

### Step 1 Извлечение слова (Core) + тесты
`CaretWordExtractor.word(before: String, windowStartsAtZero: Bool, next: Character?, tables:, sourceLayout?)`:
границы — общие множества с `KeyboardMonitor` (вынести в internal-тип; classify использует его же).
Тесты: «ujnjdj», «hello ujnjdj», «(ghbdtn», «что-то», «b[jl», «❤️ghbdtn», пробел в конце, «hel|lo»,
обрезанное окно, пустая строка.

### Step 2 `unverifiedTail` в InputStateMachine + тесты
Хоткей: `.requestManualCorrection(word:tail:sequence:context:)`.

### Step 3 `requestCaretContext` (Utils)
Возвращает `.selection(String)` / `.caret(prefix:, windowStart:, next:)` / `.unavailable` из одного
запроса к фокусу; `AXManualAccessibility` как для выделения.

### Step 4 InputEngine + AppDelegate
Seam `caretContextRequest`; без него — прежний путь `selectedTextRequest`. `teaches: false`,
`allowCaretRead`, одна проверка staleness. AppDelegate подключает coordinator.

### Step 5 Тесты пайплайна
Cmd+A → Backspace → «ujnjdj» → хоткей: план «ujnjdj», лексикон не изменился. Не конвертирует: AX отстаёт
(«ujnjd» при tail «ujnjdj»), середина слова, ввод между хоткеем и ответом, откат Caps Lock без отмены.
Буфер есть — AX не спрашиваем. Коррекция по AX → откат → исходный текст, лексикон не изменился.

### Step 6 Сборка, тесты, ревью, проверка на Mac
`swift build`, `TestRunner`, `InputPipelineTestRunner`, ревью субагентом, CI; на Mac — TextEdit и
Chromium/Electron (первый хоткей в Chrome может прийти до построения AX-дерева — как и выделение).
