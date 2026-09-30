---
id: 2026-09-30-ax-manual-accessibility-screen-reader-side-effects
title: AXManualAccessibility stays on and switches apps into screen-reader mode
type: bug
pipeline: minimal
phase: impl
created: 2026-09-30
updated: 2026-09-30
blocked_by: null
steps_done: 2
steps_total: 4
step_current: 3
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

1. ✅ Условное включение + отложенное выключение
2. ✅ Документация
3. ▶ Ревью
4. ⬜ Ручная проверка VS Code/Slack/Chrome/Telegram (локально)

## Log

- 2026-09-30: triage — pipeline `minimal`, reason: исследование: VS Code #196505 (режим скринридера), PolterType #66 (баннер в Telegram), нагрузка на Chrome
- 2026-09-30: brainstorm: воспроизвести в облаке нельзя (нет macOS); делаем безопасную часть: атрибут только если без него фокус не виден, выключаем через 30 с после последнего запроса и при выходе, не трогаем, если его включил кто-то другой; критерий — CI + ручная проверка VS Code/Slack/Chrome/Telegram (локально)
- 2026-09-30: шаг 1 ✅ Условное включение + отложенное выключение
- 2026-09-30: шаг 2 ✅ Документация

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] Первый запрос после включения ждёт дерево до 150 мс (3 × 50 мс на queryQueue); проверить локально на Electron, хватает ли — переформулировано 2026-09-30

## Verification

_Доказательства, а не утверждения. Заполняется `rtp verify <id> --run "<команда>"`: команда, exit code, хвост вывода._

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
