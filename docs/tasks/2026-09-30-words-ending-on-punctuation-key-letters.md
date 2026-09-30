---
id: 2026-09-30-words-ending-on-punctuation-key-letters
title: Words ending in letters on punctuation keys (х ъ ж э б ю ё) may be cut as trailing punctuation
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

В RuSwitcher массово не конвертировались слова, у которых последняя буква в EN-раскладке — знак препинания:
х `[`, ъ `]`, ж `;`, э `'`, б `,`, ю `.`, ё `` ` `` (`их`→`bx[`, `ещё`, `знаю`→`pyf.`, `наших`, `ghbdtn,`) —
детектор отрезал хвост как пунктуацию (rashn/RuSwitcher #35, #15, #33; xneur #2, #59: `будет`→`,eltn`). В Russian–PC
`,` и `.` стоят на `/?`, в Ukrainian legacy/PC пунктуация на других клавишах, апостроф внутри `п'ять` — не граница.
У нас `LayoutDetector.splitTrailingBoundary` отрезает хвост по `boundaryCharacterSet` (LayoutDetector.swift:894),
и `lexiconWord(from:)` на нём же — проверить, что `bx[`, `pyf.`, ``tot` `` (ещё), `ghbdtn,`, `,eltn` конвертируются, а
настоящая точка/запятая после английского слова — нет (KeySwitch решает это отдельной «моделью границы слова»
и откладывает решение при сомнении). Сначала — тесты в TestRunner на все семь букв в конце и в начале слова,
для KeyboardTables.pc и для Russian–PC/Ukrainian-legacy таблиц.

## Progress

_Шаги не заданы. `rtp steps <id> --set "…"` или `--from-plan <файл>`._

## Log

- 2026-09-30: triage — pipeline `minimal`, reason: исследование: RuSwitcher #35/#15/#33 массово не конвертировал их/ещё/знаю/ghbdtn,; проверить splitTrailingBoundary

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
