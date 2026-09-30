---
id: 2026-09-30-correction-verifies-field-text-before-deleting
title: "Correction leaves stray letters when the field changed the text (inline autocomplete, predictions, autocorrect)"
type: bug
pipeline: no-spec
phase: impl
created: 2026-09-30
updated: 2026-09-30
blocked_by: null
steps_done: 4
steps_total: 6
step_current: 5
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
5. ▶ Документация + ревью
6. ⬜ Локальная матрица и включение enforce (macOS)

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

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] Chrome/Electron без AX-дерева: фокус — контейнер → unavailable → fail-open; омнибокс Chrome может остаться непокрытым — проверить локально, альтернатива — выделение Shift+← (OpenKey), отдельная задача
- [ ] undo/revert (TextCorrector.undo) удаляет correctedText+boundary без сверки поля — тот же класс бага
- [ ] hotkey/layoutSwitch при выделенной inline-подсказке идут в ветку .selection и конвертируют подсказку вместо слова
- [ ] путь layoutSwitch со сверкой не покрыт тестом (layoutSwitchPlans строит свой движок без screenTextRequest); layoutSwitch читает AX дважды (выделение + сверка)

## Verification

- 2026-09-30 · `CI красный: https://github.com/8ui/SwitchFix/actions/runs/36777848431 (eba69c1) — EmissionLog.isEmpty не существует в тестах; исправлено в 99d374a` · exit 1 ❌

  ```
  (без вывода)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
