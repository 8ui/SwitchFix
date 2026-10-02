---
id: 2026-10-02-hotkey-and-layout-switch-convert-an-inline-autocomplete
title: Hotkey and layout-switch convert an inline autocomplete suggestion instead of the typed word
type: bug
pipeline: no-spec
phase: plan-review
created: 2026-10-02
updated: 2026-10-02
blocked_by: null
steps_done: 0
steps_total: 0
step_current: null
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

_Шаги не заданы. `rtp steps <id> --set "…"` или `--from-plan <файл>`._

## Log

- 2026-10-02: triage — pipeline `no-spec`, reason: 4-5 файлов (InputEngine, ScreenVerification, Permissions, TextCorrector, тесты), известная архитектура сверки; неочевидна реализация стирания подсказки и проверки текста перед выделением
- 2026-10-02: brainstorm (пользователь): при непустом буфере выделение = подсказка приложения; стереть её одним Backspace и исправить слово из буфера; сверка проверяет текст перед выделением, иначе отмена; оба пути (хоткей и layoutSwitch); готово = тесты + CI + проверка пользователем в Safari/Chrome/Spotlight
- 2026-10-02: artifacts.plan = docs/plans/inline-suggestion-hotkey-layout-switch-plan.md; artifacts.branch = claude/eloquent-fermat-ha8bro
- 2026-10-02: plan drafted

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
