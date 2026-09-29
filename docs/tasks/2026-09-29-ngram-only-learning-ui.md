---
id: 2026-09-29-ngram-only-learning-ui
title: "Удалить словари: n-gram единственный детектор, обучение на отменах, вкладка Слова, ползунок"
type: feature
pipeline: full
phase: plan-review
created: 2026-09-29
updated: 2026-09-29
blocked_by: null
steps_done: 0
steps_total: 0
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

_Шаги не заданы. `rtp steps <id> --set "…"` или `--from-plan <файл>`._

## Log

- 2026-09-29: triage — pipeline `full`, reason: Новая фича + удаление модуля Dictionary, >5 файлов (Core, UI, Package.swift, build-app.sh, тесты, L10n) → full. Спецификация — plan/005 (§4.5, §4.6, §10.5).
- 2026-09-29: artifacts.spec = plan/005_ngram_layout_detection.md; artifacts.branch = claude/epic-galileo-zq47ec
- 2026-09-29: brainstorm: что/зачем/критерии из plan/005 и ответов пользователя; решение удалить словари полностью — plan/005 §10.5
- 2026-09-29: spec = plan/005 (обновлён: §10.5, порядок фаз в §7); ждёт независимого ревью субагентом
- 2026-09-29: сессия 2: пользователь подтвердил preset full и порядок (1 удаление словарей → 2 PersonalLexicon → 3 вкладка «Слова» → 4 ползунок); spec отдан ревьюеру-субагенту
- 2026-09-29: spec-review (субагент general-purpose, свежий взгляд): 3 blocker + 10 major + 2 minor; все учтены в plan/005 §12 и §10.6, устаревший текст про флаг/переходный период исправлен
- 2026-09-29: artifacts.plan = docs/plans/ngram-only-learning-ui-plan.md
- 2026-09-29: план: docs/plans/ngram-only-learning-ui-plan.md, 8 шагов в 4 частях; факты сверены scratch-харнессом на Linux (2 из 51 старых проверок детектора падают на n-gram — вариант укр. раскладки и camelCase-фильтр на 'ершиЖ'; 'ghbftn' модель уже исправляет → фикстура 'rehk')

## Decisions

- 2026-09-29: словари удаляются полностью, без переходного периода и без флага движка (решение пользователя; plan/005 §10.5).
- 2026-09-29: порядок работ — сначала удаление словарей и переход на n-gram, потом `PersonalLexicon` + вкладка «Слова» + ползунок.
- 2026-09-29: выученные слова хранятся открытым текстом, вкладка «Слова» — полный CRUD (plan/005 §10.3); ползунок — 5 положений, калибровка перебором порогов (§4.6, §10.4).
- 2026-09-29: preset `full` предложен агентом; пользователь явно не подтвердил (попросил передать работу в новую сессию) — подтвердить в начале следующей сессии.

## Debt

- [ ] LayoutMapper не знает клавишу украинского апострофа на macOS — слова с ' / ї / є частично недостижимы (п'ятницю, цієї); см. plan/benchmarks/detector_005_phase2.md
- [ ] Короткие русские аббревиатуры (СМС, РФ, шт) дают 0.93% ложных при цели ≤0.5% — кандидаты для фильтра/PersonalLexicon
- [ ] Все три раскладки без истории переключений: украинский уходит в русский (uk→en 73.65%) — нужна эвристика выбора кириллицы без истории
- [ ] Цели §8 недобраны после Фазы 2 (uk родные после англ. 96.73%, ru FP≤3 0.93%, ru полнота 4–5 89.87%) — допуски и план в plan/005 §10.6

## Verification

_Доказательства, а не утверждения. Заполняется `rtp verify <id> --run "<команда>"`: команда, exit code, хвост вывода._

## Handoff

**Сгенерировано:** 2026-09-29 · `rtp handoff`

