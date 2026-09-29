# n-gram — единственный детектор, обучение на отменах, вкладка «Слова», ползунок — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Удалить словарный движок и модуль `Dictionary`, сделать n-gram единственным детектором, добавить
`PersonalLexicon` (обучение на отмене и ручной конвертации) с вкладкой «Слова» (полный CRUD) и ползунок
«Чувствительность», откалиброванный перебором порогов.

**Architecture:** `LayoutDetector.checkBuffer` становится бывшим `checkBufferNgram` (без флага движка).
`PersonalLexicon` (Core, только Foundation) хранит правила пользователя в `UserDefaults`, детектор читает
его иммутабельный снимок. `InputEngine` узнаёт происхождение коррекции (`CorrectionProvenance` в
`CorrectionPlan`) и после успешного применения/отмены учит лексикон. UI — новая вкладка SwiftUI в
`NSHostingController` и ползунок во вкладке «Коррекция»; позиция ползунка → `DetectionThresholds`.

**Tech Stack:** Swift 5.9 SwiftPM, macOS 13+, AppKit + SwiftUI, тесты — исполняемые `TestRunner` /
`InputPipelineTestRunner` (без XCTest).

**Spec:** `plan/005_ngram_layout_detection.md` — §4.3–4.6, §10.5–10.6 и **§12 (уточнения после
spec-review — главный источник для этого плана)**. Результаты детектора — `plan/benchmarks/detector_005_phase2.md`.

## Global Constraints

- Инварианты plan/003: staleness-guards в `InputEngine.prepareCorrection` и `CorrectionPlan.isEligible`
  **не меняются**; новое поле `provenance` `isEligible` не читает.
- Физический ввод не задерживается; на detection-очереди — никакого JSON/`UserDefaults`.
- Каждая пользовательская строка — через `L10n.tr("English")` + русский перевод в `Sources/UI/L10n.swift`.
- Ключи `UserDefaults`: домен `com.switchfix.app`, префикс `SwitchFix_`: `SwitchFix_personalLexicon`,
  `SwitchFix_detectionSensitivity`.
- Лимиты: лексикон — 5000 автоматически выученных записей (ручные не вытесняются); длина слова ≤ 64.
- Никаких автоконвертаций ru ↔ uk.
- Код и комментарии — английский; docs/README форка — русский; коммиты — `feat(scope):` / `fix(scope):` / `docs(scope):`.
- В облаке нет macOS: Core/UI/тесты проверяет только CI (`.github/workflows/ci.yml`, push в `claude/**`).
  После каждого шага: push → зелёный CI → `rtp verify <id> --record "CI зелёный: <push run url>"`.

## Быстрый локальный цикл на Linux (не коммитится)

Core целиком не собирается на Linux (AppKit/Carbon), но детектор — да. Для итераций по логике
детектора/лексикона: scratch-пакет в scratchpad, где `Sources/Core` — симлинки на
`LayoutDetector.swift`, `LayoutMapper.swift`, `NgramScoring.swift`, `PersonalLexicon.swift`, `LanguageModel` —
симлинки на исходники и `Resources`, `Utils` — заглушка `SwitchFixLog` (методы `debug/info/notice/error`
пустые). После `swift build -c release` сделать
`ln -sfn <Pkg>_LanguageModel.resources .build/release/SwitchFix_LanguageModel.bundle`, иначе модели не
найдутся. Toolchain: `/opt/swift/usr/bin` (см. Handoff задачи). CI остаётся единственным доказательством.

---

## Часть 1 — удаление словарей

### Step 1: удалить модуль `Dictionary` и словарный путь; n-gram — единственный детектор

**Files:**
- Modify: `Package.swift`
- Delete: `Sources/Dictionary/**`, `Sources/Core/DictionaryReadiness.swift`, `scripts/compile_dictionary.swift`,
  `scripts/merge_uk_dictionaries.py`, `Sources/TestRunner/DictionaryPerformanceTests.swift`
- Modify: `Sources/Core/LayoutDetector.swift`, `Sources/Core/NgramScoring.swift`, `Sources/Core/InputEngine.swift`
- Modify: `Sources/LanguageModel/LanguageModelStore.swift`
- Modify: `Sources/SwitchFixApp/AppDelegate.swift`, `Sources/UI/PreferencesManager.swift`, `Sources/Utils/SwitchFixLog.swift`
- Modify: `Sources/TestRunner/main.swift`, `Sources/TestRunner/NgramDetectorTests.swift`, `Sources/TestRunner/LayoutEval.swift`
- Modify: `Sources/InputPipelineTestRunner/main.swift`
- Modify: `scripts/build-app.sh`, `.gitignore`, `CLAUDE.md`, `README.md`, `plan/005_ngram_layout_detection.md`

**Interfaces:**
- Produces: `LanguageModelStore.init(resourceLocator: @escaping (ModelLanguage) -> URL? = LanguageModelStore.resourceURL)`;
  `LanguageModelReadiness.prepare(_ layout: Layout, store: LanguageModelStore = .shared) -> Bool`;
  `AutomaticCorrectionSkipRules.shouldSkip(_:)` (числа/URL/e-mail) и `AutomaticCorrectionSkipRules.isCamelCase(_:)`;
  `InputEngine.updateDetectionConfiguration(allowedLayouts:ukrainianFromVariant:ukrainianToVariant:thresholds:)` (без `engine`).
- Removes: `DetectionEngine`, `LayoutDetector.engine`, `PreferencesManager.detectionEngine`, `AutomaticDictionaryReadiness`,
  `Language`, `WordValidator`, `SuggestionEngine`, `SwitchFixLog.dictionary`.

- [ ] **1.1 Тесты сначала (TestRunner).** В `Sources/TestRunner/main.swift` две словарные ожидания
  переписываются под n-gram (проверено scratch-харнессом: остальные 49 проверок сьютов `LayoutDetector`
  на n-gram проходят):

```swift
runSuite("LayoutDetector: Convert Ukrainian 'ершиЖ' to English 'this:'") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .ukrainian
    // Legacy Ukrainian: 'ерши' is 'this'; shifted 'Ж' is the colon key, not part of an identifier.
    detector.ukrainianFromVariant = .legacy

    for char in "ершиЖ" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 1, "should convert legacy Ukrainian typed 'this:'")
    if let result = mockDelegate.results.first {
        assertEqual(result.targetLayout, .english, "target should be English")
        assertEqual(result.convertedWord, "this:", "should preserve trailing colon")
    }
}

runSuite("LayoutDetector: Legacy Ukrainian variant converts to English") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .ukrainian
    // The user's own variant decides; the fallback variant must not beat the primary
    // one on score alone ('Иууьи' on standard reads as 'Beemb', see commit 592ea8c).
    detector.ukrainianFromVariant = .legacy
    detector.ukrainianToVariant = .standard

    for char in "Иууьи" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 1, "legacy-variant word should convert")
    if let result = mockDelegate.results.first {
        assertEqual(result.targetLayout, .english, "target should be English")
        assertEqual(result.convertedWord, "Seems", "should convert to 'Seems'")
    }
}
```

  Первый заменяет существующий сьют с тем же именем, второй — «Ukrainian variant fallback converts legacy
  word to English». В `runNgramDetectorSuites` в сьют «skipped tokens» добавить `"getValue"` (camelCase
  по-прежнему пропускается), убрать `detector.engine = .ngram` из `ngramDetector(...)`.

- [ ] **1.2 Удалить словарные тесты TestRunner.** Из `main.swift`: `import Dictionary`,
  `DictionaryLoader.shared.enableTextFallbackForTesting()`, `dictionaryPath`, `forEachDictionaryWord`, все
  сьюты `BloomFilter: …`, `WordValidator: …`, `Synthetic: …`, вызов `runDictionaryPerformanceSuites()`
  и секцию «Performance» (p99 детекции уже печатает LayoutEval, p99 скоринга проверяет
  `LanguageModelTests`). Удалить `DictionaryPerformanceTests.swift`. Сьюты `LayoutDetector: …` остаются и
  теперь идут на n-gram.

- [ ] **1.3 LayoutEval без сравнения движков.** В `LayoutEval.swift` удалить `evalEngine` и
  `detector.engine = evalEngine`; `runLayoutEvalSuites()`:

```swift
func runLayoutEvalSuites() {
    var sentences: [Layout: [[String]]] = [:]
    for language in evalLanguages {
        sentences[language] = loadSentences(language)
    }
    // Dictionary-engine reference numbers are frozen in plan/benchmarks/baseline_005.md.
    runMixedEval()
    runIsolatedEval(sentences: sentences)
    runSentenceEval(sentences: sentences)
    runEdgeCaseEval()
}
```

- [ ] **1.4 NgramScoring.** Удалить `enum DetectionEngine`. Разделить правила пропуска:

```swift
/// Words the automatic path never touches: numbers, URLs and e-mail addresses.
enum AutomaticCorrectionSkipRules {
    static func shouldSkip(_ word: String) -> Bool {
        if word.allSatisfy({ $0.isNumber }) { return true }
        let lower = word.lowercased()
        if lower.hasPrefix("http") || lower.hasPrefix("www.") || lower.hasPrefix("ftp") {
            return true
        }
        return word.contains("@") && word.contains(".")
    }

    /// A lowercase letter followed by an uppercase one ("camelCase"). The detector
    /// skips a token only when both the typed and the converted core look like this:
    /// a shifted punctuation key ('ершиЖ' → 'this:') is not an identifier.
    static func isCamelCase(_ word: String) -> Bool {
        var previousIsLower = false
        for character in word {
            if character.isUppercase {
                if previousIsLower { return true }
                previousIsLower = false
            } else {
                previousIsLower = character.isLowercase
            }
        }
        return false
    }
}
```

  `LanguageModelReadiness`:

