---
id: 2026-10-02-revert-verifies-field-text
title: Revert deletes text without checking the field
type: bug
pipeline: no-spec
phase: impl
created: 2026-10-02
updated: 2026-10-02
blocked_by: null
steps_done: 3
steps_total: 4
step_current: 4
artifacts:
  spec: null
  plan: docs/plans/revert-verifies-field-text-plan.md
  branch: null
  pr: null
---

## Context

Хоткей отмены (`requestRevert` → `TextCorrector.undo`, `Sources/Core/TextCorrector.swift:244`) удаляет `correctedText + boundary` вслепую: сверка поля (`ScreenVerification`, `InputEngine.verifyScreen`) есть только у прямой коррекции. Если поле изменило текст после коррекции (автозамена, подсказка, автодополнение), отмена удалит не те символы. Долг из 2026-09-30-correction-verifies-field-text-before-deleting (Debt, «revert/undo»).
Готово, когда: при `screenTextRequest` отмена читает текст перед кареткой и отменяется при mismatch/selection, при лаге ретраит до дедлайна, при unknown — fail-open; тесты в InputPipelineTestRunner (match → отмена применена, mismatch → нет удаления, и что fallback «нечего отменять → конвертировать» не срабатывает при отказе по экрану).

## Progress

1. ✅ TextCorrector: prepareUndo/takeUndo/postUndo/discardUndo/recordUndo + undo id
2. ✅ InputEngine: ScreenCheck (retriesMismatch, acceptsReplacement, reject)
3. ✅ Revert через проверку поля + тесты
4. ▶ Docs + ревью

## Log

- 2026-10-02: triage — pipeline `no-spec`, reason: InputEngine + TextCorrector + тесты: переиспользовать verifyScreen для обратного плана; известная архитектура, 2-4 файла
- 2026-10-02: brainstorm: дизайн одобрен пользователем (prepare/apply undo, общий ScreenCheck, replaced/mismatch → отказ без fallback-конвертации, unknown → fail-open)
- 2026-10-02: artifacts.plan = docs/plans/revert-verifies-field-text-plan.md
- 2026-10-02: plan drafted
- 2026-10-02: plan-review: 2 блокера (mismatch при догоняющем поле убивал отмену; seam обходил проверяемую логику, stale-тест пустой) + should-fix (weak self, atomic take, undo id); план rev.2
- 2026-10-02: шаг 1 ✅ TextCorrector: prepareUndo/takeUndo/postUndo/discardUndo/recordUndo + undo id — prepareUndo/takeUndo/postUndo/discardUndo/recordUndo, UndoState.id; undo() удалён
- 2026-10-02: шаг 2 ▶ InputEngine: ScreenCheck (retriesMismatch, acceptsReplacement, reject)
- 2026-10-02: шаг 2 ✅ InputEngine: ScreenCheck (retriesMismatch, acceptsReplacement, reject) — ScreenCheck: retriesMismatch, acceptsReplacement, reject; weak self
- 2026-10-02: шаг 3 ✅ Revert через проверку поля + тесты — requestRevert: prepareUndo → ScreenCheck → applyRevert(takeUndo/postUndo); 6 новых тест-сьютов; ждём CI
- 2026-10-02: шаг 4 ▶ Docs + ревью

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

- **Задача:** `2026-10-02-revert-verifies-field-text` — Revert deletes text without checking the field
- **Фаза:** plan-review (pipeline `no-spec`, type `bug`)
- **Worktree:** `/home/user/SwitchFix`
- **Ветка:** `claude/eloquent-babbage-rfjo9l` — своих коммитов 2, отставание от origin/master 0
- **Незакоммиченного:** 0 файл(ов)

**Последние коммиты**

- `6651741 docs(plan): revert verifies the field text`
- `9235eba docs(tasks): open five debt tasks from the backlog and upstream review`
- `5e6ef38 Bump version to 0.0.14`

**Последние записи лога**

- 2026-10-02: triage — pipeline `no-spec`, reason: InputEngine + TextCorrector + тесты: переиспользовать verifyScreen для обратного плана; известная архитектура, 2-4 файла
- 2026-10-02: brainstorm: дизайн одобрен пользователем (prepare/apply undo, общий ScreenCheck, replaced/mismatch → отказ без fallback-конвертации, unknown → fail-open)
- 2026-10-02: artifacts.plan = docs/plans/revert-verifies-field-text-plan.md
- 2026-10-02: plan drafted

**Следующее действие**

- дать план субагенту-архитектору, потом rtp phase 2026-10-02-revert-verifies-field-text --to impl

**Заметки агента** (не выводятся из кода — грабли, тупики, договорённости)

<!-- handoff-notes -->
- 2026-10-02: Ждём plan-review от архитектора; затем rtp steps --from-plan и impl
<!-- /handoff-notes -->

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
