# План: коррекция сверяет текст поля перед удалением

Задача: `docs/tasks/2026-09-30-correction-verifies-field-text-before-deleting.md`.

**Цель.** Перед тем как стирать `deleteCount` символов, прочитать через AX текст перед кареткой и отменить
коррекцию, если он не заканчивается тем, что мы собираемся стереть. Ловит inline-автодополнение
(выделенная подсказка омнибокса/Spotlight), predictive text и автокоррекцию, принятые тем же пробелом,
Text Replacements, умные кавычки.

**Решения пользователя (2026-09-30).**
- AX не ответил (нет элемента, таймаут, нет текстового диапазона) → исправлять как раньше (fail-open).
- Для проверки `AXManualAccessibility` **не** включается: Electron без готового дерева = «AX недоступен».

**Архитектура.** Проверка — последняя ступень `InputEngine.prepareCorrection`, после существующих
staleness-guards и до постановки плана в `correctionQueue`. Запрос — новое инжектируемое замыкание
`fieldTextRequest(pid, epoch, window, completion)`; без него (тесты, старые вызовы) поведение прежнее.
Вердикт — чистая функция, тестируется без AX.

## Фаза 1: AX-чтение без включения дерева (Utils)

- `caretContext(pid:window:requestsTree:)`: при `requestsTree == false` брать `focusedElement` напрямую и
  требовать `exposesText`, иначе `.unavailable`; `AXManualAccessibility` не трогать.
- `AccessibilityFocusCoordinator.requestFieldText(pid:epoch:window:completion:)`: `queryQueue`, completion
  вызывается прямо там (без прыжка на main — меньше задержка).

## Фаза 2: вердикт (Core)

`FieldTextVerification.verdict(_ caret: CaretContext, word: String, boundary: String) -> Verdict`
(`.matches` / `.mismatch(reason)` / `.unknown`):
- `.selection` → mismatch (inline-подсказка выделена после каретки или поле само выделило текст);
- `.caret(before, …)`: `before.hasSuffix(word + boundary)` → matches; `boundary` непуст и
  `before.hasSuffix(word)` → matches (приложение ещё не обработало пробел — наши события встанут после него);
  иначе mismatch;
- `.unavailable` → unknown.
Окно запроса — `word.count + boundary.count`.

## Фаза 3: InputEngine

- Новый параметр `fieldTextRequest: FieldTextRequest? = nil`.
- В `prepareCorrection`: после guards, если запрос есть — `selectionQueue` → запрос → `inputQueue`:
  повторить guards (sequence, editGeneration, correctionEpoch, context), затем вердикт; `mismatch` →
  `correction cancelled reason=field-text-mismatch`; `matches`/`unknown` → план как сейчас.
- Вынести построение/отправку плана в функцию, чтобы оба пути (с проверкой и без) были одним кодом.
- Лог — только длины/причина (`SwitchFixLog.text`).

## Фаза 4: проводка и документация

- `AppDelegate`: `fieldTextRequest` → `focusCoordinator.requestFieldText`.
- CLAUDE.md (пайплайн, шаг 5), README (раздел форка).

## Фаза 5: тесты (InputPipelineTestRunner)

- Вердикт: совпадение с пробелом, пробел ещё не дошёл, автодополненная выделенная подсказка,
  изменённый текст (`ghbdtn` → `ghbdtnf`), `.unavailable`.
- Движок: mismatch отменяет эмиссию; matches и unavailable — эмиссия есть; ввод клавиши во время запроса
  отменяет (stale-sequence после ответа).
