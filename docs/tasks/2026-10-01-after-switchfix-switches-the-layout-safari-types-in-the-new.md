---
id: 2026-10-01-after-switchfix-switches-the-layout-safari-types-in-the-new
title: "After SwitchFix switches the layout, Safari types in the new layout while key events still carry the old one"
type: bug
pipeline: no-spec
phase: impl
created: 2026-10-01
updated: 2026-10-01
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

Ручной тест пользователя в Safari 2026-10-01 (сборка 3169092, session tap): после автокоррекции
`цщкдв`→`world` SwitchFix в 09:32:00.073 переключил раскладку на английскую (`layout changed … generated=true`).
Затем пользователь набрал «такое» на английской раскладке, и Safari показал `nfrjt`, но в буфер (09:32:08)
пришла кириллица: `model decision corrected=false margin=-32.7`, ровно с обратным знаком к +32.7 у того же
слова, исправленного в 09:32:29. Символы берутся из `keyboardGetUnicodeString` события
(`KeyboardMonitor.eventCharacterString`; таблица `translations` работает только для HID-tap): macOS
приложила к событиям старую раскладку, хотя Safari перевёл keyCode по новой. Слово осталось
неисправленным, пользователь исправил его хоткеем (selection paste). Повторить локально; варианты —
переводить keyCode по `InputSourceManager`/`KeyboardTables` и для session tap, или сверять со строкой события.

## Progress

1. ✅ Сверка символа события с таблицей текущей раскладки
2. ✅ Тест чистой функции
3. ▶ Сборка, установка, проверка, CI

## Log

- 2026-10-01: triage — pipeline `no-spec`, reason: pre-existing, не связано со сверкой поля; нужен локальный repro и выбор источника символов (event string vs keycode+layout)
- 2026-10-01: Повтор пользователя 09:51: после self-switch на русскую 20 с событий с латиницей (margin −24.5/−47.9/−11.9 у hello/world/test), Safari печатал кириллицу. Фикс: в session tap символ из таблицы translations (текущий TIS, обновляется на каждом переключении) побеждает строку события, когда они расходятся по письменности (кириллица/не кириллица). План — в Context, отдельный документ не пишу: 1 файл + тест
- 2026-10-01: шаг 1 ✅ Сверка символа события с таблицей текущей раскладки
- 2026-10-01: шаг 2 ✅ Тест чистой функции — InputPipelineTestRunner 1101/0
- 2026-10-01: verify: `Локально: InputPipelineTestRunner 1101/0; сценарий пользователя (RU-раскладка: hello ghbdtn hello world test одним потоком событий со старой раскладкой) → TextEdit «hello привет hello world test», Telegram то же, Заметки «привет мир как дела» — раньше слова после self-switch отменялись/не исправлялись` → exit 0 ✅
- 2026-10-01: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36827574792 (4848b68)` → exit 0 ✅

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] Ручное переключение (Ctrl-Space/Globe) и сразу набор: таблица обновляется по распределённому уведомлению, первые миллисекунды она старая и теперь перебивает верный символ события (ревью); у собственного переключения закрыто вызовом didSelect
- [ ] ISO-клавиши 10/50 и программные события (text expander, auto-type) исключены из подмены — у них устаревшая раскладка не лечится
- [ ] Ру↔ук и пунктуация↔пунктуация на одной клавише при устаревшей раскладке не различаются (одна письменность)

## Verification

- 2026-10-01 · `Локально: InputPipelineTestRunner 1101/0; сценарий пользователя (RU-раскладка: hello ghbdtn hello world test одним потоком событий со старой раскладкой) → TextEdit «hello привет hello world test», Telegram то же, Заметки «привет мир как дела» — раньше слова после self-switch отменялись/не исправлялись` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-10-01 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36827574792 (4848b68)` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
