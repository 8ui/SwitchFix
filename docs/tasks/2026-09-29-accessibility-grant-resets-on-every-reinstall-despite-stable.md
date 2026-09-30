---
id: 2026-09-29-accessibility-grant-resets-on-every-reinstall-despite-stable
title: Accessibility grant resets on every reinstall despite stable signing
type: bug
pipeline: minimal
phase: done
created: 2026-09-29
updated: 2026-09-30
blocked_by: null
steps_done: 3
steps_total: 3
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

1. ✅ install.sh: первая установка без вопроса, reset только ad-hoc/--reset-permissions
2. ✅ Проверка переустановки
3. ✅ Ревью

## Log

- 2026-09-29: triage — pipeline `minimal`, reason: после ./install.sh macOS сбрасывает Accessibility (лог 15:50:45 not granted), хотя подпись SwitchFix Development; до перезапуска AX чтение выделения возвращает nil
- 2026-09-30: resume: исследую причину (systematic-debugging)
- 2026-09-30: root cause: 'yes | ./install.sh' (агенты 29.09 15:07/15:44/15:50) отвечает y на 'first install?' → tccutil reset; подпись стабильна (DR = id + cert leaf)
- 2026-09-30: шаг 1 ✅ install.sh: первая установка без вопроса, reset только ad-hoc/--reset-permissions
- 2026-09-30: verify: `yes | ./install.sh (прежний репродьюсер) после фикса: ветка stable certificate, tccutil не вызван; лог 19:22:22 launched без 'Accessibility not granted'; ./install.sh --bogus → exit 2` → exit 0 ✅
- 2026-09-30: шаг 2 ✅ Проверка переустановки
- 2026-09-30: impl complete: install.sh без y/N-вопроса, reset только ad-hoc/--reset-permissions
- 2026-09-30: verify: `ревью: подпись определяется по установленному app (codesign -dvv | ^Authority=); изолированно: /Applications → certificate, ad-hoc копия → walkthrough. ВНИМАНИЕ: промежуточная версия с -dv (без Authority) в 19:27 сбросила TCC у пользователя` → exit 0 ✅
- 2026-09-30: fix по ревью: детект подписи по установленному app, reset на любом walkthrough; ошибка -dv сбросила права в 19:27, исправлено на -dvv; ждём перевыдачи прав для финального yes|./install.sh
- 2026-09-30: verify: `после перевыдачи прав: yes | ./install.sh с финальной версией (-dvv) → ветка stable certificate; 19:30:09 launched + monitoring started, без 'Accessibility not granted'` → exit 0 ✅
- 2026-09-30: шаг 3 ✅ Ревью
- 2026-09-30: verified: yes|./install.sh сохраняет права; закоммичено

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

_Отложенное, упрощения, известные пробелы. Формат — чекбоксы (их считают индекс и отчёты по долгам):_
_- `- [ ] <что отложено> — <почему/контекст>` — открытый долг_
_- `- [x] <что было> — закрыто YYYY-MM-DD: <причина/ссылка на task>` — закрытый_
_Без `[ ]`/`[x]` пункт невидим для агрегатора и теряется через 2 недели._

## Verification

- 2026-09-30 · `yes | ./install.sh (прежний репродьюсер) после фикса: ветка stable certificate, tccutil не вызван; лог 19:22:22 launched без 'Accessibility not granted'; ./install.sh --bogus → exit 2` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-09-30 · `ревью: подпись определяется по установленному app (codesign -dvv | ^Authority=); изолированно: /Applications → certificate, ad-hoc копия → walkthrough. ВНИМАНИЕ: промежуточная версия с -dv (без Authority) в 19:27 сбросила TCC у пользователя` · exit 0 ✅

  ```
  (без вывода)
  ```

- 2026-09-30 · `после перевыдачи прав: yes | ./install.sh с финальной версией (-dvv) → ветка stable certificate; 19:30:09 launched + monitoring started, без 'Accessibility not granted'` · exit 0 ✅

  ```
  (без вывода)
  ```

