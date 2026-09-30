---
id: 2026-09-30-typed-text-in-debug-log
title: Typed words are written to the debug log as public values
type: bug
pipeline: minimal
phase: triage
created: 2026-09-30
updated: 2026-09-30
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

Набранный текст попадает в unified log: `InputEngine.swift:320,322` (`buffer '…' (+ '…')`), `LayoutDetector`
(`mixed scripts, skipping '<word>'`, `common short word '<word>'`, `camelCase identifier '<word>'` и др.), при
этом CLAUDE.md говорит «every message … with public values». debug-уровень не сохраняется по умолчанию, но
`log stream --level debug` видит его любой локальный админ-процесс, а `log config` может включить сохранение.
Аналог: gswitch #6 — debug-режим писал нажатия и выделение на диск, пользователи назвали это кейлоггером; история
«дневника» Punto — главный аргумент против таких программ.
Сделать: не логировать содержимое буфера/слов как public — либо `privacy: .private`, либо логировать только
длину/хэш и решение; оставить возможность включить текст явно (флаг defaults) для отладки. Обновить раздел
Debugging в CLAUDE.md, если поменяется поведение.

## Progress

_Шаги не заданы. `rtp steps <id> --set "…"` или `--from-plan <файл>`._

## Log

- 2026-09-30: triage — pipeline `minimal`, reason: исследование: gswitch #6 — debug-лог как кейлоггер; InputEngine/LayoutDetector пишут слова с public-приватностью

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
