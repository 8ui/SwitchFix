---
id: 2026-10-02-debt-batch-rtp-l10n-terminals-tests
title: "Debt batch: rtp verify hints, L10n script, terminals, flaky revert test, learning and adjacency tests"
type: chore
pipeline: minimal
phase: review
created: 2026-10-02
updated: 2026-10-02
blocked_by: null
steps_done: 6
steps_total: 7
step_current: 7
artifacts:
  spec: null
  plan: null
  branch: null
  pr: null
---

## Context

Пачка открытых долгов из соседних задач, каждый закрывается одной-двумя правками:
1. rtp (2026-09-29-rtp-generalize): verify с неверным timeout отбрасывается целиком; подсказка для команды, начинающейся с `--`, ломается в parseArgs.
2. CI (2026-10-02-ci-odin-zapusk…): проверка дублей L10n продублирована в ci.yml и release.yml → `scripts/check-l10n.sh`.
3. hotkey-reads (2026-10-02-hotkey-reads…): терминалы вне списка (Hyper, Tabby, …) читаются после клика.
4. hotkey-reads: нестабильный тест 'revert screen check: a field still applying the correction is read again' — нужен инжектируемый дедлайн сверки.
5. learning (2026-10-02-learning-revert…): нет теста, что отмена hotkey сохраняет выученное правило с другой целью.
6. merged-short-word (2026-09-30-merged-short-word…): unit-тест смежности не покрывает остальные события сброса.
Готово, когда: правки + тесты, regress.sh rtp зелёный, CI зелёный на push-ране, долги в исходных задачах закрыты со ссылкой на эту.

## Progress

1. ✅ rtp: мягкий timeout и подсказка --run=
2. ✅ scripts/check-l10n.sh в обоих workflow
3. ✅ Терминалы без чтения поля
4. ✅ Инжектируемый дедлайн сверки + тест отката
5. ✅ Тест: отмена hotkey сохраняет правило с другой целью
6. ✅ Тесты сброса смежности в InputStateMachine
7. ▶ Ревью и CI

## Log

- 2026-10-02: triage — pipeline `minimal`, reason: шесть независимых мелких долгов (по 1-2 файла каждый, в основном тесты), без новой архитектуры; ревью субагентом и CI
- 2026-10-02: brainstorm: что — 6 долгов (см. Context); зачем — пользователь попросил закрыть следующую пачку долгов; готово — тесты + CI + закрытые долги
- 2026-10-02: шаг 1 ✅ rtp: мягкий timeout и подсказка --run= — regress 164/0
- 2026-10-02: шаг 2 ✅ scripts/check-l10n.sh в обоих workflow — скрипт ловит дубль (проверено вставкой), ci.yml и release.yml вызывают его
- 2026-10-02: шаг 3 ✅ Терминалы без чтения поля — Hyper, Tabby, Rio, Wave
- 2026-10-02: шаг 4 ✅ Инжектируемый дедлайн сверки + тест отката — InputEngine(screenCheckDeadline:), тест с дедлайном 2 с
- 2026-10-02: шаг 5 ✅ Тест: отмена hotkey сохраняет правило с другой целью
- 2026-10-02: шаг 6 ✅ Тесты сброса смежности в InputStateMachine
- 2026-10-02: impl complete: 6 правок, regress rtp 164/0; Swift проверит CI
- 2026-10-02: verify: `sh .claude/skills/run-task-pipeline/scripts/regress.sh 2>&1 | tail -1` → exit 0 ✅
- 2026-10-02: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/37026412225 (push 80f9efb; build, TestRunner, sweep, InputPipelineTestRunner, build-app)` → exit 0 ✅

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

_Отложенное, упрощения, известные пробелы. Формат — чекбоксы (их считают индекс и отчёты по долгам):_
_- `- [ ] <что отложено> — <почему/контекст>` — открытый долг_
_- `- [x] <что было> — закрыто YYYY-MM-DD: <причина/ссылка на task>` — закрытый_
_Без `[ ]`/`[x]` пункт невидим для агрегатора и теряется через 2 недели._

## Verification

- 2026-10-02 · `sh .claude/skills/run-task-pipeline/scripts/regress.sh 2>&1 | tail -1` · exit 0 ✅

  ```
  итог (все секции): PASS=164 FAIL=0
  ```

- 2026-10-02 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/37026412225 (push 80f9efb; build, TestRunner, sweep, InputPipelineTestRunner, build-app)` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
