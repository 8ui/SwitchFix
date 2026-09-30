---
id: 2026-09-30-correction-verifies-field-text-before-deleting
title: "Correction leaves stray letters when the field changed the text (inline autocomplete, predictions, autocorrect)"
type: bug
pipeline: no-spec
phase: review
created: 2026-09-30
updated: 2026-09-30
blocked_by: null
steps_done: 6
steps_total: 7
step_current: 7
artifacts:
  spec: null
  plan: docs/plans/correction-verifies-field-text-plan.md
  branch: null
  pr: null
---

## Context

Самая частая жалоба у всех аналогов (Punto, RuSwitcher #16, Keyboop #21/#23, Lang Switcher, espanso #1747,
OpenKey #37): после коррекции остаётся лишняя буква — `gпривет`, `фapp`, `yyandex.ru`. Причины, общие для
listen-only архитектуры: поле само меняет текст между нашим буфером и эмиссией —
- inline-автодополнение (омнибокс Chrome/Safari, Spotlight, Raycast, zsh-autosuggest): первый Backspace гасит
  серую подсказку, а не удаляет символ;
- inline predictive text (macOS 14+) принимается тем же пробелом, на котором мы делаем flush;
- системная автокоррекция и Text Replacements (синхронизируются из iCloud) срабатывают на том же пробеле;
- умные кавычки/тире, умные пробелы Word.
Staleness-guards (`CorrectionPlan.isEligible`) этого не видят: контекст не менялся, изменилось содержимое поля.
Варианты: перед эмиссией читать через AX текст перед кареткой (`requestCaretContext` уже есть) и отменять
коррекцию при расхождении с буфером; OpenKey для Chromium выделяет слово Shift+← и удаляет одним Backspace;
исключать поля с автодополнением. Учесть задержку AX (таймаут 50 мс) и то, что в части приложений AX-значения нет —
там решить, fail-open или fail-closed. Ссылки — отчёт исследования в чате 2026-09-30.

## Progress

1. ✅ Вердикт FieldTextVerification + тесты
2. ✅ AX-чтение requestFieldText (verifyQueue)
3. ✅ InputEngine: проверка с дедлайном в prepareCorrection
4. ✅ Проводка AppDelegate + документация
5. ✅ Тесты движка
6. ✅ Ревью
7. ▶ Ручная проверка: омнибокс, Spotlight, TextEdit с автокоррекцией, VS Code (локально)

## Log

- 2026-09-30: triage — pipeline `no-spec`, reason: исследование аналогов: самая частая жалоба (gпривет) — автодополнение/inline predictions/автозамена меняют поле, буфер ≠ текст; нужна AX-сверка перед эмиссией
- 2026-09-30: brainstorm: пользователь выбрал fail-open при недоступном AX и не включать AXManualAccessibility для проверки; критерий — тесты вердикта и движка + CI, ручная проверка в омнибоксе/Spotlight/TextEdit с автокоррекцией
- 2026-09-30: artifacts.plan = docs/plans/correction-verifies-field-text-plan.md
- 2026-09-30: plan drafted
- 2026-09-30: plan-review (Plan-агент): правило отставания AX-текста (префикс), выделение без текста = mismatch, дедлайн 40 мс, отдельная verifyQueue, нормализация регистра/кавычек, окно UTF-16, пропуск для слова с экрана
- 2026-09-30: шаг 1 ✅ Вердикт FieldTextVerification + тесты
- 2026-09-30: шаг 2 ✅ AX-чтение requestFieldText (verifyQueue)
- 2026-09-30: шаг 3 ✅ InputEngine: проверка с дедлайном в prepareCorrection
- 2026-09-30: шаг 4 ✅ Проводка AppDelegate + документация
- 2026-09-30: шаг 5 ✅ Тесты движка
- 2026-09-30: ревью (субагент): lagging перечитывается каждые 8 мс до появления границы (иначе автокоррекция на том же пробеле проскакивала); префикс ≥ половины слова; тест «клавиша во время чтения» теперь реально идёт через чтение; тест: слово с экрана не перечитывается; док-комментарий CaretContext на место
- 2026-09-30: verify: `CI красный: https://github.com/8ui/SwitchFix/actions/runs/36776051345 (94e91b3) — request в verifyFieldText не @escaping, захват в локальных func ask/decide` → exit 1 ❌
- 2026-09-30: verify: `CI красный: https://github.com/8ui/SwitchFix/actions/runs/36776973579 (1713d71) — 1041/1042: тест ждал одно чтение, lagging теперь перечитывается (задумано)` → exit 1 ❌
- 2026-09-30: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36777646863 (7f6506d)` → exit 0 ✅
- 2026-09-30: шаг 6 ✅ Ревью — ревью субагента учтено, CI зелёный
- 2026-09-30: impl complete, CI зелёный; осталась ручная проверка (шаг 7, локально)

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

- [ ] Ghost text (inline predictions macOS 14+, zsh-autosuggest) не в AXValue — не ловится; next после каретки в вердикте не используется
- [ ] Режим layoutSwitch: handleLayoutChange конвертирует любое выделение — может быть inline-подсказкой омнибокса; отдельная задача
- [ ] Если граница так и не появилась за 40 мс (занятое приложение или поле её съело), коррекция идёт fail-open и может стереть на символ больше/попасть до автокоррекции — принято ради отстающего AX Chromium — переформулировано 2026-09-30

## Verification

- 2026-09-30 · `CI красный: https://github.com/8ui/SwitchFix/actions/runs/36776051345 (94e91b3) — request в verifyFieldText не @escaping, захват в локальных func ask/decide` · exit 1 ❌

  ```
  (без вывода)
  ```

- 2026-09-30 · `CI красный: https://github.com/8ui/SwitchFix/actions/runs/36776973579 (1713d71) — 1041/1042: тест ждал одно чтение, lagging теперь перечитывается (задумано)` · exit 1 ❌

  ```
  (без вывода)
  ```

- 2026-09-30 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36777646863 (7f6506d)` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

**Сгенерировано:** 2026-09-30 · `rtp handoff`

- **Задача:** `2026-09-30-correction-verifies-field-text-before-deleting` — Correction leaves stray letters when the field changed the text (inline autocomplete, predictions, autocorrect)
- **Фаза:** review (pipeline `no-spec`, type `bug`)
- **Прогресс:** 6/7 ▰▰▰▰▰▰▱
- **Worktree:** `/home/user/SwitchFix`
- **Ветка:** `claude/funny-ramanujan-sdgiso` — своих коммитов 6, отставание от origin/master 0
- **Незакоммиченного:** 2 файл(ов)

**Шаги плана**

1. ✅ Вердикт FieldTextVerification + тесты
2. ✅ AX-чтение requestFieldText (verifyQueue)
3. ✅ InputEngine: проверка с дедлайном в prepareCorrection
4. ✅ Проводка AppDelegate + документация
5. ✅ Тесты движка
6. ✅ Ревью
7. ▶ Ручная проверка: омнибокс, Spotlight, TextEdit с автокоррекцией, VS Code (локально)

**Файлы в работе**

- `ocs/tasks/2026-09-30-correction-verifies-field-text-before-deleting.md`
- `docs/tasks/index.md`

**git diff HEAD --stat**

```
...-correction-verifies-field-text-before-deleting.md | 19 ++++++++++++++-----
 docs/tasks/index.md                                   |  4 ++--
 2 files changed, 16 insertions(+), 7 deletions(-)
```

**Последние коммиты**

- `7f6506d test(engine): a lagging field is read more than once`
- `1713d71 fix(engine): field-text request escapes into the re-read closures`
- `94e91b3 fix(engine): read a lagging field again until the boundary shows`

**Последние записи лога**

- 2026-09-30: verify: `CI красный: https://github.com/8ui/SwitchFix/actions/runs/36776051345 (94e91b3) — request в verifyFieldText не @escaping, захват в локальных func ask/decide` → exit 1 ❌
- 2026-09-30: verify: `CI красный: https://github.com/8ui/SwitchFix/actions/runs/36776973579 (1713d71) — 1041/1042: тест ждал одно чтение, lagging теперь перечитывается (задумано)` → exit 1 ❌
- 2026-09-30: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36777646863 (7f6506d)` → exit 0 ✅
- 2026-09-30: шаг 6 ✅ Ревью — ревью субагента учтено, CI зелёный
- 2026-09-30: impl complete, CI зелёный; осталась ручная проверка (шаг 7, локально)

**Открытые долги (3)**

- Ghost text (inline predictions macOS 14+, zsh-autosuggest) не в AXValue — не ловится; next после каретки в вердикте не используется
- Режим layoutSwitch: handleLayoutChange конвертирует любое выделение — может быть inline-подсказкой омнибокса; отдельная задача
- Если граница так и не появилась за 40 мс (занятое приложение или поле её съело), коррекция идёт fail-open и может стереть на символ больше/попасть до автокоррекции — принято ради отстающего AX Chromium — переформулировано 2026-09-30

**Следующее действие**

- rtp verify по командам проекта (rtp next 2026-09-30-correction-verifies-field-text-before-deleting), затем ревью субагентом → rtp phase 2026-09-30-correction-verifies-field-text-before-deleting --to done

**Заметки агента** (не выводятся из кода — грабли, тупики, договорённости)

<!-- handoff-notes -->
- 2026-09-30: Код в claude/funny-ramanujan-sdgiso, CI зелёный (7f6506d), PR не открыт. Осталась ручная проверка на macOS: омнибокс Chrome/Safari (выделенная подсказка → отмена), Spotlight, TextEdit с автокоррекцией (ghbdtn → отмена при замене), VS Code с деревом и без. Для сравнения: defaults write com.switchfix.app SwitchFix_verifyFieldText -bool NO. Смотреть лог: correction cancelled reason=field-text-*, field text <verdict> ms=
<!-- /handoff-notes -->

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
