---
id: 2026-09-30-secure-input-invalidates-buffer-and-shows-owner
title: Invalidate the buffer on Secure Input changes and show which app holds it
type: feature
pipeline: minimal
phase: review
created: 2026-09-30
updated: 2026-09-30
blocked_by: null
steps_done: 4
steps_total: 5
step_current: 5
artifacts:
  spec: null
  plan: null
  branch: claude/funny-ramanujan-sdgiso
  pr: "https://github.com/8ui/SwitchFix/pull/8"
---

## Context

Пока включён Secure Event Input, tap не получает keyDown — SwitchFix «глохнет», а буфер слова расходится с
текстом (пропущенные нажатия). Сейчас `IsSecureEventInputEnabled()` читается только при разрешении фокуса через
AX (Permissions.swift:283). Secure Input часто «залипает»: 1Password, Terminal/iTerm Secure Keyboard Entry
(iTerm включает сам на промптах пароля), loginwindow после разблокировки, браузеры (Typinator KB, Apple forums
726353, Hammerspoon #3527). Пользователь видит «сломалось».
Сделать: (1) инвалидировать буфер на любом переходе Secure Input (опрос или проверка на каждом событии/флаше);
(2) пункт-предупреждение в меню «Исправление на паузе: защищённый ввод включён <app>» — владельца можно взять
из `ioreg -l -d 1 -w 0 | grep kCGSSessionSecureInputPID` (best-effort, по словам Quinn из Apple PID бывает ложным,
особенно loginwindow). Уведомление не должно красть фокус (RuSwitcher #27). Строки — через L10n.tr.

## Progress

1. ✅ SecureInput + SecureInputMonitor (Utils)
2. ✅ Инвалидация в AppDelegate
3. ✅ Пункт меню + L10n + README
4. ✅ Ревью
5. ▶ Ручная проверка: Terminal Secure Keyboard Entry, 1Password (локально)

## Log

- 2026-09-30: triage — pipeline `minimal`, reason: исследование: Secure Input залипает (1Password, Terminal), SwitchFix молча глохнет, буфер рассинхронизируется
- 2026-09-30: brainstorm: что — опрос IsSecureEventInputEnabled раз в 1 с, на переходе новый epoch + focusMayChange, пункт в меню с владельцем из CGSessionCopyCurrentDictionary (kCGSSessionSecureInputPID, без ioreg); уведомлений нет — фокус не крадём; критерий — CI зелёный, ручная проверка с Terminal Secure Keyboard Entry
- 2026-09-30: шаг 1 ✅ SecureInput + SecureInputMonitor (Utils)
- 2026-09-30: шаг 2 ✅ Инвалидация в AppDelegate
- 2026-09-30: шаг 3 ✅ Пункт меню + L10n + README
- 2026-09-30: ревью (субагент): опрос 0.5 с (переход между опросами при 1 с терялся), имя владельца только для обычных приложений (loginwindow/фоновые PID часто устаревшие); остальное — минор
- 2026-09-30: шаг 4 ✅ Ревью
- 2026-09-30: impl complete; ручная проверка — шаг 5 (локально)
- 2026-09-30: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36772505902 (9e5f0e8)` → exit 0 ✅
- 2026-09-30: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36772967020 (374657a)` → exit 0 ✅
- 2026-09-30: artifacts.branch = claude/funny-ramanujan-sdgiso; artifacts.pr = https://github.com/8ui/SwitchFix/pull/8

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

_Отложенное, упрощения, известные пробелы. Формат — чекбоксы (их считают индекс и отчёты по долгам):_
_- `- [ ] <что отложено> — <почему/контекст>` — открытый долг_
_- `- [x] <что было> — закрыто YYYY-MM-DD: <причина/ссылка на task>` — закрытый_
_Без `[ ]`/`[x]` пункт невидим для агрегатора и теряется через 2 недели._

## Verification

- 2026-09-30 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36772505902 (9e5f0e8)` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-09-30 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36772967020 (374657a)` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

**Сгенерировано:** 2026-09-30 · `rtp handoff`

- **Задача:** `2026-09-30-secure-input-invalidates-buffer-and-shows-owner` — Invalidate the buffer on Secure Input changes and show which app holds it
- **Фаза:** review (pipeline `minimal`, type `feature`)
- **Прогресс:** 4/5 ▰▰▰▰▱
- **Worktree:** `/home/user/SwitchFix`
- **Ветка:** `claude/funny-ramanujan-sdgiso` — своих коммитов 75, отставание от origin/master 78
- **Незакоммиченного:** 4 файл(ов)

**Шаги плана**

1. ✅ SecureInput + SecureInputMonitor (Utils)
2. ✅ Инвалидация в AppDelegate
3. ✅ Пункт меню + L10n + README
4. ✅ Ревью
5. ▶ Ручная проверка: Terminal Secure Keyboard Entry, 1Password (локально)

**Файлы в работе**

- `ocs/tasks/2026-09-30-ax-manual-accessibility-screen-reader-side-effects.md`
- `docs/tasks/2026-09-30-event-tap-dies-after-sleep-without-disabled-event.md`
- `docs/tasks/2026-09-30-secure-input-invalidates-buffer-and-shows-owner.md`
- `docs/tasks/index.md`

**git diff HEAD --stat**

```
...ual-accessibility-screen-reader-side-effects.md | 67 +++++++++++++++++++++-
 ...-tap-dies-after-sleep-without-disabled-event.md | 64 ++++++++++++++++++++-
 ...ure-input-invalidates-buffer-and-shows-owner.md |  7 +++
 docs/tasks/index.md                                |  2 +-
 4 files changed, 135 insertions(+), 5 deletions(-)
```

**Последние коммиты**

- `2bb721b docs(tasks): CI evidence, close Enter and log tasks`
- `374657a fix(monitor,focus): review fixes for the tap watchdog and AXManualAccessibility`
- `684a327 docs(tasks): Enter task to review with CI evidence`

**Последние записи лога**

- 2026-09-30: ревью (субагент): опрос 0.5 с (переход между опросами при 1 с терялся), имя владельца только для обычных приложений (loginwindow/фоновые PID часто устаревшие); остальное — минор
- 2026-09-30: шаг 4 ✅ Ревью
- 2026-09-30: impl complete; ручная проверка — шаг 5 (локально)
- 2026-09-30: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36772505902 (9e5f0e8)` → exit 0 ✅
- 2026-09-30: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36772967020 (374657a)` → exit 0 ✅

**Следующее действие**

- rtp verify по командам проекта (rtp next 2026-09-30-secure-input-invalidates-buffer-and-shows-owner), затем ревью субагентом → rtp phase 2026-09-30-secure-input-invalidates-buffer-and-shows-owner --to done

**Заметки агента** (не выводятся из кода — грабли, тупики, договорённости)

<!-- handoff-notes -->
- 2026-09-30: Код в ветке claude/funny-ramanujan-sdgiso, CI зелёный; осталась только ручная проверка на macOS (последний шаг), после неё — done
<!-- /handoff-notes -->

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
