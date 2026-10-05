---
id: 2026-10-05-debt-batch-revert-shortcuts-keytables
title: "Debt batch: revert staleness mechanism test, shortcut refresh throttling, key table tests on ANSI/ISO, rebuild on keyboard type change"
type: chore
pipeline: minimal
phase: done
created: 2026-10-05
updated: 2026-10-05
blocked_by: null
steps_done: 5
steps_total: 5
step_current: null
artifacts:
  spec: null
  plan: null
  branch: claude/charming-clarke-8bf4te
  pr: "https://github.com/8ui/SwitchFix/pull/21"
---

## Context

Пачка открытых долгов из соседних задач:
1. 2026-10-02-revert-verifies-field-text: тест 'staleness during the read' проверяет исход, не механизм — повторную проверку после чтения дублирует applyRevert.
2. 2026-10-02-layout-switch-shortcuts-not-navigation: refreshInputSourceShortcuts на main при каждой активации и смене источника без троттлинга; коррекция со сменой раскладки обновляет дважды.
3. 2026-09-29-key-tables-from-installed-keyboard-layouts: тесты KeyTableBuilder без проверки пропуска dead keys; 'system tables agree' пропускает клавиши 10/50 (ё/ґ на 50 не покрыты на ANSI).
4. Там же: таблицы не перестраиваются при смене типа клавиатуры (LMGetKbdType).
Готово, когда: правки + тесты, CI зелёный на push-ране, долги в исходных задачах закрыты со ссылкой на эту.

## Progress

1. ✅ Seam исхода сверки поля + тест механизма отмены
2. ✅ Троттлинг чтения хоткеев смены источника
3. ✅ Тесты KeyTableBuilder: dead keys, 10/50 на ANSI/ISO
4. ✅ Пересборка таблиц при смене типа клавиатуры
5. ✅ Ревью и CI

## Log

- 2026-10-05: triage — pipeline `minimal`, reason: четыре независимых долга малого объёма: тестовый seam исхода сверки поля (InputEngine), троттлинг refreshInputSourceShortcuts (KeyboardMonitor/AppDelegate), тесты KeyTableBuilder, пересборка таблиц по LMGetKbdType (InputSourceManager/AppDelegate); известная архитектура; ревью субагентом, CI
- 2026-10-05: brainstorm: что — 4 долга (см. Context); зачем — пользователь попросил закрыть следующую пачку; готово — тесты + CI зелёный + закрытые долги
- 2026-10-05: шаг 1 ✅ Seam исхода сверки поля + тест механизма отмены — seam screenCheckObserver + тесты (stale/refused), ждёт CI
- 2026-10-05: шаг 2 ✅ Троттлинг чтения хоткеев смены источника — ShortcutRefresh keep/ifStale/now + тест, ждёт CI
- 2026-10-05: verify: `CI красный: https://github.com/8ui/SwitchFix/actions/runs/37287983485 (push 0a0ca8a) — сборка ок, TestRunner 1158/1: новый тест ANSI RussianWin Shift+50 ждал 'Ё', система даёт латинскую 'Ë' (санитайзер её убирает, 'Ё' на другой клавише); остальные 10/50 на ANSI совпали с .pc (ё, ґ/Ґ), round-trip ок, dead keys ок` → exit 1 ❌
- 2026-10-05: шаг 3 ✅ Тесты KeyTableBuilder: dead keys, 10/50 на ANSI/ISO — тесты 10/50 ANSI/ISO + dead keys
- 2026-10-05: шаг 4 ✅ Пересборка таблиц при смене типа клавиатуры — refreshIfKeyboardTypeChanged при активации/смене источника
- 2026-10-05: verify: `код-ревью субагентом (0a0ca8a): блокеров нет, маппинг исходов verifyScreen без регресса, тест ловит удаление повторной проверки; should-fix: уведомление после своего переключения всё равно перечитывало хоткеи (.ifStale) — теперь .keep; dead-key тест зависел от клавиатуры машины — явный ANSI; ANSI Shift+50 — исправлено в 1451bf3; nit-ы: round-trip без проверки клавиши, CLAUDE.md — исправлено в f72524a; не правлено: keyboardType(physicalLayout:) берёт первый тип из 0...255 (тест прошёл, покрытие ANSI реальное: ё/ґ на 50)` → exit 0 ✅
- 2026-10-05: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/37288304994 (push f72524a; TestRunner 1168/0, InputPipelineTestRunner 1455/0, build-app); новые сьюты 10/50 ANSI/ISO и dead keys отработали без SKIP` → exit 0 ✅
- 2026-10-05: шаг 5 ✅ Ревью и CI — ревью учтено, CI 37288304994 зелёный
- 2026-10-05: artifacts.branch = claude/charming-clarke-8bf4te
- 2026-10-05: impl complete
- 2026-10-05: 4 долга закрыто, CI 37288304994 зелёный; ветка claude/charming-clarke-8bf4te, PR не создавался
- 2026-10-05: artifacts.pr = https://github.com/8ui/SwitchFix/pull/21

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [x] пересборка таблиц по типу клавиатуры срабатывает только при активации приложения или смене источника: первые слова, набранные на новой (ISO) клавиатуре до этого, идут по старым таблицам; на Mac вживую не проверено — закрыто 2026-10-05: 2026-10-05-debt-batch-kbdtype-switch-wiring-acronyms
- [x] KeyTableBuilder.keyboardType(physicalLayout:) берёт первый тип 0...255 с нужной раскладкой — не обязательно реальный USB-тип (ревью, nit) — закрыто 2026-10-05: 2026-10-05-debt-batch-kbdtype-switch-wiring-acronyms

## Verification

- 2026-10-05 · `CI красный: https://github.com/8ui/SwitchFix/actions/runs/37287983485 (push 0a0ca8a) — сборка ок, TestRunner 1158/1: новый тест ANSI RussianWin Shift+50 ждал 'Ё', система даёт латинскую 'Ë' (санитайзер её убирает, 'Ё' на другой клавише); остальные 10/50 на ANSI совпали с .pc (ё, ґ/Ґ), round-trip ок, dead keys ок` · exit 1 ❌

  ```
  (без вывода)
  ```

- 2026-10-05 · `код-ревью субагентом (0a0ca8a): блокеров нет, маппинг исходов verifyScreen без регресса, тест ловит удаление повторной проверки; should-fix: уведомление после своего переключения всё равно перечитывало хоткеи (.ifStale) — теперь .keep; dead-key тест зависел от клавиатуры машины — явный ANSI; ANSI Shift+50 — исправлено в 1451bf3; nit-ы: round-trip без проверки клавиши, CLAUDE.md — исправлено в f72524a; не правлено: keyboardType(physicalLayout:) берёт первый тип из 0...255 (тест прошёл, покрытие ANSI реальное: ё/ґ на 50)` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-10-05 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/37288304994 (push f72524a; TestRunner 1168/0, InputPipelineTestRunner 1455/0, build-app); новые сьюты 10/50 ANSI/ISO и dead keys отработали без SKIP` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
