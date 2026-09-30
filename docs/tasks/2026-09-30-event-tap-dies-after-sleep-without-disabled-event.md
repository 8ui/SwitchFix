---
id: 2026-09-30-event-tap-dies-after-sleep-without-disabled-event
title: "Event tap silently dies after sleep, lock or re-signing"
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

`KeyboardMonitor` включает tap обратно на `tapDisabledByTimeout/ByUserInput` (KeyboardMonitor.swift:257), но
по сообщениям других проектов tap умирает и без этого события: после sleep/wake и lock/unlock (Ghostty
discussion #11819, OpenKey #87, Keyboop #23 — «со временем авто отваливается» на macOS 27), после переподписи
бинарника «tapIsEnabled() == true, но событий нет» (danielraffel.me, 2026-02), после отзыва разрешения на ходу
(preflight в живом процессе кэшируется, Apple forums 735204). Подписки на `NSWorkspace.didWakeNotification` /
`sessionDidBecomeActiveNotification` в коде нет, healthcheck нет.
Сделать: пересоздание tap по wake/unlock; периодическая проверка (например, tap жив, но ни одного события за
долгое время при активном вводе — или пробный тестовый tap); на выходе `CGEvent.tapEnable(false)` +
`CFMachPortInvalidate` (Tahoe: брошенный tap даёт рекурсию и CPU в WindowServer, PlayCover #2105).
Проверить, на каком run loop висит tap: на main любой лаг UI задерживает все нажатия в системе.

## Progress

_Шаги не заданы. `rtp steps <id> --set "…"` или `--from-plan <файл>`._

## Log

- 2026-09-30: triage — pipeline `minimal`, reason: исследование: tap умирает после sleep/wake/lock без tapDisabled-события (Ghostty, OpenKey, Keyboop); нет подписки на wake и healthcheck

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
