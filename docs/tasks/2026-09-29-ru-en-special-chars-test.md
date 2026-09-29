---
id: 2026-09-29-ru-en-special-chars-test
title: Тест обратного маппинга спецсимволов RU→EN
type: chore
pipeline: minimal
phase: done
created: 2026-09-29
updated: 2026-09-29
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

1. ✅ Добавить runSuite RU→EN спецсимволы
2. ✅ CI зелёный
3. ✅ Ревью

## Log

- 2026-09-29: triage — pipeline `minimal`, reason: 1 файл, только тест, без бизнес-логики; задача-проверка работы rtp в облаке
- 2026-09-29: brainstorm: пользователь делегировал выбор тривиальной задачи; done = новый сьют в TestRunner + зелёный CI
- 2026-09-29: шаг 1 ▶ Добавить runSuite RU→EN спецсимволы
- 2026-09-29: шаг 1 ✅ Добавить runSuite RU→EN спецсимволы — 4 ассерта, включая заглавные
- 2026-09-29: impl complete: runSuite 'LayoutMapper: Special chars RU→EN'
- 2026-09-29: code-review: субагент general-purpose (fresh-eyes) — замечаний нет; nit про 3-символьный ассерт оставлен как есть
- 2026-09-29: verify: `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36548587047` → exit 0 ✅
- 2026-09-29: шаг 2 ✅ CI зелёный
- 2026-09-29: шаг 3 ✅ Ревью — general-purpose субагент: замечаний нет
- 2026-09-29: CI зелёный, ревью пройдено

## Decisions

_Нетривиальные решения по ходу задачи. Одна строка на решение._

## Debt

_Отложенное, упрощения, известные пробелы. Формат — чекбоксы (их считают индекс и отчёты по долгам):_
_- `- [ ] <что отложено> — <почему/контекст>` — открытый долг_
_- `- [x] <что было> — закрыто YYYY-MM-DD: <причина/ссылка на task>` — закрытый_
_Без `[ ]`/`[x]` пункт невидим для агрегатора и теряется через 2 недели._

## Verification

- 2026-09-29 · `CI зелёный: https://github.com/8ui/SwitchFix/actions/runs/36548587047` · exit 0 ✅

  ```
  head 4b68e2e (включает 5a49dfd с тестом): build + TestRunner + InputPipelineTestRunner + build-app — success
  ```

## Handoff

_Передача контекста следующему агенту. Перезаписывается целиком через `rtp handoff <id>`._

## Blockers

_Текущие блокеры. Очистить, когда разрешены._
