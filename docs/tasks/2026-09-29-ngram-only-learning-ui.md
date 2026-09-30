---
id: 2026-09-29-ngram-only-learning-ui
title: "Удалить словари: n-gram единственный детектор, обучение на отменах, вкладка Слова, ползунок"
type: feature
pipeline: full
phase: done
created: 2026-09-29
updated: 2026-09-30
blocked_by: null
steps_done: 8
steps_total: 8
step_current: null
artifacts:
  spec: plan/005_ngram_layout_detection.md
  plan: docs/plans/ngram-only-learning-ui-plan.md
  branch: claude/epic-galileo-zq47ec
  pr: null
---

## Context

Продолжение plan/005 после Фаз 0–2 (eval-набор, триграммные модели, n-gram детектор за флагом — всё в ветке `claude/epic-galileo-zq47ec`, CI зелёный). Пользователь решил отказаться от словарей полностью: n-gram становится единственным детектором, модуль `Dictionary`, флаг `SwitchFix_detectionEngine` и сравнение движков удаляются. Затем — обучение на отменах (`PersonalLexicon`), вкладка «Слова» с полным CRUD и ползунок «Чувствительность» (plan/005 §4.5, §4.6). Цель — основной сценарий «родной текст + английские вставки» (сейчас n-gram: 92–98% смешанных сообщений полностью правильные, словарь 35–68%).

## Progress

1. ✅ удалить модуль `Dictionary` и словарный путь; n-gram — единственный детектор
2. ✅ `PersonalLexicon` — модель, хранение, CRUD, обучение (Core)
3. ✅ лексикон в детекторе
4. ✅ происхождение коррекции, обучение в `InputEngine`
5. ✅ вкладка «Слова» с полным CRUD
6. ✅ позиции чувствительности в `DetectionThresholds` и ползунок
7. ✅ перебор порогов, калибровка ползунка, защита от устаревших порогов
8. ✅ документация и Definition of Done

## Log

