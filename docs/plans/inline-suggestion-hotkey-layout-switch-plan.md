# Хоткей и layoutSwitch при выделенной inline-подсказке — план

Задача: `docs/tasks/2026-10-02-hotkey-and-layout-switch-convert-an-inline-autocomplete.md`.

## Проблема

Омнибокс Safari/Chrome, Spotlight и подобные поля показывают подсказку `ya[ndex.ru]`: хвост выделен,
каретка — в начале выделения. Сейчас:

- хоткей (`InputEngine.requestManualCorrection`): `caretContextRequest` возвращает `.selection("ndex.ru")`,
  и ветка selection конвертирует подсказку вставкой (`performSelectionCorrection`) вместо набранного `ya`;
- layoutSwitch (`InputEngine.handleLayoutChange`): `selectedTextRequest` возвращает подсказку — то же самое;
- если бы слово пошло обычным путём, сверка (`ScreenVerification.verdict`) отменила бы его: `.selection` → `.mismatch`.

## Правило

Буфер не пуст ⇒ с последнего движения каретки пользователь только печатал (стрелки, Shift+стрелки, Cmd+A,
клик, Tab сбрасывают буфер), значит выделение сделало приложение. Тогда выделение игнорируется, исправляется
слово из буфера, а сверка поля решает:

- текст **перед началом выделения** кончается словом (+граница) → удалить на один символ больше: первый
  Backspace гасит подсказку, остальные стирают слово; затем обычный ввод конверсии;
- иначе (или текст перед выделением не прочитан) → отмена, как сейчас.

Только для коррекций с явным намерением пользователя (провенанс не `automatic`: hotkey, hotkeyForced,
layoutSwitch). Автоматическая коррекция при выделении по-прежнему отменяется — вне объёма (долг).

Режим сверки `off` (`screenTextRequest == nil`): проверить текст перед выделением нечем — поведение
не меняется (ветка selection, как сейчас).

Буфер пуст → выделение пользовательское → ветка selection без изменений.

## Фаза 1 — FieldTextProbe и вердикт

- `Sources/Utils/Permissions.swift`: `FieldTextProbe.selection(length: Int, before: String? = nil, atTextStart: Bool = false)`.
  `fieldText`: при `range.length > 0` читать окно перед `range.location` тем же кодом, что и для каретки
  (`AXStringForRange`, фолбэк `AXValue`); не прочитали — `before: nil`. Вынести чтение окна в helper,
  чтобы обе ветки делили код.
- `Sources/Core/ScreenVerification.swift`: новый вердикт `.matchBeforeSelection` («поле кончается словом
  перед выделенной подсказкой: удалить на один больше»). `verdict(…, acceptsSelection: Bool = false)`:
  `.selection` с `before != nil` и `acceptsSelection` → вердикт для `.text(before, atTextStart)`;
  `.match` → `.matchBeforeSelection`, `.retry` → `.retry`, остальное (включая `.replaced`) → `.mismatch`.
  Без `acceptsSelection` / без `before` — `.mismatch`, как сейчас.
- Чистые тесты вердикта в `InputPipelineTestRunner` (раздел screen verification).

## Фаза 2 — InputEngine

- `ScreenCheck.acceptsSelection`; в `prepareCorrection` = `plan.provenance != .automatic`; revert — false.
- `verifyScreen`: передаёт флаг в `verdict`; `.matchBeforeSelection` в enforce → `check.proceed(word.count + boundary.count + 1)`
  (`plan.deleting`); в shadow — как сейчас (`proceed(nil)`), лог вердикта есть. `logDescription` — длина `before`.
- `requestManualCorrection`: `.selection` при `word != nil` и `screenTextRequest != nil` → игнорировать
  выделение (лог `manual: selection ignored, buffered word`), дальше `runDetection(word)` (не `screenVerified`).
- `handleLayoutChange`: непустое выделение при непустом `bufferedWord` и `screenTextRequest != nil` →
  `applyBufferedCorrection()`.

## Фаза 3 — тесты пайплайна

