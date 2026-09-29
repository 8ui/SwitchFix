# Оптимизация архитектуры словаря и мердж uk_UA + uk_full

> **Статус**: 📋 Планирование  
> **Приоритет**: Высокий  
> **Дата создания**: 2025-02-25  

---

## Контекст

SwitchFix использует словари, чтобы определять, набрано ли слово в правильной раскладке.
Текущий украинский словарь (`uk_UA.txt`) содержит **~320K базовых форм** (лемм).
Доступен полный словарь словоформ (`uk_full.txt`) с проставленными ударениями — **~2.93M строк** (~2.87M уникальных однословных форм после нормализации).

Переход на полный словарь даст значительно более высокую точность детекции (словоформы: падежи, числа, времена), но требует пересмотра архитектуры — текущая реализация не выдержит масштаб в 2.87M записей.

---

## Анализ текущей архитектуры

### Структуры данных

| Компонент | Тип | Назначение | Память (~320K слов) |
|-----------|-----|------------|---------------------|
| `BloomFilter` | `[UInt8]` bit array | Быстрая вероятностная проверка «может ли слово быть в словаре» | ~0.5 MB |
| `suggestionBuckets` | `[Character: [Int: [String]]]` | Полный список слов, индексированный по первой букве + длине | ~15-20 MB |

### Поток обработки слова (WordValidator)

```
word → lowercased() → matchesExpectedScript()?
  ↓
BloomFilter.mightContain(word)?
  ├─ YES → короткие/подозрительные слова → isExactDictionaryWord()  ← O(n) linear scan
  │        более длинные слова → считаем валидным (доверие Bloom)
  └─ NO  → dictionarySuggestion()  ← O(n × m) brute force
```

### Где используется

- **`DictionaryLoader.swift`**: загрузка словаря из .txt, построение BloomFilter и suggestionBuckets
- **`WordValidator.swift`**: проверка валидности и поиск suggestions
- **`LayoutDetector.swift`**: вызов WordValidator.validate() на каждой границе слова

---

## Выявленные проблемы

### П1: Память — `suggestionBuckets` съест ~120-165 MB RAM

Все слова хранятся в памяти как массивы `[String]`:

```swift
// DictionaryLoader.swift:11
private var suggestionBuckets: [Language: [Character: [Int: [String]]]] = [:]
```

**Расчёт для 2.87M слов:**
- Сырые строки UTF-8: ~41 MB
- С учётом overhead Swift `String` (16 bytes/small string) + `Array`: **~120-165 MB**
- Для menubar-приложения с целевым RAM < 20 MB — это неприемлемо

### П2: `isExactDictionaryWord()` — линейное сканирование O(n)

```swift
// WordValidator.swift:173-181
private func isExactDictionaryWord(_ word: String, language: Language) -> Bool {
    guard let first = word.first else { return false }
    let buckets = loader.suggestionBuckets(for: language)
    guard let byLength = buckets[first],
          let words = byLength[word.count] else { return false }
    return words.contains(word)  // ← LINEAR SCAN через Array.contains()
}
```

Бакет `[first][len]` для популярной украинской буквы (например, «п») может содержать **десятки тысяч слов** одинаковой длины. `Array.contains()` — это O(n) со сравнением строк.

### П3: `dictionarySuggestion()` — O(n × m) brute force

```swift
// WordValidator.swift:272-299
for len in minLen...maxLen {
    for candidate in lengthMap[len]! {
        damerauLevenshteinDistance(word, candidate, maxDistance: 2)  // O(n*m) per candidate
    }
}
```

Перебирает **всех кандидатов** из бакета и считает расстояние Дамерау-Левенштейна для каждого.
При 2.87M слов это может быть **50K+ сравнений** на один вызов.

### П4: Загрузка — O(n) текстовый парсинг ~80 MB при каждом запуске

```swift
// DictionaryLoader.swift:109-124
content.enumerateLines { line, _ in
    filter.insert(word)
    // ... build buckets
}
```

Парсинг 80 MB текстового файла (2.93M строк) при каждом старте: **несколько секунд** задержки до начала работы.

### П5: Параметры BloomFilter захардкожены под 400K

```swift
// DictionaryLoader.swift:90
let filter = BloomFilter(expectedItems: 400_000, falsePositiveRate: 0.01)
```

Для 2.87M слов нужно обновить параметры, иначе false positive rate резко вырастет.

---

## Анализ словарей и план мерджа

### Статистика пересечения

| Метрика | Количество |
|---------|------------|
| Слов в `uk_UA.txt` (базовые формы, lowercase) | 320,307 |
| Уникальных слов в `uk_full.txt` (без ударений, lowercase, без фраз) | 2,876,610 |
| Общих (пересечение) | 179,875 |
| **Только в `uk_UA.txt`** (отсутствуют в `uk_full.txt`) | **140,432** |
| **Только в `uk_full.txt`** | 2,696,735 |
| Фразы (многословные) в `uk_full.txt` | 16,764 |

