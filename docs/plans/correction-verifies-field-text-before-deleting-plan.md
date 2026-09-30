# План: сверка текста поля перед удалением (correction-verifies-field-text-before-deleting)

## Проблема

`prepareCorrection` удаляет `originalWord.count + boundary.count` символов, доверяя буферу. Поле может
изменить текст между нашим буфером и эмиссией, и тогда Backspace удаляет не то:

- inline-автодополнение (омнибокс Chrome/Safari, Spotlight, Raycast): подсказка — выделение после каретки,
  первый Backspace гасит её, остаётся лишняя буква (`gпривет`);
- inline predictive text (macOS 14+) и автокоррекция/Text Replacements срабатывают на том же пробеле,
  которым мы делаем flush: в поле уже другое слово.

Staleness-guards (`isEligible`) видят только наши счётчики и контекст, не содержимое поля.

## Решение

Перед эмиссией (после существующих guards, до `correctionQueue`) прочитать через AX текст перед
кареткой длиной `deleteCount` и эмитировать, только если он совпадает с тем, что мы собираемся удалить.

Вердикт (чистая функция, `ScreenVerification.verdict(expected:context:)`):

| Ответ AX | Вердикт | Действие |
|---|---|---|
| `.caret(textBefore)`, `textBefore` оканчивается на `originalWord + boundary` | `match` | эмиссия |
| `.selection(_)` (непустое выделение — inline-подсказка) | `mismatch` | отмена `screen-selection` |
| `.caret`, не совпадает | `notYet` | повтор через 20 мс; по исчерпании бюджета — отмена `screen-mismatch` |
| `.unavailable` (нет AX, таймаут, фокус не виден) | `unknown` | эмиссия (fail-open) |

Почему так:
- **Повтор вместо мгновенной отмены.** Tap видит keyDown раньше, чем приложение его обработало: первый
  ответ AX часто ещё без пробела; Chromium отдаёт AX-текст с задержкой в кадр-два. Решение всегда
  принимается по точному совпадению; бюджет повторов — 6 × 20 мс (≈120 мс), затем отмена. Пользователь
  продолжает печатать — `latestPhysicalSequence` меняется, коррекция отменяется существующим guard'ом
  (повторы после каждого ответа перепроверяют sequence/generation/epoch/context).
- **Эмиссия при совпадении на момент чтения** не защищает от автокоррекции, которая сработает позже, —
  но совпадение требует, чтобы граница (пробел) уже была в поле, а автокоррекция/predictions применяются
  на обработке того же пробела, т. е. до того, как мы его увидим.
- **Fail-open на `.unavailable`**: терминалы, Qt, часть Electron без дерева — там сейчас коррекция
  работает; fail-closed сломал бы её. Риск для таких приложений не меняется.
- **Без AXManualAccessibility.** Чтение на каждой коррекции не должно включать атрибут (иначе VS Code/
  Slack уходят в режим скринридера — задача `ax-manual-accessibility-…`). Для сверки фокус берётся
  обычным `kAXFocusedUIElement`; не виден/не текстовый — `.unavailable` → fail-open.
- **NBSP = пробел.** contenteditable в браузерах хранит хвостовой пробел как U+00A0; при сравнении
  U+00A0 приравнивается к пробелу.

Где действует: все коррекции из буфера, проходящие через `prepareCorrection` (automatic, hotkey,
hotkeyForced, layoutSwitch). Выделение (`performSelectionCorrection`) не трогаем — там удаляется
выделение, а не символы.

## Шаги

### Step 1: ScreenVerification (Core) + юнит-тесты вердикта

- `Sources/Core/ScreenVerification.swift`: `enum ScreenVerdict { match, mismatch, notYet, unknown }`,
  `static func verdict(expected: String, context: CaretContext) -> ScreenVerdict`, нормализация NBSP.
- Тесты в `InputPipelineTestRunner`: совпадение, NBSP, выделение, автокоррекция (`teh ` → `the `),
  predictive (`helo ` → `hello `), отставание (`ghbdtn` без пробела → notYet), unavailable, пустой
  expected (не бывает, но → match).

### Step 2: InputEngine — стадия сверки

- Новый инъецируемый `ScreenTextRequest = (pid_t, UInt64, Int, @escaping (CaretContext) -> Void) -> Void`
  (pid, epoch, длина окна); параметр init `screenTextRequest: ScreenTextRequest? = nil` — nil = без
  сверки (существующие тесты не меняются).
- `prepareCorrection`: после guards и построения плана — если `screenTextRequest` есть, `verifyScreen(plan,
  request, attempt: 0)` на `selectionQueue`; ответ → `inputQueue`, перепроверка sequence/generation/
  epoch/context, вердикт; `match`/`unknown` → `emit(plan)` (текущий блок `correctionQueue`); `notYet` и
  попытки не исчерпаны → `asyncAfter(20 мс)` повтор; иначе отмена с причиной в `SwitchFixLog.engine`
  (длины, без текста).
- Константы `screenCheckRetryDelay`, `screenCheckAttempts` — `static let` в `InputEngine`.

### Step 3: Coordinator + AppDelegate

- `AccessibilityFocusCoordinator.requestFieldText(pid:epoch:length:completion:)` — `caretContext` с
  параметром `requestsTree: Bool`; для сверки `false` (обычный `focusedElement` + `exposesText`, без
  AXManualAccessibility). Окно — `length` символов перед кареткой.
- `AppDelegate`: передать `screenTextRequest` в `InputEngine`.

### Step 4: Тесты пайплайна

`LearningHarness` + `ScreenStub` (ответы по очереди, счётчик запросов):
- совпадение → эмиссия; выделение → нет; автокоррекция → нет; unavailable → эмиссия;
- сначала без пробела, потом с пробелом → эмиссия; всё время без пробела → нет (по бюджету);
- печать во время запроса (`beforeReply` шлёт символ) → нет;
- склеенное короткое слово (`ше цщкли `) проверяется целиком;
- без `screenTextRequest` поведение прежнее (существующие тесты).

### Step 5: Документация + ревью

- CLAUDE.md (пайплайн, п. 5), README (раздел форка — что изменилось), закрыть долг задачи
  `merged-short-word-…` про незахваченную вставку.
- Ревью субагентом, CI.

## Риски / вне задачи

- Приложения, где AX врёт о каретке/тексте (терминалы с AXValue всего буфера, Word) → ложные отмены.
  Проверить локально: TextEdit, Notes, Chrome (омнибокс, textarea, contenteditable), Safari, Telegram,
  Slack, VS Code, Terminal, iTerm2. При ложных отменах — per-app исключение (отдельная задача).
- Задержка коррекции растёт на время AX-запроса (обычно единицы мс, худший случай — таймауты 50 мс ×
  несколько атрибутов) — больше коррекций отменяется у быстро печатающих. Замерить по логу локально.
- zsh-autosuggest и серые подсказки predictive text не видны в AX до принятия — их не ловим.
