import Carbon
import Foundation
import os
import Utils

public final class InputSourceManager {
    public static let shared = InputSourceManager()

    public struct InputSourceDescriptor: Equatable {
        public let id: String
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    private struct State {
        var sources: [String: TISInputSource] = [:]
        /// Enabled keyboard sources per layout, in discovery order.
        var layoutSources: [Layout: [String]] = [:]
        var tablesBySource: [String: KeyTable] = [:]
        /// The source each layout was last typed on; `switchTo` and the key tables follow it.
        var lastUsedSourceID: [Layout: String] = [:]
        var loggedTableFallbacks: Set<String> = []
        var descriptors: [Layout: [InputSourceDescriptor]] = [:]
        var currentLayout: Layout?
        var currentInputSourceID: String?
        var pendingSelectionID: String?
    }

    private struct SelectionCallbacks {
        var willSelect: ((Layout, String) -> Void)?
        var selectionFailed: (() -> Void)?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let selectionCallbacks = OSAllocatedUnfairLock(initialState: SelectionCallbacks())

    private init() {
        refreshInstalledSources()
    }

    /// Refresh source discovery away from the input and correction hot paths.
    public func refreshInstalledSources() {
        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return
        }

        var discovered: [String: TISInputSource] = [:]
        var layoutSources: [Layout: [String]] = [:]
        var tables: [String: KeyTable] = [:]
        var fallbacks: [String] = []
        var descriptors: [Layout: [InputSourceDescriptor]] = [:]
        let keyboardType = UInt32(LMGetKbdType())

        for source in sources {
            guard let sourceID = Self.stringProperty(source, kTISPropertyInputSourceID),
                  let layout = Layout.allCases.first(where: { $0.matches(sourceID: sourceID) }) else {
                continue
            }
            let sourceName = Self.stringProperty(source, kTISPropertyLocalizedName) ?? sourceID
            if let type = Self.stringProperty(source, kTISPropertyInputSourceType),
               type != (kTISTypeKeyboardLayout as String) {
                continue
            }

            discovered[sourceID] = source
            layoutSources[layout, default: []].append(sourceID)
            // Phonetic layouts are not ЙЦУКЕН-shaped; thresholds were never calibrated on them.
            let systemTable = sourceID.hasSuffix("Russian-Phonetic")
                ? nil
                : KeyTableBuilder.table(for: source, layout: layout, keyboardType: keyboardType)
            if systemTable == nil { fallbacks.append(sourceID) }
            tables[sourceID] = systemTable ?? KeyboardTables.pc.primary(for: layout)
            descriptors[layout, default: []].append(InputSourceDescriptor(id: sourceID, name: sourceName))
        }

        for (layout, list) in descriptors {
            descriptors[layout] = list.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }

        let currentSourceID = Self.fetchCurrentInputSourceID()
        let discoveredSources = discovered
        let discoveredLayoutSources = layoutSources
        let discoveredTables = tables
        let discoveredDescriptors = descriptors
        let fallbackIDs = fallbacks
        let newFallbacks = state.withLock { value -> [String] in
            value.sources = discoveredSources
            value.layoutSources = discoveredLayoutSources
            value.tablesBySource = discoveredTables
            value.descriptors = discoveredDescriptors
            value.lastUsedSourceID = value.lastUsedSourceID.filter { discoveredSources[$0.value] != nil }
            if discoveredSources[currentSourceID] != nil {
                let layout = Self.layout(for: currentSourceID)
                if value.lastUsedSourceID[layout] == nil { value.lastUsedSourceID[layout] = currentSourceID }
            }
            let fresh = fallbackIDs.filter { !value.loggedTableFallbacks.contains($0) }
            value.loggedTableFallbacks.formUnion(fresh)
            return fresh
        }
        for sourceID in newFallbacks {
            SwitchFixLog.source.info("key table unavailable for \(sourceID), using built-in")
        }
    }

