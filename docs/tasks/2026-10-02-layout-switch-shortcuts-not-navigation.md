---
id: 2026-10-02-layout-switch-shortcuts-not-navigation
title: Ctrl-Space and other layout-switch shortcuts are classified as navigation
type: bug
pipeline: no-spec
phase: triage
created: 2026-10-02
updated: 2026-10-02
blocked_by: null
steps_done: 0
steps_total: 0
step_current: null
artifacts:
  spec: null
  plan: null
  branch: null
  pr: null
---

## Context

`KeyboardMonitor.classify` приватный и без тестов; особый случай смены раскладки есть только для Globe (keyCode 179). Ctrl-Space / Ctrl-Option-Space и другие системные хоткеи смены источника классифицируются как навигация, поэтому режим «по переключению» теряет слово (долг из 2026-09-30-layout-switch-mode-loses-the-word…), а регресс 179 пройдёт незаметно.
Готово, когда: classify — чистая тестируемая функция, системные хоткеи смены источника (из symbolic hotkeys или Ctrl-Space по умолчанию) не сбрасывают слово как навигация; тесты в InputPipelineTestRunner.

## Progress

_Шаги не заданы. `rtp steps <id> --set "…"` или `--from-plan <файл>`._

## Log

- 2026-10-02: triage — pipeline `no-spec`, reason: вынести KeyboardMonitor.classify в чистую тестируемую функцию + распознавать системные хоткеи смены источника; KeyboardMonitor + тесты

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
