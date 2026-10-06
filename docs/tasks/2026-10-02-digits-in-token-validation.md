---
id: 2026-10-02-digits-in-token-validation
title: "Index expressions like obj[0] and w[1] are converted"
type: bug
pipeline: minimal
phase: done
created: 2026-10-02
updated: 2026-10-06
blocked_by: null
steps_done: 3
steps_total: 3
step_current: null
artifacts:
  spec: null
  plan: null
  branch: null
  pr: "https://github.com/8ui/SwitchFix/pull/12"
---

## Context

`LayoutDetector.splitTokenForValidation` (`Sources/Core/LayoutDetector.swift:~870`) считает цифры частью слова (`ch.isLetter || ch.isNumber`), поэтому `obj[0]`, `w[1]` и подобные индексы в коде проходят детекцию и конвертируются. Долг из 2026-09-30-words-ending-on-punctuation-key-letters.
Готово, когда: токены с цифрами-индексами не конвертируются автоматически (тест в TestRunner), LayoutEval без регресса (ru/uk restored %, FP).

## Progress

1. ✅ Тест: индексы остаются (до фикса FAIL в CI)
2. ✅ Правило: латинский токен с цифрой у скобки — нейтрально пропускать автоисправление
3. ✅ Eval-сравнение и ревью

## Log

- 2026-10-02: triage — pipeline `minimal`, reason: одна функция splitTokenForValidation в LayoutDetector + тест; eval проверит FP
- 2026-10-02: brainstorm: пользователь одобрил узкое нейтральное правило по образцу флагов вместо правки splitTokenForValidation
- 2026-10-02: verify: `до фикса: CI https://github.com/8ui/SwitchFix/actions/runs/36990742397 — 5 FAIL (obj[0]→щиох0ъ, w[1]→цх1ъ, x[0].→чх0ъю, arr[12]→фккх12ъ, a[0],/b[1]); m{1}, [0] уже оставались` → exit 1 ❌
- 2026-10-02: шаг 1 ✅ Тест: индексы остаются (до фикса FAIL в CI)
- 2026-10-02: шаг 2 ✅ Правило: латинский токен с цифрой у скобки — нейтрально пропускать автоисправление — shouldSkipAutomaticIndexExpression рядом с правилом флагов
- 2026-10-02: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36991085388 (push dd11ce7; TestRunner 612/0, InputPipelineTestRunner 1172/0); LayoutEval и threshold sweep побайтно совпадают с базой 36990249513` → exit 0 ✅
- 2026-10-02: verify: `CI зелёный после правок ревью: https://github.com/8ui/SwitchFix/actions/runs/36991541543 (push 7f18ea8; TestRunner 613/0, InputPipelineTestRunner 1173/0)` → exit 0 ✅
- 2026-10-02: verify: `код-ревью субагентом: блокеров нет; should-fix (вытеснение старого переключения) и тестовые замечания исправлены в 7f18ea8` → exit 0 ✅
- 2026-10-02: шаг 3 ✅ Eval-сравнение и ревью
- 2026-10-02: impl + ревью + CI; остаётся в review до merge ветки
- 2026-10-02: artifacts.pr = https://github.com/8ui/SwitchFix/pull/12
- 2026-10-02: merged in PR 12 (f180995)

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [x] arr[i], dict["k"] без цифры правилом не покрыты (идут через модель) — закрыто 2026-10-06: 2026-10-06-index-expressions-without-digits-measure-and-pin-in-edge
- [x] нейтральный пропуск (флаг и индекс) обнуляет consecutiveWrongCount/pendingSwitch — в прозе 'cnhjrf 2[ rjvyfnyfz' разрывает серию; прозрачный пропуск (только state=.buffering) — решение для обоих правил — закрыто 2026-10-02: 2026-10-02-debt-batch-skip-adjacency-suffix-tests

## Verification

- 2026-10-02 · `до фикса: CI https://github.com/8ui/SwitchFix/actions/runs/36990742397 — 5 FAIL (obj[0]→щиох0ъ, w[1]→цх1ъ, x[0].→чх0ъю, arr[12]→фккх12ъ, a[0],/b[1]); m{1}, [0] уже оставались` · exit 1 ❌

  ```
  (без вывода)
  ```

- 2026-10-02 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36991085388 (push dd11ce7; TestRunner 612/0, InputPipelineTestRunner 1172/0); LayoutEval и threshold sweep побайтно совпадают с базой 36990249513` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-10-02 · `CI зелёный после правок ревью: https://github.com/8ui/SwitchFix/actions/runs/36991541543 (push 7f18ea8; TestRunner 613/0, InputPipelineTestRunner 1173/0)` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-10-02 · `код-ревью субагентом: блокеров нет; should-fix (вытеснение старого переключения) и тестовые замечания исправлены в 7f18ea8` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
