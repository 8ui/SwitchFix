# Украинский апостроф: клавиша `\` на Ukrainian-PC

Задача: `docs/tasks/2026-10-06-ukrainian-apostrophe-key-is-not-mapped-words-with-cannot-be.md`.

## Факты (UCKeyTranslate на macOS 27)

| Раскладка | `\` (42) | `` ` `` (50) | `'` (39) |
|---|---|---|---|
| Ukrainian-PC | `ʼ` U+02BC / Shift `₴` | `ґ` | `є` |
| Ukrainian (старая) | `ґ` | `'` / Shift `~` | `є` |
| Ukrainian-QWERTY (фонетика) | `є` | `ь` | `ʼ` |

Сейчас:
- `.pc` Ukrainian (= Ukrainian-PC) не знает `\` → апостроф недостижим в тестах, LayoutEval и валидации лексикона.
- `KeyTableBuilder.sanitized` выбрасывает `ʼ`: это буква (Lm), но `Layout.ownsLetter` для кириллицы принимает только U+0400–04FF → реальная таблица тоже без апострофа.
- `\` — жёсткая граница слова (`WordBoundary`, `LayoutDetector.boundaryCharacterSet`): `p\znybwr` режется на `p` + `znybwr`.
- Модель: `TextNormalization` уже сводит `ʼ`/`’` к `'`, `'` есть в алфавите uk — переобучение не нужно.

## Шаги

### Step 1 Таблицы: `ʼ` на `\` в `.pc` и в санитайзере
- `PCLayoutData.enToUkStandard`: `"\\": "ʼ"` (legacy наследует).
- `Layout.ownsLetter`: украинская раскладка владеет U+02BC.
- `LayoutMapper.canBeTyped`: `ʼ` наравне с `'`/`’`.
- Тесты `KeyTableTests`: `.pc` uk `\`→`ʼ`; санитайзер сохраняет `ʼ` у Ukrainian-PC; RU не меняется.

### Step 2 Граница слова: `\` остаётся в слове
- `\` в мягкий набор `WordBoundary` и в «keep»-набор `LayoutDetector.boundaryCharacterSet` (правило то же: клавиша пунктуации, которая буква/знак слова в другой раскладке).
- Тест классификации: `\` → `.character`; детектор: `p\znybwr` (uk разрешён) → `пʼятницю`; английский токен с `\` (`C:\Users`, `\n`) не конвертируется.

### Step 3 LayoutEval: апостроф достижим
- `tokenize` для uk: `'`/`’` → `ʼ` (так печатает Ukrainian-PC), чтобы `typedForm` шёл через `\`.
- Прогон `TestRunner --layout-eval-only` до/после; цифры uk записать в `plan/benchmarks/` (отчёт, не порог).

### Step 4 Проверки и ревью
- `swift build`, `TestRunner`, `InputPipelineTestRunner`, threshold sweep не должен измениться для en/ru.

## После plan-review (Plan, opus)

- H1: `LayoutMapper.canBeTyped(.english)` — объединение клавиш `enToRu` и `enToUkStandard`, иначе лексикон/вкладка «Слова» отвергают `p\znybwr`; `LexiconKey.normalize`: `ʼ` → `'` (M4).
- H2/M1: `\` — часть слова только между двумя буквами. Детектор: автоматическая коррекция английского токена с `\` прозрачно пропускается, если `\` не единственный, не между буквами или украинский не среди целей (`C:\Users`, `\n`, `path\to\file`). `CaretWordExtractor`: `\` — символ слова только между буквами.
- M3: мягкий набор пунктуации — одна константа `WordBoundary`, детектор берёт её же.
- H3: базовый LayoutEval снят до правок; `tokenize` для uk сводит `'`/`’`/`ʼ` к `ʼ`; результаты — в `plan/benchmarks/uk_apostrophe.md`. Строки edge_cases для путей и слов с апострофом.
- M6 (принято, в долг): `ʼ` — буква (Lm), `мʼя` считается 3 буквами.
- L1 (ограничение): Shift+`\` = `|` остаётся границей — капсом с апострофом не исправится.
