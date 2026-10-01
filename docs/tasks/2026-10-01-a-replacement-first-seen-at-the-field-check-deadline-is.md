---
id: 2026-10-01-a-replacement-first-seen-at-the-field-check-deadline-is
title: A replacement first seen at the field-check deadline is cancelled instead of confirmed (flaky CI)
type: bug
pipeline: minimal
phase: review
created: 2026-10-01
updated: 2026-10-01
blocked_by: null
steps_done: 2
steps_total: 3
step_current: 3
artifacts:
  spec: null
  plan: null
  branch: null
  pr: null
---

## Context

_2-5 строк: что делаем и зачем. Задача этой секции — чтобы через N дней можно было восстановить контекст без чтения spec/plan._

## Progress

1. ✅ Тест на замену на дедлайне
2. ✅ Исправление + unknown после замены
3. ▶ Ревью и CI

## Log

- 2026-10-01: triage — pipeline `minimal`, reason: 1 файл кода + тест; CI 85aa658 упал на 'a field that lags, then autocorrects' — три чтения не уложились в 150 мс
- 2026-10-01: шаг 1 ✅ Тест на замену на дедлайне — воспроизведено: 3 FAIL
- 2026-10-01: шаг 2 ✅ Исправление + unknown после замены — 1107/0 дважды
- 2026-10-01: замена на дедлайне получает одно подтверждающее чтение; unknown после увиденной замены отменяет

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