### Примечания

- `uk_full.txt` содержит **словоформы с ударениями** (Unicode U+0301 combining acute accent), например: `абажу́р`, `аба́тський`
- `uk_UA.txt` содержит **леммы без ударений**, всё в lowercase: `абажур`, `абатський`
- `uk_full.txt` сохраняет регистр (имена собственные с большой буквы): `Аарон`, `Абадан`
- 140K слов из `uk_UA.txt` **отсутствуют** в `uk_full.txt` — это преимущественно:
  - Составные слова: `мультифакторний`, `спецкомплекс`
  - Редкие дериваты: `якнайощадливіший`
  - Имена/фамилии: `кольченко`, `гоцалюк`
  - Современная лексика: `буккросинг`

---

## Архитектурные решения (обновлено)

1. Базовый путь: **packed mmap lexicon + binary search** с проверкой exact-match по строке.
2. **BloomFilter** в новой архитектуре не обязателен. Добавляется, только если бенчмарки покажут заметный выигрыш на negative lookup.
3. Если нужно O(1), рассматриваем **MPHF (минимальный perfect hash)** как отдельный вариант индексации.
4. Независимо от индексации (`binary search` или `MPHF`) exact-match должен подтверждаться сравнением с байтами слова (чтобы избежать ложных попаданий).
5. Если цель по RAM для low-end жёстко `<20 MB RSS`, DAWG/DAFSA рассматривается раньше, а не как «далёкая перспектива».

---

## План реализации

### Фаза 0: Baseline-бенчмарки текущего состояния ⏱ ~0.5 ч

**Цель**: Зафиксировать точку отсчёта до любых архитектурных изменений.

**Шаги**:

1. Снять baseline на текущей архитектуре (словарь ~320K):
   - startup/load time (cold/warm)
   - RSS после load
   - exact lookup latency (avg/p95/p99)
   - suggestion latency (avg/p95/p99)

2. Сохранить отчёт в `plan/benchmarks/baseline_320k.md`.

---

### Фаза 1: Мердж словарей + валидация качества ⏱ ~1.5 ч

**Цель**: Объединить `uk_UA.txt` и `uk_full.txt` без мусорных или повреждённых токенов.

**Шаги**:

1. Создать `scripts/merge_uk_dictionaries.py`:
   - Читать `uk_full.txt`, убрать ударения (U+0301), привести к lowercase, отбросить многословные фразы
   - Читать `uk_UA.txt`, привести к lowercase
   - Сделать union

2. Добавить контроль качества при мердже:
   - Отбросить пустые строки, mixed-script, строки с цифрами/управляющими символами
   - Отбросить 1-2-символьные записи из основного словаря (короткие слова уже контролируются `shortWords`)
   - Построить отчёт о коллизиях после нормализации (accents/case)

3. Записать артефакты:
   - `uk_UA_merged.txt` (финальный нормализованный словарь)
   - `uk_UA_custom.txt` (слова, которые были только в старом `uk_UA.txt`)
   - `plan/artifacts/uk_UA_merge_report.json` (метрики качества/коллизии)

4. Перезаписать runtime-источник `uk_UA.txt` merged-версией

**Ожидаемый результат**: ~3.02M уникальных валидных слов.

---

### Фаза 2: Бинарный формат v2 + mmap + partitioned index ⏱ ~6 ч

**Цель**: Быстрый exact lookup с минимальным heap-RAM и прозрачной миграцией API.

**Шаги**:

1. Ввести абстракцию доступа к словарю:
   - `DictionaryIndex` / `MappedDictionary` protocol
   - `WordValidator` работает с интерфейсом, а не с конкретной структурой `[String]`

2. Реализовать `uk_UA.bin` v2:
   - Header: `magic`, `version`, `wordCount`, `flags`, offsets секций
   - `firstCharPartitions`: table first-char -> `(start, count)` для сужения диапазона поиска
   - `offsets` (`UInt32[wordCount+1]`)
   - `wordsBlob` (конкатенированный UTF-8)
   - optional section: Bloom bits (только если включено флагом и оправдано бенчмарком)

3. Реализовать exact lookup:
   - `partition -> binary search -> byte compare`
   - Без linear scan и без `Set<String>`

4. Обновить `DictionaryLoader`:
   - Приоритет `.bin` через `mmap` (read-only)
   - `.txt` fallback оставить для debug-режима

5. Интегрировать компиляцию словаря в сборку:
   - `scripts/compile_dictionary.swift`
   - `scripts/build-app.sh` + `Package.swift`

