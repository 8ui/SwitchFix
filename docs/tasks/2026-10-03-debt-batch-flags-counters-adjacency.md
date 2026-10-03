---
id: 2026-10-03-debt-batch-flags-counters-adjacency
title: "Debt batch: adjacency on mode change, lexicon counters on edit, long flags, transparent flag skip, revert fallback tests"
type: chore
pipeline: minimal
phase: impl
created: 2026-10-03
updated: 2026-10-03
blocked_by: null
steps_done: 2
steps_total: 6
step_current: 3
artifacts:
  spec: null
  plan: null
  branch: null
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
3. ▶ Многобуквенные флаги
4. ⬜ Прозрачный пропуск флага/индекса
5. ⬜ Тесты fallback отката с правилами
6. ⬜ Ревью, CI, eval

## Log

- 2026-10-03: triage — pipeline `minimal`, reason: пять независимых мелких долгов (1-2 файла каждый, в основном тесты + локальные правила детектора), без новой архитектуры; ревью субагентом, CI и сравнение LayoutEval с базой
- 2026-10-03: brainstorm: что — 5 долгов (см. Context); зачем — пользователь попросил закрыть следующую пачку; готово — тесты + CI + eval vs база + закрытые долги
- 2026-10-03: шаг 1 ✅ Смежность при смене режима — InputStateMachine: смена режима сбрасывает wordFollowsFlush; тест в 'flush adjacency'
- 2026-10-03: шаг 2 ✅ Счётчики при правке записи — PersonalLexicon.update берёт счётчики из хранимой записи; тест

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
