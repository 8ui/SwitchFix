---
id: 2026-10-02-learning-revert-and-cancelled-outcome
title: "Learning gaps: hotkey revert keeps the learned rule, cancelled corrections count as corrected"
type: bug
pipeline: no-spec
phase: plan-review
created: 2026-10-02
updated: 2026-10-02
blocked_by: null
steps_done: 0
steps_total: 0
step_current: null
artifacts:
  spec: null
  plan: docs/plans/learning-revert-and-cancelled-outcome-plan.md
  branch: null
  pr: null
---

## Context

Два пробела обучения: (1) отмена `hotkey`-коррекции, произведённой выученным правилом `alwaysCorrect`, правило не забывает (CLAUDE.md «Known gap»; `InputEngine.learnFromReverted`, `case .hotkey` ничего не делает); (2) коррекция, отменённая после детекции (Enter, staleness, экран), всё равно записала `recordOutcome(.corrected)` в LayoutDetector и потратила pendingSwitch — ослабляет защиту коротких слов (долг из 2026-09-30-automatic-correction-retypes-the-enter-that-ended-the-word).
Готово, когда: отмена hotkey-коррекции по learned rule забывает правило (не трогая `manual`), у детектора есть хук «коррекция не применена», откатывающий outcome; тесты в InputPipelineTestRunner.

## Progress

_Шаги не заданы. `rtp steps <id> --set "…"` или `--from-plan <файл>`._

## Log

- 2026-10-02: triage — pipeline `no-spec`, reason: InputEngine learnFromReverted + LayoutDetector recordOutcome + PersonalLexicon; 3 файла, нужна схема хука отмены
- 2026-10-02: brainstorm: пользователь одобрил (а) forgetAccepted при отмене .hotkey, (б) detectionID + noteCorrectionNotApplied во всех точках отмены, откат pendingSwitch только без новой детекции
- 2026-10-02: artifacts.plan = docs/plans/learning-revert-and-cancelled-outcome-plan.md
- 2026-10-02: plan drafted

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

**Сгенерировано:** 2026-10-02 · `rtp handoff`

- **Задача:** `2026-10-02-learning-revert-and-cancelled-outcome` — Learning gaps: hotkey revert keeps the learned rule, cancelled corrections count as corrected
- **Фаза:** plan-review (pipeline `no-spec`, type `bug`)
- **Worktree:** `/home/user/SwitchFix`
- **Ветка:** `claude/eloquent-babbage-rfjo9l` — своих коммитов 14, отставание от origin/master 0
- **Незакоммиченного:** 0 файл(ов)

**Последние коммиты**

- `e295188 fix(engine): reverting a hotkey correction forgets the learned rule`
- `6edaeec docs(plan): learning gaps and layout-switch shortcuts`
- `e476f83 docs(tasks): close the index-expression debt`

**Последние записи лога**

- 2026-10-02: triage — pipeline `no-spec`, reason: InputEngine learnFromReverted + LayoutDetector recordOutcome + PersonalLexicon; 3 файла, нужна схема хука отмены
- 2026-10-02: brainstorm: пользователь одобрил (а) forgetAccepted при отмене .hotkey, (б) detectionID + noteCorrectionNotApplied во всех точках отмены, откат pendingSwitch только без новой детекции
- 2026-10-02: artifacts.plan = docs/plans/learning-revert-and-cancelled-outcome-plan.md
- 2026-10-02: plan drafted

**Следующее действие**

- дать план субагенту-архитектору, потом rtp phase 2026-10-02-learning-revert-and-cancelled-outcome --to impl

**Заметки агента** (не выводятся из кода — грабли, тупики, договорённости)

<!-- handoff-notes -->
- 2026-10-02: Task 1 плана (а) сделан заранее (не зависит от ревью) в коммите выше; ждём plan-review для (б)
<!-- /handoff-notes -->

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