    /// Key tables per layout: the override or last-used source first, then the other
    /// enabled sources of that layout; `.pc` for layouts without sources.
    public func keyboardTables(overrides: [Layout: String] = [:]) -> KeyboardTables {
        state.withLock { value in
            KeyboardTables.resolve(
                layoutSources: value.layoutSources,
                tablesBySource: value.tablesBySource,
                firstChoice: value.lastUsedSourceID.merging(overrides) { $1 }
            )
        }
    }

    public func refreshCurrentInputSource() {
        let sourceID = Self.fetchCurrentInputSourceID()
        let layout = Self.layout(for: sourceID)
        state.withLock { value in
            value.currentInputSourceID = sourceID
            value.currentLayout = layout
            if value.sources[sourceID] != nil {
                value.lastUsedSourceID[layout] = sourceID
            }
        }
    }

    public func setSelectionCallbacks(
        willSelect: ((Layout, String) -> Void)?,
        selectionFailed: (() -> Void)?
    ) {
        selectionCallbacks.withLock { value in
            value.willSelect = willSelect
            value.selectionFailed = selectionFailed
        }
    }

    public func consumeExpectedSelection(sourceID: String) -> Bool {
        state.withLock { value in
            guard let pending = value.pendingSelectionID else { return false }
            value.pendingSelectionID = nil
            return pending == sourceID
        }
    }

    public func currentLayout() -> Layout {
        if let cached = state.withLock({ $0.currentLayout }) {
            return cached
        }
        refreshCurrentInputSource()
        return state.withLock { $0.currentLayout ?? .english }
    }

    public func currentInputSourceID() -> String {
        if let cached = state.withLock({ $0.currentInputSourceID }) {
            return cached
        }
        refreshCurrentInputSource()
        return state.withLock { $0.currentInputSourceID ?? "unknown" }
    }

    /// Select a cached source with one TIS call and no source enumeration.
    @discardableResult
    public func switchTo(_ layout: Layout) -> Bool {
        guard let target = state.withLock({ value -> (TISInputSource, String)? in
            let candidates = value.layoutSources[layout] ?? []
            let lastUsed = value.lastUsedSourceID[layout].flatMap { candidates.contains($0) ? $0 : nil }
            guard let sourceID = lastUsed ?? candidates.first,
                  let source = value.sources[sourceID] else {
                return nil
            }
            if value.currentInputSourceID == sourceID {
                return (source, sourceID)
            }
            value.pendingSelectionID = sourceID
            return (source, sourceID)
        }) else {
            SwitchFixLog.source.error("switchTo(\(layout.rawValue)): no cached input source")
            return false
        }
        if currentInputSourceID() == target.1 {
            state.withLock { $0.pendingSelectionID = nil }
            SwitchFixLog.source.debug("switchTo(\(layout.rawValue)): already active")
            return true
        }

        let callbacks = selectionCallbacks.withLock { $0 }
        callbacks.willSelect?(layout, target.1)
        let status = TISSelectInputSource(target.0)
        if status != noErr {
            state.withLock { value in
                if value.pendingSelectionID == target.1 {
                    value.pendingSelectionID = nil
                }
            }
            callbacks.selectionFailed?()
            SwitchFixLog.source.error("switchTo(\(layout.rawValue)): TISSelectInputSource failed (\(status))")
        } else {
            SwitchFixLog.source.notice("layout switched to \(layout.rawValue) (\(target.1))")
        }
        return status == noErr
    }

    public func availableLayouts() -> [Layout] {
        let available = state.withLock { Set($0.descriptors.keys) }
        return Layout.allCases.filter { available.contains($0) }
    }

    public func availableInputSourcesByLayout() -> [Layout: [InputSourceDescriptor]] {
        state.withLock { $0.descriptors }
    }

    private static func fetchCurrentInputSourceID() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let id = stringProperty(source, kTISPropertyInputSourceID) else {
            return "unknown"
        }
        return id
    }

    private static func layout(for sourceID: String) -> Layout {
        if let layout = Layout.allCases.first(where: { $0.matches(sourceID: sourceID) }) {
            return layout
        }
        let lowered = sourceID.lowercased()
        if lowered.contains("russian") { return .russian }
        if lowered.contains("ukrainian") { return .ukrainian }
        return .english
    }

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