```swift
public enum LanguageModelReadiness {
    @discardableResult
    public static func prepare(_ layout: Layout, store: LanguageModelStore = .shared) -> Bool {
        store.model(for: layout.modelLanguage) != nil && store.model(for: .english) != nil
    }
}
```

  Обновить doc-комментарий `DetectionThresholds` (без упоминания «dictionary engine»).

- [ ] **1.5 LanguageModelStore — инжектируемый поиск ресурса.**

```swift
public final class LanguageModelStore: @unchecked Sendable {
    public static let shared = LanguageModelStore()

    private let resourceLocator: (ModelLanguage) -> URL?
    // ...
    public init(resourceLocator: @escaping (ModelLanguage) -> URL? = LanguageModelStore.resourceURL) {
        self.resourceLocator = resourceLocator
    }
```

  `model(for:)` зовёт `resourceLocator(language)` вместо `Self.resourceURL(for:)`; `resourceURL(for:)`
  становится `public static`. Комментарий к классу: «keep in sync with `scripts/build-app.sh`» без ссылки на
  `DictionaryLoader`.

- [ ] **1.6 LayoutDetector.** Удалить `import Dictionary`, `validator`, `engine`, весь словарный
  `checkBuffer` (старые строки ~230–327); тело `checkBufferNgram` становится `checkBuffer` (после проверки
  смешанных скриптов). Начало проверки:

```swift
let originalParts = splitTokenForValidation(word)
let core = originalParts.core.isEmpty ? word : originalParts.core

if AutomaticCorrectionSkipRules.shouldSkip(core)
    || shouldSkipAutomaticEnglishAcronymCorrection(word: word, sourceLayout: sourceLayout) {
    markValidInCurrentLanguage()
    return nil
}
let typedIsCamelCase = AutomaticCorrectionSkipRules.isCamelCase(core)
```

  В цикле конверсий, сразу после `let convertedCore = …`:

```swift
if typedIsCamelCase && AutomaticCorrectionSkipRules.isCamelCase(convertedCore) {
    markValidInCurrentLanguage()
    return nil
}
```

  `Language` заменить на `Layout`: `shouldAllowAcronymFallback(original:converted:currentLayout: Layout)`,
  `containsVowel(_:layout: Layout)` (switch по `.english/.ukrainian/.russian`), удалить
  `languageForLayout`. Комментарии «dictionary» → «model». Doc-комментарий `finishCorrection`:
  «Shared tail of a detected correction» (без «both engines»).

- [ ] **1.7 InputEngine / AppDelegate / Preferences / Log.**
  - `InputEngine.DetectionConfiguration`: убрать `engine`; `updateDetectionConfiguration` без параметра
    `engine`; в `runDetection` убрать `self.detector.engine = …`; комментарий «even when the dictionary does
    not recognize the word» → «even when the model does not».
  - `AppDelegate`: удалить `detectionEngine`; `prepareDictionaries` → `prepareLanguageModels`, внутри
    `LanguageModelReadiness.prepare(layout)`; лог `"automatic correction unavailable for layouts: …"` оставить;
    `updateDetectionConfiguration` без `engine:`.
  - `PreferencesManager`: удалить `Keys.detectionEngine` и `detectionEngine`.
  - `SwitchFixLog`: удалить `dictionary` (spec §12.11 предлагал переименовать в `.model` — не нужно:
    категория не используется; `lexicon` добавляется в шаге 2).

- [ ] **1.8 InputPipelineTestRunner.** Сьют `missing dictionary seam` → `missing language model seam`:

```swift
run("missing language model seam") {
    let missing = LanguageModelStore(resourceLocator: { _ in nil })
    check(!LanguageModelReadiness.prepare(.english, store: missing), "a missing model must report the layout unavailable")
    check(!LanguageModelReadiness.prepare(.russian, store: missing), "every layout needs its model and the English one")
    check(LanguageModelReadiness.prepare(.russian), "bundled models must load in the test runner")
    // … остаток сьюта (детекция без коррекции) без изменений
}
```

  В `Package.swift` добавить `"LanguageModel"` в зависимости `InputPipelineTestRunner`, в файле —
  `import LanguageModel`.

- [ ] **1.9 Package.swift.** Удалить таргет `Dictionary` и его упоминания в `SwitchFixApp`, `Core`,
  `TestRunner`. Граф: `Utils` ← `LanguageModel` ← `Core`.

- [ ] **1.10 build-app.sh.** Удалить `compile_bin_if_needed` и три вызова, блок копирования
  `SwitchFix_Dictionary.bundle`. Блок модели:

```bash
# Copy the language model bundle (the only detector's data). Newer SwiftPM emits a
# macOS-style bundle (Contents/Resources); LanguageModelStore.resourceURL handles both.
MODEL_BUNDLE_SRC="$PRODUCTS_DIR/SwitchFix_LanguageModel.bundle"
if [ ! -d "$MODEL_BUNDLE_SRC" ]; then
    echo "ERROR: SwitchFix_LanguageModel.bundle not found in $PRODUCTS_DIR; automatic correction would be dead." >&2
    exit 1
fi
cp -R "$MODEL_BUNDLE_SRC" "$APP_BUNDLE/Contents/Resources/"
MODEL_DIR="$APP_BUNDLE/Contents/Resources/SwitchFix_LanguageModel.bundle"
[ -d "$MODEL_DIR/Contents/Resources" ] && MODEL_DIR="$MODEL_DIR/Contents/Resources"
for lang in en ru uk; do
    if [ ! -f "$MODEL_DIR/$lang.sfng" ]; then
        echo "ERROR: $lang.sfng missing from the language model bundle." >&2
        exit 1
    fi
done
echo "Copied language model bundle (en, ru, uk) to Contents/Resources/."
```

- [ ] **1.11 Удаление файлов и .gitignore.**

```bash
git rm -r -q Sources/Dictionary Sources/Core/DictionaryReadiness.swift scripts/compile_dictionary.swift \
  scripts/merge_uk_dictionaries.py Sources/TestRunner/DictionaryPerformanceTests.swift
```

  Из `.gitignore` убрать блок «Generated dictionary artifacts» (`.build/dictionary-bin/`,
  `Sources/Dictionary/Resources/uk_full.txt`); строки `plan/artifacts/*`, `scripts/__pycache__/` оставить.
  Проверка остатков: `grep -rn "Dictionary\|WordValidator\|DetectionEngine\|detectionEngine\|SuggestionEngine\|BloomFilter" Sources scripts Package.swift`
  → только `infoDictionary` / `CFDictionary` / `defaults.dictionary`.

- [ ] **1.12 Документация.** `CLAUDE.md`: команды (`TestRunner` — «detection/model/mapper tests»,
  `build-app.sh` — «copies the language model bundle, signs»); абзац Tests — убрать
  `enableTextFallbackForTesting`/`*.txt`; Module graph `Utils` ← `LanguageModel` ← `Core` ← `UI` ←
  `SwitchFixApp`; пункт 4 пайплайна: `LayoutDetector` (+ `NgramMarginScorer`, `ShortWordTable`,
  `ScriptAnalyzer`, `LayoutMapper`); абзац **Dictionaries** удалить, абзац **Language models** переписать
  (единственный детектор, без флага, `build-app.sh` падает без бандла модели); Conventions — plan 005 в работе.
  `README.md` (русская секция форка): пункт «Хоткей переводит слово всегда…» — «даже если модель не
  уверена»; новый пункт «Словари удалены: раскладку определяет символьная n-граммная модель (~450 КБ
  вместо ~70 МБ словарей), понимает словоформы, сленг и техтермины»; английская строка «How it works»
  п.3 — «scored by character n-gram language models of each layout's language». `plan/005` §11: отметить
  «нет словарей» и пункт `CLAUDE.md`/`README.md` частично.

- [ ] **1.13 Linux-проверка.** `PATH=/opt/swift/usr/bin:$PATH swift build -c release --product ModelTrainer`
  → Build complete (LanguageModel изменился). Scratch-харнесс: сьюты `LayoutDetector` + `NgramDetector` зелёные.

- [ ] **1.14 Commit + CI.**

```bash
git add -A && git commit -m "feat(detector)!: remove dictionaries, n-gram is the only detector"
git push -u origin claude/epic-galileo-zq47ec
```

  Дождаться CI (GitHub MCP `actions_list` / `get_job_logs`), записать `rtp verify … --record "CI зелёный: <url>"`.
  Красный CI → чинить в этом же шаге (не переходить дальше).

---

## Часть 2 — `PersonalLexicon`

### Step 2: `PersonalLexicon` — модель, хранение, CRUD, обучение (Core)

**Files:**
- Modify: `Sources/Core/LayoutMapper.swift` (`Layout: Codable, Sendable`; `canBeTyped`)
- Create: `Sources/Core/PersonalLexicon.swift`
- Modify: `Sources/Utils/SwitchFixLog.swift` (`lexicon`)
- Create: `Sources/TestRunner/PersonalLexiconTests.swift`; Modify: `Sources/TestRunner/main.swift`

**Interfaces (Produces):**

