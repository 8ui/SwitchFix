---
id: 2026-10-02-learning-revert-and-cancelled-outcome
title: "Learning gaps: hotkey revert keeps the learned rule, cancelled corrections count as corrected"
type: bug
pipeline: no-spec
phase: review
created: 2026-10-02
updated: 2026-10-02
blocked_by: null
steps_done: 4
steps_total: 4
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

1. ✅ (а) отмена hotkey забывает выученное правило
2. ✅ (б) detectionID + noteCorrectionNotApplied в детекторе + тесты
3. ✅ (б) движок зовёт хук во всех точках отмены + тесты
4. ✅ Ревью и CI

## Log

- 2026-10-02: triage — pipeline `no-spec`, reason: InputEngine learnFromReverted + LayoutDetector recordOutcome + PersonalLexicon; 3 файла, нужна схема хука отмены
- 2026-10-02: brainstorm: пользователь одобрил (а) forgetAccepted при отмене .hotkey, (б) detectionID + noteCorrectionNotApplied во всех точках отмены, откат pendingSwitch только без новой детекции
- 2026-10-02: artifacts.plan = docs/plans/learning-revert-and-cancelled-outcome-plan.md
- 2026-10-02: plan drafted
- 2026-10-02: шаг 1 ✅ (а) отмена hotkey забывает выученное правило — e295188, CI зелёный 36992606419; условие rule == alwaysCorrect(to: target) добавлено по plan-review
- 2026-10-02: plan-review: 3 блокера (слово рудщ→helo; reset не чистил lastCorrection; гонка в тесте движка) + should-fix; план rev.2
- 2026-10-02: шаг 2 ✅ (б) detectionID + noteCorrectionNotApplied в детекторе + тесты
- 2026-10-02: шаг 3 ✅ (б) движок зовёт хук во всех точках отмены + тесты — ждём CI
- 2026-10-02: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36993289377 (push 5bf3102; TestRunner 632/0, InputPipelineTestRunner 1222/0); LayoutEval и sweep идентичны базе` → exit 0 ✅
- 2026-10-02: verify: `CI зелёный после правок код-ревью: https://github.com/8ui/SwitchFix/actions/runs/36994039723 (push 3b3512a; TestRunner 632/0, InputPipelineTestRunner 1223/0)` → exit 0 ✅
- 2026-10-02: verify: `код-ревью субагентом: блокеров нет; should-fix (порядок в тесте) и нитпики исправлены в 3b3512a` → exit 0 ✅
- 2026-10-02: шаг 4 ✅ Ревью и CI
- 2026-10-02: impl + ревью + CI; остаётся в review до merge ветки

## Decisions

- Состояние подтверждения переключения восстанавливается целиком (как будто слова не было), не только при shouldSwitchLayout == true — согласовано с переводом исхода в .unknown
- Исход переводится в .unknown для любой причины отмены (Enter, устаревание, экран); разделение по причине (Enter/stale — улики верны) не делаем — одобренный дизайн; при быстром наборе отмены stale-during-screen-check частые, и после них переключение обычно не восстанавливается (была новая детекция)

## Debt

- [ ] нет теста, что отмена hotkey сохраняет выученное правило с другой целью (цель не установлена / teaches:false)

## Verification

- 2026-10-02 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36993289377 (push 5bf3102; TestRunner 632/0, InputPipelineTestRunner 1222/0); LayoutEval и sweep идентичны базе` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-10-02 · `CI зелёный после правок код-ревью: https://github.com/8ui/SwitchFix/actions/runs/36994039723 (push 3b3512a; TestRunner 632/0, InputPipelineTestRunner 1223/0)` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-10-02 · `код-ревью субагентом: блокеров нет; should-fix (порядок в тесте) и нитпики исправлены в 3b3512a` · exit 0 ✅

  ```
  (без вывода)
  ```

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
