---
id: 2026-09-30-correction-verifies-field-text-before-deleting
title: "Correction leaves stray letters when the field changed the text (inline autocomplete, predictions, autocorrect)"
type: bug
pipeline: no-spec
phase: impl
created: 2026-09-30
updated: 2026-10-01
blocked_by: null
steps_done: 6
steps_total: 7
step_current: 6
artifacts:
  spec: null
  plan: docs/plans/correction-verifies-field-text-before-deleting-plan.md
  branch: claude/beautiful-shannon-hg5k6h
  pr: null
---

## Context

Самая частая жалоба у всех аналогов (Punto, RuSwitcher #16, Keyboop #21/#23, Lang Switcher, espanso #1747,
OpenKey #37): после коррекции остаётся лишняя буква — `gпривет`, `фapp`, `yyandex.ru`. Причины, общие для
listen-only архитектуры: поле само меняет текст между нашим буфером и эмиссией —
- inline-автодополнение (омнибокс Chrome/Safari, Spotlight, Raycast, zsh-autosuggest): первый Backspace гасит
  серую подсказку, а не удаляет символ;
- inline predictive text (macOS 14+) принимается тем же пробелом, на котором мы делаем flush;
- системная автокоррекция и Text Replacements (синхронизируются из iCloud) срабатывают на том же пробеле;
- умные кавычки/тире, умные пробелы Word.
Staleness-guards (`CorrectionPlan.isEligible`) этого не видят: контекст не менялся, изменилось содержимое поля.
Варианты: перед эмиссией читать через AX текст перед кареткой (`requestCaretContext` уже есть) и отменять
коррекцию при расхождении с буфером; OpenKey для Chromium выделяет слово Shift+← и удаляет одним Backspace;
исключать поля с автодополнением. Учесть задержку AX (таймаут 50 мс) и то, что в части приложений AX-значения нет —
там решить, fail-open или fail-closed. Ссылки — отчёт исследования в чате 2026-09-30.

## Progress

1. ✅ ScreenVerification (Core) + чистые тесты вердикта
2. ✅ InputEngine — стадия сверки
3. ✅ Coordinator + AppDelegate
4. ✅ Тесты пайплайна
5. ✅ Документация + ревью
6. ▶ Локальная матрица и включение enforce (macOS)
7. ✅ Автозамена: стирать слово, которое показывает поле (вердикт replaced)

## Log

- 2026-09-30: triage — pipeline `no-spec`, reason: исследование аналогов: самая частая жалоба (gпривет) — автодополнение/inline predictions/автозамена меняют поле, буфер ≠ текст; нужна AX-сверка перед эмиссией
- 2026-09-30: brainstorm (агент, пользователь делегировал выбор): сверка AX-текста перед кареткой перед эмиссией; selection → отмена, несовпадение → повтор 6×20 мс → отмена, unavailable → fail-open; без AXManualAccessibility; NBSP=пробел; критерий — тесты пайплайна + CI, ручная проверка в приложениях локально
- 2026-09-30: artifacts.plan = docs/plans/correction-verifies-field-text-before-deleting-plan.md; artifacts.branch = claude/beautiful-shannon-hg5k6h
- 2026-09-30: plan drafted
- 2026-09-30: plan-review (Plan, opus): принят; вердикт по эквивалентности той же длины (регистр, умные кавычки, NBSP), lagging vs mismatch, дедлайн 150 мс, FieldTextProbe с transient, без AXManualAccessibility, режим off/shadow/enforce (shadow по умолчанию до локальной матрицы), обход терминалов, пропуск для caretWord
- 2026-09-30: шаг 1 ✅ ScreenVerification (Core) + чистые тесты вердикта — ScreenVerification + FieldTextProbe, чистые тесты (проверит CI)
- 2026-09-30: шаг 2 ✅ InputEngine — стадия сверки — verifyScreen с дедлайном, emit, isCurrent, screenVerified
- 2026-09-30: шаг 3 ✅ Coordinator + AppDelegate — requestFieldText без AXManualAccessibility, режим SwitchFix_fieldTextCheck (shadow), обход терминалов
- 2026-09-30: шаг 4 ✅ Тесты пайплайна — ScreenStub + 7 сценариев пайплайна (проверит CI)
- 2026-09-30: code-review (субагент, opus): blocker — порядок аргументов в тестовом verdict() не компилировался; should-fix — shadow задерживал коррекцию ретраями (теперь одно чтение и эмиссия), пустое поле давало mismatch (теперь retry/unknown), тайминг тестов 0.4 с для позитивных (теперь 2 с); нит nonisolated в AppDelegate не взят — тот же паттерн, что у существующих замыканий
- 2026-09-30: verify: `CI красный: https://github.com/8ui/SwitchFix/actions/runs/36777848431 (eba69c1) — EmissionLog.isEmpty не существует в тестах; исправлено в 99d374a` → exit 1 ❌
- 2026-09-30: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36778002647 (99d374a) — InputPipelineTestRunner 1063/0, 8 новых сьютов screen check/verification` → exit 0 ✅
- 2026-09-30: шаг 5 ✅ Документация + ревью — ревью субагентом, CI зелёный
- 2026-09-30: impl complete; остался шаг 6 — локальная матрица в shadow и решение о enforce по умолчанию (macOS)
- 2026-10-01: verify: `Локальная матрица (macOS 27, сборка 3169092, enforce, синтетические HID-события с keyCode + computer use): TextEdit 9×match; Notes 11×match, 2×mismatch = настоящая автозамена руддщ→«Руда» (без сверки стёрла бы перевод строки); Telegram 3×match; хоткей (одиночный Option) match; Chrome омнибокс 2×unknown(unavailable) → fail-open. Ложных отмен на обычном наборе нет; остальные 5 mismatch — артефакт постера (второе слово того же процесса после переключения раскладки, буфер vbh / поле «мир»).` → exit 0 ✅
- 2026-10-01: шаг 6 ▶ Локальная матрица и включение enforce (macOS)
- 2026-10-01: шаг 6: матрица TextEdit/Notes/Telegram/хоткей в enforce — ложных отмен нет; Chrome-омнибокс unavailable; Safari/Chrome textarea не проверены (браузеры только на чтение). Локально SwitchFix_fieldTextCheck=enforce; решение о default ждёт пользователя
- 2026-10-01: Safari и Notes: автозамена (руддщ→«руда») до чтения поля → enforce отменяет, слово остаётся автозаменённым. Делаю вердикт replaced: стирать слово, которое показывает поле
- 2026-10-01: шаг 7 ▶ Автозамена: стирать слово, которое показывает поле (вердикт replaced)
- 2026-10-01: verify: `Локально: InputPipelineTestRunner 1090/0, TestRunner 603/0 (2ca5243)` → exit 0 ✅
- 2026-10-01: шаг 7 ✅ Автозамена: стирать слово, которое показывает поле (вердикт replaced) — ревью субагентом учтено; ждёт CI 36826731829 и повтор пользователя в Safari
- 2026-10-01: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36826731829 (2ca5243)` → exit 0 ✅
- 2026-10-01: verify: `Живая автозамена в Заметках: руддщ→«Руда», verdict=replaced(5) attempts=3 → «Hello» (сборка с 2ca5243)` → exit 0 ✅

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] Chrome-омнибокс подтверждён локально 2026-10-01: probe=unavailable (не transient) → fail-open, сверка gпривет там не ловит; альтернатива — выделение Shift+← (OpenKey), отдельная задача — переформулировано 2026-10-01
- [ ] undo/revert (TextCorrector.undo) удаляет correctedText+boundary без сверки поля — тот же класс бага
- [ ] hotkey/layoutSwitch при выделенной inline-подсказке идут в ветку .selection и конвертируют подсказку вместо слова
- [ ] путь layoutSwitch со сверкой не покрыт тестом (layoutSwitchPlans строит свой движок без screenTextRequest); layoutSwitch читает AX дважды (выделение + сверка)
- [x] Автозамена до коррекции (Notes: руддщ→«Руда»): сверка отменяет коррекцию, текст не портится, но в поле остаётся автозаменённое слово — можно стирать то, что показывает поле (длина слова из AX), и вставлять конверсию — закрыто 2026-10-01: d8fad9b+2ca5243: вердикт replaced
- [ ] Заметки, быстрый непрерывный набор (120 мс/символ): изредка пропадает пробел между исправленными словами (приветhello) при verdict=match у всех трёх коррекций — поле меняется между чтением и Backspace (TOCTOU); в начале нового абзаца probe=unavailable → fail-open и однажды съеден перевод строки

