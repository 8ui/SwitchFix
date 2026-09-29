---
id: 2026-09-29-accessibility-grant-resets-on-every-reinstall-despite-stable
title: Accessibility grant resets on every reinstall despite stable signing
type: bug
pipeline: minimal
phase: triage
created: 2026-09-29
updated: 2026-09-29
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

_2-5 строк: что делаем и зачем. Задача этой секции — чтобы через N дней можно было восстановить контекст без чтения spec/plan._

## Progress

_Шаги не заданы. `rtp steps <id> --set "…"` или `--from-plan <файл>`._

## Log

- 2026-09-29: triage — pipeline `minimal`, reason: после ./install.sh macOS сбрасывает Accessibility (лог 15:50:45 not granted), хотя подпись SwitchFix Development; до перезапуска AX чтение выделения возвращает nil

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

**Сгенерировано:** 2026-09-29 · `rtp handoff`

- **Задача:** `2026-09-29-accessibility-grant-resets-on-every-reinstall-despite-stable` — Accessibility grant resets on every reinstall despite stable signing
- **Фаза:** triage (pipeline `minimal`, type `bug`)
- **Worktree:** `/Users/andrejsokolov/Desktop/projects/SwitchFix`
- **Ветка:** `claude/epic-galileo-zq47ec` — своих коммитов 40, отставание от origin/master 0
- **Незакоммиченного:** 4 файл(ов)

**Файлы в работе**

- `ocs/tasks/2026-09-29-key-tables-from-installed-keyboard-layouts.md`
- `docs/tasks/index.md`
- `docs/plans/key-tables-from-installed-layouts-plan.md`
- `docs/tasks/2026-09-29-accessibility-grant-resets-on-every-reinstall-despite-stable.md`

**git diff HEAD --stat**

```
...-09-29-key-tables-from-installed-keyboard-layouts.md | 17 ++++++++++++-----
 docs/tasks/index.md                                     |  5 +++--
 2 files changed, 15 insertions(+), 7 deletions(-)
```

**Последние коммиты**

- `16155c7 fix(selection): convert letterless selections from the current layout first`
- `997338e docs: key tables from installed layouts`
- `52b87ae refactor(layout): replace UkrainianKeyboardVariant with key tables from installed layouts`

**Последние записи лога**

- 2026-09-29: triage — pipeline `minimal`, reason: после ./install.sh macOS сбрасывает Accessibility (лог 15:50:45 not granted), хотя подпись SwitchFix Development; до перезапуска AX чтение выделения возвращает nil

**Следующее действие**

- реализовать → rtp phase 2026-09-29-accessibility-grant-resets-on-every-reinstall-despite-stable --to impl

**Заметки агента** (не выводятся из кода — грабли, тупики, договорённости)

<!-- handoff-notes -->
- 2026-09-29: Факты 2026-09-29: .codesign-identity = 'SwitchFix Development' (есть в keychain, build-app.sh подписывает им, --deep). После ./install.sh лог: 'Permissions: Accessibility not granted, requesting access', пользователь выдаёт снова; уже запущенный процесс до перезапуска получает nil от AX (selectionLen=-1). Input Monitoring при этом не слетал. Проверить: designated requirement (codesign -d -r-), сертификат self-signed без доверия (DR = cdhash?), что делает install.sh с TCC (tccutil/regrant-permissions.sh).
<!-- /handoff-notes -->

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