- Хоткей: буфер `ujnjdj`, caret `.selection("ndex")`, screen `.selection(length: 4, before: "ujnjdj")` →
  одна эмиссия, `deleteCount == 7`, `correctedText == "готово"`; screen `.selection(length: 4, before: "other")`
  → отмены; `before: nil` → отмена; буфер пуст + выделение → ветка selection (эмиссии плана нет).
- Режим off: буфер + выделение → как раньше (ветка selection).
- layoutSwitch: `LearningHarness(mode: .layoutSwitch)` с `selectedTextRequest` из `CaretStub`, screen
  `.selection(before: "ghbdtn")` → план `deleteCount == 7`, `correctedText == "привет"`. Закрывает часть долга
  «путь layoutSwitch со сверкой не покрыт тестом».
- Автоматическая коррекция с `.selection(before: "ghbdtn ")` по-прежнему отменяется.

## Фаза 4 — документация, ревью, CI

- CLAUDE.md (п. 5 пайплайна): одна фраза про подсказку при непустом буфере.
- Ревью субагентом, push, зелёный CI, `rtp verify --record`.
- Ручная проверка пользователем: Safari/Chrome омнибокс, Spotlight (хоткей и Globe в режиме layoutSwitch).

## Риски

- Поле, которое после Backspace по подсказке тут же предлагает новую (каждый Backspace гасит новую подсказку):
  тогда слово сотрётся не полностью. Проверка вручную в Spotlight; при проблеме — долг.
- Undo после такой коррекции: поле может снова показать подсказку → сверка revert увидит выделение и откажет
  (текст не портится). Долг, если подтвердится.

## Поправки после plan-review (заменяют пункты выше, где расходятся)

- **Режим обработки выделения** вместо `provenance != .automatic`: `DetectionRequest.selectionHandling`
  (`ScreenSelectionHandling`: `.refuse` — по умолчанию, автоматика; `.accept` — хоткей/layoutSwitch без
  увиденного выделения; `.require` — движок проигнорировал выделение). `ScreenCheck` получает его же.
- **B1 — fail-closed:** при `.require` проходит только `.matchBeforeSelection`; `.match` без выделения,
  `.unknown`, `.replaced` — отмена (чтение каретки и сверка — разные AX-пути; без этого fail-open удалил бы
  word.count, и первый Backspace съела бы подсказка → «uготово»).
- **Только enforce:** выделение игнорируется лишь при `screenCheckMode == .enforce`; shadow и off — старая
  ветка selection (shadow всегда `proceed(nil)` и испортил бы текст).
- **Вердикт с payload:** `.matchBeforeSelection(deleteCount:)` = word+boundary+1 считается в
  `ScreenVerification`; не переиспользовать `.replaced` (его подтверждение вторым чтением).
  `.selection(before: nil)` при accept/require: `final ? .mismatch : .retry` (чтение окна могло быть
  transient); `.unknown` от внутреннего вердикта → `.mismatch` явно.
- **Только хвост:** `fieldText` даёт `before` лишь если выделение доходит до конца текста
  (`location + length == AXNumberOfCharacters`, когда счётчик известен) — inline-подсказка всегда хвост.
- **logDescription:** `.selection(length, before, _)` — `before` только через `SwitchFixLog.text`.
- **handleLayoutChange:** проверка буфера (enforce) — до `ScriptAnalyzer.containsScript`.
- **Тесты layoutSwitch:** параметры `selectedText`, `screen`, `screenCheckMode` у `layoutSwitchPlans`;
  случаи enforce (+1), off (ветка selection).
- **Хоткей-тесты:** caret `.selection` + screen `.unavailable` → отмена; + screen `.text(before: word)` →
  отмена; caret `.unavailable` + screen `.selection(before: word)` → эмиссия 7; `before: ""` → отмена; shadow →
  ветка selection.
- **Отложено в долг:** revert после такой коррекции (новая подсказка → revert откажет), автоматическая
  коррекция при подсказке.
- Пуш на CI после фаз 1–3 вместе (тесты нужны для проверки), затем документация.
