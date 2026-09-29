---
id: 2026-09-29-key-tables-from-installed-keyboard-layouts
title: Key tables from installed keyboard layouts
type: bug
pipeline: full
phase: impl
created: 2026-09-29
updated: 2026-09-29
blocked_by: null
steps_done: 4
steps_total: 5
step_current: 5
artifacts:
  spec: docs/features/key-tables-from-installed-layouts-spec.md
  plan: docs/plans/key-tables-from-installed-layouts-plan.md
  branch: null
  pr: null
---

## Context

_2-5 строк: что делаем и зачем. Задача этой секции — чтобы через N дней можно было восстановить контекст без чтения spec/plan._

## Progress

1. ✅ Task 1: KeyTable types и .pc
2. ✅ Task 2: KeyTableBuilder + sanity
3. ✅ Task 3: InputSourceManager per-source tables
4. ✅ Task 4: замена UkrainianKeyboardVariant
5. ▶ Task 5: docs, сборка, ручная проверка

## Log

- 2026-09-29: triage — pipeline `full`, reason: >5 файлов Core+App, влияет на детектор; статичные PC-таблицы неверны для mac Russian/Ukrainian, British-PC, Shift+цифр
- 2026-09-29: brainstorm: пользователь выбрал таблицы из системы, full, убрать UkrainianKeyboardVariant
- 2026-09-29: artifacts.spec = docs/features/key-tables-from-installed-layouts-spec.md
- 2026-09-29: spec drafted
- 2026-09-29: spec-review (general-purpose opus): 3 blocker/7 major/6 minor учтены в ревизии 2; вне объёма → debt
- 2026-09-29: artifacts.plan = docs/plans/key-tables-from-installed-layouts-plan.md
- 2026-09-29: plan drafted (5 tasks)
- 2026-09-29: plan-review (Plan opus): C1 crash dict literal, C2 internal PCLayoutData, H1-H4, M2-M4 учтены
- 2026-09-29: шаг 1 ✅ Task 1: KeyTable types и .pc — 290 passed; .pc == static convert для всех пар
- 2026-09-29: шаг 2 ✅ Task 2: KeyTableBuilder + sanity — 533 passed; найдено: ISO-клавиша 10 дублирует ё в RussianWin, mac Ukrainian = legacy
- 2026-09-29: шаг 3 ✅ Task 3: InputSourceManager per-source tables — 536 passed, app builds
- 2026-09-29: шаг 4 ✅ Task 4: замена UkrainianKeyboardVariant — 533+886 passed; eval без изменений (кроме таймингов), sweep идентичен

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] Границы слова по физической клавише: № ? @ # $ % ^ & * обрывают слово — спека key-tables, вне объёма
- [ ] Перестраивать таблицы при смене типа клавиатуры (LMGetKbdType) — спека key-tables, вне объёма
- [ ] Report-only LayoutEval на реальных (не .pc) таблицах — спека key-tables M4
- [ ] Общий dependency-free таргет с ключевыми данными для Core и ModelTrainer — спека key-tables B2
- [ ] Автодетекция перебирает все таблицы исходной раскладки (US+Colemak/Dvorak): первая прошедшая порог побеждает — не измерено LayoutEval

## Verification

_Доказательства, а не утверждения. Заполняется `rtp verify <id> --run "<команда>"`: команда, exit code, хвост вывода._

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
