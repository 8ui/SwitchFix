---
id: 2026-10-01-after-switchfix-switches-the-layout-safari-types-in-the-new
title: "After SwitchFix switches the layout, Safari types in the new layout while key events still carry the old one"
type: bug
pipeline: no-spec
phase: triage
created: 2026-10-01
updated: 2026-10-01
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

_Шаги не заданы. `rtp steps <id> --set "…"` или `--from-plan <файл>`._

## Log

- 2026-10-01: triage — pipeline `no-spec`, reason: pre-existing, не связано со сверкой поля; нужен локальный repro и выбор источника символов (event string vs keycode+layout)

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