## Handoff

**Сгенерировано:** 2026-09-30 · `rtp handoff`

- **Задача:** `2026-09-29-accessibility-grant-resets-on-every-reinstall-despite-stable` — Accessibility grant resets on every reinstall despite stable signing
- **Фаза:** review (pipeline `minimal`, type `bug`)
- **Прогресс:** 2/3 ▰▰▱
- **Worktree:** `/Users/andrejsokolov/Desktop/projects/SwitchFix`
- **Ветка:** `claude/epic-galileo-zq47ec` — своих коммитов 55, отставание от origin/master 0
- **Незакоммиченного:** 5 файл(ов)

**Шаги плана**

1. ✅ install.sh: первая установка без вопроса, reset только ad-hoc/--reset-permissions
2. ✅ Проверка переустановки
3. ▶ Ревью

**Файлы в работе**

- `gitignore`
- `README.md`
- `docs/tasks/2026-09-29-accessibility-grant-resets-on-every-reinstall-despite-stable.md`
- `docs/tasks/index.md`
- `install.sh`

**git diff HEAD --stat**

```
.gitignore                                         |  2 +-
 README.md                                          |  2 +
 ...ant-resets-on-every-reinstall-despite-stable.md | 34 +++++++++++++----
 docs/tasks/index.md                                |  4 +-
 install.sh                                         | 43 ++++++++++++++++------
 5 files changed, 63 insertions(+), 22 deletions(-)
```

**Последние коммиты**

- `9683dca docs(tasks): close caret-word hotkey task`
- `b1ec339 feat(input): hotkey converts the word before the caret when nothing is buffered`
- `23c884c docs(tasks): note review for Words tab task`

**Последние записи лога**

- 2026-09-30: verify: `yes | ./install.sh (прежний репродьюсер) после фикса: ветка stable certificate, tccutil не вызван; лог 19:22:22 launched без 'Accessibility not granted'; ./install.sh --bogus → exit 2` → exit 0 ✅
- 2026-09-30: шаг 2 ✅ Проверка переустановки
- 2026-09-30: impl complete: install.sh без y/N-вопроса, reset только ad-hoc/--reset-permissions
- 2026-09-30: verify: `ревью: подпись определяется по установленному app (codesign -dvv | ^Authority=); изолированно: /Applications → certificate, ad-hoc копия → walkthrough. ВНИМАНИЕ: промежуточная версия с -dv (без Authority) в 19:27 сбросила TCC у пользователя` → exit 0 ✅
- 2026-09-30: fix по ревью: детект подписи по установленному app, reset на любом walkthrough; ошибка -dv сбросила права в 19:27, исправлено на -dvv; ждём перевыдачи прав для финального yes|./install.sh

**Следующее действие**

- rtp verify по командам проекта (rtp next 2026-09-29-accessibility-grant-resets-on-every-reinstall-despite-stable), затем ревью субагентом → rtp phase 2026-09-29-accessibility-grant-resets-on-every-reinstall-despite-stable --to done

**Заметки агента** (не выводятся из кода — грабли, тупики, договорённости)

<!-- handoff-notes -->
- 2026-09-29: Факты 2026-09-29: .codesign-identity = 'SwitchFix Development' (есть в keychain, build-app.sh подписывает им, --deep). После ./install.sh лог: 'Permissions: Accessibility not granted, requesting access', пользователь выдаёт снова; уже запущенный процесс до перезапуска получает nil от AX (selectionLen=-1). Input Monitoring при этом не слетал. Проверить: designated requirement (codesign -d -r-), сертификат self-signed без доверия (DR = cdhash?), что делает install.sh с TCC (tccutil/regrant-permissions.sh).
- 2026-09-30: После того как пользователь заново выдаст Accessibility + Input Monitoring: запустить 'yes | ./install.sh' и убедиться, что в логе нет 'Accessibility not granted'. Только после этого — коммит (install.sh, README.md) и done. codesign -dv НЕ печатает Authority — нужен -dvv.
<!-- /handoff-notes -->

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
