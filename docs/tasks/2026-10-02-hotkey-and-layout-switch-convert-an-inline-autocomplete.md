---
id: 2026-10-02-hotkey-and-layout-switch-convert-an-inline-autocomplete
title: Hotkey and layout-switch convert an inline autocomplete suggestion instead of the typed word
type: bug
pipeline: no-spec
phase: review
created: 2026-10-02
updated: 2026-10-02
blocked_by: null
steps_done: 5
steps_total: 6
step_current: 6
artifacts:
  spec: null
  plan: docs/plans/inline-suggestion-hotkey-layout-switch-plan.md
  branch: claude/eloquent-fermat-ha8bro
  pr: "https://github.com/8ui/SwitchFix/pull/13"
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
4. ✅ CI зелёный
5. ✅ Документация + ревью
6. ▶ Ручная проверка пользователем на Mac

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
- 2026-10-02: code-review (субагент, opus): блокеров нет; взято — строгий суффикс перед выделением (без фолбэка пропавшего пробела), selectionEmission для тестов ветки selection, waitUntil в layoutSwitchPlans, doc accept, имя теста; терминал и require без выделения — отмена, решения записаны
- 2026-10-02: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/37014978012 (0950868)` → exit 0 ✅
- 2026-10-02: шаг 4 ✅ CI зелёный — CI 37014978012 зелёный
- 2026-10-02: шаг 5 ✅ Документация + ревью — CLAUDE.md, plan-review и code-review субагентами
- 2026-10-02: impl complete; ждёт ручной проверки пользователем на Mac (шаг 6)
- 2026-10-02: шаг 6 ▶ Ручная проверка пользователем на Mac
- 2026-10-02: artifacts.pr = https://github.com/8ui/SwitchFix/pull/13
- 2026-10-02: verify: `ручная проверка на Mac (сборка 0950868, тестовое приложение с inline-подсказкой как в омнибоксе, реальные CGEvent, log stream): хоткей и ⌃Space в layoutSwitch` → exit 0 ✅

## Decisions

- Терминал (сверка обойдена, поле unavailable) с подсвеченным выделением и набранным словом: хоткей/Globe отменяются (require → mismatch) — безопасно; раньше вставлялась конверсия выделения, тоже неверно. В логе probe=unavailable.
- require + поле без выделения (подсказку убрали между чтениями) — отмена без повтора: консервативно, текст не портится.
- Вставка выделения вынесена в инжектируемый `selectionEmission`, чтобы тесты доказывали ветку selection, а не только отсутствие эмиссии.

## Debt

- [ ] Revert после коррекции с подсказкой: поле снова показывает подсказку → сверка revert видит выделение и отказывает (текст цел); можно принять с deleteCount+1
- [ ] Автоматическая коррекция при выделенной подсказке по-прежнему отменяется — можно применить то же правило

## Verification

- 2026-10-02 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/37014978012 (0950868)` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-10-02 · `ручная проверка на Mac (сборка 0950868, тестовое приложение с inline-подсказкой как в омнибоксе, реальные CGEvent, log stream): хоткей и ⌃Space в layoutSwitch` · exit 0 ✅

  ```
  до PR: Option в поле ghbdtn[.ru] → ghbdtnюкг (баг воспроизведён)
  хоткей: verdict=matchBeforeSelection(deleteCount: 7) → привет, раскладка RussianWin
  layoutSwitch + ⌃Space: с подсказкой → привет (deleteCount 7), без подсказки → привет (match); каждый сценарий ×2
  регрессии нет: обычное слово → привет; Cmd+A при пустом буфере → selection paste → привет; Cmd+V + хоткей → без изменений
  Safari/Chrome/Spotlight не проверены (браузеры недоступны агенту для ввода) — за пользователем
  TestRunner 632/0, InputPipelineTestRunner 1284/0 локально
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
