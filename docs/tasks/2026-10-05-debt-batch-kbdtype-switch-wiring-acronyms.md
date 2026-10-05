---
id: 2026-10-05-debt-batch-kbdtype-switch-wiring-acronyms
title: "Debt batch: keyboard type from key events, layout-switch wiring tests, automatic acronym fallback"
type: chore
pipeline: minimal
phase: impl
created: 2026-10-05
updated: 2026-10-05
blocked_by: null
steps_done: 2
steps_total: 4
step_current: 3
artifacts:
  spec: null
  plan: null
  branch: null
  pr: null
---

## Context

Пачка открытых долгов:
1. 2026-10-05-debt-batch-revert-shortcuts-keytables: таблицы по типу клавиатуры пересобираются только при активации/смене источника — первые слова на новой (ISO) клавиатуре идут по старым; keyboardType(physicalLayout:) берёт первый тип 0...255.
2. 2026-10-02-recheck-context-before-layout-switch: тест покрывает предикат mayFinishLayoutSwitch, но не проводку finishLayoutSwitch (main + TIS) и не токен вытеснения.
3. 2026-09-29-ngram-only-learning-ui: короткие русские аббревиатуры дают 0.93% ложных (СМС→CVC, НН→YY, СК→CR, ТВ→ND, ДБ→L<) — это automatic acronym fallback (капс без гласных ≤3 букв); сделать его только ручным, как английское правило аббревиатур.
Готово, когда: правки + тесты, CI зелёный, LayoutEval сравнён с базой (ru FP 2-3 и en-on-ru restored 2-3), долги закрыты/переформулированы.

## Progress

1. ✅ Тип клавиатуры из события tap-а + известные типы первыми
2. ✅ Тестируемая проводка finishLayoutSwitch
3. ▶ Acronym fallback только для хоткея + eval
4. ⬜ Ревью и CI

## Log

- 2026-10-05: triage — pipeline `minimal`, reason: три независимых долга малого объёма: тип клавиатуры из события tap-а (KeyboardMonitor/InputSourceManager/AppDelegate), тестируемая проводка finishLayoutSwitch (TextCorrector), acronym fallback только для хоткея (LayoutDetector, замер LayoutEval); ревью субагентом, CI
- 2026-10-05: brainstorm: что — 3 долга (см. Context); зачем — пользователь попросил ещё пачку; готово — тесты + CI + eval vs база; Enter-долг не взят: тихое переключение раскладки после отправки — продуктовое решение
- 2026-10-05: шаг 1 ✅ Тип клавиатуры из события tap-а + известные типы первыми — код, ждёт CI
- 2026-10-05: шаг 2 ✅ Тестируемая проводка finishLayoutSwitch — TextCorrector: очередь/frontmost/switcher инъекциями + тест
- 2026-10-05: verify: `код-ревью субагентом (ce6d884): блокер — тест проводки сравнивал rawValue 'ru'/'en', а у Layout 'russian'/'english'; should-fix: активация/смена источника пересобирали по LMGetKbdType (мог откатить таблицы), переводы монитора шли с LMGetKbdType, события чужого софта меняли тип (шторм пересборок), CLAUDE.md — всё исправлено в следующем коммите (запоминание последнего типа, только hidSystemState); принято: ГКД/ЗРЗ (английские аббревиатуры без гласных на русской раскладке) больше не исправляются автоматически — сверить в eval` → exit 1 ❌

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

_Отложенное, упрощения, известные пробелы. Формат — чекбоксы (их считают индекс и отчёты по долгам):_
_- `- [ ] <что отложено> — <почему/контекст>` — открытый долг_
_- `- [x] <что было> — закрыто YYYY-MM-DD: <причина/ссылка на task>` — закрытый_
_Без `[ ]`/`[x]` пункт невидим для агрегатора и теряется через 2 недели._

## Verification

- 2026-10-05 · `код-ревью субагентом (ce6d884): блокер — тест проводки сравнивал rawValue 'ru'/'en', а у Layout 'russian'/'english'; should-fix: активация/смена источника пересобирали по LMGetKbdType (мог откатить таблицы), переводы монитора шли с LMGetKbdType, события чужого софта меняли тип (шторм пересборок), CLAUDE.md — всё исправлено в следующем коммите (запоминание последнего типа, только hidSystemState); принято: ГКД/ЗРЗ (английские аббревиатуры без гласных на русской раскладке) больше не исправляются автоматически — сверить в eval` · exit 1 ❌

  ```
  (без вывода)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