## Verification

- 2026-09-30 · `CI красный: https://github.com/8ui/SwitchFix/actions/runs/36777848431 (eba69c1) — EmissionLog.isEmpty не существует в тестах; исправлено в 99d374a` · exit 1 ❌

  ```
  (без вывода)
  ```

- 2026-09-30 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36778002647 (99d374a) — InputPipelineTestRunner 1063/0, 8 новых сьютов screen check/verification` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-10-01 · `Локальная матрица (macOS 27, сборка 3169092, enforce, синтетические HID-события с keyCode + computer use): TextEdit 9×match; Notes 11×match, 2×mismatch = настоящая автозамена руддщ→«Руда» (без сверки стёрла бы перевод строки); Telegram 3×match; хоткей (одиночный Option) match; Chrome омнибокс 2×unknown(unavailable) → fail-open. Ложных отмен на обычном наборе нет; остальные 5 mismatch — артефакт постера (второе слово того же процесса после переключения раскладки, буфер vbh / поле «мир»).` · exit 0 ✅

  ```
  verdict counts: TextEdit match 8 (att1 5, att2 3) · Notes match 11, mismatch 6 (2 autocorrect, 4 артефакт) · Telegram match 3 · Chrome unknown 2. Safari, textarea в Chrome, Slack, VS Code (в списке исключений) — не проверены: браузеры выданы computer use только на чтение.
  ```

- 2026-10-01 · `Локально: InputPipelineTestRunner 1090/0, TestRunner 603/0 (2ca5243)` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-10-01 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36826731829 (2ca5243)` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-10-01 · `Живая автозамена в Заметках: руддщ→«Руда», verdict=replaced(5) attempts=3 → «Hello» (сборка с 2ca5243)` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