- **Задача:** `2026-09-29-ngram-only-learning-ui` — Удалить словари: n-gram единственный детектор, обучение на отменах, вкладка Слова, ползунок
- **Фаза:** spec-review (pipeline `full`, type `feature`)
- **Worktree:** `/home/user/SwitchFix`
- **Ветка:** `claude/epic-galileo-zq47ec` — своих коммитов 12, отставание от origin/master 0
- **Незакоммиченного:** 2 файл(ов)

**Файлы в работе**

- `ocs/tasks/2026-09-29-ngram-only-learning-ui.md`
- `docs/tasks/index.md`

**git diff HEAD --stat**

```
docs/tasks/2026-09-29-ngram-only-learning-ui.md | 51 ++++++++++++++++++++++++-
 docs/tasks/index.md                             |  2 +-
 2 files changed, 51 insertions(+), 2 deletions(-)
```

**Последние коммиты**

- `b5c3393 docs(plan): drop the dictionary engine entirely; track next phase in rtp`
- `b5410ae Merge remote-tracking branch 'origin/master' into claude/epic-galileo-zq47ec`
- `9ab1ff6 docs(plan): record n-gram vs dictionary detector results (plan 005 phase 2)`

**Последние записи лога**

- 2026-09-29: triage — pipeline `full`, reason: Новая фича + удаление модуля Dictionary, >5 файлов (Core, UI, Package.swift, build-app.sh, тесты, L10n) → full. Спецификация — plan/005 (§4.5, §4.6, §10.5).
- 2026-09-29: artifacts.spec = plan/005_ngram_layout_detection.md; artifacts.branch = claude/epic-galileo-zq47ec
- 2026-09-29: brainstorm: что/зачем/критерии из plan/005 и ответов пользователя; решение удалить словари полностью — plan/005 §10.5
- 2026-09-29: spec = plan/005 (обновлён: §10.5, порядок фаз в §7); ждёт независимого ревью субагентом

**Открытые долги (3)**

- LayoutMapper не знает клавишу украинского апострофа на macOS — слова с ' / ї / є частично недостижимы (п'ятницю, цієї); см. plan/benchmarks/detector_005_phase2.md
- Короткие русские аббревиатуры (СМС, РФ, шт) дают 0.93% ложных при цели ≤0.5% — кандидаты для фильтра/PersonalLexicon
- Все три раскладки без истории переключений: украинский уходит в русский (uk→en 73.65%) — нужна эвристика выбора кириллицы без истории

**Следующее действие**

- дать spec независимому субагенту-ревьюеру, потом rtp phase 2026-09-29-ngram-only-learning-ui --to plan

**Заметки агента** (не выводятся из кода — грабли, тупики, договорённости)

<!-- handoff-notes -->
- 2026-09-29: Swift в облаке ставится вручную: curl download.swift.org swift-6.1.2 ubuntu24.04 → /opt/swift, PATH=/opt/swift/usr/bin. На Linux собираются только LanguageModel и ModelTrainer (Core/UI/App — AppKit/Carbon); Core и тесты проверяет только CI macOS (push в claude/** запускает CI, ~4 мин; логи — GitHub MCP get_job_logs, таблицы LayoutEval в хвосте лога TestRunner).
- 2026-09-29: Корпуса: scripts/fetch-corpora.sh (Leipzig/OPUS/github-docs, сверка scripts/corpora.sha256); обучение детерминировано, ModelTrainer train перегенерирует и ShortWordTable+Generated.swift. Быстрая оценка без macOS: .build/release/ModelTrainer eval / score.
- 2026-09-29: Удаление словарей затрагивает: Package.swift (Dictionary target), Core/LayoutDetector (словарный путь, WordValidator, import Dictionary), Core/DictionaryReadiness, AppDelegate.prepareDictionaries, build-app.sh (compile_dictionary, SFDICT2), scripts/compile_dictionary.swift, TestRunner (WordValidator/Bloom/Dictionary perf suites, enableTextFallbackForTesting), InputPipelineTestRunner ('missing dictionary seam' — AutomaticDictionaryReadiness), CLAUDE.md/README. Инварианты plan/003 (staleness guards в prepareCorrection/CorrectionPlan.isEligible) не трогать.
<!-- /handoff-notes -->

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
