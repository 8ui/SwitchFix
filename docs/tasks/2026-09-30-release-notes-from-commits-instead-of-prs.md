---
id: 2026-09-30-release-notes-from-commits-instead-of-prs
title: Release notes from commits instead of PRs
type: chore
pipeline: minimal
phase: done
created: 2026-09-30
updated: 2026-09-30
blocked_by: null
steps_done: 4
steps_total: 4
step_current: null
artifacts:
  spec: null
  plan: null
  branch: null
  pr: null
---

## Context

_2-5 строк: что делаем и зачем. Задача этой секции — чтобы через N дней можно было восстановить контекст без чтения spec/plan._

## Progress

1. ✅ scripts/release-notes.sh
2. ✅ release.yml: fetch-depth 0 + body_path
3. ✅ Проверка на v0.0.11..v0.0.12
4. ✅ Ревью

## Log

- 2026-09-30: triage — pipeline `minimal`, reason: generate_release_notes перечисляет только PR, а коммиты льются напрямую → v0.0.12 показал 1 пункт; скрипт + body_path, 2 файла
- 2026-09-30: brainstorm: заметки из feat/fix коммитов между тегами; пользователь одобрил
- 2026-09-30: шаг 1 ✅ scripts/release-notes.sh
- 2026-09-30: шаг 2 ✅ release.yml: fetch-depth 0 + body_path
- 2026-09-30: verify: `scripts/release-notes.sh v0.0.12 '' 8ui/SwitchFix` → exit 0 ✅
- 2026-09-30: verify: `ruby -ryaml -e 'YAML.load_file(".github/workflows/release.yml")'` → exit 0 ✅
- 2026-09-30: скрипт + release.yml готовы; ждём прогон в ubuntu (mawk) и ревью
- 2026-09-30: ревью: блокеров нет; принят --match 'v*'; жду прогон под mawk в ubuntu:24.04
- 2026-09-30: verify: `ubuntu:24.04, mawk 1.3.4 20240123: scripts/release-notes.sh v0.0.12 '' 8ui/SwitchFix — вывод идентичен macOS (27 строк)` → exit 0 ✅
- 2026-09-30: шаг 3 ✅ Проверка на v0.0.11..v0.0.12
- 2026-09-30: шаг 4 ✅ Ревью
- 2026-09-30: проверено под mawk, ревью пройдено
- 2026-09-30: закоммичено и запушено

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

_Отложенное, упрощения, известные пробелы. Формат — чекбоксы (их считают индекс и отчёты по долгам):_
_- `- [ ] <что отложено> — <почему/контекст>` — открытый долг_
_- `- [x] <что было> — закрыто YYYY-MM-DD: <причина/ссылка на task>` — закрытый_
_Без `[ ]`/`[x]` пункт невидим для агрегатора и теряется через 2 недели._

## Verification

- 2026-09-30 · `scripts/release-notes.sh v0.0.12 '' 8ui/SwitchFix` · exit 0 ✅

  ```
  - hotkey converts the word before the caret when nothing is buffered
  
  ## Исправления
  - prefer the primary Ukrainian variant in the n-gram engine
  - disambiguate Layout from SwiftUI's Layout protocol in the Words tab
  - address code review of learning and the Words tab
  - recognize Australian, Canadian, Irish and British-PC as English
  - convert letterless selections from the current layout first
  - address key-table review
  - keep the word across the Globe key in layout-switch mode
  - live Words tab counters, accessibility labels, wider Words tab
  - keep TCC grants on reinstall with a stable signature
  
  **Full Changelog**: https://github.com/8ui/SwitchFix/compare/v0.0.11...v0.0.12
  ```

- 2026-09-30 · `ruby -ryaml -e 'YAML.load_file(".github/workflows/release.yml")'` · exit 0 ✅

  ```
  (пустой вывод)
  ```

- 2026-09-30 · `ubuntu:24.04, mawk 1.3.4 20240123: scripts/release-notes.sh v0.0.12 '' 8ui/SwitchFix — вывод идентичен macOS (27 строк)` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