- 2026-09-29: triage — pipeline `full`, reason: Новая фича + удаление модуля Dictionary, >5 файлов (Core, UI, Package.swift, build-app.sh, тесты, L10n) → full. Спецификация — plan/005 (§4.5, §4.6, §10.5).
- 2026-09-29: artifacts.spec = plan/005_ngram_layout_detection.md; artifacts.branch = claude/epic-galileo-zq47ec
- 2026-09-29: brainstorm: что/зачем/критерии из plan/005 и ответов пользователя; решение удалить словари полностью — plan/005 §10.5
- 2026-09-29: spec = plan/005 (обновлён: §10.5, порядок фаз в §7); ждёт независимого ревью субагентом
- 2026-09-29: сессия 2: пользователь подтвердил preset full и порядок (1 удаление словарей → 2 PersonalLexicon → 3 вкладка «Слова» → 4 ползунок); spec отдан ревьюеру-субагенту
- 2026-09-29: spec-review (субагент general-purpose, свежий взгляд): 3 blocker + 10 major + 2 minor; все учтены в plan/005 §12 и §10.6, устаревший текст про флаг/переходный период исправлен
- 2026-09-29: artifacts.plan = docs/plans/ngram-only-learning-ui-plan.md
- 2026-09-29: план: docs/plans/ngram-only-learning-ui-plan.md, 8 шагов в 4 частях; факты сверены scratch-харнессом на Linux (2 из 51 старых проверок детектора падают на n-gram — вариант укр. раскладки и camelCase-фильтр на 'ершиЖ'; 'ghbftn' модель уже исправляет → фикстура 'rehk')
- 2026-09-29: plan-review (субагент Plan, свежий взгляд): 1 blocker (цифры в словах eviction-теста) + 5 major (ß в canBeTyped, дубли ключей L10n → CI-шаг, ru↔uk правила, O(n) пересборка индекса, ключ с завершающей пунктуацией) + minor — всё внесено в план
- 2026-09-29: verify: `CI зелёный (шаг 1, fa10cdf): https://github.com/8ui/SwitchFix/actions/runs/36558306033` → exit 0 ✅
- 2026-09-29: шаг 1 ✅ удалить модуль `Dictionary` и словарный путь; n-gram — единственный детектор — CI зелёный, run 36558306033
- 2026-09-29: шаг 2 ▶ `PersonalLexicon` — модель, хранение, CRUD, обучение (Core)
- 2026-09-29: шаг 2 ✅ `PersonalLexicon` — модель, хранение, CRUD, обучение (Core) — Linux-харнесс: 151/0; CI — вместе с шагом 4
- 2026-09-29: шаг 3 ▶ лексикон в детекторе
- 2026-09-29: шаг 3 ✅ лексикон в детекторе — Linux-харнесс 161/0
- 2026-09-29: шаг 4 ▶ происхождение коррекции, обучение в `InputEngine`
- 2026-09-29: verify: `CI зелёный (шаги 2–6, 234f49e): https://github.com/8ui/SwitchFix/actions/runs/36559220374` → exit 0 ✅
- 2026-09-29: шаг 4 ✅ происхождение коррекции, обучение в `InputEngine` — CI 36559220374; был красный прогон из-за гонки в тесте last-Cyrillic (исправлено drain)
- 2026-09-29: шаг 5 ✅ вкладка «Слова» с полным CRUD — CI 36559220374 (сборка UI); визуальная проверка на macOS — в долг
- 2026-09-29: verify: `CI зелёный (шаги 6–7, e1935c2): https://github.com/8ui/SwitchFix/actions/runs/36559786804` → exit 0 ✅
- 2026-09-29: шаг 6 ✅ позиции чувствительности в `DetectionThresholds` и ползунок — CI 36559786804
- 2026-09-29: шаг 7 ✅ перебор порогов, калибровка ползунка, защита от устаревших порогов — positions +4/+2/0/-2/-4; базовые пороги не менялись; thresholds_005.md
- 2026-09-29: шаг 8 ▶ документация и Definition of Done
- 2026-09-29: шаг 8 ✅ документация и Definition of Done — CLAUDE.md, README, plan/005 DoD
- 2026-09-29: impl complete: 8/8 шагов; code-review субагентом: 0 blocker, 3 major + 7 minor — все исправлены в c307b45
- 2026-09-29: security-review (субагент): уязвимостей с уверенностью ≥8 нет; secure-focus guards покрывают все пути обучения
- 2026-09-29: verify: `CI зелёный (после code-review, c307b45): https://github.com/8ui/SwitchFix/actions/runs/36560545031` → exit 0 ✅
- 2026-09-29: остаётся в review: нужна живая проверка вкладки «Слова» и ползунка на macOS пользователем (в облаке только сборка); код, тесты и доказательства CI готовы
- 2026-09-29: инструкция для ручной проверки на macOS: docs/testing/ngram-lexicon-manual-test.md
- 2026-09-30: verify: `Ручная проверка на macOS 27 (RussianWin + Australian, ISO kbd), сценарии A–G, 2026-09-29/30` → exit 0 ✅
- 2026-09-30: ручная проверка A–G пройдена; найденные баги вынесены в отдельные задачи; остаются debts (пороги по умолчанию, апостроф, аббревиатуры, выбор кириллицы) — закрыть в done по решению пользователя
- 2026-09-30: решение пользователя 2026-09-30: базовые пороги оставить до пересмотра по логам; закрыть задачу, открытые debts остаются в индексе, баги ручной проверки — в задачах 2026-09-30-*

## Decisions

- 2026-09-29: словари удаляются полностью, без переходного периода и без флага движка (решение пользователя; plan/005 §10.5).
- 2026-09-29: порядок работ — сначала удаление словарей и переход на n-gram, потом `PersonalLexicon` + вкладка «Слова» + ползунок.
- 2026-09-29: выученные слова хранятся открытым текстом, вкладка «Слова» — полный CRUD (plan/005 §10.3); ползунок — 5 положений, калибровка перебором порогов (§4.6, §10.4).
- 2026-09-29: preset `full` предложен агентом; пользователь явно не подтвердил (попросил передать работу в новую сессию) — подтвердить в начале следующей сессии.

## Debt

- [ ] LayoutMapper не знает клавишу украинского апострофа на macOS — слова с ' / ї / є частично недостижимы (п'ятницю, цієї); см. plan/benchmarks/detector_005_phase2.md
- [ ] Короткие русские аббревиатуры (СМС, РФ, шт) дают 0.93% ложных при цели ≤0.5% — кандидаты для фильтра/PersonalLexicon
- [ ] Все три раскладки без истории переключений: украинский уходит в русский (uk→en 73.65%) — нужна эвристика выбора кириллицы без истории
- [x] Цели §8 недобраны после Фазы 2 (uk родные после англ. 96.73%, ru FP≤3 0.93%, ru полнота 4–5 89.87%) — допуски и план в plan/005 §10.6 — закрыто 2026-09-29: plan/005 §10.6 — допуски приняты, DoD отмечен
- [x] Проверить вкладку «Слова» и ползунок «Чувствительность» вживую на macOS (в облаке только сборка в CI): таблица, сортировка, форма, удаление, сброс, перевод — закрыто 2026-09-30: ручная проверка 2026-09-30; недочёты → 2026-09-30-words-tab-live-match-counters-accessibility-labels-truncated
- [ ] Базовые пороги оставлены (решение пользователя 2026-09-30, thresholds_005.md); пересмотреть по реальным логам 'model decision' (info) — правило §4.6.2 рекомендует ниже (T4 3 вместо 8), но на шумной выборке — переформулировано 2026-09-30

