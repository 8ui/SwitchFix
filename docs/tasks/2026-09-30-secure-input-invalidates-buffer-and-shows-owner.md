---
id: 2026-09-30-secure-input-invalidates-buffer-and-shows-owner
title: Invalidate the buffer on Secure Input changes and show which app holds it
type: feature
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

_Шаги не заданы. `rtp steps <id> --set "…"` или `--from-plan <файл>`._

## Log

- 2026-09-30: triage — pipeline `minimal`, reason: исследование: Secure Input залипает (1Password, Terminal), SwitchFix молча глохнет, буфер рассинхронизируется

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
