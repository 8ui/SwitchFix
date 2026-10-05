---
id: 2026-10-02-revert-verifies-field-text
title: Revert deletes text without checking the field
type: bug
pipeline: no-spec
phase: done
created: 2026-10-02
updated: 2026-10-05
blocked_by: null
steps_done: 4
steps_total: 4
step_current: null
artifacts:
  spec: null
  plan: docs/plans/revert-verifies-field-text-plan.md
  branch: null
  pr: "https://github.com/8ui/SwitchFix/pull/12"
---

## Context

Хоткей отмены (`requestRevert` → `TextCorrector.undo`, `Sources/Core/TextCorrector.swift:244`) удаляет `correctedText + boundary` вслепую: сверка поля (`ScreenVerification`, `InputEngine.verifyScreen`) есть только у прямой коррекции. Если поле изменило текст после коррекции (автозамена, подсказка, автодополнение), отмена удалит не те символы. Долг из 2026-09-30-correction-verifies-field-text-before-deleting (Debt, «revert/undo»).
Готово, когда: при `screenTextRequest` отмена читает текст перед кареткой и отменяется при mismatch/selection, при лаге ретраит до дедлайна, при unknown — fail-open; тесты в InputPipelineTestRunner (match → отмена применена, mismatch → нет удаления, и что fallback «нечего отменять → конвертировать» не срабатывает при отказе по экрану).

## Progress

1. ✅ TextCorrector: prepareUndo/takeUndo/postUndo/discardUndo/recordUndo + undo id
2. ✅ InputEngine: ScreenCheck (retriesMismatch, acceptsReplacement, reject)
3. ✅ Revert через проверку поля + тесты
4. ✅ Docs + ревью

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
- 2026-10-02: impl complete: 71d3a8a + e9bbeab (правки по код-ревью: refreshedRevert под rebase, restoreUndo, без ретрая для selection/replaced, тесты takeUndo и новой коррекции)
- 2026-10-02: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36990249513 (push e9bbeab; TestRunner 603/0, InputPipelineTestRunner 1166/0, 9 новых revert-сьютов)` → exit 0 ✅
- 2026-10-02: verify: `код-ревью субагентом: блокеров нет; 4 should-fix исправлены в e9bbeab` → exit 0 ✅
- 2026-10-02: шаг 4 ✅ Docs + ревью — ревью + CI
- 2026-10-02: CI зелёный, ревью пройдено; остаётся в review до merge ветки claude/eloquent-babbage-rfjo9l в master (PR — по решению пользователя)
- 2026-10-02: artifacts.pr = https://github.com/8ui/SwitchFix/pull/12
- 2026-10-02: merged in PR 12 (f180995)

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] отмена, чья сверка поля идёт во время собственного переключения раскладки, отменяется как устаревшая: окно — не только промежуток до rebaseUndoContext, но и до повторного разрешения фокуса (свой switch ставит secureFocus .unknown, isUndoEligible требует notSecure); на практике отмену жмут позже переключения, нажатие можно повторить — переформулировано 2026-10-05
- [x] тест 'staleness during the read' проверяет исход, не механизм: повторную проверку после чтения дублирует applyRevert — закрыто 2026-10-05: 2026-10-05-debt-batch-revert-shortcuts-keytables

## Verification

- 2026-10-02 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36990249513 (push e9bbeab; TestRunner 603/0, InputPipelineTestRunner 1166/0, 9 новых revert-сьютов)` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-10-02 · `код-ревью субагентом: блокеров нет; 4 should-fix исправлены в e9bbeab` · exit 0 ✅

  ```
  (без вывода)
  ```

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
