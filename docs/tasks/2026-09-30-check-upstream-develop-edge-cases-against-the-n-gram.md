---
id: 2026-09-30-check-upstream-develop-edge-cases-against-the-n-gram
title: Check upstream develop edge cases against the n-gram detector
type: bug
pipeline: no-spec
phase: triage
created: 2026-09-30
updated: 2026-09-30
blocked_by: null
steps_done: 0
steps_total: 0
step_current: null
artifacts:
  spec: null
  plan: null
  branch: null
  pr: null
---

## Context

В `upstream/develop` (rundax, ветка устарела относительно форка: база 0df61fb, 2026-08-07) есть 8 коммитов, не перенесённых в master
(`origin/develop` удалена 2026-09-30, оригинал — `upstream/develop`). Вливать целиком нельзя: вернёт словарный движок и
конфликтует с переписанным пайплайном. Задача: воспроизвести их кейсы тестами на текущем n-gram детекторе / пайплайне
и портировать только то, что реально падает.

Кейсы по коммитам (`git show <sha>` в `upstream/develop`):
- `fb33eb9` — одиночные символы и флаги вида `-r` не конвертировать (LayoutDetector, TestRunner)
- `b1eb723` — не исправлять внутри слова (каретка посреди слова) и неоднозначные слова (InputStateMachine, LayoutDetector)
- `6224c8d` — не удалять текст при смешанном вводе en/ru в одном слове, синхронизация раскладки (InputEngine, TextCorrector)
- `bdee150` — deletion plans, boundary resets, выбор codesign identity (InputStateMachine, TextCorrector, build-app.sh, setup-codesign.sh)
- `6fa5577` — session tap + pacing для Chromium; вероятно, покрыто `AppPostMode`, проверить только отсутствие регрессии
- не применимо (словари удалены): `a90a53d`, словарная часть `119d6f1`; `5f0c10e` — сверить только скрипты

## Progress

_Шаги не заданы. `rtp steps <id> --set "…"` или `--from-plan <файл>`._

## Log

- 2026-09-30: triage — pipeline `no-spec`, reason: 8 коммитов upstream/develop не перенесены; проверить тестами -r/одиночные символы, исправление внутри слова, смешанный ввод; портировать только падающее

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

**Сгенерировано:** 2026-09-30 · `rtp handoff`

- **Задача:** `2026-09-30-check-upstream-develop-edge-cases-against-the-n-gram` — Check upstream develop edge cases against the n-gram detector
- **Фаза:** triage (pipeline `no-spec`, type `bug`)
- **Worktree:** `/Users/andrejsokolov/Desktop/projects/SwitchFix`
- **Ветка:** `master` — своих коммитов 0, отставание от origin/master 0
- **Незакоммиченного:** 2 файл(ов)

**Файлы в работе**

- `ocs/tasks/index.md`
- `docs/tasks/2026-09-30-check-upstream-develop-edge-cases-against-the-n-gram.md`

**git diff HEAD --stat**

```
docs/tasks/index.md | 6 ++++--
 1 file changed, 4 insertions(+), 2 deletions(-)
```

**Последние коммиты**

- `8d79fdb docs(tasks): close release notes task`
- `e81b78d ci(release): build release notes from commits instead of PRs`
- `ae11039 docs(tasks): close release v0.0.12 task`

**Последние записи лога**

- 2026-09-30: triage — pipeline `no-spec`, reason: 8 коммитов upstream/develop не перенесены; проверить тестами -r/одиночные символы, исправление внутри слова, смешанный ввод; портировать только падающее

**Следующее действие**

- написать план → rtp phase 2026-09-30-check-upstream-develop-edge-cases-against-the-n-gram --to plan-review

**Заметки агента** (не выводятся из кода — грабли, тупики, договорённости)

<!-- handoff-notes -->
- 2026-09-30: Не начата: только заведена по итогам разбора develop. Начать с brainstorming + плана; тесты — в TestRunner (детектор) и InputPipelineTestRunner (пайплайн).
<!-- /handoff-notes -->

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
