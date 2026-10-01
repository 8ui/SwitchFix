---
id: 2026-09-30-event-tap-dies-after-sleep-without-disabled-event
title: "Event tap silently dies after sleep, lock or re-signing"
type: bug
pipeline: minimal
phase: done
created: 2026-09-30
updated: 2026-10-01
blocked_by: null
steps_done: 4
steps_total: 4
step_current: null
artifacts:
  spec: null
  plan: null
  branch: claude/funny-ramanujan-sdgiso
  pr: "https://github.com/8ui/SwitchFix/pull/8"
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

1. ✅ restart/isTapEnabled/lastMouseDownUptime в KeyboardMonitor
2. ✅ Wake/unlock + сторож кликов в AppDelegate
3. ✅ Ревью
4. ✅ Ручная проверка sleep/lock/переподпись (локально)

## Log

- 2026-09-30: triage — pipeline `minimal`, reason: исследование: tap умирает после sleep/wake/lock без tapDisabled-события (Ghostty, OpenKey, Keyboop); нет подписки на wake и healthcheck
- 2026-09-30: brainstorm: что — пересоздавать tap по wake/screensDidWake/sessionDidBecomeActive/screenIsUnlocked + сторож: глобальный монитор кликов (без разрешений) сверяет, видел ли tap тот же клик; зачем — tap умирает молча; критерий — CI + ручная проверка sleep/lock (локально). stop() уже делал tapEnable(false)+CFMachPortInvalidate. Tap на main run loop, но listen-only — нажатия системы не задерживает, только наше наблюдение
- 2026-09-30: шаг 1 ✅ restart/isTapEnabled/lastMouseDownUptime в KeyboardMonitor
- 2026-09-30: шаг 2 ✅ Wake/unlock + сторож кликов в AppDelegate
- 2026-09-30: ревью (субагент): сторож сравнивает время самого клика (NSEvent.timestamp) с приёмом в tap — зависание main не даёт ложных рестартов; HID-tap не проверяется (не видит session-клики); wake/unlock — один рестарт через 1 с после последнего уведомления, мимо лимита; keyboardMonitor присваивается только после успешного start
- 2026-09-30: шаг 3 ✅ Ревью
- 2026-09-30: impl complete; ручная проверка — шаг 4 (локально)
- 2026-09-30: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36772967020 (374657a)` → exit 0 ✅
- 2026-09-30: artifacts.branch = claude/funny-ramanujan-sdgiso; artifacts.pr = https://github.com/8ui/SwitchFix/pull/8
- 2026-09-30: влито в master (https://github.com/8ui/SwitchFix/pull/8); осталась ручная проверка на macOS
- 2026-10-01: verify: `Локально: переподпись работающего /Applications/SwitchFix.app той же identity (codesign --force) — тот же процесс продолжил получать нажатия, коррекция ghbdtn→привет прошла; сторож не понадобился. Сон и блокировка экрана не проверены (нужна разблокировка паролем) — за пользователем` → exit 0 ✅
- 2026-10-01: verify: `Пользователь: блокировка экрана — 13:27:12 'recreating event tap (com.apple.screenIsUnlocked)', коррекции в Telegram сразу после разблокировки прошли` → exit 0 ✅
- 2026-10-01: шаг 4 ✅ Ручная проверка sleep/lock/переподпись (локально) — lock ✓, переподпись ✓, сон пропущен
- 2026-10-01: ручная проверка: блокировка и переподпись пройдены, сон пропущен по решению пользователя

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] Сторож доказывает только доставку мыши: tap, получающий клики без клавиш (переподпись со старым Input Monitoring), не ловится; состояние модификатор-хоткея (controlTapArmed, lastAlphaShiftState) переживает рестарт
- [ ] Сон/пробуждение не проверены вручную — пропущено по решению пользователя 2026-10-01; блокировка и переподпись проверены

## Verification

- 2026-09-30 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36772967020 (374657a)` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-10-01 · `Локально: переподпись работающего /Applications/SwitchFix.app той же identity (codesign --force) — тот же процесс продолжил получать нажатия, коррекция ghbdtn→привет прошла; сторож не понадобился. Сон и блокировка экрана не проверены (нужна разблокировка паролем) — за пользователем` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-10-01 · `Пользователь: блокировка экрана — 13:27:12 'recreating event tap (com.apple.screenIsUnlocked)', коррекции в Telegram сразу после разблокировки прошли` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

