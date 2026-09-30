---
id: 2026-09-30-unicode-events-carry-keycode-zero
title: Unicode correction events carry keyCode 0 (A)
type: bug
pipeline: minimal
phase: impl
created: 2026-09-30
updated: 2026-09-30
blocked_by: null
steps_done: 2
steps_total: 4
step_current: 3
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

1. ✅ TextCorrector.keyCode(for:) + таблицы от InputEngine
2. ✅ Тест
3. ▶ Ревью
4. ⬜ Проверка в Telegram/JetBrains/TextEdit/Chrome (локально)

## Log

- 2026-09-30: triage — pipeline `minimal`, reason: исследование: keyCode 0 = kVK_ANSI_A; Qt/Java/VM/remote транслируют по keycode и печатают a (espanso, omarchy, Qt forum)
- 2026-09-30: brainstorm: что — keycode символа из KeyboardTables (раскладка плана, потом любая), пробел 49; зачем — Qt/Java/удалённый доступ печатают «a» по keycode 0; критерий — тест keyCode(for:) + CI; проверка в Telegram/JetBrains — локально
- 2026-09-30: шаг 1 ✅ TextCorrector.keyCode(for:) + таблицы от InputEngine
- 2026-09-30: шаг 2 ✅ Тест

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] Символы вне таблиц (эмодзи и т. п.) по-прежнему идут с keycode 0; Shift для заглавных не выставляется (флаги очищены намеренно) — приложения, транслирующие по keycode, получат строчную

## Verification

_Доказательства, а не утверждения. Заполняется `rtp verify <id> --run "<команда>"`: команда, exit code, хвост вывода._

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
