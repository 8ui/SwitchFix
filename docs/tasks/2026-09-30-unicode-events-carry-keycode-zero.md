---
id: 2026-09-30-unicode-events-carry-keycode-zero
title: Unicode correction events carry keyCode 0 (A)
type: bug
pipeline: minimal
phase: impl
created: 2026-09-30
updated: 2026-09-30
blocked_by: null
steps_done: 0
steps_total: 4
step_current: 1
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

1. ▶ Локально выяснить, как Qt/Java/UTM транслируют keycode (Unicode-строка или keycode через активную раскладку)
2. ⬜ Решение по результату
3. ⬜ Тест
4. ⬜ Ревью

## Log

- 2026-09-30: triage — pipeline `minimal`, reason: исследование: keyCode 0 = kVK_ANSI_A; Qt/Java/VM/remote транслируют по keycode и печатают a (espanso, omarchy, Qt forum)
- 2026-09-30: brainstorm: что — keycode символа из KeyboardTables (раскладка плана, потом любая), пробел 49; зачем — Qt/Java/удалённый доступ печатают «a» по keycode 0; критерий — тест keyCode(for:) + CI; проверка в Telegram/JetBrains — локально
- 2026-09-30: шаг 1 ✅ TextCorrector.keyCode(for:) + таблицы от InputEngine
- 2026-09-30: шаг 2 ✅ Тест
- 2026-09-30: ревью (субагент): фикс отменён. События постятся до switchTo(target), так что приложение, транслирующее keycode через активную раскладку, напечатает букву ИСХОДНОЙ раскладки (key 4 → h, т. е. ghbdtn вместо привет); э/є/ё/ґ попадают на мёртвые клавиши US-International (39, 50). Нужна локальная проверка в Telegram/JetBrains: какую раскладку они используют для keycode, и помогает ли переключить раскладку ДО эмиссии

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] Если реальный keycode — то только вместе со сменой раскладки ДО эмиссии и с проверкой мёртвых клавиш (US-International: ' и `); первая попытка (48abd3f) откачена — переформулировано после ревью — переформулировано 2026-09-30

## Verification

_Доказательства, а не утверждения. Заполняется `rtp verify <id> --run "<команда>"`: команда, exit code, хвост вывода._

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