```swift
public enum LexiconRule: Codable, Equatable, Sendable { case neverCorrect; case alwaysCorrect(to: Layout) }
public enum LexiconOrigin: String, Codable, Sendable { case learnedFromRevert, learnedFromHotkey, manual }
public struct LexiconEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var word: String            // LexiconKey.normalize-d
    public var sourceLayout: Layout
    public var rule: LexiconRule
    public var origin: LexiconOrigin
    public let createdAt: Date
    public var lastMatchedAt: Date?
    public var matchCount: Int
}
public struct LexiconKey: Hashable, Sendable {
    public let word: String; public let sourceLayout: Layout
    public init(word: String, sourceLayout: Layout)   // normalizes
    public static func normalize(_ token: String) -> String
}
public enum LexiconValidationError: Error, Equatable { case empty, tooLong, notTypable, sameLayoutTarget, unsupportedPair }
public enum LexiconAddResult: Equatable { case added(LexiconEntry), duplicate(LexiconEntry), invalid(LexiconValidationError) }
public protocol PersonalLexiconStorage: AnyObject { func load() -> Data?; func save(_ data: Data) }
public final class UserDefaultsLexiconStorage: PersonalLexiconStorage { public init(defaults: UserDefaults = .standard) }
public final class InMemoryLexiconStorage: PersonalLexiconStorage { public init(); public private(set) var saveCount: Int }
public final class PersonalLexicon: @unchecked Sendable {
    public static let shared: PersonalLexicon
    public static let maxLearnedEntries = 5000
    public static let maxWordLength = 64
    public init(storage: PersonalLexiconStorage, saveDelay: TimeInterval = 2, now: @escaping () -> Date = Date.init)
    public var entries: [LexiconEntry] { get }
    public func rule(for word: String, sourceLayout: Layout) -> LexiconRule?
    public static func validate(word: String, sourceLayout: Layout, rule: LexiconRule) -> LexiconValidationError?
    public func add(word: String, sourceLayout: Layout, rule: LexiconRule) -> LexiconAddResult   // origin .manual
    public func update(_ entry: LexiconEntry) -> LexiconValidationError?                           // becomes .manual
    public func remove(ids: Set<UUID>)
    public func removeLearned()
    public func removeAll()
    public func recordRejected(word: String, sourceLayout: Layout)
    public func recordAccepted(word: String, sourceLayout: Layout, target: Layout)
    public func forgetAccepted(word: String, sourceLayout: Layout)
    public func noteMatch(word: String, sourceLayout: Layout)
    public func flush()
}
public extension Notification.Name { static let personalLexiconDidChange: Notification.Name }
```

- [ ] **2.1 Тесты сначала** — `Sources/TestRunner/PersonalLexiconTests.swift`, `runPersonalLexiconSuites()`
  вызывается из `main.swift` перед `runLanguageModelSuites()`:

```swift
import Foundation
import Core

private func makeLexicon(
    _ storage: InMemoryLexiconStorage = InMemoryLexiconStorage(),
    saveDelay: TimeInterval = 0,
    clock: @escaping () -> Date = Date.init
) -> PersonalLexicon {
    PersonalLexicon(storage: storage, saveDelay: saveDelay, now: clock)
}

func runPersonalLexiconSuites() {
    runSuite("PersonalLexicon: normalization") {
        assertEqual(LexiconKey.normalize("Ghbdtn"), "ghbdtn")
        assertEqual(LexiconKey.normalize("П’ятниця"), "п'ятниця")
        assertEqual(LexiconKey(word: "Hf,jnftn", sourceLayout: .english), LexiconKey(word: "hf,jnftn", sourceLayout: .english))
    }

    runSuite("PersonalLexicon: validation") {
        assertEqual(PersonalLexicon.validate(word: "", sourceLayout: .english, rule: .neverCorrect), .empty)
        assertEqual(PersonalLexicon.validate(word: String(repeating: "a", count: 65), sourceLayout: .english, rule: .neverCorrect), .tooLong)
        assertEqual(PersonalLexicon.validate(word: "привет", sourceLayout: .english, rule: .neverCorrect), .notTypable)
        assertEqual(PersonalLexicon.validate(word: "ghbdtn", sourceLayout: .english, rule: .alwaysCorrect(to: .english)), .sameLayoutTarget)
        assertEqual(PersonalLexicon.validate(word: "было", sourceLayout: .russian, rule: .alwaysCorrect(to: .ukrainian)), .unsupportedPair, "no ru ↔ uk rules")
        assert(PersonalLexicon.validate(word: ",erdf", sourceLayout: .english, rule: .alwaysCorrect(to: .russian)) == nil, "punctuation keys are letters on the other layout")
        assert(PersonalLexicon.validate(word: "п'ятниця", sourceLayout: .ukrainian, rule: .neverCorrect) == nil, "apostrophe is allowed")
    }

    runSuite("PersonalLexicon: CRUD") {
        let lexicon = makeLexicon()
        guard case .added(let entry) = lexicon.add(word: "Kubectl", sourceLayout: .english, rule: .neverCorrect) else {
            return assert(false, "add should succeed")
        }
        assertEqual(entry.word, "kubectl")
        assertEqual(entry.origin, .manual)
        assertEqual(lexicon.rule(for: "KUBECTL", sourceLayout: .english), .neverCorrect)
        if case .duplicate(let existing) = lexicon.add(word: "kubectl", sourceLayout: .english, rule: .alwaysCorrect(to: .russian)) {
            assertEqual(existing.id, entry.id, "duplicate points at the existing entry")
        } else {
            assert(false, "same word + layout must be reported as duplicate")
        }
        var edited = entry
        edited.rule = .alwaysCorrect(to: .russian)
        assert(lexicon.update(edited) == nil, "update should succeed")
        assertEqual(lexicon.rule(for: "kubectl", sourceLayout: .english), .alwaysCorrect(to: .russian))
        lexicon.remove(ids: [entry.id])
        assert(lexicon.rule(for: "kubectl", sourceLayout: .english) == nil, "removed")
    }

    runSuite("PersonalLexicon: learning never overrides manual entries") {
        let lexicon = makeLexicon()
        _ = lexicon.add(word: "ghbdtn", sourceLayout: .english, rule: .alwaysCorrect(to: .russian))
        lexicon.recordRejected(word: "ghbdtn", sourceLayout: .english)
        assertEqual(lexicon.rule(for: "ghbdtn", sourceLayout: .english), .alwaysCorrect(to: .russian))
        lexicon.forgetAccepted(word: "ghbdtn", sourceLayout: .english)
        assertEqual(lexicon.rule(for: "ghbdtn", sourceLayout: .english), .alwaysCorrect(to: .russian))
    }

    runSuite("PersonalLexicon: the latest automatic lesson wins") {
        let lexicon = makeLexicon()
        lexicon.recordAccepted(word: "rehk", sourceLayout: .english, target: .russian)
        assertEqual(lexicon.rule(for: "rehk", sourceLayout: .english), .alwaysCorrect(to: .russian))
        assertEqual(lexicon.entries.first?.origin, .learnedFromHotkey)
        lexicon.recordRejected(word: "rehk", sourceLayout: .english)
        assertEqual(lexicon.rule(for: "rehk", sourceLayout: .english), .neverCorrect)
        assertEqual(lexicon.entries.count, 1, "one entry per word + layout")
        lexicon.forgetAccepted(word: "rehk", sourceLayout: .english)
        assertEqual(lexicon.rule(for: "rehk", sourceLayout: .english), .neverCorrect, "forget removes only hotkey lessons")
    }

    runSuite("PersonalLexicon: eviction keeps manual entries") {
        var tick = 0.0
        // Deferred save: 5000 synchronous JSON writes would dominate the run.
        let lexicon = makeLexicon(saveDelay: 3600, clock: { tick += 1; return Date(timeIntervalSince1970: tick) })
        _ = lexicon.add(word: "manual", sourceLayout: .english, rule: .neverCorrect)
        // Letters only: digits are not keys of the layout tables and would fail validation.
        func word(_ index: Int) -> String {
            let letters = Array("abcdefghijklmnopqrstuvwxyz")
            var value = index, result = "w"
            repeat { result.append(letters[value % 26]); value /= 26 } while value > 0
            return result
        }
        for index in 0..<(PersonalLexicon.maxLearnedEntries + 10) {
            lexicon.recordRejected(word: word(index), sourceLayout: .english)
        }
        assertEqual(lexicon.entries.filter { $0.origin != .manual }.count, PersonalLexicon.maxLearnedEntries)
        assert(lexicon.rule(for: "manual", sourceLayout: .english) != nil, "manual entry survives")
        assert(lexicon.rule(for: word(0), sourceLayout: .english) == nil, "oldest learned entry is evicted")
        assert(lexicon.rule(for: word(PersonalLexicon.maxLearnedEntries + 9), sourceLayout: .english) != nil, "newest stays")
    }

    runSuite("PersonalLexicon: persistence round-trip") {
        let storage = InMemoryLexiconStorage()
        let lexicon = makeLexicon(storage)
        lexicon.recordRejected(word: "ok", sourceLayout: .english)
        _ = lexicon.add(word: "сщвуч", sourceLayout: .ukrainian, rule: .alwaysCorrect(to: .english))
        lexicon.noteMatch(word: "сщвуч", sourceLayout: .ukrainian)
        lexicon.flush()
        let reloaded = makeLexicon(storage)
        assertEqual(reloaded.entries.count, 2)
        assertEqual(reloaded.rule(for: "сщвуч", sourceLayout: .ukrainian), .alwaysCorrect(to: .english))
        assertEqual(reloaded.entries.first { $0.word == "сщвуч" }?.matchCount, 1)
        lexicon.removeLearned()
        assertEqual(lexicon.entries.map(\.word), ["сщвуч"])
        lexicon.removeAll()
        assert(lexicon.entries.isEmpty, "all removed")
    }

    runSuite("PersonalLexicon: corrupt storage starts empty") {
        let storage = InMemoryLexiconStorage()
        storage.save(Data("not json".utf8))
        assert(makeLexicon(storage).entries.isEmpty, "corrupt data must not crash")
    }
}
```

