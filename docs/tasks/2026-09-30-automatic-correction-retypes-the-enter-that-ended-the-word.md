---
id: 2026-09-30-automatic-correction-retypes-the-enter-that-ended-the-word
title: Automatic correction retypes the Enter that ended the word
type: bug
pipeline: minimal
phase: impl
created: 2026-09-30
updated: 2026-09-30
blocked_by: null
steps_done: 2
steps_total: 3
step_current: 3
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

1. ✅ Отмена коррекции при границе Enter
2. ✅ Тест пайплайна
3. ▶ Ревью

## Log

- 2026-09-30: triage — pipeline `minimal`, reason: KeyboardMonitor: Return → .boundary("\n"); CorrectionPlan.replacementText = converted + boundary → после Enter (сообщение уже отправлено) коррекция перенабирает '\n' — в чатах возможна повторная отправка; найдено ревью задачи 2026-09-30-merged-short-word-correction-deletes-text-without-checking
- 2026-09-30: brainstorm: вывод — слово, законченное Enter, не исправлять автоматически (текст уже отправлен); критерий — тест пайплайна: Enter → нет эмиссии, следующий пробел → коррекция
- 2026-09-30: шаг 1 ✅ Отмена коррекции при границе Enter — prepareCorrection: cancelReason word-ended-by-enter
- 2026-09-30: шаг 2 ✅ Тест пайплайна — InputPipelineTestRunner: automatic correction: a word ended by Enter
- 2026-09-30: ревью (субагент): keypad Enter (76) попадал в буфер как U+0003 — теперь граница \n; тест проверяет ровно одну коррекцию без \n; README: space or punctuation; два минорных — в долг

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] Отменённая Enter-коррекция всё равно пишет детектору recordOutcome(.corrected) и тратит pendingSwitch — ослабляет защиту коротких слов на следующих словах; нужен хук «отменено» в детекторе
- [ ] Слово, законченное Enter, не переключает раскладку, и Shift+Return (перевод строки без отправки) тоже пропускается — можно переключать источник без перенабора и/или пропускать Shift+Return

## Verification

_Доказательства, а не утверждения. Заполняется `rtp verify <id> --run "<команда>"`: команда, exit code, хвост вывода._

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
