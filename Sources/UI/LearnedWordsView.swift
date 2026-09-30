import SwiftUI
import Core

/// `Layout` alone is ambiguous next to SwiftUI's `Layout` protocol.
typealias KeyboardLayout = Core.Layout

// MARK: - Model

/// A lexicon entry with the sortable, localized values the table shows.
struct LexiconRow: Identifiable {
    let entry: LexiconEntry
    var id: UUID { entry.id }
    var word: String { entry.word }
    var layoutName: String { LexiconText.code(entry.sourceLayout) }
    var ruleName: String { LexiconText.rule(entry.rule) }
    var originName: String { LexiconText.origin(entry.origin) }
    var matchCount: Int { entry.matchCount }
    var lastMatched: Date { entry.lastMatchedAt ?? .distantPast }
    var lastUsedText: String { LexiconText.lastUsed(entry.lastMatchedAt) }
}

enum LexiconText {
    static func code(_ layout: KeyboardLayout) -> String {
        switch layout {
        case .english: return "EN"
        case .ukrainian: return "UK"
        case .russian: return "RU"
        }
    }

    static func rule(_ rule: LexiconRule) -> String {
        switch rule {
        case .neverCorrect: return L10n.tr("Don't correct")
        case .alwaysCorrect(let target): return String(format: L10n.tr("Correct → %@"), code(target))
        }
    }

    static func origin(_ origin: LexiconOrigin) -> String {
        switch origin {
        case .learnedFromRevert: return L10n.tr("Revert")
        case .learnedFromHotkey: return L10n.tr("Hotkey")
        case .manual: return L10n.tr("Manual")
        }
    }

    static func lastUsed(_ date: Date?) -> String {
        guard let date else { return L10n.tr("Never used") }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return String(format: L10n.tr("Last used: %@"), formatter.string(from: date))
    }

    static func error(_ error: LexiconValidationError) -> String {
        switch error {
        case .empty: return L10n.tr("Enter a word.")
        case .tooLong: return L10n.tr("The word is too long (64 characters at most).")
        case .notTypable: return L10n.tr("These characters can't be typed on the selected layout.")
        case .sameLayoutTarget: return L10n.tr("Choose a different target layout.")
        case .unsupportedPair: return L10n.tr("SwitchFix converts only between English and Russian or Ukrainian.")
        case .duplicate: return L10n.tr("This word is already in the list. Edit the existing entry instead.")
        case .missing: return L10n.tr("This entry has changed meanwhile. Close the form and try again.")
        }
    }
}

/// The add/edit form's state.
struct LexiconDraft: Identifiable {
    /// Sheet identity; stays the same while the form is open.
    let id = UUID()
    /// The entry being edited, nil for a new one.
    var entryID: UUID?
    var word = ""
    var sourceLayout: KeyboardLayout = .english
    var neverCorrect = true
    var target: KeyboardLayout = .russian
    var matchCount = 0
    var lastMatchedAt: Date?

    init() {}

    init(entry: LexiconEntry) {
        entryID = entry.id
        word = entry.word
        sourceLayout = entry.sourceLayout
        matchCount = entry.matchCount
        lastMatchedAt = entry.lastMatchedAt
        switch entry.rule {
        case .neverCorrect:
            neverCorrect = true
            target = LexiconDraft.targets(for: entry.sourceLayout)[0]
        case .alwaysCorrect(let layout):
            neverCorrect = false
            target = layout
        }
    }

    var rule: LexiconRule { neverCorrect ? .neverCorrect : .alwaysCorrect(to: target) }

    /// Conversions are English ↔ Cyrillic only.
    static func targets(for source: KeyboardLayout) -> [KeyboardLayout] {
        source == .english ? [.russian, .ukrainian] : [.english]
    }
}

final class LearnedWordsViewModel: ObservableObject {
    enum RuleFilter: Hashable {
        case all
        case neverCorrect
        case alwaysCorrect
    }

    @Published private(set) var entries: [LexiconEntry] = []
    @Published var searchText = ""
    @Published var ruleFilter: RuleFilter = .all
    @Published var sortOrder: [KeyPathComparator<LexiconRow>] = [KeyPathComparator(\LexiconRow.word)]
    @Published var selection: Set<UUID> = []

    private let lexicon: PersonalLexicon

