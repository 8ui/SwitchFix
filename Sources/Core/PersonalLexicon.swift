import Foundation
import Utils

/// What SwitchFix does with a word typed on a given layout (plan/005 §4.5).
public enum LexiconRule: Codable, Equatable, Sendable {
    /// Leave the word as typed.
    case neverCorrect
    /// Convert the word to `to` without asking the model.
    case alwaysCorrect(to: Layout)
}

/// Where a rule came from. Rules the user made or edited (`manual`) are never changed
/// by learning and never evicted.
public enum LexiconOrigin: String, Codable, Sendable {
    case learnedFromRevert
    case learnedFromHotkey
    case manual
}

public struct LexiconEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    /// Normalized with `LexiconKey.normalize`.
    public var word: String
    public var sourceLayout: Layout
    public var rule: LexiconRule
    public var origin: LexiconOrigin
    public let createdAt: Date
    public var lastMatchedAt: Date?
    public var matchCount: Int

    var key: LexiconKey { LexiconKey(normalized: word, sourceLayout: sourceLayout) }
}

/// A word as the detector sees it (the token without trailing boundary punctuation)
/// plus the layout it was typed on.
public struct LexiconKey: Hashable, Sendable {
    public let word: String
    public let sourceLayout: Layout

    public init(word: String, sourceLayout: Layout) {
        self.init(normalized: Self.normalize(word), sourceLayout: sourceLayout)
    }

    init(normalized: String, sourceLayout: Layout) {
        self.word = normalized
        self.sourceLayout = sourceLayout
    }

    public static func normalize(_ token: String) -> String {
        token.lowercased().replacingOccurrences(of: "’", with: "'")
    }
}

public enum LexiconValidationError: Error, Equatable, Sendable {
    case empty
    case tooLong
    /// The characters are not keys of the source layout.
    case notTypable
    case sameLayoutTarget
    /// Only English ↔ Cyrillic conversions exist; never Russian ↔ Ukrainian.
    case unsupportedPair
}

public enum LexiconAddResult: Equatable, Sendable {
    case added(LexiconEntry)
    /// The word + layout is already listed; edit that entry instead.
    case duplicate(LexiconEntry)
    case invalid(LexiconValidationError)
}

public protocol PersonalLexiconStorage: AnyObject {
    func load() -> Data?
    func save(_ data: Data)
}

public final class UserDefaultsLexiconStorage: PersonalLexiconStorage {
    public static let key = "SwitchFix_personalLexicon"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> Data? { defaults.data(forKey: Self.key) }
    public func save(_ data: Data) { defaults.set(data, forKey: Self.key) }
}

public final class InMemoryLexiconStorage: PersonalLexiconStorage {
    private let lock = NSLock()
    private var data: Data?
    private var saves = 0

    public init() {}

    public var saveCount: Int { lock.locked { saves } }
    public func load() -> Data? { lock.locked { data } }
    public func save(_ data: Data) {
        lock.locked {
            self.data = data
            saves += 1
        }
    }
}

/// The user's personal word rules: learned from reverts and forced hotkey
/// conversions, and edited in the Words settings tab.
///
/// Thread-safe. The detector reads rules on its own queue through `rule(for:)`,
/// which only does a dictionary lookup under a lock; encoding and storage happen on
/// a private queue after `saveDelay`. Logs never contain the words themselves.
public final class PersonalLexicon: @unchecked Sendable {
    public static let shared = PersonalLexicon(storage: UserDefaultsLexiconStorage())
    public static let maxLearnedEntries = 5000
    public static let maxWordLength = 64

    private let storage: PersonalLexiconStorage
    private let saveDelay: TimeInterval
    private let now: () -> Date
    private let lock = NSLock()
    private var items: [LexiconEntry] = []
    private var index: [LexiconKey: Int] = [:]
    private var learnedCount = 0
    private let saveQueue = DispatchQueue(label: "com.switchfix.lexicon", qos: .utility)
    /// Accessed only on `saveQueue`.
    private var pendingSave: DispatchWorkItem?