- [ ] **2.2 `Layout` Codable + `canBeTyped`.** `public enum Layout: String, CaseIterable, Equatable, Codable, Sendable`.
  В `LayoutMapper`:

```swift
/// Whether every character of `text` is a key of `layout` (letters of its script,
/// or punctuation keys that are letters on another layout, e.g. ',' → 'б'), plus apostrophes.
public static func canBeTyped(_ text: String, on layout: Layout) -> Bool {
    let keys: Set<Character>
    switch layout {
    case .english: keys = Set(enToRu.keys)
    case .russian: keys = Set(ruToEn.keys)
    case .ukrainian: keys = Set(ukStandardToEn.keys).union(ukLegacyToEn.keys)
    }
    return !text.isEmpty && text.contains(where: \.isLetter)
        && text.allSatisfy { keys.contains($0) || $0 == "'" || $0 == "’" }   // tables already hold shifted keys
}
```

- [ ] **2.3 `PersonalLexicon.swift`** (`Foundation` + `Utils` ради `SwitchFixLog`; без `os`/AppKit, чтобы
  собирался в Linux-харнессе с заглушкой `Utils`).
  Ключевые решения реализации:
  - состояние под `NSLock`: `entries: [LexiconEntry]` (порядок вставки), индекс `[LexiconKey: Int]` и
    `rules: [LexiconKey: LexiconRule]` — **обновляются по одной записи**, без пересборки на каждую мутацию
    (удаление — swap-remove с правкой индекса одной перемещённой записи); `LexiconKey` имеет internal
    `init(normalized:sourceLayout:)` без повторной нормализации для уже нормализованных `entry.word`;
    `rule(for:)` нормализует один раз и читает словарь под локом; вытеснение — один проход, отбирающий
    лишние записи (сортировка кандидатов по `lastMatchedAt ?? createdAt`), затем пересборка индекса один раз;
  - `LexiconKey.normalize`: `token.lowercased().replacingOccurrences(of: "’", with: "'")`;
  - `validate`: пусто → `.empty`; `count > maxWordLength` → `.tooLong`; `!LayoutMapper.canBeTyped` →
    `.notTypable`; `.alwaysCorrect(to: sourceLayout)` → `.sameLayoutTarget`; `.alwaysCorrect` между двумя
    кириллическими раскладками → `.unsupportedPair` (глобальное правило «никаких ru ↔ uk»);
  - `add` → `.duplicate(existing)` при совпадении ключа, иначе запись `.manual`;
  - `update` валидирует и ставит `origin = .manual` (правка пользователем = ручное решение); если после
    правки ключ совпал с другой записью, та удаляется (дубликатов не бывает);
  - `learn(key:rule:origin:)` (private): если есть запись `.manual` → ничего; иначе заменить/добавить с новым
    `createdAt`, затем `evictIfNeeded()`: пока автоматически выученных > `maxLearnedEntries` — удалить с
    минимальным `lastMatchedAt ?? createdAt`;
  - `recordRejected` → `learn(.neverCorrect, .learnedFromRevert)`; `recordAccepted` →
    `learn(.alwaysCorrect(to:), .learnedFromHotkey)`; `forgetAccepted` удаляет запись только с origin
    `.learnedFromHotkey`; все три игнорируют слова, не прошедшие `validate`;
  - `noteMatch`: `matchCount += 1`, `lastMatchedAt = now()`, без пересборки `rules`;
  - сохранение: `scheduleSave()` — `DispatchWorkItem` на приватной serial-очереди `com.switchfix.lexicon`
    с задержкой `saveDelay` (предыдущий отменяется); тело кодирует `entries` `JSONEncoder` (даты
    `.iso8601`), `storage.save`, потом `DispatchQueue.main.async { NotificationCenter.default.post(name: .personalLexiconDidChange, object: self) }`
    и `SwitchFixLog.lexicon.notice("saved entries=\(n)")` — **без слов**; при `saveDelay == 0` сохраняет
    синхронно; `flush()` — `saveQueue.sync { pending?.cancel(); если было ожидающее — сохранить }`, чтобы не
    писать дважды параллельно с уже стартовавшим work item;
  - `load` в `init`: `JSONDecoder` (`.iso8601`), ошибка → пустой лексикон + `SwitchFixLog.lexicon.error("lexicon decode failed")`;
  - `UserDefaultsLexiconStorage`: ключ `"SwitchFix_personalLexicon"`, `defaults.data(forKey:)` / `set(_:forKey:)`;
  - `public static let shared = PersonalLexicon(storage: UserDefaultsLexiconStorage())`.
  - `SwitchFixLog`: `public static let lexicon = SwitchFixLogger(category: "lexicon")`. В Linux-харнессе
    заглушке добавить `lexicon` и `error`.

- [ ] **2.4 Проверка.** Linux-харнесс: скопировать `PersonalLexiconTests.swift`-сьюты в харнесс
  (`PersonalLexicon.swift`, `LayoutMapper.swift` — симлинки), все зелёные. Commit
  `feat(lexicon): personal lexicon storage, CRUD and learning rules`. CI — вместе с шагом 4 (шаги 2–4 — одна
  часть; push допустим после каждого шага, CI должен быть зелёным до начала шага 5).

### Step 3: лексикон в детекторе

**Files:** Modify `Sources/Core/LayoutDetector.swift`; Modify `Sources/TestRunner/NgramDetectorTests.swift`

**Interfaces:**
- Consumes: `PersonalLexicon.rule(for:sourceLayout:)`, `noteMatch`.
- Produces: `LayoutDetector.lexicon: PersonalLexicon?` (по умолчанию `nil`); `LayoutDetector.preferredCyrillicLayout: Layout?`
  (читает `lastCyrillicLayout`).

- [ ] **3.1 Тесты сначала** (в `runNgramDetectorSuites`):

```swift
runSuite("NgramDetector: personal lexicon rules") {
    let lexicon = PersonalLexicon(storage: InMemoryLexiconStorage(), saveDelay: 0)
    func detect(_ word: String, current: Layout, allowed: Set<Layout> = [.english, .russian]) -> DetectionResult? {
        let detector = ngramDetector(current: current, allowed: allowed)
        detector.lexicon = lexicon
        detector.addCharacter(word)
        return detector.flushBuffer(boundaryCharacter: " ")
    }

    assertEqual(detect("ghbdtn", current: .english)?.convertedWord, "привет", "baseline: corrected")
    lexicon.recordRejected(word: "ghbdtn", sourceLayout: .english)
    assert(detect("Ghbdtn", current: .english) == nil, "neverCorrect wins, case-insensitive")

    assert(detect("rehk", current: .english) == nil, "baseline: the typo is not recognized")
    lexicon.recordAccepted(word: "rehk", sourceLayout: .english, target: .russian)
    let learned = detect("Rehk", current: .english)
    assertEqual(learned?.convertedWord, "Курл", "alwaysCorrect converts with case")
    assertEqual(learned?.shouldSwitchLayout, true, "user rule is confident: switch layout")

    _ = lexicon.add(word: "jr", sourceLayout: .english, rule: .alwaysCorrect(to: .russian))
    let short = detect("jr", current: .english)
    assertEqual(short?.convertedWord, "ок", "short words bypass the low-confidence path")
    assertEqual(short?.shouldSwitchLayout, true, "and switch immediately")

    _ = lexicon.add(word: "qwzx", sourceLayout: .english, rule: .alwaysCorrect(to: .ukrainian))
    assert(detect("qwzx", current: .english, allowed: [.english, .russian]) == nil, "target layout not installed → rule ignored")

    _ = lexicon.add(word: "API", sourceLayout: .english, rule: .alwaysCorrect(to: .russian))
    assertEqual(detect("API", current: .english)?.convertedWord, "ФЗШ", "user rule beats the ALLCAPS heuristic")
    assertEqual(lexicon.entries.first { $0.word == "ghbdtn" }?.matchCount, 1, "neverCorrect hits are counted")
}
```

- [ ] **3.2 Реализация.** В `checkBuffer` после `AutomaticCorrectionSkipRules.shouldSkip(core)` (числа/URL/
  e-mail) и **до** `shouldSkipAutomaticEnglishAcronymCorrection`/camelCase:

```swift
if let rule = lexicon?.rule(for: word, sourceLayout: sourceLayout) {
    switch rule {
    case .neverCorrect:
        SwitchFixLog.detector.debug("lexicon: keep '\(word)'")
        lexicon?.noteMatch(word: word, sourceLayout: sourceLayout)
        markValidInCurrentLanguage()
        return nil
    case .alwaysCorrect(let target):
        if let result = finishLexiconCorrection(word: word, sourceLayout: sourceLayout, target: target) {
            return result
        }
    }
}
```