## Verification

- 2026-09-29 · `CI зелёный (шаг 1, fa10cdf): https://github.com/8ui/SwitchFix/actions/runs/36558306033` · exit 0 ✅

  ```
  TestRunner 168 passed 0 failed; InputPipeline 858 passed 0 failed; build-app: Copied language model bundle (en, ru, uk); .app 3.3M
  ```

- 2026-09-29 · `CI зелёный (шаги 2–6, 234f49e): https://github.com/8ui/SwitchFix/actions/runs/36559220374` · exit 0 ✅

  ```
  все шаги success: L10n без дублей, build, TestRunner, InputPipelineTestRunner (включая 8 learning-сьютов), build-app
  ```

- 2026-09-29 · `CI зелёный (шаги 6–7, e1935c2): https://github.com/8ui/SwitchFix/actions/runs/36559786804` · exit 0 ✅

  ```
  L10n ok; build; TestRunner ok (checksum guard); Threshold sweep 24s, строки SWEEP совпадают с Linux-харнессом; InputPipeline 878 passed 0 failed; build-app ok, .app 3.8M
  ```

- 2026-09-29 · `CI зелёный (после code-review, c307b45): https://github.com/8ui/SwitchFix/actions/runs/36560545031` · exit 0 ✅

  ```
  conclusion success: L10n, build, TestRunner (+новые тесты лексикона), sweep, InputPipeline (+learning-тесты), build-app
  ```

- 2026-09-30 · `Ручная проверка на macOS 27 (RussianWin + Australian, ISO kbd), сценарии A–G, 2026-09-29/30` · exit 0 ✅

  ```
  A ✅ после 2 фиксов (Australian как English 126f5f3; таблицы клавиш из системы 83cc15c). B ✅ отмена→Не исправлять→keep→удаление. C ✅ хоткей учит, 1–2 символа не учит, Caps без отмены не учит. D ✅ кроме D2 (🌐 в режиме смены раскладки теряет слово → задача 2026-09-30-layout-switch-mode-…); D5 — неверный пример в инструкции, исправлен. E ✅ функции; недочёты: счётчики не обновляются вживую, нет AX-подписей кнопок, обрезаны заголовки → задача 2026-09-30-words-tab-…. F ✅ 5 позиций, неактивен вне автоматического режима, порог 7+ букв 9.0→1.0, 4–6 букв 12.0 на Осторожно, без перезапуска. G ✅ выделение туда-обратно, Telegram, Chrome, Claude, 🌐 не теряет нажатия, лексикон и ползунок переживают перезапуск.
  ```

## Handoff

**Сгенерировано:** 2026-09-30 · `rtp handoff`

- **Задача:** `2026-09-29-ngram-only-learning-ui` — Удалить словари: n-gram единственный детектор, обучение на отменах, вкладка Слова, ползунок
- **Фаза:** review (pipeline `full`, type `feature`)
- **Прогресс:** 8/8 ▰▰▰▰▰▰▰▰
- **Worktree:** `/Users/andrejsokolov/Desktop/projects/SwitchFix`
- **Ветка:** `claude/epic-galileo-zq47ec` — своих коммитов 46, отставание от origin/master 0
- **Незакоммиченного:** 1 файл(ов)

**Шаги плана**

1. ✅ удалить модуль `Dictionary` и словарный путь; n-gram — единственный детектор
2. ✅ `PersonalLexicon` — модель, хранение, CRUD, обучение (Core)
3. ✅ лексикон в детекторе
4. ✅ происхождение коррекции, обучение в `InputEngine`
5. ✅ вкладка «Слова» с полным CRUD
6. ✅ позиции чувствительности в `DetectionThresholds` и ползунок
7. ✅ перебор порогов, калибровка ползунка, защита от устаревших порогов
8. ✅ документация и Definition of Done

**Файлы в работе**

- `gitignore`

**git diff HEAD --stat**

```
.gitignore | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
```

**Последние коммиты**

- `27b84cc docs(testing): manual test results, corrected D5 example, automation notes`
- `b15ebf8 docs(tasks): Words tab findings from manual test E`
- `6e14366 docs(tasks): layout-switch Globe key bug`

**Последние записи лога**

