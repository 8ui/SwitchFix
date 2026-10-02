---
id: 2026-10-02-readme-rewrite-independent-project
title: "README rewrite: independent project, no fork"
type: chore
pipeline: minimal
phase: done
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

_2-5 строк: что делаем и зачем. Задача этой секции — чтобы через N дней можно было восстановить контекст без чтения spec/plan._

## Progress

_Шаги не заданы. `rtp steps <id> --set "…"` или `--from-plan <файл>`._

## Log

- 2026-10-02: triage — pipeline `minimal`, reason: docs-only: README rewritten from scratch, no code
- 2026-10-02: README переписан с нуля на русском: без картинки, без раздела о форке и ссылок на rundax; SwitchFix.gif удалён
- 2026-10-02: только документация, CI не запускается (*.md)
- 2026-10-02: долг: новое название

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] новое название и бренд приложения — README пока оставлен с именем SwitchFix; переименование .app, bundle id com.switchfix.app, ключей SwitchFix_*, лог-подсистемы и скриптов — отдельная задача (сбросит разрешения и настройки пользователей)

## Verification

_Доказательства, а не утверждения. Заполняется `rtp verify <id> --run "<команда>"`: команда, exit code, хвост вывода._

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
