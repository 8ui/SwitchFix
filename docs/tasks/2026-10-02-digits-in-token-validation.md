---
id: 2026-10-02-digits-in-token-validation
title: "Index expressions like obj[0] and w[1] are converted"
type: bug
pipeline: minimal
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

`LayoutDetector.splitTokenForValidation` (`Sources/Core/LayoutDetector.swift:~870`) считает цифры частью слова (`ch.isLetter || ch.isNumber`), поэтому `obj[0]`, `w[1]` и подобные индексы в коде проходят детекцию и конвертируются. Долг из 2026-09-30-words-ending-on-punctuation-key-letters.
Готово, когда: токены с цифрами-индексами не конвертируются автоматически (тест в TestRunner), LayoutEval без регресса (ru/uk restored %, FP).

## Progress

_Шаги не заданы. `rtp steps <id> --set "…"` или `--from-plan <файл>`._

## Log

- 2026-10-02: triage — pipeline `minimal`, reason: одна функция splitTokenForValidation в LayoutDetector + тест; eval проверит FP

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
