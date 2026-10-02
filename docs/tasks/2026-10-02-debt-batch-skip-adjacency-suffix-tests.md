---
id: 2026-10-02-debt-batch-skip-adjacency-suffix-tests
title: "Debt batch: transparent token skip, adjacency on mode change, suffix after correction, revert and layout-switch tests"
type: chore
pipeline: minimal
phase: done
created: 2026-10-02
updated: 2026-10-02
blocked_by: null
steps_done: 6
steps_total: 6
step_current: null
artifacts:
  spec: null
  plan: null
  branch: claude/elegant-lovelace-qzt32s
  pr: "https://github.com/8ui/SwitchFix/pull/17"
---

## Context

Следующая пачка открытых долгов из соседних задач:
1. digits-in-token-validation: нейтральный пропуск флага/индекса обнуляет consecutiveWrongCount/pendingSwitch — сделать прозрачным (только state=.buffering).
2. merged-short-word: updatePreferences сбрасывает смежность только при выключении, не при смене режима.
3. hotkey-converts-the-word-before-the-caret: применённая автокоррекция не обновляет ScreenSuffix — хоткей после неё не читает слово перед кареткой.
4. debt-batch-rtp-l10n (прошлая пачка): путь teaches:false (хоткей отката без отмены → конвертация) с выученным правилом не проверен.
5. correction-verifies-field-text: путь layoutSwitch со сверкой поля не покрыт тестом.
Готово, когда: правки + тесты, CI зелёный на push-ране, долги в исходных задачах закрыты со ссылкой на эту.

## Progress

1. ✅ Прозрачный пропуск флага/индекса в детекторе
2. ✅ Смежность сбрасывается при смене режима
3. ✅ ScreenSuffix после применённой автокоррекции
4. ✅ Тест: откат без отмены с выученным правилом (teaches:false)
5. ✅ Тест: layoutSwitch со сверкой поля
6. ✅ Ревью и CI

## Log

- 2026-10-02: triage — pipeline `minimal`, reason: пять независимых мелких долгов (1-2 файла каждый, в основном тесты), без новой архитектуры; ревью субагентом и CI
- 2026-10-02: brainstorm: что — 5 долгов (см. Context); зачем — пользователь попросил закрыть следующую пачку долгов; готово — тесты + CI + закрытые долги
- 2026-10-02: шаг 1 ✅ Прозрачный пропуск флага/индекса в детекторе — neutral-ветка оставляет только state=.buffering; тест yf / -r|w[1] / yf
- 2026-10-02: шаг 2 ✅ Смежность сбрасывается при смене режима — updatePreferences снимает wordFollowsFlush при смене режима; тест
- 2026-10-02: шаг 3 ✅ ScreenSuffix после применённой автокоррекции — ScreenSuffix.replaced + InputEngine.noteScreenCorrected; drainCorrection для теста
- 2026-10-02: шаг 4 ✅ Тест: откат без отмены с выученным правилом (teaches:false) — тест: fallback отката не трогает выученное правило
- 2026-10-02: шаг 5 ✅ Тест: layoutSwitch со сверкой поля — тест: mismatch, lag, unreadable, shadow в layoutSwitch
- 2026-10-02: impl complete: 5 правок/тестов; Swift проверит CI
- 2026-10-02: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/37065371507 (push a17f87d; build, TestRunner, sweep, InputPipelineTestRunner, build-app)` → exit 0 ✅
- 2026-10-02: verify: `код-ревью субагентом: блокеров нет; should-fix (своё переключение раскладки после коррекции стирало суффикс через updateContext) исправлен — generatedLayoutSwitched; нитпики (serial у прозрачного пропуска, doc drainCorrection) учтены` → exit 0 ✅
- 2026-10-02: verify: `CI зелёный после правок ревью: https://github.com/8ui/SwitchFix/actions/runs/37065872250 (push 93df46a)` → exit 0 ✅
- 2026-10-02: шаг 6 ✅ Ревью и CI — ревью учтено, CI зелёный
- 2026-10-02: artifacts.branch = claude/elegant-lovelace-qzt32s
- 2026-10-02: 5 долгов закрыто, CI 37065872250 зелёный; ветка claude/elegant-lovelace-qzt32s, PR не создавался
- 2026-10-02: artifacts.pr = https://github.com/8ui/SwitchFix/pull/17

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] суффикс следует за коррекцией, только если после неё ничего не обработано; клавиша между apply и уведомлением делает экран неизвестным (хоткей не сработает, текст цел)
- [ ] хоткей после автокоррекции + Backspace (конвертирует исправленное слово обратно) на Mac вживую не проверен

## Verification

- 2026-10-02 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/37065371507 (push a17f87d; build, TestRunner, sweep, InputPipelineTestRunner, build-app)` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-10-02 · `код-ревью субагентом: блокеров нет; should-fix (своё переключение раскладки после коррекции стирало суффикс через updateContext) исправлен — generatedLayoutSwitched; нитпики (serial у прозрачного пропуска, doc drainCorrection) учтены` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-10-02 · `CI зелёный после правок ревью: https://github.com/8ui/SwitchFix/actions/runs/37065872250 (push 93df46a)` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
