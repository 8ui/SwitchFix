---
id: 2026-10-02-revert-verifies-field-text
title: Revert deletes text without checking the field
type: bug
pipeline: no-spec
phase: triage
created: 2026-10-02
updated: 2026-10-02
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

Хоткей отмены (`requestRevert` → `TextCorrector.undo`, `Sources/Core/TextCorrector.swift:244`) удаляет `correctedText + boundary` вслепую: сверка поля (`ScreenVerification`, `InputEngine.verifyScreen`) есть только у прямой коррекции. Если поле изменило текст после коррекции (автозамена, подсказка, автодополнение), отмена удалит не те символы. Долг из 2026-09-30-correction-verifies-field-text-before-deleting (Debt, «revert/undo»).
Готово, когда: при `screenTextRequest` отмена читает текст перед кареткой и отменяется при mismatch/selection, при лаге ретраит до дедлайна, при unknown — fail-open; тесты в InputPipelineTestRunner (match → отмена применена, mismatch → нет удаления, и что fallback «нечего отменять → конвертировать» не срабатывает при отказе по экрану).

## Progress

_Шаги не заданы. `rtp steps <id> --set "…"` или `--from-plan <файл>`._

## Log

- 2026-10-02: triage — pipeline `no-spec`, reason: InputEngine + TextCorrector + тесты: переиспользовать verifyScreen для обратного плана; известная архитектура, 2-4 файла

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

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
