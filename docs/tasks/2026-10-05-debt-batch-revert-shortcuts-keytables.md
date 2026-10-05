---
id: 2026-10-05-debt-batch-revert-shortcuts-keytables
title: "Debt batch: revert staleness mechanism test, shortcut refresh throttling, key table tests on ANSI/ISO, rebuild on keyboard type change"
type: chore
pipeline: minimal
phase: impl
created: 2026-10-05
updated: 2026-10-05
blocked_by: null
steps_done: 2
steps_total: 5
step_current: 3
artifacts:
  spec: null
  plan: null
  branch: null
  pr: null
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
3. ▶ Тесты KeyTableBuilder: dead keys, 10/50 на ANSI/ISO
4. ⬜ Пересборка таблиц при смене типа клавиатуры
5. ⬜ Ревью и CI

## Log

- 2026-10-05: triage — pipeline `minimal`, reason: четыре независимых долга малого объёма: тестовый seam исхода сверки поля (InputEngine), троттлинг refreshInputSourceShortcuts (KeyboardMonitor/AppDelegate), тесты KeyTableBuilder, пересборка таблиц по LMGetKbdType (InputSourceManager/AppDelegate); известная архитектура; ревью субагентом, CI
- 2026-10-05: brainstorm: что — 4 долга (см. Context); зачем — пользователь попросил закрыть следующую пачку; готово — тесты + CI зелёный + закрытые долги
- 2026-10-05: шаг 1 ✅ Seam исхода сверки поля + тест механизма отмены — seam screenCheckObserver + тесты (stale/refused), ждёт CI
- 2026-10-05: шаг 2 ✅ Троттлинг чтения хоткеев смены источника — ShortcutRefresh keep/ifStale/now + тест, ждёт CI

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
