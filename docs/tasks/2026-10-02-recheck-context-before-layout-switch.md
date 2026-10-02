---
id: 2026-10-02-recheck-context-before-layout-switch
title: Layout switch after a correction runs on main without rechecking the context
type: bug
pipeline: minimal
phase: impl
created: 2026-10-02
updated: 2026-10-02
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

После коррекции/отмены `TextCorrector.apply`/`undo` (`Sources/Core/TextCorrector.swift:193,293`) ставят `inputSourceManager.switchTo` в `DispatchQueue.main.async` без перепроверки контекста: если пользователь успел сменить приложение, раскладка переключится в нём. Upstream rundax 0fe6b7d перепроверяет `isPlanCurrent` + frontmost PID на main перед switchTo и в `performSelectionCorrection`.
Готово, когда: на main перед switchTo повторяется проверка (isEligible по свежему снимку + `NSWorkspace.frontmostApplication.pid == targetPID`), в selection-пути есть сверка frontmost; тест на устаревший контекст (переключения нет).

## Progress

1. ✅ Чистый предикат + перепроверка на main в apply/postUndo
2. ✅ Проверка frontmost в selection-пути
3. ▶ Тесты предиката, CI и ревью

## Log

- 2026-10-02: triage — pipeline `minimal`, reason: TextCorrector: apply/undo/selection — перепроверка isEligible и frontmost PID на main перед switchTo (upstream 0fe6b7d); один файл + тест
- 2026-10-02: brainstorm: пользователь одобрил перепроверку на main (isEligible по свежему снимку + frontmost PID) и чистый предикат для тестов
- 2026-10-02: шаг 1 ✅ Чистый предикат + перепроверка на main в apply/postUndo — mayFinishLayoutSwitch + finishLayoutSwitch на main
- 2026-10-02: шаг 2 ✅ Проверка frontmost в selection-пути — frontmost перед вставкой и перед switch после вставки

## Decisions

- На main проверяется контекст (pid, эпоха фокуса, appAllowed, secure) и frontmost, но не sequence/editGeneration: набор после коррекции не должен отменять переключение — следующие клавиши уже в новой раскладке; upstream isPlanCurrent здесь был бы регрессом для быстрого набора

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
