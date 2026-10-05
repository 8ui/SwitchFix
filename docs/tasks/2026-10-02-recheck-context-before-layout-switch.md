---
id: 2026-10-02-recheck-context-before-layout-switch
title: Layout switch after a correction runs on main without rechecking the context
type: bug
pipeline: minimal
phase: done
created: 2026-10-02
updated: 2026-10-05
blocked_by: null
steps_done: 3
steps_total: 3
step_current: null
artifacts:
  spec: null
  plan: null
  branch: null
  pr: "https://github.com/8ui/SwitchFix/pull/12"
---

## Context

После коррекции/отмены `TextCorrector.apply`/`undo` (`Sources/Core/TextCorrector.swift:193,293`) ставят `inputSourceManager.switchTo` в `DispatchQueue.main.async` без перепроверки контекста: если пользователь успел сменить приложение, раскладка переключится в нём. Upstream rundax 0fe6b7d перепроверяет `isPlanCurrent` + frontmost PID на main перед switchTo и в `performSelectionCorrection`.
Готово, когда: на main перед switchTo повторяется проверка (isEligible по свежему снимку + `NSWorkspace.frontmostApplication.pid == targetPID`), в selection-пути есть сверка frontmost; тест на устаревший контекст (переключения нет).

## Progress

1. ✅ Чистый предикат + перепроверка на main в apply/postUndo
2. ✅ Проверка frontmost в selection-пути
3. ✅ Тесты предиката, CI и ревью

## Log

- 2026-10-02: triage — pipeline `minimal`, reason: TextCorrector: apply/undo/selection — перепроверка isEligible и frontmost PID на main перед switchTo (upstream 0fe6b7d); один файл + тест
- 2026-10-02: brainstorm: пользователь одобрил перепроверку на main (isEligible по свежему снимку + frontmost PID) и чистый предикат для тестов
- 2026-10-02: шаг 1 ✅ Чистый предикат + перепроверка на main в apply/postUndo — mayFinishLayoutSwitch + finishLayoutSwitch на main
- 2026-10-02: шаг 2 ✅ Проверка frontmost в selection-пути — frontmost перед вставкой и перед switch после вставки
- 2026-10-02: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36991085388 (push dd11ce7 включает ba1f61a; новый сьют 'layout switch after a correction: rechecked on main')` → exit 0 ✅
- 2026-10-02: verify: `CI зелёный после правок ревью: https://github.com/8ui/SwitchFix/actions/runs/36991541543 (push 7f18ea8; TestRunner 613/0, InputPipelineTestRunner 1173/0)` → exit 0 ✅
- 2026-10-02: verify: `код-ревью субагентом: блокеров нет; should-fix (вытеснение старого переключения) и тестовые замечания исправлены в 7f18ea8` → exit 0 ✅
- 2026-10-02: шаг 3 ✅ Тесты предиката, CI и ревью
- 2026-10-02: impl + ревью + CI; остаётся в review до merge ветки
- 2026-10-02: artifacts.pr = https://github.com/8ui/SwitchFix/pull/12
- 2026-10-02: merged in PR 12 (f180995)

## Decisions

- На main проверяется контекст (pid, эпоха фокуса, appAllowed, secure) и frontmost, но не sequence/editGeneration: набор после коррекции не должен отменять переключение — следующие клавиши уже в новой раскладке; upstream isPlanCurrent здесь был бы регрессом для быстрого набора

## Debt

- [x] тест покрывает предикат mayFinishLayoutSwitch, но не проводку finishLayoutSwitch (main + TIS) и не токен вытеснения — закрыто 2026-10-05: 2026-10-05-debt-batch-kbdtype-switch-wiring-acronyms

## Verification

- 2026-10-02 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36991085388 (push dd11ce7 включает ba1f61a; новый сьют 'layout switch after a correction: rechecked on main')` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-10-02 · `CI зелёный после правок ревью: https://github.com/8ui/SwitchFix/actions/runs/36991541543 (push 7f18ea8; TestRunner 613/0, InputPipelineTestRunner 1173/0)` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-10-02 · `код-ревью субагентом: блокеров нет; should-fix (вытеснение старого переключения) и тестовые замечания исправлены в 7f18ea8` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
