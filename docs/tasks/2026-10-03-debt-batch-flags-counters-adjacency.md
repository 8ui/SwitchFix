---
id: 2026-10-03-debt-batch-flags-counters-adjacency
title: "Debt batch: adjacency on mode change, lexicon counters on edit, long flags, transparent flag skip, revert fallback tests"
type: chore
pipeline: minimal
phase: done
created: 2026-10-03
updated: 2026-10-03
blocked_by: null
steps_done: 6
steps_total: 6
step_current: null
artifacts:
  spec: null
  plan: null
  branch: claude/brave-franklin-mgg4gy
  pr: null
---

## Context

Пачка открытых долгов из соседних задач:
1. merged-short-word (2026-09-30-merged-short-word…): `InputStateMachine.updatePreferences` сбрасывает смежность только при выключении, не при смене режима.
2. words-tab (2026-09-30-words-tab…): форма «Изменить» сохраняет снимок matchCount/lastMatchedAt и затирает срабатывания между открытием и Save.
3. check-upstream (2026-09-30-check-upstream…): многобуквенные флаги (-rf, -la, -xzf, --force) идут через модель.
4. digits (2026-10-02-digits-in-token-validation): нейтральный пропуск флага/индекса обнуляет pendingSwitch/consecutiveWrongCount — нужен прозрачный.
5. debt-batch (2026-10-02-debt-batch…): путь teaches:false (fallback хоткея отката) с выученным правилом не проверен.
Готово, когда: правки + тесты, CI зелёный на push-ране, LayoutEval сравнён с базой master, долги в исходных задачах закрыты со ссылкой на эту.

## Progress

1. ✅ Смежность при смене режима
2. ✅ Счётчики при правке записи
3. ✅ Многобуквенные флаги
4. ✅ Прозрачный пропуск флага/индекса
5. ✅ Тесты fallback отката с правилами
6. ✅ Ревью, CI, eval

## Log

- 2026-10-03: triage — pipeline `minimal`, reason: пять независимых мелких долгов (1-2 файла каждый, в основном тесты + локальные правила детектора), без новой архитектуры; ревью субагентом, CI и сравнение LayoutEval с базой
- 2026-10-03: brainstorm: что — 5 долгов (см. Context); зачем — пользователь попросил закрыть следующую пачку; готово — тесты + CI + eval vs база + закрытые долги
- 2026-10-03: шаг 1 ✅ Смежность при смене режима — InputStateMachine: смена режима сбрасывает wordFollowsFlush; тест в 'flush adjacency'
- 2026-10-03: шаг 2 ✅ Счётчики при правке записи — PersonalLexicon.update берёт счётчики из хранимой записи; тест
- 2026-10-03: verify: `до фикса: CI https://github.com/8ui/SwitchFix/actions/runs/37119332302 (push 268283c) — TestRunner 652/2: падает только прозрачный пропуск (флаг/индекс между 'yf yf'); многобуквенные флаги -rf -la -ltr -xzf -xvzf -avz --amend --force --force-with-lease уже остаются (модель), '-ghbdtn' → '-привет'` → exit 1 ❌
- 2026-10-03: шаг 3 ✅ Многобуквенные флаги — проверено CI: модель уже оставляет флаги; правило не расширено, тесты фиксируют поведение
- 2026-10-03: шаг 4 ✅ Прозрачный пропуск флага/индекса — detector: пропуск без сбросов; CI 37119420306 зелёный, LayoutEval/sweep = база 37027049646
- 2026-10-03: шаг 5 ✅ Тесты fallback отката с правилами — тест: fallback отката не трогает never/always правила
- 2026-10-03: impl complete: 4 правки + тесты; правило флагов не понадобилось
- 2026-10-03: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/37119420306 (push 4f09a8d; TestRunner 654/0); LayoutEval и threshold sweep совпадают с базой 37027049646 (кроме таймингов)` → exit 0 ✅
- 2026-10-03: verify: `код-ревью субагентом: блокеров нет; should-fix (прозрачность только для однобуквенных флагов) — комментарий сужен + долг; nit-ы: счётчики при переименовании обнуляются (26aeecf), serial — долг, пиннинг-тест помечен` → exit 0 ✅
- 2026-10-03: verify: `CI зелёный после правок ревью: https://github.com/8ui/SwitchFix/actions/runs/37119599598 (push 26aeecf; TestRunner 657/0, InputPipelineTestRunner 1386/0, build-app)` → exit 0 ✅
- 2026-10-03: шаг 6 ✅ Ревью, CI, eval — ревью учтено, CI зелёный
- 2026-10-03: 5 долгов закрыто, CI 37119599598 зелёный; ветка claude/brave-franklin-mgg4gy, PR не создавался
- 2026-10-03: artifacts.branch = claude/brave-franklin-mgg4gy

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] многобуквенные флаги (-rf, -la) держит модель, а не правило: они не прозрачны — сбрасывают подтверждение переключения и пишутся в контекст как .validCurrent ('yf -la yf' не переключает)
- [ ] пропуск флага/индекса тратит detectionSerial: отчёт noteCorrectionNotApplied о коррекции до флага уже не восстанавливает состояние переключения (окно ~150 мс) — ревью nit

## Verification

- 2026-10-03 · `до фикса: CI https://github.com/8ui/SwitchFix/actions/runs/37119332302 (push 268283c) — TestRunner 652/2: падает только прозрачный пропуск (флаг/индекс между 'yf yf'); многобуквенные флаги -rf -la -ltr -xzf -xvzf -avz --amend --force --force-with-lease уже остаются (модель), '-ghbdtn' → '-привет'` · exit 1 ❌

  ```
  (без вывода)
  ```

- 2026-10-03 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/37119420306 (push 4f09a8d; TestRunner 654/0); LayoutEval и threshold sweep совпадают с базой 37027049646 (кроме таймингов)` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-10-03 · `код-ревью субагентом: блокеров нет; should-fix (прозрачность только для однобуквенных флагов) — комментарий сужен + долг; nit-ы: счётчики при переименовании обнуляются (26aeecf), serial — долг, пиннинг-тест помечен` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-10-03 · `CI зелёный после правок ревью: https://github.com/8ui/SwitchFix/actions/runs/37119599598 (push 26aeecf; TestRunner 657/0, InputPipelineTestRunner 1386/0, build-app)` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
