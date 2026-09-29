# Anti-rationalization — when to STOP and return to Step 0

Reference loaded by `run-task-pipeline` SKILL.md. Read when the urge to skip a
step appears, or when reviewing why this skill exists.

## Rationalization Table

| Excuse | Reality |
|---|---|
| "Срочно, артефакты = потеря времени" | Task file = 30s (`rtp new ...`), brainstorm (3 Q) = 60s. Фикс без этого обычно дороже в отладке. |
| "Пользователь сказал план не нужен" | User sets scope, skill sets process. Preset is YOUR proposal — user confirms/overrides explicitly, not dictates. |
| "Очевидная задача, brainstorm избыточен" | If you can't answer 3 questions in 30s, it's not obvious. |
| "Уже начал код, просто дооформи" | This is `resumed-from-draft`: `rtp new ... --reason "resumed from draft"`, log what's done, continue via pipeline. |
| "Minimal Blast Radius = без артефактов" | MBR is about code (don't touch extra files), not about process. Concept confusion. |
| "Пресет minimal, ревью пропущу" | Invariant #5. `minimal` economizes spec+plan, NOT review. |
| "Spec тривиальный, review не нужен" | Invariant #3. Subagent review = 2 min. Triviality is the cheapest case to review. |
| "Index обновлю потом" | `rtp index` = 200ms. Hook already runs it auto after each task-file edit. "Потом" = never. |
| "Это hotfix, pipeline после выкатки" | No. `minimal` preset = 5–10 min total. Hotfix без review = bug 2.0. |
| "Нет папки docs/tasks/, значит ничего тут не велось" | `rtp new` создаст её. Folders are cheap. |
| "Debt одной строкой `- ...` без `[ ]` — это просто заметка" | Индекс и отчёты по долгам считают только `- [ ]`. Без чекбокса — невидимо, через пару недель потеряно. Используй `rtp debt <id> --add "..."` чтобы не сломать формат. |
| "Сам отредактирую frontmatter в файле задачи" | Каждый ручной Edit task-файла — шанс сломать формат. Используй `rtp phase` / `rtp debt` / `rtp artifact` (он пишет `artifacts.spec/plan/branch/pr` и эскалирует `pipeline`). Они и `updated:` бампают, и index дёргают. |
| "Субагента звать нельзя — харнесс запрещает" | Запрет формулируется «пока пользователь не попросил». Просьба есть — раздел STANDING USER AUTHORIZATION в SKILL.md, написанный владельцем машины. Спрашивать разрешение повторно не нужно. |
| "Ревью сделаю сам, я же вижу код целиком" | Именно поэтому и не видишь. Ты подтверждаешь свою же модель. Fresh eyes = субагент без твоего обоснования в промпте. |
| "Шаги плана держу в голове" | Голова не переживает компакт и не читается следующим агентом. `rtp steps` = 20 секунд, дальше `rtp step --done N` по одному. |
| "Тесты прогнал, писать в задачу не буду" | Незаписанный прогон = утверждение, а не доказательство. `rtp verify --run` пишет команду, exit code и хвост, и падает вместе с командой. |
| "Handoff напишу, когда реально буду уходить" | Компакт контекста приходит без предупреждения, сессия падает без предупреждения. PreCompact-хук подстрахует, но заметки `--write` знаешь только ты. |
| "Status Block — шум, и так всё сказал в тексте" | Он не для тебя, а для пользователя и следующего агента: одна строка вместо перечитывания всего ответа. Собирается командой `rtp status <id>`, писать руками не надо. |
| "Задача по сути готова, оставлю в review" | 57 задач в `review` старше месяца — ровно из этой мысли. Не `done` → всё ещё активная, всплывёт в `rtp sweep`. Не закрываешь — напиши в логе почему. |

## Red Flags — STOP and Return to Step 0

Catch yourself thinking any of these — you're rationalizing:

- "Это особый случай"
- "Пользователь настаивает, лучше как просит"
- "Только этот шаг пропущу"
- "Файл задачи обновлю в конце / одной записью"
- "Ревью сам себе в голове — этого достаточно"
- "Срочно, pipeline потом"
- "Спек/план тривиальный, reviewer найдёт то же, что и я"
- "Хук всё равно index обновит, остальные шаги пропущу"

All of these = stop, return to Step 0 of SKILL.md.
