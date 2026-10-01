---
id: 2026-10-01-a-replacement-first-seen-at-the-field-check-deadline-is
title: A replacement first seen at the field-check deadline is cancelled instead of confirmed (flaky CI)
type: bug
pipeline: minimal
phase: done
created: 2026-10-01
updated: 2026-10-01
blocked_by: null
steps_done: 3
steps_total: 3
step_current: null
artifacts:
  spec: null
  plan: null
  branch: claude/replaced-confirm-after-deadline
  pr: "https://github.com/8ui/SwitchFix/pull/11"
---

## Context

_2-5 строк: что делаем и зачем. Задача этой секции — чтобы через N дней можно было восстановить контекст без чтения spec/plan._

## Progress

1. ✅ Тест на замену на дедлайне
2. ✅ Исправление + unknown после замены
3. ✅ Ревью и CI

## Log

- 2026-10-01: triage — pipeline `minimal`, reason: 1 файл кода + тест; CI 85aa658 упал на 'a field that lags, then autocorrects' — три чтения не уложились в 150 мс
- 2026-10-01: шаг 1 ✅ Тест на замену на дедлайне — воспроизведено: 3 FAIL
- 2026-10-01: шаг 2 ✅ Исправление + unknown после замены — 1107/0 дважды
- 2026-10-01: замена на дедлайне получает одно подтверждающее чтение; unknown после увиденной замены отменяет
- 2026-10-01: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36874278871 (728a7be)` → exit 0 ✅
- 2026-10-01: ревью субагентом: замена забывалась на пути retry (AX-таймаут между чтениями) → флаг sawReplacement переживает retry; отдельная причина в логе; негативные тесты ждут второго чтения. 1111/0 ×3
- 2026-10-01: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36874858640 (b3b5045)` → exit 0 ✅
- 2026-10-01: шаг 3 ✅ Ревью и CI — ревью учтено, CI зелёный
- 2026-10-01: artifacts.branch = claude/replaced-confirm-after-deadline; artifacts.pr = https://github.com/8ui/SwitchFix/pull/11
- 2026-10-01: PR 8ui/SwitchFix#11 влит; релиз v0.0.14

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

_Отложенное, упрощения, известные пробелы. Формат — чекбоксы (их считают индекс и отчёты по долгам):_
_- `- [ ] <что отложено> — <почему/контекст>` — открытый долг_
_- `- [x] <что было> — закрыто YYYY-MM-DD: <причина/ссылка на task>` — закрытый_
_Без `[ ]`/`[x]` пункт невидим для агрегатора и теряется через 2 недели._

## Verification

- 2026-10-01 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36874278871 (728a7be)` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-10-01 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36874858640 (b3b5045)` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