```swift
/// A user rule is an explicit decision: no low-confidence confirmation, no short-word
/// suppression or merging; the layout switches at once.
private func finishLexiconCorrection(word: String, sourceLayout: Layout, target: Layout) -> DetectionResult? {
    // Same guard as validation: English ↔ Cyrillic only, never Russian ↔ Ukrainian.
    guard (sourceLayout == .english) != (target == .english), allowedLayouts.contains(target) else { return nil }
    let converted = LayoutMapper.convert(
        word,
        from: sourceLayout,
        to: target,
        ukrainianFromVariant: ukrainianFromVariant,
        ukrainianToVariant: ukrainianToVariant
    )
    guard converted != word else { return nil }
    let result = DetectionResult(
        sourceLayout: sourceLayout,
        targetLayout: target,
        convertedWord: applyCase(from: word, to: converted),
        originalWord: word,
        shouldSwitchLayout: true
    )
    consecutiveWrongCount = 0
    lastDetectionResult = result
    pendingSwitchLayout = nil
    pendingSwitchCount = 0
    recordOutcome(.corrected)
    state = .buffering
    return result
}
```

  `lexicon` с `applyCase`: `LayoutMapper.convert` сохраняет регистр посимвольно, `applyCase` нормализует
  Capitalized/ALLCAPS как у модели. `public var preferredCyrillicLayout: Layout? { lastCyrillicLayout }`.
  `matchCount` для `alwaysCorrect` не трогаем здесь (учитывается после применения — шаг 4).

- [ ] **3.3 Проверка.** Linux-харнесс: сьют выше + все `LayoutDetector`/`NgramDetector`. Commit
  `feat(detector): apply personal lexicon rules before the model`.

### Step 4: происхождение коррекции, обучение в `InputEngine`

**Files:**
- Modify: `Sources/Core/TextCorrector.swift`, `Sources/Core/InputEngine.swift`, `Sources/SwitchFixApp/AppDelegate.swift`
- Modify: `Sources/InputPipelineTestRunner/main.swift`

**Interfaces:**
- Produces:

```swift
public enum CorrectionProvenance: Equatable, Sendable {
    case automatic      // boundary-triggered detection
    case hotkey         // hotkey, and the detector itself found the correction
    case hotkeyForced   // hotkey converted a word the detector did not recognize
    case selection      // selected text replaced via paste
    case layoutSwitch   // layout-switch correction mode
}
// CorrectionPlan: + public let provenance: CorrectionProvenance  (init param, default .automatic)
// TextCorrector.undo(...) -> CorrectionPlan?   (the reverted plan; @discardableResult)
public typealias RevertEmission = (UInt64, InputContextSnapshot) -> CorrectionPlan?
// InputEngine.init(..., lexicon: PersonalLexicon? = nil, revertEmission: RevertEmission? = nil)
```

- [ ] **4.1 Тесты сначала** (`InputPipelineTestRunner`), реальный детектор (без `exactDetection`),
  эмиссия и отмена — через швы:

```swift
private final class EmissionLog {
    private let lock = NSLock()
    private var plans: [CorrectionPlan] = []
    func append(_ plan: CorrectionPlan) { lock.lock(); plans.append(plan); lock.unlock() }
    var last: CorrectionPlan? { lock.lock(); defer { lock.unlock() }; return plans.last }
    var count: Int { lock.lock(); defer { lock.unlock() }; return plans.count }
}

private func waitUntil(_ timeout: TimeInterval = 2, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        Thread.sleep(forTimeInterval: 0.01)
    }
    return condition()
}

private struct LearningHarness {
    let store: CaptureStateStore
    let engine: InputEngine
    let lexicon: PersonalLexicon
    let emitted: EmissionLog
    var timestamp: UInt64 = 0

    init(mode: InputCorrectionMode = .automatic, revertReturnsNothing: Bool = false) {
        let current = context()
        store = CaptureStateStore(context: current, hotkeys: HotkeyConfiguration(hotkeyModifiers: 0))
        lexicon = PersonalLexicon(storage: InMemoryLexiconStorage(), saveDelay: 0)
        let emitted = EmissionLog()
        self.emitted = emitted
        engine = InputEngine(
            captureState: store,
            initialContext: current,
            preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: mode),
            correctionEmission: { plan in emitted.append(plan); return true },
            lexicon: lexicon,
            revertEmission: { _, _ in revertReturnsNothing ? nil : emitted.last }
        )
        engine.updateDetectionConfiguration(
            allowedLayouts: [.english, .russian],
            ukrainianFromVariant: .standard,
            ukrainianToVariant: .standard
        )
    }

    mutating func send(_ kind: CapturedInput.Kind) {
        timestamp += 1
        engine.enqueue(store.capture(
            timestamp: timestamp, kind: kind, keyCode: 0, flagsRawValue: 0,
            isAutorepeat: false, sourcePID: 1, sourceUserData: 0
        ))
    }

    mutating func type(_ word: String, boundary: String? = " ") {
        for character in word { send(.character(String(character))) }
        if let boundary { send(.boundary(boundary)) }
    }
}

run("learning: revert of an automatic correction teaches neverCorrect") {
    var harness = LearningHarness()
    harness.type("ghbdtn")
    check(waitUntil { harness.emitted.count == 1 }, "automatic correction is emitted")
    check(harness.emitted.last?.provenance == .automatic, "boundary correction is automatic")
    harness.send(.revertHotkey)
    check(waitUntil { harness.lexicon.rule(for: "ghbdtn", sourceLayout: .english) == .neverCorrect }, "revert is learned")
    harness.type("ghbdtn")
    check(!waitUntil(0.3) { harness.emitted.count > 1 }, "the reverted word is not corrected again")
}

run("learning: forced hotkey conversion teaches alwaysCorrect, its revert forgets") {
    var harness = LearningHarness()
    harness.type("rehk", boundary: nil)
    harness.send(.hotkey)
    check(waitUntil { harness.emitted.count == 1 }, "hotkey converts the unrecognized word")
    check(harness.emitted.last?.provenance == .hotkeyForced, "forced conversion is marked")
    check(waitUntil { harness.lexicon.rule(for: "rehk", sourceLayout: .english) == .alwaysCorrect(to: .russian) }, "hotkey lesson is learned")
    harness.send(.boundary(" "))
    harness.type("rehk")
    check(waitUntil { harness.emitted.count == 2 }, "the learned word is corrected automatically")
    check(harness.emitted.last?.provenance == .automatic, "second correction is automatic")
    check(waitUntil { harness.lexicon.entries.first?.matchCount == 1 }, "applied rule is counted")
}

run("learning: reverting a forced hotkey conversion forgets the lesson") {
    var harness = LearningHarness()
    harness.type("rehk", boundary: nil)
    harness.send(.hotkey)
    check(waitUntil { harness.lexicon.rule(for: "rehk", sourceLayout: .english) != nil }, "learned")
    harness.send(.revertHotkey)
    check(waitUntil { harness.lexicon.rule(for: "rehk", sourceLayout: .english) == nil }, "revert of a hotkey fix forgets, never adds neverCorrect")
}

run("learning: manual entries are not overwritten by reverts") {
    var harness = LearningHarness()
    _ = harness.lexicon.add(word: "ghbdtn", sourceLayout: .english, rule: .alwaysCorrect(to: .russian))
    harness.type("ghbdtn")
    check(waitUntil { harness.emitted.count == 1 }, "corrected by the manual rule")
    harness.send(.revertHotkey)
    check(!waitUntil(0.3) { harness.lexicon.rule(for: "ghbdtn", sourceLayout: .english) != .alwaysCorrect(to: .russian) }, "manual rule stays")
}

run("learning: forced hotkey target follows the last Cyrillic layout") {
    var harness = LearningHarness()
    harness.engine.updateDetectionConfiguration(
        allowedLayouts: Set(Layout.allCases), ukrainianFromVariant: .standard, ukrainianToVariant: .standard
    )
    func switchLayout(to layout: Layout) {
        let next = harness.store.replaceContext(
            frontmostPID: 100, appAllowed: true, layout: layout,
            inputSourceID: "com.test.\(layout.rawValue)", secureFocus: .notSecure
        )
        harness.engine.updateContext(next)
    }
    // Typing on Russian makes it the detector's last Cyrillic layout (survives reset()).
    switchLayout(to: .russian)
    harness.type("привет")
    switchLayout(to: .english)
    harness.type("rehk", boundary: nil)
    harness.send(.hotkey)
    check(waitUntil { harness.emitted.last?.targetLayout == .russian }, "forced Latin conversion prefers Russian, not the first installed (Ukrainian)")
}

run("learning: revert without undo state falls back to a forced hotkey conversion that teaches") {
    var harness = LearningHarness(revertReturnsNothing: true)
    harness.type("rehk", boundary: nil)
    harness.send(.revertHotkey)
    check(waitUntil { harness.lexicon.rule(for: "rehk", sourceLayout: .english) == .alwaysCorrect(to: .russian) }, "fallback conversion is a lesson too")
}

run("learning: trailing punctuation is not part of the learned word") {
    var harness = LearningHarness()
    harness.type("rehk!", boundary: nil)
    harness.send(.hotkey)
    check(waitUntil { harness.lexicon.rule(for: "rehk", sourceLayout: .english) != nil }, "learned without '!'")
}

run("learning: merged multi-word corrections are not learned") {
    let plan = CorrectionPlan(
        boundarySequence: 1, contextEpoch: 1, targetPID: 100, editGeneration: 1, correctionEpoch: 1,
        deleteCount: 9, replacementText: "it works ", originalText: "ше цщкли", correctedText: "it works",
        boundaryText: " ", originalLayout: .ukrainian, targetLayout: .english, provenance: .automatic
    )
    check(!InputEngine.isLearnable(plan), "a merged phrase is not a single token")
    check(!InputEngine.isLearnable(CorrectionPlan(
        boundarySequence: 1, contextEpoch: 1, targetPID: 100, editGeneration: 1, correctionEpoch: 1,
        deleteCount: 5, replacementText: "hello", originalText: "руддщ", correctedText: "hello",
        boundaryText: "", originalLayout: .russian, targetLayout: .english, provenance: .selection
    )), "selection replacements do not teach")
}
```

