---
id: 2026-09-30-ax-manual-accessibility-screen-reader-side-effects
title: AXManualAccessibility stays on and switches apps into screen-reader mode
type: bug
pipeline: minimal
phase: review
created: 2026-09-30
updated: 2026-09-30
blocked_by: null
steps_done: 3
steps_total: 4
step_current: 4
artifacts:
  spec: null
  plan: null
  branch: null
  pr: null
---

## Context

`AccessibilityFocusCoordinator.selectedText` и `caretContext` (Permissions.swift:362,385) ставят
`AXManualAccessibility = true` на приложение. Вызываются по требованию (AppDelegate.swift:61,69 — хоткей/выделение),
но атрибут после этого остаётся включённым до перезапуска приложения. Известные побочные эффекты: VS Code
переходит в режим скринридера (звуки, ломаются хоткеи Copilot — microsoft/vscode #196505), Chrome заметно
тяжелеет (Rectangle #1065), Qt/Telegram показывает баннер «включён скринридер» (PolterType #66), в части версий
Electron атрибут не поддерживается (electron #37465).
Сделать: воспроизвести в VS Code/Slack/Chrome; если подтверждается — ставить атрибут только если без него AX не
видит фокус, и/или снимать его обратно (false) после запроса; не ставить его не-Electron-приложениям.
Если задача `correction-verifies-field-text-before-deleting` начнёт читать AX на каждой коррекции, эта проблема
станет массовой — решать до неё или вместе.

## Progress

1. ✅ Условное включение + отложенное выключение
2. ✅ Документация
3. ✅ Ревью
4. ▶ Ручная проверка VS Code/Slack/Chrome/Telegram (локально)

## Log

- 2026-09-30: triage — pipeline `minimal`, reason: исследование: VS Code #196505 (режим скринридера), PolterType #66 (баннер в Telegram), нагрузка на Chrome
- 2026-09-30: brainstorm: воспроизвести в облаке нельзя (нет macOS); делаем безопасную часть: атрибут только если без него фокус не виден, выключаем через 30 с после последнего запроса и при выходе, не трогаем, если его включил кто-то другой; критерий — CI + ручная проверка VS Code/Slack/Chrome/Telegram (локально)
- 2026-09-30: шаг 1 ✅ Условное включение + отложенное выключение
- 2026-09-30: шаг 2 ✅ Документация
- 2026-09-30: ревью (субагент): атрибут включается и когда фокус есть, но без kAXSelectedTextRange (Chromium отдаёт контейнер); не трогаем при таймауте AX (.cannotComplete), VoiceOver, AXEnhancedUserInterface; уже наш — переустанавливаем true (могли выключить)
- 2026-09-30: шаг 3 ✅ Ревью
- 2026-09-30: impl complete; ручная проверка — шаг 4 (локально)
- 2026-09-30: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36772967020 (374657a)` → exit 0 ✅

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] Первый запрос после включения ждёт дерево до 150 мс (3 × 50 мс на queryQueue); проверить локально на Electron, хватает ли — переформулировано 2026-09-30
- [ ] После аварийного выхода атрибут остаётся включённым, и следующий запуск его не выключит (фокус виден — не наш); reset при выходе может разминуться с запросом между set и schedule; Electron может не отвечать на getter AXManualAccessibility — тогда включённый скринридером атрибут выглядит «не включённым»

## Verification

- 2026-09-30 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36772967020 (374657a)` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

**Сгенерировано:** 2026-09-30 · `rtp handoff`

- **Задача:** `2026-09-30-ax-manual-accessibility-screen-reader-side-effects` — AXManualAccessibility stays on and switches apps into screen-reader mode
- **Фаза:** review (pipeline `minimal`, type `bug`)
- **Прогресс:** 3/4 ▰▰▰▱
- **Worktree:** `/home/user/SwitchFix`
- **Ветка:** `claude/funny-ramanujan-sdgiso` — своих коммитов 75, отставание от origin/master 78
- **Незакоммиченного:** 3 файл(ов)

**Шаги плана**

1. ✅ Условное включение + отложенное выключение
2. ✅ Документация
3. ✅ Ревью
4. ▶ Ручная проверка VS Code/Slack/Chrome/Telegram (локально)

**Файлы в работе**

- `ocs/tasks/2026-09-30-ax-manual-accessibility-screen-reader-side-effects.md`
- `docs/tasks/2026-09-30-event-tap-dies-after-sleep-without-disabled-event.md`
- `docs/tasks/index.md`

**git diff HEAD --stat**

```
...ual-accessibility-screen-reader-side-effects.md |  7 ++-
 ...-tap-dies-after-sleep-without-disabled-event.md | 64 +++++++++++++++++++++-
 docs/tasks/index.md                                |  2 +-
 3 files changed, 69 insertions(+), 4 deletions(-)
```

**Последние коммиты**

- `2bb721b docs(tasks): CI evidence, close Enter and log tasks`
- `374657a fix(monitor,focus): review fixes for the tap watchdog and AXManualAccessibility`
- `684a327 docs(tasks): Enter task to review with CI evidence`

**Последние записи лога**

- 2026-09-30: шаг 2 ✅ Документация
- 2026-09-30: ревью (субагент): атрибут включается и когда фокус есть, но без kAXSelectedTextRange (Chromium отдаёт контейнер); не трогаем при таймауте AX (.cannotComplete), VoiceOver, AXEnhancedUserInterface; уже наш — переустанавливаем true (могли выключить)
- 2026-09-30: шаг 3 ✅ Ревью
- 2026-09-30: impl complete; ручная проверка — шаг 4 (локально)
- 2026-09-30: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36772967020 (374657a)` → exit 0 ✅

**Открытые долги (2)**

- Первый запрос после включения ждёт дерево до 150 мс (3 × 50 мс на queryQueue); проверить локально на Electron, хватает ли — переформулировано 2026-09-30
- После аварийного выхода атрибут остаётся включённым, и следующий запуск его не выключит (фокус виден — не наш); reset при выходе может разминуться с запросом между set и schedule; Electron может не отвечать на getter AXManualAccessibility — тогда включённый скринридером атрибут выглядит «не включённым»

**Следующее действие**

- rtp verify по командам проекта (rtp next 2026-09-30-ax-manual-accessibility-screen-reader-side-effects), затем ревью субагентом → rtp phase 2026-09-30-ax-manual-accessibility-screen-reader-side-effects --to done

**Заметки агента** (не выводятся из кода — грабли, тупики, договорённости)

<!-- handoff-notes -->
- 2026-09-30: Код в ветке claude/funny-ramanujan-sdgiso, CI зелёный; осталась только ручная проверка на macOS (последний шаг), после неё — done
<!-- /handoff-notes -->

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
