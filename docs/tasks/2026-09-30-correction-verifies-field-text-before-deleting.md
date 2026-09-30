---
id: 2026-09-30-correction-verifies-field-text-before-deleting
title: "Correction leaves stray letters when the field changed the text (inline autocomplete, predictions, autocorrect)"
type: bug
pipeline: no-spec
phase: impl
created: 2026-09-30
updated: 2026-09-30
blocked_by: null
steps_done: 5
steps_total: 7
step_current: 6
artifacts:
  spec: null
  plan: docs/plans/correction-verifies-field-text-plan.md
  branch: null
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

1. ✅ Вердикт FieldTextVerification + тесты
2. ✅ AX-чтение requestFieldText (verifyQueue)
3. ✅ InputEngine: проверка с дедлайном в prepareCorrection
4. ✅ Проводка AppDelegate + документация
5. ✅ Тесты движка
6. ▶ Ревью
7. ⬜ Ручная проверка: омнибокс, Spotlight, TextEdit с автокоррекцией, VS Code (локально)

## Log

- 2026-09-30: triage — pipeline `no-spec`, reason: исследование аналогов: самая частая жалоба (gпривет) — автодополнение/inline predictions/автозамена меняют поле, буфер ≠ текст; нужна AX-сверка перед эмиссией
- 2026-09-30: brainstorm: пользователь выбрал fail-open при недоступном AX и не включать AXManualAccessibility для проверки; критерий — тесты вердикта и движка + CI, ручная проверка в омнибоксе/Spotlight/TextEdit с автокоррекцией
- 2026-09-30: artifacts.plan = docs/plans/correction-verifies-field-text-plan.md
- 2026-09-30: plan drafted
- 2026-09-30: plan-review (Plan-агент): правило отставания AX-текста (префикс), выделение без текста = mismatch, дедлайн 40 мс, отдельная verifyQueue, нормализация регистра/кавычек, окно UTF-16, пропуск для слова с экрана
- 2026-09-30: шаг 1 ✅ Вердикт FieldTextVerification + тесты
- 2026-09-30: шаг 2 ✅ AX-чтение requestFieldText (verifyQueue)
- 2026-09-30: шаг 3 ✅ InputEngine: проверка с дедлайном в prepareCorrection
- 2026-09-30: шаг 4 ✅ Проводка AppDelegate + документация
- 2026-09-30: шаг 5 ✅ Тесты движка
- 2026-09-30: ревью (субагент): lagging перечитывается каждые 8 мс до появления границы (иначе автокоррекция на том же пробеле проскакивала); префикс ≥ половины слова; тест «клавиша во время чтения» теперь реально идёт через чтение; тест: слово с экрана не перечитывается; док-комментарий CaretContext на место

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] Ghost text (inline predictions macOS 14+, zsh-autosuggest) не в AXValue — не ловится; next после каретки в вердикте не используется
- [ ] Режим layoutSwitch: handleLayoutChange конвертирует любое выделение — может быть inline-подсказкой омнибокса; отдельная задача
- [ ] Если граница так и не появилась за 40 мс (занятое приложение или поле её съело), коррекция идёт fail-open и может стереть на символ больше/попасть до автокоррекции — принято ради отстающего AX Chromium — переформулировано 2026-09-30

## Verification

_Доказательства, а не утверждения. Заполняется `rtp verify <id> --run "<команда>"`: команда, exit code, хвост вывода._

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