- [ ] **4.2 CorrectionPlan / TextCorrector.** Добавить `CorrectionProvenance` (в `TextCorrector.swift`
  рядом с `CorrectionPlan`), поле `provenance` + параметр `provenance: CorrectionProvenance = .automatic`
  последним в `init`. `isEligible` не менять. `rebaseUndoContext` передаёт `provenance: plan.provenance`;
  `performSelectionCorrection` создаёт план с `provenance: .selection`. `undo` возвращает `CorrectionPlan?`:
  `return undo.plan` вместо `return true`, `nil` вместо `false`.

- [ ] **4.3 InputEngine.**
  - `init(..., selectedTextRequest:, lexicon: PersonalLexicon? = nil, revertEmission: RevertEmission? = nil)`;
    в `init` — `detector.lexicon = lexicon`.
  - `runDetection(_ request:, forceConversion:)`: сохранить `let detectorResult = result` сразу после
    `flushBuffer` (до ветки принудительной конвертации, которая перезаписывает `result`), затем:
    `let provenance: CorrectionProvenance = !forceConversion ? .automatic : (detectorResult != nil ? .hotkey : .hotkeyForced)`
    (с `customDetection` — `.automatic`/`.hotkey`). Передаёт в `prepareCorrection(result:request:provenance:)`.
    Путь layout-switch (`applyBufferedCorrection`) — `.layoutSwitch`.
  - Выбор цели при принудительной конвертации латиницы (§12.6):

```swift
let preferred = self.detector.preferredCyrillicLayout
let allowed = configuration.allowedLayouts
if let (target, converted) = alternatives.first(where: { $0.0 == preferred && allowed.contains($0.0) })
    ?? alternatives.first(where: { allowed.contains($0.0) })
    ?? alternatives.first {
```

  - `prepareCorrection` кладёт `provenance` в план; в `correctionQueue` существующий guard
    `plan.isEligible(using:)` **остаётся первым**, после него эмиссия:

```swift
let applied = self.customEmission.map { $0(plan) }
    ?? self.corrector.apply(plan, latestCaptureState: self.captureState.snapshot)
if applied { self.learnFromApplied(plan) }
```

  - `.requestRevert`:

```swift
correctionQueue.async { [weak self] in
    guard let self else { return }
    let reverted = self.revertEmission.map { $0(sequence, context) }
        ?? self.corrector.undo(sequence: sequence, context: context, latestCaptureState: self.captureState.snapshot)
    if let reverted {
        self.learnFromReverted(reverted)
    } else {
        self.inputQueue.async {
            self.requestManualCorrection(word: word, sequence: sequence, context: context)
        }
    }
}
```

  - обучение (вызывается на correction-очереди; лексикон потокобезопасен). Учат только одиночные токены
    с провенансом `.automatic`/`.hotkeyForced`; цель нужна лишь `recordAccepted` (у `.hotkeyForced` она
    всегда задана — `shouldSwitchLayout: true`), поэтому автоматическая коррекция без переключения
    раскладки (короткое слово без подтверждения) при отмене тоже учит `neverCorrect`:

```swift
/// Only single-token automatic corrections and forced hotkey conversions teach the lexicon.
public static func isLearnable(_ plan: CorrectionPlan) -> Bool {
    guard !plan.originalText.isEmpty,
          !plan.originalText.contains(where: \.isWhitespace) else { return false }
    switch plan.provenance {
    case .automatic, .hotkeyForced: return true
    case .hotkey, .selection, .layoutSwitch: return false
    }
}

private func learnFromApplied(_ plan: CorrectionPlan) {
    guard let lexicon, Self.isLearnable(plan) else { return }
    switch plan.provenance {
    case .automatic:
        lexicon.noteMatch(word: plan.originalText, sourceLayout: plan.originalLayout)
    case .hotkeyForced:
        guard let target = plan.targetLayout,
              (plan.originalLayout == .english) != (target == .english) else { return }
        lexicon.recordAccepted(word: plan.originalText, sourceLayout: plan.originalLayout, target: target)
    default:
        break
    }
}

private func learnFromReverted(_ plan: CorrectionPlan) {
    guard let lexicon, Self.isLearnable(plan) else { return }
    switch plan.provenance {
    case .automatic: lexicon.recordRejected(word: plan.originalText, sourceLayout: plan.originalLayout)
    case .hotkeyForced: lexicon.forgetAccepted(word: plan.originalText, sourceLayout: plan.originalLayout)
    default: break
    }
}
```

  `noteMatch` меняет счётчик, только если запись для ключа существует (иначе — no-op).
  **Ключ обучения = ключ поиска детектора.** `plan.originalText` у ручной коррекции — весь буфер, включая
  завершающую пунктуацию (`ghbdtn!`), а детектор ищет слово после `splitTrailingBoundary`. Вынести
  `splitTrailingBoundary` в `public static func LayoutDetector.lexiconWord(from token: String) -> String`
  (возвращает ядро без завершающих граничных символов; экземплярный метод вызывает его) и передавать в
  `recordRejected/recordAccepted/forgetAccepted/noteMatch` именно `LayoutDetector.lexiconWord(from: plan.originalText)`;
  пустой результат → не учить. Тест в 4.1: хоткей на `rehk!` учит `rehk`, затем `rehk ` исправляется автоматически.
  Ограничение (документировать в CLAUDE.md): отмена `.hotkey`-коррекции, результат которой дал выученный
  `alwaysCorrect`, правило не забывает — это делается во вкладке «Слова».

- [ ] **4.4 AppDelegate.** `InputEngine(..., lexicon: PersonalLexicon.shared)`; в
  `applicationWillTerminate` — `PersonalLexicon.shared.flush()`.

- [ ] **4.5 Проверка + commit + CI.** Linux: `swift build --product ModelTrainer` (LanguageModel не
  менялся — sanity). Commit `feat(engine): learn from reverts and forced hotkey conversions`, push, CI зелёный,
  `rtp verify --record`.

---

## Часть 3 — вкладка «Слова»

### Step 5: вкладка «Слова» с полным CRUD

**Files:**
- Create: `Sources/UI/LearnedWordsView.swift`
- Modify: `Sources/UI/SettingsWindowController.swift`, `Sources/UI/L10n.swift`

**Interfaces:**
- Consumes: весь публичный API `PersonalLexicon` (шаг 2), `.personalLexiconDidChange`.
- Produces: `SettingsTab.words` (между `.apps` и `.about`).

- [ ] **5.1 `SettingsTab`.** `case general, correction, apps, words, about`; `title` → `L10n.tr("Words")`;
  `symbolName` → `"text.book.closed"`; `rootView` → `AnyView(LearnedWordsView(settings: model))`.
  `SettingsTab(rawValue:)` используется по индексу — порядок кейсов = порядок вкладок.

- [ ] **5.2 View model.**

```swift
final class LearnedWordsViewModel: ObservableObject {
    enum RuleFilter: Hashable { case all, neverCorrect, alwaysCorrect }

    @Published private(set) var entries: [LexiconEntry] = []
    @Published var searchText = ""
    @Published var ruleFilter: RuleFilter = .all
    @Published var sortOrder: [KeyPathComparator<LexiconRow>] = [KeyPathComparator(\LexiconRow.word)]
    @Published var selection: Set<UUID> = []

    private let lexicon: PersonalLexicon

    init(lexicon: PersonalLexicon = .shared) {
        self.lexicon = lexicon
        reload()
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .personalLexiconDidChange, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc func reload() { entries = lexicon.entries }

    var rows: [LexiconRow] {
        entries.map(LexiconRow.init)
            .filter { searchText.isEmpty || $0.word.localizedCaseInsensitiveContains(searchText) }
            .filter { row in
                switch ruleFilter {
                case .all: return true
                case .neverCorrect: return row.entry.rule == .neverCorrect
                case .alwaysCorrect: return row.entry.rule != .neverCorrect
                }
            }
            .sorted(using: sortOrder)
    }

    func save(_ draft: LexiconDraft) -> String? { … }   // add or update; returns localized error or nil
    func removeSelected() { lexicon.remove(ids: selection); selection = []; reload() }
    func removeLearned() { lexicon.removeLearned(); reload() }
    func removeAll() { lexicon.removeAll(); reload() }
}
```

  `LexiconRow: Identifiable` — обёртка с сортируемыми полями `word: String`, `layoutName: String`,
  `ruleName: String`, `originName: String`, `matchCount: Int`, `lastMatched: Date` (`?? .distantPast`),
  `id = entry.id`. `LexiconDraft` — `id: UUID?`, `word`, `sourceLayout`, `neverCorrect: Bool`,
  `target: Layout`. `save`: новая запись → `lexicon.add`; `.duplicate(existing)` → вернуть
  `L10n.tr("This word is already in the list. Edit the existing entry instead.")` и выделить её;
  существующая → `lexicon.update`. Ошибки валидации → строки:
  `.empty` «Enter a word.», `.tooLong` «The word is too long (64 characters at most).»,
  `.notTypable` «These characters can't be typed on the selected layout.»,
  `.sameLayoutTarget` «Choose a different target layout.», `.unsupportedPair` «SwitchFix converts only
  between English and Russian or Ukrainian.».
  Изменения, пришедшие из детектора (счётчики), обновляют таблицу через уведомление.

