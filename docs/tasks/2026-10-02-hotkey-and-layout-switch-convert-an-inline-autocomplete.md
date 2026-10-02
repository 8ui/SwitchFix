---
id: 2026-10-02-hotkey-and-layout-switch-convert-an-inline-autocomplete
title: Hotkey and layout-switch convert an inline autocomplete suggestion instead of the typed word
type: bug
pipeline: no-spec
phase: impl
created: 2026-10-02
updated: 2026-10-02
blocked_by: null
steps_done: 3
steps_total: 6
step_current: 4
artifacts:
  spec: null
  plan: docs/plans/inline-suggestion-hotkey-layout-switch-plan.md
  branch: claude/eloquent-fermat-ha8bro
  pr: null
---

## Context

Поле с inline-автодополнением (омнибокс Safari/Chrome, Spotlight) показывает `ya[ndex.ru]` с выделенным хвостом.
Хоткей (`requestManualCorrection`) и режим layoutSwitch (`handleLayoutChange`) видят непустое AX-выделение и идут в ветку
selection: конвертируют подсказку вставкой вместо набранного слова. Пока буфер не пуст, выделение сделано не пользователем
(стрелки, Shift+стрелки, Cmd+A, клик сбрасывают буфер), поэтому при непустом буфере выделение — подсказка: стереть её одним
Backspace и исправить слово из буфера, если текст перед выделением кончается этим словом; иначе отмена.
Долг из 2026-09-30-correction-verifies-field-text-before-deleting.

## Progress

1. ✅ Probe и вердикт (Utils, ScreenVerification)
2. ✅ InputEngine: режим выделения, хоткей, layoutSwitch
3. ✅ Тесты пайплайна и вердикта
4. ▶ CI зелёный
5. ⬜ Документация + ревью
6. ⬜ Ручная проверка пользователем на Mac

## Log

- 2026-10-02: triage — pipeline `no-spec`, reason: 4-5 файлов (InputEngine, ScreenVerification, Permissions, TextCorrector, тесты), известная архитектура сверки; неочевидна реализация стирания подсказки и проверки текста перед выделением
- 2026-10-02: brainstorm (пользователь): при непустом буфере выделение = подсказка приложения; стереть её одним Backspace и исправить слово из буфера; сверка проверяет текст перед выделением, иначе отмена; оба пути (хоткей и layoutSwitch); готово = тесты + CI + проверка пользователем в Safari/Chrome/Spotlight
- 2026-10-02: artifacts.plan = docs/plans/inline-suggestion-hotkey-layout-switch-plan.md; artifacts.branch = claude/eloquent-fermat-ha8bro
- 2026-10-02: plan drafted
- 2026-10-02: plan-review (Plan, opus): принят с поправками — fail-closed при увиденном выделении (B1), только enforce, payload в вердикте, только хвост, transient retry, лог без текста, порядок в handleLayoutChange, тесты через layoutSwitchPlans; revert и автоматика — в долг
- 2026-10-02: шаг 1 ▶ Probe и вердикт (Utils, ScreenVerification)
- 2026-10-02: шаг 1 ✅ Probe и вердикт (Utils, ScreenVerification) — FieldTextProbe.selection(before:atTextStart:) только для хвоста; вердикт matchBeforeSelection, ScreenSelectionHandling refuse/accept/require
- 2026-10-02: шаг 2 ▶ InputEngine: режим выделения, хоткей, layoutSwitch
- 2026-10-02: шаг 2 ✅ InputEngine: режим выделения, хоткей, layoutSwitch — только enforce; require при проигнорированном выделении, accept для хоткея/layoutSwitch; лог без текста
- 2026-10-02: шаг 3 ▶ Тесты пайплайна и вердикта
- 2026-10-02: шаг 3 ✅ Тесты пайплайна и вердикта — вердикт (20 проверок), хоткей (7 сценариев), автоматика, layoutSwitch через layoutSwitchPlans (5)
- 2026-10-02: шаг 4 ▶ CI зелёный

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] Revert после коррекции с подсказкой: поле снова показывает подсказку → сверка revert видит выделение и отказывает (текст цел); можно принять с deleteCount+1
- [ ] Автоматическая коррекция при выделенной подсказке по-прежнему отменяется — можно применить то же правило

## Verification

_Доказательства, а не утверждения. Заполняется `rtp verify <id> --run "<команда>"`: команда, exit code, хвост вывода._

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
