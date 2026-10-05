---
id: 2026-10-05-debt-batch-kbdtype-switch-wiring-acronyms
title: "Debt batch: keyboard type from key events, layout-switch wiring tests, automatic acronym fallback"
type: chore
pipeline: minimal
phase: done
created: 2026-10-05
updated: 2026-10-05
blocked_by: null
steps_done: 4
steps_total: 4
step_current: null
artifacts:
  spec: null
  plan: null
  branch: claude/charming-clarke-8bf4te
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
3. ✅ Acronym fallback только для хоткея + eval
4. ✅ Ревью и CI

## Log

- 2026-10-05: triage — pipeline `minimal`, reason: три независимых долга малого объёма: тип клавиатуры из события tap-а (KeyboardMonitor/InputSourceManager/AppDelegate), тестируемая проводка finishLayoutSwitch (TextCorrector), acronym fallback только для хоткея (LayoutDetector, замер LayoutEval); ревью субагентом, CI
- 2026-10-05: brainstorm: что — 3 долга (см. Context); зачем — пользователь попросил ещё пачку; готово — тесты + CI + eval vs база; Enter-долг не взят: тихое переключение раскладки после отправки — продуктовое решение
- 2026-10-05: шаг 1 ✅ Тип клавиатуры из события tap-а + известные типы первыми — код, ждёт CI
- 2026-10-05: шаг 2 ✅ Тестируемая проводка finishLayoutSwitch — TextCorrector: очередь/frontmost/switcher инъекциями + тест
- 2026-10-05: verify: `код-ревью субагентом (ce6d884): блокер — тест проводки сравнивал rawValue 'ru'/'en', а у Layout 'russian'/'english'; should-fix: активация/смена источника пересобирали по LMGetKbdType (мог откатить таблицы), переводы монитора шли с LMGetKbdType, события чужого софта меняли тип (шторм пересборок), CLAUDE.md — всё исправлено в следующем коммите (запоминание последнего типа, только hidSystemState); принято: ГКД/ЗРЗ (английские аббревиатуры без гласных на русской раскладке) больше не исправляются автоматически — сверить в eval` → exit 1 ❌
- 2026-10-05: verify: `CI красный: https://github.com/8ui/SwitchFix/actions/runs/37289365842 (push ce6d884) — TestRunner 1176/0, InputPipelineTestRunner 1455/4: только 4 проверки нового теста проводки (rawValue 'ru' vs 'russian', найдено ревью; поведение верное — got [russian], [russian, english]); LayoutEval vs база 37288304994: см. Decisions; sweep: только строки T3 (FP 0.32→0.27, restored −0.07..−0.18 п.п.)` → exit 1 ❌
- 2026-10-05: шаг 3 ✅ Acronym fallback только для хоткея + eval — eval сравнён, компромисс в Decisions
- 2026-10-05: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/37289712125 (push 7ee2945; TestRunner 1176/0, InputPipelineTestRunner 1459/0, build-app); LayoutEval = ce6d884 (компромисс в Decisions)` → exit 0 ✅
- 2026-10-05: шаг 4 ✅ Ревью и CI — ревью учтено, CI 37289712125 зелёный
- 2026-10-05: artifacts.branch = claude/charming-clarke-8bf4te
- 2026-10-05: impl complete
- 2026-10-05: 3 долга закрыто (+1 переформулирован), CI 37289712125 зелёный, eval-компромисс в Decisions; PR не создавался

## Decisions

- Acronym fallback только по запросу (как английское правило капса): LayoutEval (ce6d884 vs f72524a) — ru FP 2-3 буквы 0.93%→0.41% (СМС, ДБ, НН, СК, ТВ больше не портятся; цель ≤0.5% выполнена), ценой en-on-ru restored 2-3 97.53%→96.18% (−23: PM, VI, II, UN, HR, ID — английские аббревиатуры без гласных в русской раскладке; en-on-uk −22), в предложениях −2 слова. Порча правильно набранной аббревиатуры хуже пропуска (хоткей исправит); различить ЗЬ/НДС по таблицам нельзя — PM/VI/II нет в ShortWordTable

## Debt

- [ ] английские аббревиатуры без гласных, набранные в русской/украинской раскладке (PM→ЗЬ, II→ШШ, UN→ГТ), больше не исправляются автоматически — только хоткеем (en-on-ru restored 2-3 −1.35 п.п.)
- [ ] смена типа клавиатуры на Mac вживую не проверена (внешняя ISO-клавиатура на ANSI-MacBook): пересборка по событию tap-а, только hidSystemState

## Verification

- 2026-10-05 · `код-ревью субагентом (ce6d884): блокер — тест проводки сравнивал rawValue 'ru'/'en', а у Layout 'russian'/'english'; should-fix: активация/смена источника пересобирали по LMGetKbdType (мог откатить таблицы), переводы монитора шли с LMGetKbdType, события чужого софта меняли тип (шторм пересборок), CLAUDE.md — всё исправлено в следующем коммите (запоминание последнего типа, только hidSystemState); принято: ГКД/ЗРЗ (английские аббревиатуры без гласных на русской раскладке) больше не исправляются автоматически — сверить в eval` · exit 1 ❌

  ```
  (без вывода)
  ```

- 2026-10-05 · `CI красный: https://github.com/8ui/SwitchFix/actions/runs/37289365842 (push ce6d884) — TestRunner 1176/0, InputPipelineTestRunner 1455/4: только 4 проверки нового теста проводки (rawValue 'ru' vs 'russian', найдено ревью; поведение верное — got [russian], [russian, english]); LayoutEval vs база 37288304994: см. Decisions; sweep: только строки T3 (FP 0.32→0.27, restored −0.07..−0.18 п.п.)` · exit 1 ❌

  ```
  (без вывода)
  ```

- 2026-10-05 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/37289712125 (push 7ee2945; TestRunner 1176/0, InputPipelineTestRunner 1459/0, build-app); LayoutEval = ce6d884 (компромисс в Decisions)` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