- [ ] **5.3 View.** По образцу `AppsSettingsView` (`SettingsTabContainer`, заголовок, рамка с таблицей и
  панелью `+`/`−`, `SettingsNote`):
  - над таблицей: `TextField(L10n.tr("Search"), text: $model.searchText)` и
    `Picker` фильтра (`All` / `Don't correct` / `Correct`), `.pickerStyle(.segmented)`;
  - `Table(model.rows, selection: $model.selection, sortOrder: $model.sortOrder)`, колонки
    (ширина окна 520 pt): `Word` (`value: \.word`), `Layout` (`\.layoutName`, 70),
    `Rule` (`\.ruleName`, 130: «Don't correct» / «Correct → EN/UK/RU»), `Source` (`\.originName`, 70:
    «Revert» / «Hotkey» / «Manual»), `Uses` (`TableColumn(…, value: \.matchCount) { Text("\($0.matchCount)") }`
    — у не-`String` колонки нужен content-closure, 45); колонки строятся content-closure'ами, и на
    содержимое **каждой ячейки** вешается `.help(row.lastUsedText)` — «Last used: <дата>»
    (`L10n.tr("Last used: %@")`, `DateFormatter` `.short`/`.short`) или «Never used» (на строку `Table`
    `.help` не повесить);
    `.frame(height: 260)`; `.contextMenu(forSelectionType: UUID.self, menu: …, primaryAction: { ids in edit(ids.first) })`
    — двойной клик открывает редактирование;
  - `.onDeleteCommand { model.removeSelected() }` — клавиша Delete;
  - панель: `+` (открывает форму с пустым черновиком), `−` (`disabled(model.selection.isEmpty)`),
    `Edit…` (`disabled(model.selection.count != 1)`), справа `Menu` «…» с «Reset Learned Words…» и
    «Delete All Words…» — пункты меню только выставляют `@State pendingConfirmation`, а `.confirmationDialog`
    висит на корневом view вкладки («Reset learned words? Words you added
    yourself stay.», «Delete all words? This can't be undone.», кнопки `Reset` / `Delete All`
    `role: .destructive`, `Cancel`);
  - форма — `.sheet(item:)` с `LexiconDraft` (идентичность — отдельный неопциональный `draftID = UUID()`,
    `entryID: UUID?` — редактируемая запись; для существующей записи форма показывает «Last used» и
    «Uses» только для чтения): `TextField("Word")`, `Picker("Typed on:")` (установленные
    раскладки = `Layout.allCases`), `Picker("Rule:")` (`Don't correct` / `Correct to`), при «Correct to» —
    `Picker("Target layout:")` — для кириллицы только English, для English — Russian/Ukrainian; строка ошибки красным `SettingsNote`; кнопки `Cancel`
    (`.cancelAction`) и `Save` (`.defaultAction`), закрытие только если `save` вернул `nil`;
  - `SettingsNote(text: L10n.tr("SwitchFix learns from your actions: undoing an automatic correction adds “Don't correct”, converting a word with the hotkey adds “Correct”. Your own entries are never changed automatically."))`.

- [ ] **5.4 L10n.** Русские переводы всех новых строк (раздел `// Words tab`), напр.: «Words» → «Слова»,
  «Learned Words» → «Выученные слова», «Search» → «Поиск», «All» → «Все», «Don't correct» → «Не
  исправлять», «Correct» → «Исправлять», «Correct → %@» → «Исправлять → %@», «Correct to» →
  «Исправлять в», «Word» → «Слово», «Layout» → «Раскладка», «Rule» → «Правило», «Source» → «Источник»,
  «Uses» → «Срабатываний», «Revert» → «Откат», «Hotkey» → «Хоткей», «Manual» → «Вручную»,
  «Last used: %@» → «Последнее срабатывание: %@», «Never used» → «Ещё не срабатывало», «Edit…» →
  «Изменить…», «Typed on:» → «Набрано в раскладке:», «Rule:» → «Правило:», «Target layout:» →
  «Целевая раскладка:», «Save» → «Сохранить» (`"Cancel"` и `"Correct"` **уже есть** — переиспользовать), «Reset Learned Words…» →
  «Сбросить выученные…», «Delete All Words…» → «Удалить все слова…», «Reset» → «Сбросить», «Delete All»
  → «Удалить все», диалоги и ошибки из 5.2/5.3. Ключ «Revert» не должен конфликтовать с существующими
  («Revert Last:» — другой ключ); проверить `grep -n '"Cancel"\|"Save"\|"Search"\|"All"' Sources/UI/L10n.swift`
  на дубликаты — словарь с повторным ключом падает в рантайме при первом русском lookup, а CI его не
  трогает. Поэтому добавить в `ci.yml` шаг перед сборкой:

```yaml
      - name: L10n has no duplicate keys
        run: |
          dups=$(grep -oE '^ *"([^"\\]|\\.)*": ' Sources/UI/L10n.swift | sed 's/^ *//' | sort | uniq -d)
          if [ -n "$dups" ]; then echo "Duplicate L10n keys:"; echo "$dups"; exit 1; fi
```

  (проверить локально на Linux: на текущем файле шаг проходит, с искусственным дублем — падает).

- [ ] **5.5 Проверка + commit + CI.** CI (сборка UI — единственная автоматическая проверка SwiftUI).
  Commit `feat(ui): Words settings tab for the personal lexicon`. Визуальную проверку на macOS записать в
  долг задачи (`rtp debt --add "Проверить вкладку «Слова» на macOS: …"`), если пользователь не проверит сам.

---

## Часть 4 — ползунок «Чувствительность»

### Step 6: позиции чувствительности в `DetectionThresholds` и ползунок

**Files:**
- Modify: `Sources/Core/NgramScoring.swift`, `Sources/Core/LayoutDetector.swift`
- Modify: `Sources/UI/PreferencesManager.swift`, `Sources/UI/SettingsView.swift`, `Sources/UI/L10n.swift`
- Modify: `Sources/SwitchFixApp/AppDelegate.swift`
- Modify: `Sources/TestRunner/NgramDetectorTests.swift`

**Interfaces (Produces):**

```swift
public struct DetectionThresholds {
    public static let sensitivityPositions = 0...4          // 0 = Cautious … 4 = Bold
    public static let defaultSensitivity = 2
    public static let sensitivityOffsets: [Double] = [4, 2, 0, -2, -4]   // уточняются в шаге 7
    public static let minimumThreshold: Double = 1
    public var convertsShortWords = true
    public static func forSensitivity(_ position: Int) -> DetectionThresholds
    // threshold(forLetterCount:) → max(minimumThreshold, base + sensitivityOffset)
}
public struct NgramMarginScorer { public init(store: LanguageModelStore); public func margin(...) -> Double? }
```

- [ ] **6.1 Тесты сначала** (`NgramDetectorTests.swift`: добавить `import LanguageModel`):

```swift
runSuite("NgramDetector: sensitivity") {
    let scorer = NgramMarginScorer(store: .shared)
    // 'hf,jnftn' → 'работает', 8 letters: bucket 7+.
    guard let margin = scorer.margin(typedCore: "hf,jnftn", source: .english, convertedCore: "работает", target: .russian) else {
        return assert(false, "models must load")
    }
    func detect(offset: Double) -> DetectionResult? {
        let detector = ngramDetector(current: .english, allowed: [.english, .russian])
        var thresholds = DetectionThresholds.default
        thresholds.sensitivityOffset = offset
        detector.thresholds = thresholds
        detector.addCharacter("hf,jnftn")
        return detector.flushBuffer(boundaryCharacter: " ")
    }
    let base = DetectionThresholds.default.sevenPlusLetters
    assert(detect(offset: margin - base + 0.5) == nil, "threshold above the margin keeps the word")
    assert(detect(offset: margin - base - 0.5) != nil, "threshold below the margin corrects it")

    let cautious = DetectionThresholds.forSensitivity(0)
    let bold = DetectionThresholds.forSensitivity(4)
    assert(cautious.threshold(forLetterCount: 7)! > DetectionThresholds.forSensitivity(2).threshold(forLetterCount: 7)!, "cautious is stricter")
    assert(bold.threshold(forLetterCount: 7)! >= DetectionThresholds.minimumThreshold, "never below the floor")
    assertEqual(DetectionThresholds.forSensitivity(2), DetectionThresholds.default, "middle position = calibrated defaults")
    assertEqual(DetectionThresholds.forSensitivity(99), DetectionThresholds.forSensitivity(4), "out of range clamps")

    let detector = ngramDetector(current: .english, allowed: [.english, .russian])
    detector.thresholds = cautious
    detector.addCharacter("yf")
    assert(detector.flushBuffer(boundaryCharacter: " ") == nil, "Cautious never auto-corrects short words")
}
```

- [ ] **6.2 Реализация.** `NgramMarginScorer` и его `init`/`margin` — `public`.
  `forSensitivity`: `let p = min(max(position, 0), 4)`; `var t = DetectionThresholds.default`;
  `t.sensitivityOffset = sensitivityOffsets[p]`; `t.convertsShortWords = p != 0`. В `threshold(forLetterCount:)`
  — `max(Self.minimumThreshold, base + sensitivityOffset)`. В `LayoutDetector.checkBuffer` ветка
  `ShortWordTable.contains(convertedCore, …)` выполняется только при `thresholds.convertsShortWords`
  (сохранение **исходного** короткого слова — «common short word … no correction» — остаётся всегда).
  Обновить doc-комментарий `DetectionThresholds` (позиции, пол, ссылку на `thresholds_005.md`).
  §4.6.4: решение детектора логировать на уровне `info` **без слова** —
  `SwitchFixLog.detector.info("ngram decision margin=… threshold=… letters=… corrected=…")` рядом с
  существующим `debug` (со словом).

