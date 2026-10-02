---
id: 2026-10-02-hotkey-reads-the-word-before-the-caret-after-a-click-or
title: Hotkey reads the word before the caret after a click or arrow key
type: feature
pipeline: no-spec
phase: impl
created: 2026-10-02
updated: 2026-10-02
blocked_by: null
steps_done: 3
steps_total: 4
step_current: 4
artifacts:
  spec: null
  plan: docs/plans/hotkey-after-click-plan.md
  branch: null
  pr: null
---

## Context

_2-5 строк: что делаем и зачем. Задача этой секции — чтобы через N дней можно было восстановить контекст без чтения spec/plan._

## Progress

1. ✅ Kind.caretMove + классификация + автомат (все exhaustive switch) + тесты
2. ✅ InputEngine: focusResolved/focusMoved, задержка, enforce-сверка, терминалы; AppDelegate
3. ✅ Тесты пайплайна
4. ▶ CI, ревью, документация (CLAUDE.md, долг исходной задачи)

## Log

- 2026-10-02: triage — pipeline `no-spec`, reason: Долг из 2026-09-30-hotkey-converts-…: KeyboardMonitor/CapturedInput/InputStateMachine/InputEngine + тесты, известная архитектура (ScreenSuffix), неочевидная реализация (смена контекста стирает суффикс, отставание AX) → no-spec. Brainstorm: пользователь отдал выбор долга; результат — клик/стрелка → хоткей без набора конвертирует слово перед кареткой; Cmd+V/Opt+Backspace/forward delete/Tab/Esc/правый клик — по-прежнему невидимая правка; готово = тесты пайплайна + CI зелёный.
- 2026-10-02: brainstorm: пользователь отдал выбор долга; выбран «хоткей после клика/стрелки»; критерий — тесты пайплайна + CI
- 2026-10-02: artifacts.plan = docs/plans/hotkey-after-click-plan.md
- 2026-10-02: plan drafted
- 2026-10-02: plan-review (Plan, opus): 3 blocker (терминалы, равные устаревшие чтения AX, Shift+стрелка) + should-fix учтены: сверка поля перед удалением вместо двойного чтения, пауза 200 мс от caretMove, только enforce, без Shift/↑↓/PgUp/PgDn/кликов с модификаторами, явные focusResolved/focusMoved
- 2026-10-02: шаг 1 ✅ Kind.caretMove + классификация + автомат (все exhaustive switch) + тесты — Kind.caretMove, classifyMouseDown/isCaretMove, focusResolved/focusMoved
- 2026-10-02: шаг 2 ✅ InputEngine: focusResolved/focusMoved, задержка, enforce-сверка, терминалы; AppDelegate — задержка 200 мс, enforce-сверка с requiresScreenMatch, терминалы через readsScreenAfterCaretMove
- 2026-10-02: шаг 3 ✅ Тесты пайплайна — тесты классификации, автомата, пайплайна
- 2026-10-02: шаг 4 ▶ CI, ревью, документация (CLAUDE.md, долг исходной задачи)

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] Клик по пункту меню/подсказке, вставляющий текст, считается движением каретки: защищают только пауза 200 мс от mouse-up и повторное чтение поля (оба из одного источника AX) — проверить на Mac в Chrome/Electron
- [ ] Гонка (безопасная): если уведомление о смене фокуса AX обработано раньше клика, клик отбрасывается как устаревший и хоткей в новом поле ничего не делает
- [ ] Терминалы вне fieldTextHidingBundleIdentifiers (Hyper, Tabby) не исключены из чтения слова после клика

## Verification

_Доказательства, а не утверждения. Заполняется `rtp verify <id> --run "<команда>"`: команда, exit code, хвост вывода._

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