**Сгенерировано:** 2026-10-01 · `rtp handoff`

- **Задача:** `2026-09-30-event-tap-dies-after-sleep-without-disabled-event` — Event tap silently dies after sleep, lock or re-signing
- **Фаза:** review (pipeline `minimal`, type `bug`)
- **Прогресс:** 3/4 ▰▰▰▱
- **Worktree:** `/Users/andrejsokolov/Desktop/projects/SwitchFix`
- **Ветка:** `master` — своих коммитов 0, отставание от origin/master 0
- **Незакоммиченного:** 4 файл(ов)

**Шаги плана**

1. ✅ restart/isTapEnabled/lastMouseDownUptime в KeyboardMonitor
2. ✅ Wake/unlock + сторож кликов в AppDelegate
3. ✅ Ревью
4. ▶ Ручная проверка sleep/lock/переподпись (локально)

**Файлы в работе**

- `ocs/tasks/2026-09-30-ax-manual-accessibility-screen-reader-side-effects.md`
- `docs/tasks/2026-09-30-event-tap-dies-after-sleep-without-disabled-event.md`
- `docs/tasks/2026-09-30-secure-input-invalidates-buffer-and-shows-owner.md`
- `docs/tasks/index.md`

**git diff HEAD --stat**

```
...manual-accessibility-screen-reader-side-effects.md | 19 ++++++++++++++-----
 ...ent-tap-dies-after-sleep-without-disabled-event.md |  7 +++++++
 ...secure-input-invalidates-buffer-and-shows-owner.md | 17 +++++++++++++----
 docs/tasks/index.md                                   |  8 +++-----
 4 files changed, 37 insertions(+), 14 deletions(-)
```

**Последние коммиты**

- `7d0b8b8 docs(tasks): local manual checks for the PR 8 tasks`
- `3cfd637 docs(tasks): close tasks merged in PR 10`
- `0b5bb5c Merge pull request #10 from 8ui/claude/beautiful-shannon-hg5k6h`

**Последние записи лога**

- 2026-09-30: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36772967020 (374657a)` → exit 0 ✅
- 2026-09-30: artifacts.branch = claude/funny-ramanujan-sdgiso; artifacts.pr = https://github.com/8ui/SwitchFix/pull/8
- 2026-09-30: влито в master (https://github.com/8ui/SwitchFix/pull/8); осталась ручная проверка на macOS
- 2026-10-01: verify: `Локально: переподпись работающего /Applications/SwitchFix.app той же identity (codesign --force) — тот же процесс продолжил получать нажатия, коррекция ghbdtn→привет прошла; сторож не понадобился. Сон и блокировка экрана не проверены (нужна разблокировка паролем) — за пользователем` → exit 0 ✅
- 2026-10-01: verify: `Пользователь: блокировка экрана — 13:27:12 'recreating event tap (com.apple.screenIsUnlocked)', коррекции в Telegram сразу после разблокировки прошли` → exit 0 ✅

**Открытые долги (1)**

- Сторож доказывает только доставку мыши: tap, получающий клики без клавиш (переподпись со старым Input Monitoring), не ловится; состояние модификатор-хоткея (controlTapArmed, lastAlphaShiftState) переживает рестарт

**Следующее действие**

- rtp verify по командам проекта (rtp next 2026-09-30-event-tap-dies-after-sleep-without-disabled-event), затем ревью субагентом → rtp phase 2026-09-30-event-tap-dies-after-sleep-without-disabled-event --to done

**Заметки агента** (не выводятся из кода — грабли, тупики, договорённости)

<!-- handoff-notes -->
- 2026-09-30: Код в ветке claude/funny-ramanujan-sdgiso, CI зелёный; осталась только ручная проверка на macOS (последний шаг), после неё — done
- 2026-10-01: Осталось только проверить сон (pmset sleepnow или закрыть крышку): в логе должно быть 'recreating event tap' по wake и рабочие коррекции после. Блокировка и переподпись проверены 2026-10-01.
<!-- /handoff-notes -->

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
