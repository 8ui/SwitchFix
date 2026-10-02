---
id: 2026-10-02-ci-odin-zapusk-na-kommit-s-kodom-testy-v-relize
title: "CI: один запуск на коммит с кодом, тесты в релизе"
type: chore
pipeline: minimal
phase: done
created: 2026-10-02
updated: 2026-10-02
blocked_by: null
steps_done: 4
steps_total: 4
step_current: null
artifacts:
  spec: null
  plan: null
  branch: null
  pr: null
---

## Context

_2-5 строк: что делаем и зачем. Задача этой секции — чтобы через N дней можно было восстановить контекст без чтения spec/plan._

## Progress

1. ✅ ci.yml: триггеры и paths-ignore
2. ✅ release.yml: тесты перед сборкой
3. ✅ CLAUDE.md
4. ✅ Ревью и проверка CI

## Log

- 2026-10-02: triage — pipeline `minimal`, reason: 2 workflow-файла + CLAUDE.md, без кода приложения
- 2026-10-02: brainstorm в чате: что — убрать дубли CI (push master, pull_request), расширить paths-ignore, тесты в release.yml; зачем — 2-3 запуска на коммит; готово — один push-ран на коммит с кодом в claude/**, релиз гоняет тесты
- 2026-10-02: шаг 1 ✅ ci.yml: триггеры и paths-ignore
- 2026-10-02: шаг 2 ✅ release.yml: тесты перед сборкой
- 2026-10-02: шаг 3 ✅ CLAUDE.md
- 2026-10-02: impl complete
- 2026-10-02: review (general-purpose, opus): medium — PR с docs-only head без галочки, формулировка исправлена; low — тесты на Intel впервые в релизе, edge cases paths-filter приняты
- 2026-10-02: PR https://github.com/8ui/SwitchFix/pull/15; master влит (конфликт только в index.md). На push ветки — только push-раны, pull_request-рана нет. Ждём зелёный CI 37024845906
- 2026-10-02: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/37024845906 (push, 4319da1); pull_request-ранов нет, прогон 7f08632 отменён следующим push` → exit 0 ✅
- 2026-10-02: шаг 4 ✅ Ревью и проверка CI
- 2026-10-02: CI зелёный, PR #15 открыт, мёрж за пользователем

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [x] Проверка L10n продублирована в ci.yml и release.yml — вынести в скрипт, если начнут расходиться — закрыто 2026-10-02: 2026-10-02-debt-batch-rtp-l10n-terminals-tests

## Verification

- 2026-10-02 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/37024845906 (push, 4319da1); pull_request-ранов нет, прогон 7f08632 отменён следующим push` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