- 2026-09-29: verify: `CI зелёный (после code-review, c307b45): https://github.com/8ui/SwitchFix/actions/runs/36560545031` → exit 0 ✅
- 2026-09-29: остаётся в review: нужна живая проверка вкладки «Слова» и ползунка на macOS пользователем (в облаке только сборка); код, тесты и доказательства CI готовы
- 2026-09-29: инструкция для ручной проверки на macOS: docs/testing/ngram-lexicon-manual-test.md
- 2026-09-30: verify: `Ручная проверка на macOS 27 (RussianWin + Australian, ISO kbd), сценарии A–G, 2026-09-29/30` → exit 0 ✅
- 2026-09-30: ручная проверка A–G пройдена; найденные баги вынесены в отдельные задачи; остаются debts (пороги по умолчанию, апостроф, аббревиатуры, выбор кириллицы) — закрыть в done по решению пользователя

**Открытые долги (4)**

- LayoutMapper не знает клавишу украинского апострофа на macOS — слова с ' / ї / є частично недостижимы (п'ятницю, цієї); см. plan/benchmarks/detector_005_phase2.md
- Короткие русские аббревиатуры (СМС, РФ, шт) дают 0.93% ложных при цели ≤0.5% — кандидаты для фильтра/PersonalLexicon
- Все три раскладки без истории переключений: украинский уходит в русский (uk→en 73.65%) — нужна эвристика выбора кириллицы без истории
- Базовые пороги: перебор по правилу §4.6.2 рекомендует ниже текущих (T4 3 вместо 8 и т. д., thresholds_005.md) — решение пользователя: оставить или сдвинуть «по умолчанию» к позиции 3; пересмотреть по логам 'model decision' (info)

**Следующее действие**

- rtp verify по командам проекта (rtp next 2026-09-29-ngram-only-learning-ui), затем ревью субагентом → rtp phase 2026-09-29-ngram-only-learning-ui --to done

**Заметки агента** (не выводятся из кода — грабли, тупики, договорённости)

<!-- handoff-notes -->
- 2026-09-29: Swift в облаке ставится вручную: curl download.swift.org swift-6.1.2 ubuntu24.04 → /opt/swift, PATH=/opt/swift/usr/bin. На Linux собираются только LanguageModel и ModelTrainer (Core/UI/App — AppKit/Carbon); Core и тесты проверяет только CI macOS (push в claude/** запускает CI, ~4 мин; логи — GitHub MCP get_job_logs, таблицы LayoutEval в хвосте лога TestRunner).
- 2026-09-29: Корпуса: scripts/fetch-corpora.sh (Leipzig/OPUS/github-docs, сверка scripts/corpora.sha256); обучение детерминировано, ModelTrainer train перегенерирует и ShortWordTable+Generated.swift. Быстрая оценка без macOS: .build/release/ModelTrainer eval / score.
- 2026-09-29: Удаление словарей затрагивает: Package.swift (Dictionary target), Core/LayoutDetector (словарный путь, WordValidator, import Dictionary), Core/DictionaryReadiness, AppDelegate.prepareDictionaries, build-app.sh (compile_dictionary, SFDICT2), scripts/compile_dictionary.swift, TestRunner (WordValidator/Bloom/Dictionary perf suites, enableTextFallbackForTesting), InputPipelineTestRunner ('missing dictionary seam' — AutomaticDictionaryReadiness), CLAUDE.md/README. Инварианты plan/003 (staleness guards в prepareCorrection/CorrectionPlan.isEligible) не трогать.
- 2026-09-29: Linux-харнесс для детектора/лексикона/LayoutEval/sweep: scratchpad/harness (Sources/Core — симлинки LayoutDetector/LayoutMapper/NgramScoring/PersonalLexicon, Harness — симлинки тестов TestRunner и LayoutEval, заглушка Utils.SwitchFixLog); после swift build: ln -sfn H_LanguageModel.resources .build/release/SwitchFix_LanguageModel.bundle; запускать из корня репо (--threshold-sweep ~40 с). InputEngine/UI на Linux не собираются — только CI. В SwiftUI-файлах Layout конфликтует с SwiftUI.Layout — использовать KeyboardLayout. security-review скиллу нужен origin/HEAD: git remote set-head origin master.
- 2026-09-30: 2026-09-30: ручная проверка A–G на macOS пройдена (rtp verify записан). Остаётся решение пользователя: перевести в done (найденные баги вынесены в задачи 2026-09-30-*) и что делать с порогами по умолчанию (debt). Инструкция docs/testing/ngram-lexicon-manual-test.md обновлена: D5, хоткеи, §5 про автоматизацию через osascript/AX. В .gitignore незакоммиченная случайная строка 'ghbdtn ' — не наша, не коммитить, сказать пользователю.
<!-- /handoff-notes -->

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