    public init(storage: PersonalLexiconStorage, saveDelay: TimeInterval = 2, now: @escaping () -> Date = Date.init) {
        self.storage = storage
        self.saveDelay = saveDelay
        self.now = now
        guard let data = storage.load() else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            for entry in try decoder.decode([LexiconEntry].self, from: data) where index[entry.key] == nil {
                insert(entry)
            }
        } catch {
            SwitchFixLog.lexicon.error("lexicon decode failed, starting empty")
        }
    }

    // MARK: - Reading

    public var entries: [LexiconEntry] {
        lock.locked { items }
    }

    public func rule(for word: String, sourceLayout: Layout) -> LexiconRule? {
        let key = LexiconKey(word: word, sourceLayout: sourceLayout)
        return lock.locked { index[key].map { items[$0].rule } }
    }

    public static func validate(word: String, sourceLayout: Layout, rule: LexiconRule) -> LexiconValidationError? {
        let normalized = LexiconKey.normalize(word)
        if normalized.isEmpty { return .empty }
        if normalized.count > maxWordLength { return .tooLong }
        if !LayoutMapper.canBeTyped(normalized, on: sourceLayout) { return .notTypable }
        if case .alwaysCorrect(let target) = rule {
            if target == sourceLayout { return .sameLayoutTarget }
            if (sourceLayout == .english) == (target == .english) { return .unsupportedPair }
        }
        return nil
    }

    // MARK: - Editing (Words tab)

    /// Adds a rule the user made.
    public func add(word: String, sourceLayout: Layout, rule: LexiconRule) -> LexiconAddResult {
        if let error = Self.validate(word: word, sourceLayout: sourceLayout, rule: rule) {
            return .invalid(error)
        }
        let key = LexiconKey(word: word, sourceLayout: sourceLayout)
        let result: LexiconAddResult = lock.locked {
            if let existing = index[key] {
                return .duplicate(items[existing])
            }
            let entry = LexiconEntry(
                id: UUID(),
                word: key.word,
                sourceLayout: sourceLayout,
                rule: rule,
                origin: .manual,
                createdAt: now(),
                lastMatchedAt: nil,
                matchCount: 0
            )
            insert(entry)
            return .added(entry)
        }
        if case .added = result { scheduleSave() }
        return result
    }

    /// Replaces the entry with the same id. An edited entry becomes the user's own
    /// (`manual`); another entry that now has the same word + layout is dropped.
    @discardableResult
    public func update(_ entry: LexiconEntry) -> LexiconValidationError? {
        if let error = Self.validate(word: entry.word, sourceLayout: entry.sourceLayout, rule: entry.rule) {
            return error
        }
        var edited = entry
        edited.word = LexiconKey.normalize(entry.word)
        edited.origin = .manual
        let changed: Bool = lock.locked {
            guard let position = items.firstIndex(where: { $0.id == entry.id }) else { return false }
            removeEntry(at: position)
            if let clash = index[edited.key] {
                removeEntry(at: clash)
            }
            insert(edited)
            return true
        }
        if changed { scheduleSave() }
        return nil
    }

    public func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        mutate { removeAll(where: { ids.contains($0.id) }) }
    }

    /// Removes everything learned automatically; the user's own entries stay.
    public func removeLearned() {
        mutate { removeAll(where: { $0.origin != .manual }) }
    }

    public func removeAll() {
        mutate { removeAll(where: { _ in true }) }
    }

    // MARK: - Learning

    /// An automatic correction of `word` was reverted: stop correcting it.
    public func recordRejected(word: String, sourceLayout: Layout) {
        learn(word: word, sourceLayout: sourceLayout, rule: .neverCorrect, origin: .learnedFromRevert)
    }

    /// The user converted `word` with the hotkey although detection did not: correct it
    /// automatically from now on.
    public func recordAccepted(word: String, sourceLayout: Layout, target: Layout) {
        learn(word: word, sourceLayout: sourceLayout, rule: .alwaysCorrect(to: target), origin: .learnedFromHotkey)
    }

    /// A forced hotkey conversion was reverted: drop what that conversion taught.
    public func forgetAccepted(word: String, sourceLayout: Layout) {
        let key = LexiconKey(word: word, sourceLayout: sourceLayout)
        mutate {
            guard let position = index[key], items[position].origin == .learnedFromHotkey else { return false }
            removeEntry(at: position)
            return true
        }
    }

    /// A rule was applied; updates its counters. No-op for words without a rule.
    public func noteMatch(word: String, sourceLayout: Layout) {
        let key = LexiconKey(word: word, sourceLayout: sourceLayout)
        mutate {
            guard let position = index[key] else { return false }
            items[position].matchCount += 1
            items[position].lastMatchedAt = now()
            return true
        }
    }

    /// Writes a pending change now (e.g. at app termination).
    public func flush() {
        saveQueue.sync {
            guard let pending = pendingSave else { return }
            pending.cancel()
            pendingSave = nil
            performSave()
        }
    }

    // MARK: - Private

    private func learn(word: String, sourceLayout: Layout, rule: LexiconRule, origin: LexiconOrigin) {
        guard Self.validate(word: word, sourceLayout: sourceLayout, rule: rule) == nil else { return }
        let key = LexiconKey(word: word, sourceLayout: sourceLayout)
        mutate {
            if let position = index[key] {
                guard items[position].origin != .manual else { return false }
                removeEntry(at: position)
            }
            insert(LexiconEntry(
                id: UUID(),
                word: key.word,
                sourceLayout: sourceLayout,
                rule: rule,
                origin: origin,
                createdAt: now(),
                lastMatchedAt: nil,
                matchCount: 0
            ))
            evictIfNeeded()
            return true
        }
    }

    /// Runs `change` under the lock and schedules a save when it reports a change.
    private func mutate(_ change: () -> Bool) {
        if lock.locked(change) {
            scheduleSave()
        }
    }

    // Callers hold `lock`.
    private func insert(_ entry: LexiconEntry) {
        index[entry.key] = items.count
        items.append(entry)
        if entry.origin != .manual { learnedCount += 1 }
    }

    // Callers hold `lock`. Swap-remove: the last entry moves into `position`.
    private func removeEntry(at position: Int) {
        let removed = items[position]
        index[removed.key] = nil
        if removed.origin != .manual { learnedCount -= 1 }
        let last = items.count - 1
        if position != last {
            items[position] = items[last]
            index[items[position].key] = position
        }
        items.removeLast()
    }

    // Callers hold `lock`.
    private func removeAll(where shouldRemove: (LexiconEntry) -> Bool) -> Bool {
        let kept = items.filter { !shouldRemove($0) }
        guard kept.count != items.count else { return false }
        items = []
        index = [:]
        learnedCount = 0
        kept.forEach(insert)
        return true
    }

    // Callers hold `lock`. Evicts the learned entries unused for the longest time.
    private func evictIfNeeded() {
        let excess = learnedCount - Self.maxLearnedEntries
        guard excess > 0 else { return }
        let oldest = items
            .filter { $0.origin != .manual }
            .sorted { ($0.lastMatchedAt ?? $0.createdAt) < ($1.lastMatchedAt ?? $1.createdAt) }
            .prefix(excess)
            .map(\.key)
        for key in oldest {
            if let position = index[key] { removeEntry(at: position) }
        }
    }

    private func scheduleSave() {
        guard saveDelay > 0 else {
            saveQueue.sync {
                pendingSave?.cancel()
                pendingSave = nil
                performSave()
            }
            return
        }
        saveQueue.async { [weak self] in
            guard let self else { return }
            self.pendingSave?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingSave = nil
                self.performSave()
            }
            self.pendingSave = work
            self.saveQueue.asyncAfter(deadline: .now() + self.saveDelay, execute: work)
        }
    }

    // Runs on `saveQueue`.
    private func performSave() {
        let snapshot = entries
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else {
            SwitchFixLog.lexicon.error("lexicon encode failed")
            return
        }
        storage.save(data)
        SwitchFixLog.lexicon.notice("lexicon saved entries=\(snapshot.count)")
        DispatchQueue.main.async { [weak self] in
            NotificationCenter.default.post(name: .personalLexiconDidChange, object: self)
        }
    }
}

public extension Notification.Name {
    static let personalLexiconDidChange = Notification.Name("SwitchFix_PersonalLexiconDidChange")
}

private extension NSLock {
    /// `NSLocking.withLock` needs macOS 14; the app supports macOS 13.
    func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
