---
id: 2026-09-30-automatic-correction-retypes-the-enter-that-ended-the-word
title: Automatic correction retypes the Enter that ended the word
type: bug
pipeline: minimal
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

`KeyboardMonitor` превращает Return в `.boundary("\n")`, `InputStateMachine` сбрасывает слово с этой
границей, а `InputEngine.prepareCorrection` строит план `deleteCount = word + boundary`,
`replacementText = converted + boundary`. В чатах Enter уже отправил сообщение: коррекция стирает в пустом
поле (Backspace ничего не делает или стирает чужое) и печатает `привет\n` — вторая отправка. В терминале —
повторный запуск команды. Не проверено в реальном приложении; из кода следует. Найдено ревью задачи
`2026-09-30-merged-short-word-correction-deletes-text-without-checking`.
Варианты: не исправлять автоматически слово, завершённое Enter (самое безопасное), или исправлять без
перенабора границы — но после Enter текст уже ушёл, так что, скорее всего, первое.

## Progress

_Шаги не заданы. `rtp steps <id> --set "…"` или `--from-plan <файл>`._

## Log

- 2026-09-30: triage — pipeline `minimal`, reason: KeyboardMonitor: Return → .boundary("\n"); CorrectionPlan.replacementText = converted + boundary → после Enter (сообщение уже отправлено) коррекция перенабирает '\n' — в чатах возможна повторная отправка; найдено ревью задачи 2026-09-30-merged-short-word-correction-deletes-text-without-checking

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