    init(lexicon: PersonalLexicon = .shared) {
        self.lexicon = lexicon
        reload()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reload),
            name: .personalLexiconDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc func reload() {
        entries = lexicon.entries
        selection.formIntersection(entries.map(\.id))
    }

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

    func draft(for id: UUID?) -> LexiconDraft? {
        guard let id, let entry = entries.first(where: { $0.id == id }) else { return nil }
        return LexiconDraft(entry: entry)
    }

    /// Saves the form; returns a localized error to show, or nil when saved.
    func save(_ draft: LexiconDraft) -> String? {
        if let entryID = draft.entryID,
           var entry = entries.first(where: { $0.id == entryID }) {
            entry.word = draft.word
            entry.sourceLayout = draft.sourceLayout
            entry.rule = draft.rule
            if let error = lexicon.update(entry) {
                return LexiconText.error(error)
            }
            reload()
            return nil
        }
        switch lexicon.add(word: draft.word, sourceLayout: draft.sourceLayout, rule: draft.rule) {
        case .added(let entry):
            reload()
            selection = [entry.id]
            return nil
        case .duplicate(let existing):
            selection = [existing.id]
            return L10n.tr("This word is already in the list. Edit the existing entry instead.")
        case .invalid(let error):
            return LexiconText.error(error)
        }
    }

    /// Deletes the selected rows that are visible: rows hidden by the search or filter
    /// stay, even if they were selected earlier.
    func removeSelected() {
        let visible = Set(rows.map(\.id))
        lexicon.remove(ids: selection.intersection(visible))
        selection = []
        reload()
    }

    func removeLearned() {
        lexicon.removeLearned()
        reload()
    }

    func removeAll() {
        lexicon.removeAll()
        reload()
    }
}

// MARK: - Views

struct LearnedWordsView: View {
    @ObservedObject var settings: SettingsViewModel
    @StateObject private var model = LearnedWordsViewModel()
    @State private var draft: LexiconDraft?
    @State private var pendingConfirmation: Confirmation?

    private enum Confirmation: Identifiable {
        case resetLearned
        case deleteAll
        var id: Self { self }
    }

    var body: some View {
        SettingsTabContainer(language: settings.language, width: SettingsTab.words.contentWidth) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("Learned Words")).font(.headline)

