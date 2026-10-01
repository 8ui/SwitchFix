# План: коррекция сверяет текст поля перед удалением

Задача: `docs/tasks/2026-09-30-correction-verifies-field-text-before-deleting.md`.

**Цель.** Перед тем как стирать `deleteCount` символов, прочитать через AX текст перед кареткой и отменить
коррекцию, если поле уже изменило то, что мы собираемся стереть: inline-автодополнение (выделенная
подсказка омнибокса/Spotlight), автокоррекция и Text Replacements, predictive text (где он пишет в значение
поля), вставка неразрывного пробела перед пунктуацией.

**Решения пользователя (2026-09-30).**
- AX не ответил (нет элемента, таймаут, нет текстового диапазона) → исправлять как раньше (fail-open).
- Для проверки `AXManualAccessibility` **не** включается: Electron без готового дерева = «AX недоступен».

**Правило ввода.** Проверка никогда не задерживает физический ввод: она асинхронна на `inputQueue`,
у движка свой дедлайн 40 мс, по истечении — как «недоступно» (fail-open), поздний ответ игнорируется.

## Фаза 1: вердикт (Core, чистая функция) + тесты

`FieldTextVerification.verdict(_ snapshot: FieldTextSnapshot, word: String, boundary: String)` →
`.matches` / `.lagging` / `.mismatch(reason)` / `.unknown`. Сравнение после нормализации: регистр
(автокапитализация) и типографика (“”„«» → ", ‘’ → ', – — → -) — это замена 1:1, число символов то же.
- `.unavailable` → `.unknown`; `.selection` (выделенный диапазон, даже без текста) → mismatch `selection`.
- `.before(text)`:
  - граница непуста и текст заканчивается ею → нужен суффикс `word + boundary`, иначе mismatch `changed`
    (сюда попадают автокоррекция, Text Replacement, NBSP);
  - иначе (граница ещё не дошла или AX-текст Chromium отстаёт) → текст должен заканчиваться непустым
    префиксом `word` (включая всё слово) → `.lagging`/`.matches`; иначе mismatch `changed`.
- `word` — это `originalWord` (у склеенного короткого слова — обе части), `next` после каретки не
  используется (ghost text неотличим от обычной правки в середине — известное ограничение).
Окно запроса — `(word + boundary).utf16.count` (AX-диапазоны в UTF-16).

## Фаза 2: AX-чтение (Utils)

- `FieldTextSnapshot`: `.before(String)` / `.selection` / `.unavailable`.
- `AccessibilityFocusCoordinator.requestFieldText(pid:utf16Length:completion:)` на отдельной serial
  `verifyQueue` (не на `queryQueue`: там фокус-запросы и 150-мс ожидание дерева), completion там же.
- Минимум запросов, таймаут 20 мс: фокус → `AXSelectedTextRange` (длина > 0 → `.selection`) →
  `AXStringForRange` окна перед кареткой. `AXManualAccessibility` не трогается.

## Фаза 3: InputEngine

- Параметр `fieldTextRequest: FieldTextRequest? = nil`; nil — поведение прежнее (все старые тесты).
- `DetectionRequest.verifiesFieldText` (по умолчанию true); false для слова, прочитанного с экрана хоткеем
  (`caretWord` только что сверен с `screenSuffix`).
- `prepareCorrection`: после guards строит план; с проверкой — запрос + дедлайн, завершение ровно одно
  (флаг на `inputQueue`); mismatch → `correction cancelled reason=field-text-<reason>` (notice);
  иначе эмиссия тем же кодом, что и без проверки (`emit(plan)`), `isEligible` на `correctionQueue` как раньше.
- Лог: длительность проверки в мс и вердикт.
- Покрывает автоматические, layoutSwitch и хоткей-с-буфером планы.

## Фаза 4: проводка и документация

- `AppDelegate`: `fieldTextRequest` → `focusCoordinator.requestFieldText`, если `SwitchFix_verifyFieldText`
  не выключен (`defaults write com.switchfix.app SwitchFix_verifyFieldText -bool NO` — для ручного сравнения).
- CLAUDE.md (пайплайн, шаг 5), README (раздел форка).

## Фаза 5: тесты движка (InputPipelineTestRunner)

mismatch отменяет; matches/lagging/unavailable — эмиссия; запрос, который не отвечает, — эмиссия после
дедлайна, поздний ответ не даёт второй; нажатие во время медленного запроса — отмена; layoutSwitch и
хоткей-с-буфером проверяются, слово с экрана — нет; nil-запрос — как раньше.

## Отложено

- В режиме layoutSwitch `handleLayoutChange` конвертирует любое выделение — может быть inline-подсказкой
  омнибокса (отдельная задача).
- Перенос капитализации приложения в `convertedWord`.
