---
id: 2026-09-30-unicode-events-carry-keycode-zero
title: Unicode correction events carry keyCode 0 (A)
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

`TextCorrector.makeUnicodeEvent` создаёт событие через `makeKeyEvent(keyCode: 0, …)` и кладёт символ через
`keyboardSetUnicodeString`. keyCode 0 — это kVK_ANSI_A. Приложения, которые транслируют по keycode, а не по
Unicode-строке (Qt, Java/JetBrains, QEMU/UTM, клиенты удалённого доступа), печатают «a»/«ф» вместо символа
(omacom/try-omarchy #222, Qt forum 19330; в документации Apple сказано, что строку могут игнорировать).
Возможно, это и есть часть причины, по которой Telegram/Qt потребовал режим доставки `session`.
Сделать: ставить реальный keycode символа в целевой раскладке (обратная таблица из `KeyboardTables`, у
`LayoutMapper` она по сути есть), для символов вне таблицы — keycode, не соответствующий букве. Проверить в
Telegram, JetBrains, TextEdit, Chrome при `postToPid` и при session.

## Progress

_Шаги не заданы. `rtp steps <id> --set "…"` или `--from-plan <файл>`._

## Log

- 2026-09-30: triage — pipeline `minimal`, reason: исследование: keyCode 0 = kVK_ANSI_A; Qt/Java/VM/remote транслируют по keycode и печатают a (espanso, omarchy, Qt forum)

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