                HStack {
                    TextField(L10n.tr("Search"), text: $model.searchText)
                        .textFieldStyle(.roundedBorder)
                    Picker("", selection: $model.ruleFilter) {
                        Text(L10n.tr("All")).tag(LearnedWordsViewModel.RuleFilter.all)
                        Text(L10n.tr("Don't correct")).tag(LearnedWordsViewModel.RuleFilter.neverCorrect)
                        Text(L10n.tr("Correct")).tag(LearnedWordsViewModel.RuleFilter.alwaysCorrect)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                VStack(spacing: 0) {
                    table
                    Divider()
                    toolbar
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

                SettingsNote(text: L10n.tr("SwitchFix learns from your actions: undoing an automatic correction adds “Don't correct”, converting a word with the hotkey adds “Correct”. Your own entries are never changed automatically."))
            }
        }
        .sheet(item: $draft) { current in
            LexiconEntryForm(draft: current, save: model.save) { draft = nil }
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { pendingConfirmation != nil },
                set: { if !$0 { pendingConfirmation = nil } }
            ),
            presenting: pendingConfirmation
        ) { confirmation in
            switch confirmation {
            case .resetLearned:
                Button(L10n.tr("Reset"), role: .destructive, action: model.removeLearned)
            case .deleteAll:
                Button(L10n.tr("Delete All"), role: .destructive, action: model.removeAll)
            }
            Button(L10n.tr("Cancel"), role: .cancel) {}
        }
    }

    private var confirmationTitle: String {
        switch pendingConfirmation {
        case .resetLearned: return L10n.tr("Reset learned words? Words you added yourself stay.")
        case .deleteAll: return L10n.tr("Delete all words? This can't be undone.")
        case nil: return ""
        }
    }

    private var table: some View {
        Table(model.rows, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn(L10n.tr("Word"), value: \.word) { row in
                Text(row.word).help(row.lastUsedText)
            }
            TableColumn(L10n.tr("Layout"), value: \.layoutName) { row in
                Text(row.layoutName).help(row.lastUsedText)
            }
            .width(88)
            TableColumn(L10n.tr("Rule"), value: \.ruleName) { row in
                Text(row.ruleName).help(row.lastUsedText)
            }
            .width(125)
            TableColumn(L10n.tr("Source"), value: \.originName) { row in
                Text(row.originName).help(row.lastUsedText)
            }
            .width(80)
            TableColumn(L10n.tr("Uses"), value: \.matchCount) { row in
                Text("\(row.matchCount)").help(row.lastUsedText)
            }
            .width(105)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if ids.count == 1 {
                Button(L10n.tr("Edit…")) { draft = model.draft(for: ids.first) }
            }
            Button(L10n.tr("Delete")) {
                model.selection = ids
                model.removeSelected()
            }
        } primaryAction: { ids in
            if ids.count == 1 { draft = model.draft(for: ids.first) }
        }
        .onDeleteCommand(perform: model.removeSelected)
        .frame(height: 260)
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            Button {
                draft = LexiconDraft()
            } label: {
                Image(systemName: "plus").frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .help(L10n.tr("Add Word"))
            .accessibilityLabel(L10n.tr("Add Word"))

            Divider().frame(height: 12)

            Button(action: model.removeSelected) {
                Image(systemName: "minus").frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .help(L10n.tr("Delete"))
            .accessibilityLabel(L10n.tr("Delete"))
            .disabled(model.selection.isEmpty)

            Divider().frame(height: 12)

            Button(L10n.tr("Edit…")) { draft = model.draft(for: model.selection.first) }
                .buttonStyle(.borderless)
                .padding(.horizontal, 6)
                .accessibilityLabel(L10n.tr("Edit…"))
                .disabled(model.selection.count != 1)

            Spacer()

            Menu {
                Button(L10n.tr("Reset Learned Words…")) { pendingConfirmation = .resetLearned }
                Button(L10n.tr("Delete All Words…")) { pendingConfirmation = .deleteAll }
            } label: {
                // On the image: the menu takes its AX title from the symbol name ("More").
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel(L10n.tr("More actions"))
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L10n.tr("More actions"))
        }
        .padding(4)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

/// Add/edit form for one lexicon entry.
struct LexiconEntryForm: View {
    @State var draft: LexiconDraft
    let save: (LexiconDraft) -> String?
    let dismiss: () -> Void
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.entryID == nil ? L10n.tr("Add Word") : L10n.tr("Edit Word")).font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text(L10n.tr("Word:")).gridColumnAlignment(.trailing)
                    TextField("", text: $draft.word).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text(L10n.tr("Typed on:"))
                    Picker("", selection: $draft.sourceLayout) {
                        ForEach(KeyboardLayout.allCases, id: \.self) { layout in
                            Text(L10n.tr(layout.displayName)).tag(layout)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: draft.sourceLayout) { source in
                        if !LexiconDraft.targets(for: source).contains(draft.target) {
                            draft.target = LexiconDraft.targets(for: source)[0]
                        }
                    }
                }
                GridRow {
                    Text(L10n.tr("Rule:"))
                    Picker("", selection: $draft.neverCorrect) {
                        Text(L10n.tr("Don't correct")).tag(true)
                        Text(L10n.tr("Correct to")).tag(false)
                    }
                    .labelsHidden()
                    .pickerStyle(.radioGroup)
                }
                if !draft.neverCorrect {
                    GridRow {
                        Text(L10n.tr("Target layout:"))
                        Picker("", selection: $draft.target) {
                            ForEach(LexiconDraft.targets(for: draft.sourceLayout), id: \.self) { layout in
                                Text(L10n.tr(layout.displayName)).tag(layout)
                            }
                        }
                        .labelsHidden()
                    }
                }
                if draft.entryID != nil {
                    GridRow {
                        Text(L10n.tr("Uses:"))
                        Text("\(draft.matchCount) · \(LexiconText.lastUsed(draft.lastMatchedAt))")
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let error {
                SettingsNote(text: error, color: .red)
            }

            HStack {
                Spacer()
                Button(L10n.tr("Cancel"), action: dismiss).keyboardShortcut(.cancelAction)
                Button(L10n.tr("Save")) {
                    error = save(draft)
                    if error == nil { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