6. Согласовать allow/deny overrides с новым форматом:
   - либо вшивать overrides в `.bin` на этапе компиляции
   - либо применять runtime overlay поверх mmap-словаря
   - зафиксировать выбранную стратегию, чтобы не потерять текущее поведение `*_allow.txt` / `*_deny.txt`

**Заметка по памяти**:
- Typical RSS может быть значительно ниже размера файла.
- Worst-case RSS может приблизиться к полному mapped size (зависит от паттерна доступа и pressure).
- Ключевое преимущество `mmap`: страницы могут быть выгружены ОС, в отличие от heap `[String]`.

---

### Фаза 2b: MPHF spike (опционально, time-boxed) ⏱ ~1-2 дня

**Цель**: Проверить, действительно ли MPHF лучше partitioned binary search для этого кейса.

**Шаги**:

1. Построить прототип индекса (CHD/аналог) для merged-словаря.
2. Сравнить:
   - exact lookup latency (avg/p95/p99)
   - размер индекса
   - сложность build/runtime-кода
3. Решение:
   - `adopt`, если p99 exact lookup >=2x быстрее partitioned binary search **и** дополнительный build-time <=5s
   - `reject`, если прирост <2x или build-time overhead >5s
   - если за 2 дня критерии не доказаны, spike закрывается решением `reject`

---

### Фаза 3: Конкретный алгоритм suggestions — trigram index + bounded DL ⏱ ~4 ч

**Цель**: Убрать brute-force и корректно обрабатывать ошибки в первой букве.

**Оценка размера индекса (до компрессии)**:
- ~3M слов, средняя длина ~9 -> ~7 триграмм/слово -> ~21M postings
- в `UInt32` это ~84 MB raw
- нужна компрессия (delta + varint) и mmap/sidecar-формат, иначе индекс съест RAM-преимущество Фазы 2

**Шаги**:

1. Добавить компактный trigram inverted index (можно отдельной секцией в `.bin` или sidecar):
   - trigram -> список `wordId`
   - posting lists хранить в сжатом виде (delta + varint)
   - индекс lazy-loaded (только при первом suggestion)

2. Candidate retrieval:
   - Извлечь триграммы из input
   - Объединить/пересечь posting lists
   - Отобрать top-K по overlap score

3. Final ranking:
   - Для top-K считать bounded Damerau-Levenshtein
   - Ввести hard cap на количество DL-сравнений
   - Ограничить `maxDistance` в зависимости от длины слова

4. Оптимизировать DL:
   - Перейти с полной 2D-матрицы на rolling rows (O(m) памяти)
   - Использовать reusable buffer (без повторных heap-аллокаций на каждом кандидате)

---

### Фаза 4: Runtime-политика для low-end + fallback cleanup ⏱ ~2.5 ч

**Цель**: Избежать RAM-спайков на слабых машинах под нагрузкой.

**Шаги**:

1. Убрать eager prewarm тяжёлых путей:
   - suggestions не прогревать на старте
   - словари загружать lazy по факту использования

2. Для `.txt` fallback (debug):
   - убрать квадратичный паттерн построения bucket'ов
   - заменить на in-place mutation через `default: []`

3. Добавить политику освобождения кешей:
   - trigram/prefix-кеши сбрасывать после idle timeout или memory warning

---

### Фаза 5: Benchmark & regression harness ⏱ ~3 ч

**Цель**: Подтверждать каждую фазу численно, а не интуитивно.

**Шаги**:

1. Добавить performance harness (`DictionaryPerformanceTests.swift` или отдельный бенч-раннер):
   - cold/warm load time
   - RSS после load и после suggestion burst
   - exact lookup latency (avg/p95/p99)
   - suggestion latency (avg/p95/p99)
   - false-positive behavior на random gibberish

2. Методика измерений:
   - wall-clock: `ContinuousClock` / signpost
   - memory: `mach_task_basic_info` + проверка через Instruments

3. Сохранять baseline-отчёт в `plan/benchmarks/` для сравнения между фазами.
   - baseline из Фазы 0 — обязательный эталон

---

### Фаза 6: DAWG/DAFSA (если нужно) ⏱ ~8 ч

**Цель**: Достичь минимального RAM, если mmap + trigram не укладывается в цель.

**Когда переходить**:

1. Если после фаз 2-5 `RSS (typical) > 30 MB` на low-end-профиле.
2. Если `suggestion latency p99 > 40 ms` на low-end-профиле после trigram + bounded DL.

**Ожидания**:
- 5-15 MB (ориентировочно, зависит от реализации и служебных структур)
- O(L) exact lookup + естественная prefix-навигация

---

## Сравнительная таблица

