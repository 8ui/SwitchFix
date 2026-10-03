---
id: 2026-10-03-debt-batch-flags-brackets-suggestion
title: "Debt batch: transparent long flags, bracketed short word in context, inline suggestion for automatic correction and revert"
type: chore
pipeline: minimal
phase: done
created: 2026-10-03
updated: 2026-10-03
blocked_by: null
steps_done: 5
steps_total: 5
step_current: null
artifacts:
  spec: null
  plan: null
  branch: claude/admiring-mccarthy-6g7at7
  pr: null
---

## Context

Пачка открытых долгов из соседних задач:
1. 2026-10-03-debt-batch-flags-counters-adjacency: многобуквенные флаги (-la, -rf, --force) держит модель — они не прозрачны ('yf -la yf' не переключает).
2. 2026-09-30-check-upstream-develop-edge-cases-against-the-n-gram: правило B считает word.count с пунктуацией — 3-буквенное слово в скобке не удерживается контекстом.
3. 2026-10-02-hotkey-and-layout-switch-convert-an-inline-autocomplete: автоматическая коррекция при выделенной inline-подсказке отменяется — применить то же правило (стереть подсказку лишним Backspace).
4. Там же: откат после коррекции с подсказкой отказывает (сверка видит выделение) — принять с deleteCount+1.
Готово, когда: правки + тесты, CI зелёный на push-ране, LayoutEval сравнён с базой, долги в исходных задачах закрыты со ссылкой на эту.

## Progress

1. ✅ Прозрачные многобуквенные флаги
2. ✅ Короткое слово в скобке в контексте
3. ✅ Подсказка при автоматической коррекции
4. ✅ Подсказка при откате
5. ✅ Ревью, CI, eval

## Log

- 2026-10-03: triage — pipeline `minimal`, reason: четыре независимых долга: 2 правила детектора (LayoutDetector) и 2 режима выделения в сверке (InputEngine); известная архитектура, 2-3 файла кода + тесты; ревью субагентом, CI, LayoutEval против базы
- 2026-10-03: brainstorm: что — 4 долга (см. Context); зачем — пользователь попросил закрыть следующую пачку; готово — тесты + CI + eval vs база + закрытые долги
- 2026-10-03: шаг 1 ✅ Прозрачные многобуквенные флаги — код + тесты (a0a3417), ждёт CI
- 2026-10-03: шаг 2 ✅ Короткое слово в скобке в контексте — код + тесты (a0a3417), ждёт CI
- 2026-10-03: шаг 3 ✅ Подсказка при автоматической коррекции — код + тесты (a0a3417), ждёт CI
- 2026-10-03: шаг 4 ✅ Подсказка при откате — код + тесты (a0a3417), ждёт CI
- 2026-10-03: шаг 5 ▶ Ревью, CI, eval
- 2026-10-03: verify: `CI красный: https://github.com/8ui/SwitchFix/actions/runs/37130078051 (push a0a3417) — TestRunner зелёный, InputPipelineTestRunner 1435/1: 'timeouts are read again' (тайминг: 3 чтения не влезли в 150 мс, путь .unavailable не затронут) — тесту дан свой дедлайн 600 мс` → exit 1 ❌
- 2026-10-03: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/37130269102 (push 01fb8e9; TestRunner 687/0, InputPipelineTestRunner 1436/0, build-app); LayoutEval и threshold sweep (172 SWEEP-строки) совпадают с базой 37129456647 (e211b47 = master), кроме таймингов` → exit 0 ✅
- 2026-10-03: verify: `код-ревью субагентом (a0a3417): блокеров нет; should-fix — выделение, затем нечитаемое поле удаляло набранную длину (автоматика и откат теперь .accept) — исправлено sawSelection + тесты (578a633); nit-ы: сохранённый pendingSuppressedShort всегда nil — явный сброс + тест; устаревшее сообщение теста; формулировка CLAUDE.md; принято без правки: '-hello'/'-1' тоже прозрачны, '(еру)' и '-ghb' теперь низкой уверенности (без мгновенного переключения, как 'еру')` → exit 0 ✅
- 2026-10-03: verify: `CI зелёный после ревью: https://github.com/8ui/SwitchFix/actions/runs/37130535693 (push 578a633; TestRunner 688/0, InputPipelineTestRunner 1442/0, build-app); LayoutEval/sweep = база 37129456647` → exit 0 ✅
- 2026-10-03: шаг 5 ✅ Ревью, CI, eval — ревью учтено, CI 37130535693 зелёный, eval = база
- 2026-10-03: artifacts.branch = claude/admiring-mccarthy-6g7at7
- 2026-10-03: 4 долга закрыто, CI 37130535693 зелёный, eval = база; ветка claude/admiring-mccarthy-6g7at7, PR не создавался

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] автоматическая коррекция и откат с inline-подсказкой на Mac вживую не проверены (Safari/Chrome-омнибокс) — только тесты пайплайна
- [ ] прозрачны все '-слова' из ASCII-букв/цифр, оставленные моделью ('-hello', '-1'): в маркированных списках они больше не дают английского контекста — ревью, принято

## Verification

- 2026-10-03 · `CI красный: https://github.com/8ui/SwitchFix/actions/runs/37130078051 (push a0a3417) — TestRunner зелёный, InputPipelineTestRunner 1435/1: 'timeouts are read again' (тайминг: 3 чтения не влезли в 150 мс, путь .unavailable не затронут) — тесту дан свой дедлайн 600 мс` · exit 1 ❌

  ```
  (без вывода)
  ```

- 2026-10-03 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/37130269102 (push 01fb8e9; TestRunner 687/0, InputPipelineTestRunner 1436/0, build-app); LayoutEval и threshold sweep (172 SWEEP-строки) совпадают с базой 37129456647 (e211b47 = master), кроме таймингов` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-10-03 · `код-ревью субагентом (a0a3417): блокеров нет; should-fix — выделение, затем нечитаемое поле удаляло набранную длину (автоматика и откат теперь .accept) — исправлено sawSelection + тесты (578a633); nit-ы: сохранённый pendingSuppressedShort всегда nil — явный сброс + тест; устаревшее сообщение теста; формулировка CLAUDE.md; принято без правки: '-hello'/'-1' тоже прозрачны, '(еру)' и '-ghb' теперь низкой уверенности (без мгновенного переключения, как 'еру')` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-10-03 · `CI зелёный после ревью: https://github.com/8ui/SwitchFix/actions/runs/37130535693 (push 578a633; TestRunner 688/0, InputPipelineTestRunner 1442/0, build-app); LayoutEval/sweep = база 37129456647` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
