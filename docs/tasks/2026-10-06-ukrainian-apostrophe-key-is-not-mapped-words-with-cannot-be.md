---
id: 2026-10-06-ukrainian-apostrophe-key-is-not-mapped-words-with-cannot-be
title: "Ukrainian apostrophe key is not mapped: words with ʼ cannot be corrected"
type: bug
pipeline: no-spec
phase: review
created: 2026-10-06
updated: 2026-10-06
blocked_by: null
steps_done: 4
steps_total: 4
step_current: null
artifacts:
  spec: null
  plan: docs/plans/uk-apostrophe-plan.md
  branch: null
  pr: null
---

## Context

Долг из 2026-09-29-ngram-only-learning-ui: украинские слова с апострофом (пʼятниця, обʼєкт), набранные в английской раскладке, не исправлялись. Ukrainian-PC ставит ʼ (U+02BC) на клавишу `\`: `.pc`-таблица её не знала, санитайзер выбрасывал ʼ (буква Lm вне U+0400–04FF), а `\` резал слово. План: `docs/plans/uk-apostrophe-plan.md`, замер: `plan/benchmarks/uk_apostrophe.md`.

## Progress

1. ✅ Таблицы: ʼ на \ в .pc, ownsLetter, canBeTyped(.english), LexiconKey
2. ✅ Граница слова: общий мягкий набор, \ между буквами в детекторе и CaretWordExtractor
3. ✅ LayoutEval: ʼ в uk, edge cases, бенчмарк до/после
4. ✅ Проверки и ревью

## Log

- 2026-10-06: triage — pipeline `no-spec`, reason: Ukrainian-PC ставит ʼ (U+02BC) на клавишу \; затрагивает KeyTables (.pc), KeyTableBuilder (ownsLetter), WordBoundary (\ в слове), LayoutEval (reachability) + тесты — 4-5 файлов, известная архитектура; детектор, нужен прогон LayoutEval
- 2026-10-06: brainstorm: долг из 2026-09-29-ngram-only-learning-ui; UCKeyTranslate: Ukrainian-PC ставит ʼ на \, санитайзер его выбрасывает, \ — граница слова
- 2026-10-06: artifacts.plan = docs/plans/uk-apostrophe-plan.md
- 2026-10-06: plan drafted
- 2026-10-06: plan-review (Plan, opus): 3 high / 6 medium / 6 low — учтены в плане (раздел «После plan-review»); базовый LayoutEval снят
- 2026-10-06: шаг 1 ✅ Таблицы: ʼ на \ в .pc, ownsLetter, canBeTyped(.english), LexiconKey
- 2026-10-06: шаг 2 ✅ Граница слова: общий мягкий набор, \ между буквами в детекторе и CaretWordExtractor — \ склеивает слово только перед я/ю/є/ї после буквенной клавиши
- 2026-10-06: шаг 3 ✅ LayoutEval: ʼ в uk, edge cases, бенчмарк до/после — unreachable 21→0, ложных 0, edge 12/12; plan/benchmarks/uk_apostrophe.md
- 2026-10-06: impl complete
- 2026-10-06: verify: `swift build -c release` → exit 0 ✅
- 2026-10-06: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-10-06: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-10-06: verify: `scripts/check-l10n.sh` → exit 0 ✅
- 2026-10-06: verify: `swift build -c release` → exit 0 ✅
- 2026-10-06: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-10-06: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-10-06: verify: `swift build -c release` → exit 0 ✅
- 2026-10-06: verify: `swift run -c release TestRunner` → exit 0 ✅
- 2026-10-06: verify: `swift run -c release InputPipelineTestRunner` → exit 0 ✅
- 2026-10-06: шаг 4 ✅ Проверки и ревью — code-review general-purpose (opus) ×2: 4 находки исправлены, A/escape — в долг
- 2026-10-06: code-review ×2 (general-purpose, opus): RU+UK last-ru, legacy ґ, RU-only edge, hotkey after / — исправлены; двойной \ в хоткее исправлен; A и escape — в долг

## Decisions

- `\` — символ буфера у всех, но автоматическая коррекция токена с `\` идёт только в цель, которой клавиша подходит (`backslashFits`): апостроф — только как украинская связка (буквенная клавиша + я/ю/є/ї), буква (ґ, старая Apple Ukrainian) — никогда, пунктуация (RussianWin) — только вне ядра токена. Иначе прозрачный пропуск.
- Связка требует я/ю/є/ї после апострофа — отсекает пути (`\Users`, `\dir`) и escape (`\n`) без отдельного правила путей.

## Debt

- [ ] ʼ — буква (Lm) и считается в длине: мʼя идёт как 3 буквы, пʼять как 5 — пороги по длине чуть строже/мягче для слов с апострофом (plan-review M6)
- [ ] капсом с апострофом не исправляется: Shift+\ = | (граница), с Caps Lock G\ZNYBWZ тоже — как до задачи (plan-review L1)
- [ ] на старой раскладке Apple Ukrainian (ґ на \) слова с ґ, набранные в en, по-прежнему не исправляются автоматически — \ там не склеивает
- [ ] пользователь с ru+uk, у которого последняя кириллица — русская, слово с апострофом в en не исправит автоматически (цель ru не подходит) — только хоткеем
- [ ] \ теперь в буфере у всех: путь C:\dir\ghbdtn больше не исправляет ghbdtn автоматически (раньше \ резал слово) — пропуск прозрачный
- [ ] украинское слово вплотную к \ (ghbdsn\, \ghbdsn) с украинской целью больше не исправляется автоматически (на master: привіт\) — нужна конверсия без краевого \; пока остаётся как набрано (ревью A)
- [ ] однобуквенные escape при русской цели конвертируются: \r→\к, \b→\и (как одиночные r/b на master) — можно требовать ≥2 букв для краевого \ (ревью)

## Verification

- 2026-10-06 · `swift build -c release` · exit 0 ✅

  ```
  Building for production...
  [2 / 12]
  Build complete! (0,40 с)
  ```

- 2026-10-06 · `swift run -c release TestRunner` · exit 0 ✅

  ```
  | fix uk←en word-forms | 10/11 | сфеі (want cats) |
  | fix en←ru word-forms | 9/10 | pfdnhf→завтра (want завтра) |
  | fix en←ru slang-tech | 5/7 | ofc (want щас), rhby; (want кринж) |
  | fix en←uk word-forms | 6/6 |  |
  | fix en←uk slang-tech | 3/4 | yjhv→норм (want норм) |
  | keep en←en backslash | 6/6 |  |
  | fix en←uk apostrophe | 6/6 |  |
  
  ========================================
  Results: 1206 passed, 0 failed
  ALL TESTS PASSED
  
  Building for production...
  Build complete! (0,21 с)
  ```

- 2026-10-06 · `swift run -c release InputPipelineTestRunner` · exit 0 ✅

  ```
  --- layout switch after a correction: rechecked on main ---
  --- layout switch after a correction: queued, rechecked and superseded ---
  --- revert screen check: a hotkey correction (no boundary) ---
  --- key-down classification: input-source shortcuts act like the Globe key ---
  --- key-down classification: other keys as before ---
  --- key-down classification: caret moves and unseen edits ---
  --- mouse-down classification ---
  --- input-source shortcuts from com.apple.symbolichotkeys ---
  --- input-source shortcuts: re-read at most once per interval unless forced ---
  
  Input pipeline: 1469 passed, 0 failed
  
  Building for production...
  Build complete! (0,20 с)
  ```

- 2026-10-06 · `scripts/check-l10n.sh` · exit 0 ✅

  ```
  L10n: 123 keys, no duplicates
  ```

- 2026-10-06 · `swift build -c release` · exit 0 ✅

  ```
  Building for production...
  [2 / 12]
  [3 / 6] TestRunner-product
  [5 / 7] TestRunner-product
  [7 / 7] TestRunner-product
  [8 / 9] TestRunner-product
  Build complete! (9,86 с)
  ```

- 2026-10-06 · `swift run -c release TestRunner` · exit 0 ✅

  ```
  | fix en←ru word-forms | 9/10 | pfdnhf→завтра (want завтра) |
  | fix en←ru slang-tech | 5/7 | ofc (want щас), rhby; (want кринж) |
  | fix en←uk word-forms | 6/6 |  |
  | fix en←uk slang-tech | 3/4 | yjhv→норм (want норм) |
  | keep en←en backslash | 6/6 |  |
  | fix en←uk apostrophe | 6/6 |  |
  
  ========================================
  Results: 1209 passed, 0 failed
  ALL TESTS PASSED
  
  Building for production...
  [1 / 9]
  Build complete! (0,41 с)
  ```

- 2026-10-06 · `swift run -c release InputPipelineTestRunner` · exit 0 ✅

  ```
  --- layout switch after a correction: queued, rechecked and superseded ---
  --- revert screen check: a hotkey correction (no boundary) ---
  --- key-down classification: input-source shortcuts act like the Globe key ---
  --- key-down classification: other keys as before ---
  --- key-down classification: caret moves and unseen edits ---
  --- mouse-down classification ---
  --- input-source shortcuts from com.apple.symbolichotkeys ---
  --- input-source shortcuts: re-read at most once per interval unless forced ---
  
  Input pipeline: 1471 passed, 0 failed
  
  Building for production...
  [1 / 9]
  Build complete! (0,37 с)
  ```

- 2026-10-06 · `swift build -c release` · exit 0 ✅

  ```
  Building for production...
  [2 / 6] Core
  Build complete! (0,22 с)
  ```

- 2026-10-06 · `swift run -c release TestRunner` · exit 0 ✅

  ```
  | fix uk←en word-forms | 10/11 | сфеі (want cats) |
  | fix en←ru word-forms | 9/10 | pfdnhf→завтра (want завтра) |
  | fix en←ru slang-tech | 5/7 | ofc (want щас), rhby; (want кринж) |
  | fix en←uk word-forms | 6/6 |  |
  | fix en←uk slang-tech | 3/4 | yjhv→норм (want норм) |
  | keep en←en backslash | 6/6 |  |
  | fix en←uk apostrophe | 6/6 |  |
  
  ========================================
  Results: 1210 passed, 0 failed
  ALL TESTS PASSED
  
  Building for production...
  Build complete! (0,19 с)
  ```

- 2026-10-06 · `swift run -c release InputPipelineTestRunner` · exit 0 ✅

  ```
  --- layout switch after a correction: rechecked on main ---
  --- layout switch after a correction: queued, rechecked and superseded ---
  --- revert screen check: a hotkey correction (no boundary) ---
  --- key-down classification: input-source shortcuts act like the Globe key ---
  --- key-down classification: other keys as before ---
  --- key-down classification: caret moves and unseen edits ---
  --- mouse-down classification ---
  --- input-source shortcuts from com.apple.symbolichotkeys ---
  --- input-source shortcuts: re-read at most once per interval unless forced ---
  
  Input pipeline: 1472 passed, 0 failed
  
  Building for production...
  Build complete! (0,20 с)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
