---
id: 2026-09-30-ax-manual-accessibility-screen-reader-side-effects
title: AXManualAccessibility stays on and switches apps into screen-reader mode
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

`AccessibilityFocusCoordinator.selectedText` и `caretContext` (Permissions.swift:362,385) ставят
`AXManualAccessibility = true` на приложение. Вызываются по требованию (AppDelegate.swift:61,69 — хоткей/выделение),
но атрибут после этого остаётся включённым до перезапуска приложения. Известные побочные эффекты: VS Code
переходит в режим скринридера (звуки, ломаются хоткеи Copilot — microsoft/vscode #196505), Chrome заметно
тяжелеет (Rectangle #1065), Qt/Telegram показывает баннер «включён скринридер» (PolterType #66), в части версий
Electron атрибут не поддерживается (electron #37465).
Сделать: воспроизвести в VS Code/Slack/Chrome; если подтверждается — ставить атрибут только если без него AX не
видит фокус, и/или снимать его обратно (false) после запроса; не ставить его не-Electron-приложениям.
Если задача `correction-verifies-field-text-before-deleting` начнёт читать AX на каждой коррекции, эта проблема
станет массовой — решать до неё или вместе.

## Progress

_Шаги не заданы. `rtp steps <id> --set "…"` или `--from-plan <файл>`._

## Log

- 2026-09-30: triage — pipeline `minimal`, reason: исследование: VS Code #196505 (режим скринридера), PolterType #66 (баннер в Telegram), нагрузка на Chrome

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