- [ ] **6.3 Настройка.** `PreferencesManager`:

```swift
/// Detection sensitivity position, 0 (Cautious) … 4 (Bold); 2 = calibrated defaults.
public var detectionSensitivity: Int {
    get {
        guard let value = defaults.object(forKey: Keys.detectionSensitivity) as? Int else {
            return DetectionThresholds.defaultSensitivity
        }
        return min(max(value, 0), 4)
    }
    set {
        let clamped = min(max(newValue, 0), 4)
        guard clamped != detectionSensitivity else { return }
        defaults.set(clamped, forKey: Keys.detectionSensitivity)
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }
}
```

  (`Keys.detectionSensitivity = "SwitchFix_detectionSensitivity"`; в `PreferencesManager.swift` добавить
  `import Core` — сейчас его нет.) `SettingsViewModel`: `@Published var detectionSensitivity: Double`
  (Slider работает с `Double`) + `didSet` пишет `Int(detectionSensitivity.rounded())`, синхронизация в
  `syncFromPreferences`.

- [ ] **6.4 UI.** В `CorrectionSettingsView` после «Correction Mode»:

```swift
SettingsSection(title: L10n.tr("Sensitivity")) {
    Slider(value: $model.detectionSensitivity, in: 0...4, step: 1) {
        EmptyView()
    } minimumValueLabel: {
        Text(L10n.tr("Cautious"))
    } maximumValueLabel: {
        Text(L10n.tr("Bold"))
    }
    SettingsNote(text: sensitivityDescription)
}
.disabled(model.correctionMode != .automatic)
```

  `sensitivityDescription` по позиции: 0 — «Corrects only clear cases; short words are left to the
  hotkey.», 1 — «Fewer corrections, fewer mistakes.», 2 — «Balanced (recommended).», 3 — «Corrects more
  words, occasionally by mistake.», 4 — «Corrects as much as possible; undo mistakes with Revert Last.».
  Переводы: «Sensitivity» → «Чувствительность», «Cautious» → «Осторожно», «Bold» → «Смело», описания.

- [ ] **6.5 AppDelegate.** `updateDetectionConfiguration(allowedLayouts:)` передаёт
  `thresholds: .forSensitivity(PreferencesManager.shared.detectionSensitivity)`; в `preferencesDidUpdate`
  добавить `updateDetectionConfiguration(allowedLayouts: readyLayouts)` под guard `modelsPrepared`
  (новый флаг, `true` в completion `prepareLanguageModels`) — иначе до подготовки моделей уйдёт пустой
  набор раскладок.

- [ ] **6.6 Проверка + commit.** Linux-харнесс для 6.1 (детекторная часть). Commit
  `feat(ui): detection sensitivity slider`. CI — вместе с шагом 7.

### Step 7: перебор порогов, калибровка ползунка, защита от устаревших порогов

**Files:**
- Create: `Sources/TestRunner/ThresholdSweep.swift`; Modify: `Sources/TestRunner/LayoutEval.swift` (хелперы
  `private` → внутренние), `Sources/TestRunner/main.swift`
- Modify: `Sources/Core/NgramScoring.swift` (`calibratedModelChecksums`, итоговые `sensitivityOffsets`)
- Modify: `.github/workflows/ci.yml`
- Create: `plan/benchmarks/thresholds_005.md`

- [ ] **7.1 Guard-тест сначала** (`LanguageModelTests` или `NgramDetectorTests`):

```swift
runSuite("DetectionThresholds: calibrated for the bundled models") {
    for language in ModelLanguage.allCases {
        guard let url = LanguageModelStore.resourceURL(for: language), let data = try? Data(contentsOf: url) else {
            assert(false, "\(language.rawValue).sfng must be bundled"); continue
        }
        let actual = NgramBinaryFormat.checksum(of: data)
        assertEqual(DetectionThresholds.calibratedModelChecksums[language], actual,
                    "\(language.rawValue).sfng changed: rerun `TestRunner --threshold-sweep`, update DetectionThresholds and plan/benchmarks/thresholds_005.md, then this checksum")
    }
}
```

  Проще, чем новый API: каждый `.sfng` уже заканчивается FNV-1a суммой предыдущих байт — тест читает
  последние 8 байт little-endian (`data.suffix(8).enumerated().reduce(0) { $0 | UInt64($1.element) << (8 * $1.offset) }`);
  `NgramBinaryFormat.checksum(of:)` **не добавлять**, в тесте заменить на это выражение. Значения для
  `calibratedModelChecksums`:

```bash
python3 -c 'import struct; [print(l, hex(struct.unpack("<Q", open(f"Sources/LanguageModel/Resources/{l}.sfng","rb").read()[-8:])[0])) for l in ("en","ru","uk")]' 
```

  (сверить с порядком байт записи в `NgramBinaryFormat.append`).

- [ ] **7.2 `--threshold-sweep`.** `ThresholdSweep.swift`, `runThresholdSweep()`; в `main.swift` рядом с
  `--layout-eval-only`: `if CommandLine.arguments.contains("--threshold-sweep") { runThresholdSweep(); exit(0) }`.
  Метрики на данных LayoutEval, конфигурация «en + native» (основная):
  - **по корзинам** (3, 4, 5, 6, 7+ букв) для базового порога `T` ∈ 0…14 шаг 0.5 (§4.6.1) (все корзины сразу —
    слова разной длины независимы): FP% по правильно набранным словам всех трёх языков и recall% по
    набранным в чужой раскладке → строки TSV `bucket\tT\tfp\trecall`;
  - **по сдвигам** `offset` ∈ −6…+6 шаг 0.5 и `convertsShortWords` (true; и false для самой строгой): FP% ≥ 4
    букв, FP% ≤ 3, recall 4–5, recall 6+, ложные в смешанных сообщениях, «полностью правильные»
    (relies on app / switches late) → TSV `offset\t…`;
  - печатать с префиксом `SWEEP\t` для `grep` в логе CI; вывести рекомендацию по правилу §4.6.2 + §12.10:
    минимальный `T` на корзину с FP ≤ 0.1% (≥ 4 букв) / ≤ 0.5% (3 буквы).
  Реализация переиспользует `tokenize`, `loadSentences`, `loadMixed`, `typedForm`, `isReachable`,
  `restores`, `detect`, `wrongLayouts`, `EvalConfig` из `LayoutEval.swift` — перенести их в
  `enum EvalSupport` (internal static), чтобы не конфликтовать с `detect`/`makeDetector` в других файлах;
  прогон ≈ 29 + 25 полных проходов eval — следить за временем шага в CI (цель < 2 мин; если больше —
  считать отступ каждого слова один раз через `NgramMarginScorer` и применять пороги к готовым числам); цикл
  смешанных сообщений вынести из `runMixedEval` в функцию `mixedMetrics(thresholds:) -> (fully: Double, fp: Int, …)`,
  которую зовут и отчёт, и перебор; `makeDetector(current:allowed:thresholds: = .default)`.

- [ ] **7.3 CI.** В `ci.yml` после шага TestRunner:

```yaml
      - name: Threshold sweep (report-only)
        shell: bash
        run: |
          set -o pipefail
          swift run -c release TestRunner --threshold-sweep | tee threshold-sweep.txt
```

- [ ] **7.4 Калибровка.** Push, дождаться CI, взять строки `SWEEP` из лога (`get_job_logs`). Выбрать
  `sensitivityOffsets` так, чтобы: позиция 2 = 0; позиции 1/3 — ближайшие сдвиги, при которых recall
  4–5 или FP ≥ 4 букв меняется заметно (≥ 1 п.п. recall или ≥ 0.05 п.п. FP); позиции 0/4 — следующий
  шаг; ни одна позиция не даёт ложных в смешанных сообщениях больше 0 для позиций 0–2. Если перебор
  по корзинам рекомендует другие базовые пороги, чем T3=12, T4–T6=8, T7+=5, — **не менять молча**:
  записать расхождение в `thresholds_005.md` и в лог задачи, менять только если новая точка не хуже по
  целям §8 (с допусками §10.6).
  Записать `plan/benchmarks/thresholds_005.md`: дата, контрольные суммы моделей, таблица по корзинам,
  таблица по сдвигам, выбранные позиции с ожидаемыми recall/FP, команда воспроизведения.

- [ ] **7.5 Commit + CI.** `feat(detector): calibrate sensitivity positions by threshold sweep`; CI
  зелёный, `rtp verify --record`.

### Step 8: документация и Definition of Done

- [ ] **8.1** `CLAUDE.md`: `PersonalLexicon` (Core, `SwitchFix_personalLexicon`, обучение только на
  `.automatic`/`.hotkeyForced` одиночных токенах, ручные записи не перезаписываются), `CorrectionProvenance`
  (не читается `isEligible`), `revertEmission`/`lexicon` в списке швов `InputEngine`, вкладка «Слова» в
  перечне вкладок, `SwitchFix_detectionSensitivity`, `--threshold-sweep` в Commands и правило «переобучил
  модель → sweep → `calibratedModelChecksums`».
- [ ] **8.2** `README.md` (русская секция): пункты «Учится на отменах и хоткее, вкладка «Слова»» и
  «Ползунок «Чувствительность»».
- [ ] **8.3** `plan/005`: статус «✅ Реализовано» + ссылки на коммиты, отметки §11, результаты
  `thresholds_005.md`.
- [ ] **8.4** Commit `docs: n-gram detector, personal lexicon and sensitivity`, CI зелёный, переход задачи в
  review.