**Сгенерировано:** 2026-09-30 · `rtp handoff`

- **Задача:** `2026-09-30-correction-verifies-field-text-before-deleting` — Correction leaves stray letters when the field changed the text (inline autocomplete, predictions, autocorrect)
- **Фаза:** review (pipeline `no-spec`, type `bug`)
- **Прогресс:** 5/6 ▰▰▰▰▰▱
- **Worktree:** `/home/user/SwitchFix`
- **Ветка:** `claude/beautiful-shannon-hg5k6h` — своих коммитов 83, отставание от origin/master 78
- **Незакоммиченного:** 2 файл(ов)

**Шаги плана**

1. ✅ ScreenVerification (Core) + чистые тесты вердикта
2. ✅ InputEngine — стадия сверки
3. ✅ Coordinator + AppDelegate
4. ✅ Тесты пайплайна
5. ✅ Документация + ревью
6. ▶ Локальная матрица и включение enforce (macOS)

**Файлы в работе**

- `ocs/tasks/2026-09-30-correction-verifies-field-text-before-deleting.md`
- `docs/tasks/index.md`

**git diff HEAD --stat**

```
...-correction-verifies-field-text-before-deleting.md | 19 ++++++++++++++-----
 docs/tasks/index.md                                   |  4 ++--
 2 files changed, 16 insertions(+), 7 deletions(-)
```

**Последние коммиты**

- `2fa1393 docs(tasks): record red CI run`
- `99d374a test(engine): EmissionLog has no isEmpty`
- `eba69c1 fix(engine): review fixes for the field-text check`

**Последние записи лога**

- 2026-09-30: code-review (субагент, opus): blocker — порядок аргументов в тестовом verdict() не компилировался; should-fix — shadow задерживал коррекцию ретраями (теперь одно чтение и эмиссия), пустое поле давало mismatch (теперь retry/unknown), тайминг тестов 0.4 с для позитивных (теперь 2 с); нит nonisolated в AppDelegate не взят — тот же паттерн, что у существующих замыканий
- 2026-09-30: verify: `CI красный: https://github.com/8ui/SwitchFix/actions/runs/36777848431 (eba69c1) — EmissionLog.isEmpty не существует в тестах; исправлено в 99d374a` → exit 1 ❌
- 2026-09-30: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36778002647 (99d374a) — InputPipelineTestRunner 1063/0, 8 новых сьютов screen check/verification` → exit 0 ✅
- 2026-09-30: шаг 5 ✅ Документация + ревью — ревью субагентом, CI зелёный
- 2026-09-30: impl complete; остался шаг 6 — локальная матрица в shadow и решение о enforce по умолчанию (macOS)

**Открытые долги (4)**

- Chrome/Electron без AX-дерева: фокус — контейнер → unavailable → fail-open; омнибокс Chrome может остаться непокрытым — проверить локально, альтернатива — выделение Shift+← (OpenKey), отдельная задача
- undo/revert (TextCorrector.undo) удаляет correctedText+boundary без сверки поля — тот же класс бага
- hotkey/layoutSwitch при выделенной inline-подсказке идут в ветку .selection и конвертируют подсказку вместо слова
- путь layoutSwitch со сверкой не покрыт тестом (layoutSwitchPlans строит свой движок без screenTextRequest); layoutSwitch читает AX дважды (выделение + сверка)

**Следующее действие**

- rtp verify по командам проекта (rtp next 2026-09-30-correction-verifies-field-text-before-deleting), затем ревью субагентом → rtp phase 2026-09-30-correction-verifies-field-text-before-deleting --to done

**Заметки агента** (не выводятся из кода — грабли, тупики, договорённости)

<!-- handoff-notes -->
- 2026-09-30: Режим по умолчанию shadow (SwitchFix_fieldTextCheck): enforce включать только после локальной матрицы. В логе искать 'screen check verdict=' (probe/attempts/ms/pid) и 'correction cancelled reason=screen-mismatch'. Главный вопрос матрицы — отдаёт ли Chrome-омнибокс что-то кроме unavailable без AX-дерева. shadow делает одно чтение без ретраев; lagging-логика работает только в enforce.
<!-- /handoff-notes -->

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
