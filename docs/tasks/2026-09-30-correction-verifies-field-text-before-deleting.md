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

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

_Отложенное, упрощения, известные пробелы. Формат — чекбоксы (их считают индекс и отчёты по долгам):_
_- `- [ ] <что отложено> — <почему/контекст>` — открытый долг_
_- `- [x] <что было> — закрыто YYYY-MM-DD: <причина/ссылка на task>` — закрытый_
_Без `[ ]`/`[x]` пункт невидим для агрегатора и теряется через 2 недели._

## Verification

_Доказательства, а не утверждения. Заполняется `rtp verify <id> --run "<команда>"`: команда, exit code, хвост вывода._

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