| Подход | RAM (2.87M+) | Exact lookup | Suggestion | Время старта | Сложность |
|--------|--------------|--------------|------------|--------------|-----------|
| **Текущий** (Bloom + Array buckets) | ~165 MB RSS | O(n) | O(n × m) | ~3-5с | — |
| **Set\<String\> quick fix** (НЕ рекомендуется) | ~100-130 MB RSS | O(1) | O(n × m) | ~3-5с | Низкая |
| **mmap + partitioned binary search** | typical lower RSS, worst-case до mapped size | O(log n) в partition | O(K × DL), K capped | <150ms cold / <50ms warm | Средняя |
| **mmap + optional Bloom prefilter** | +~3.5 MB mapped | O(1)+O(log n) для miss/hit path | O(K × DL), K capped | <150ms cold / <50ms warm | Средняя |
| **mmap + MPHF (+verify)** | индекс ~1-3 MB + blob | O(1) | O(K × DL), K capped | <150ms cold / <50ms warm | Средняя-Высокая |
| **DAWG/DAFSA** | ~5-15 MB | O(L) | O(L × neighbors) | <50ms | Высокая |

---

## Рекомендуемая последовательность

1. Фаза 0 (baseline-бенчмарки)
2. Фаза 1 (мердж + data quality checks)
3. Фаза 2 (mmap + partitioned binary search + protocol abstraction)
4. Фаза 5 (бенчмарки после Фазы 2 против baseline)
5. Фаза 2b (time-boxed MPHF spike, опционально)
6. Фаза 3 (trigram suggestions + optimized DL)
7. Фаза 4 (runtime cleanup для low-end)
8. Фаза 6 (DAWG/DAFSA), только если метрики не проходят

---

## Файлы, которые изменятся

| Файл | Фазы | Тип изменений |
|------|------|---------------|
| `scripts/merge_uk_dictionaries.py` | 1 | Новый |
| `Sources/Dictionary/Resources/uk_UA.txt` | 1 | Перезапись |
| `Sources/Dictionary/Resources/uk_UA_custom.txt` | 1 | Новый |
| `plan/artifacts/uk_UA_merge_report.json` | 1 | Новый |
| `scripts/compile_dictionary.swift` | 2 | Новый |
| `Sources/Dictionary/Resources/uk_UA.bin` | 2 | Новый (сгенерированный ресурс) |
| `Sources/Dictionary/DictionaryIndex.swift` | 2 | Новый protocol |
| `Sources/Dictionary/MappedDictionary.swift` | 2 | Новый |
| `Sources/Dictionary/DictionaryBinaryFormat.swift` | 2 | Новый |
| `Sources/Dictionary/DictionaryLoader.swift` | 2, 4 | Рефакторинг |
| `Sources/Dictionary/WordValidator.swift` | 2, 3, 4 | Рефакторинг |
| `Sources/Dictionary/DamerauLevenshtein.swift` | 3 | Новый internal-модуль (не public API) |
| `Sources/SwitchFixApp/AppDelegate.swift` | 4 | Обновление политики prewarm |
| `Sources/Dictionary/TrigramIndex.swift` | 3 | Новый |
| `Sources/TestRunner/DictionaryPerformanceTests.swift` | 5 | Новый |
| `scripts/build-app.sh` | 2 | Обновление pipeline |
| `Package.swift` | 2 | Ресурсы (`.bin`) |
| `plan/benchmarks/baseline_320k.md` | 0 | Новый baseline-отчёт |
| `plan/benchmarks/*.md` | 5 | Новые benchmark-отчёты |

---

## Критерии завершения

- [ ] Мердж прошёл data quality checks; отчёт (`plan/artifacts/uk_UA_merge_report.json`) сохранён
- [ ] `WordValidator` работает через абстракцию `DictionaryIndex`, без знания storage details
- [ ] Exact lookup без linear scan по `[String]`; подтверждено test coverage
- [ ] Алгоритм suggestions: trigram candidate retrieval + bounded DL (не prefix-only brute force)
- [ ] Реализация DL без полной 2D heap-матрицы на каждый вызов
- [ ] Overrides (`*_allow.txt`, `*_deny.txt`) работают в новой архитектуре (compile-time merge или runtime overlay)
- [ ] Цели по RAM зафиксированы как **typical** и **worst-case**; worst-case не маскируется
- [ ] RSS (typical) с активным `uk_UA`: цель <30 MB; stretch goal <20 MB
- [ ] Startup: <150ms cold, <50ms warm
- [ ] Есть benchmark harness и baseline-отчёты (включая `baseline_320k.md`)
- [ ] Runtime-пакет не зависит от `uk_full.txt`; в сборку входит `.bin`
- [ ] Если MPHF spike выполнен, зафиксировано решение «берём/не берём» с kill criteria
- [ ] DAWG gate формализован: переход, если `RSS (typical) > 30 MB` или `suggestion p99 > 40 ms` после Фазы 4
