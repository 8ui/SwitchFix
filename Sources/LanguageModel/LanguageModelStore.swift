import Foundation

/// Loads and caches the bundled `<code>.sfng` models.
///
/// Resource lookup mirrors `DictionaryLoader.findDictionaryURL`: the SwiftPM resource
/// bundle may sit next to the executable (`swift run`) or inside the app's
/// `Contents/Resources`, and newer SwiftPM versions put files under the bundle's own
/// `Contents/Resources` — keep this in sync with `scripts/build-app.sh`.
public final class LanguageModelStore: @unchecked Sendable {
    public static let shared = LanguageModelStore()

    private let lock = NSLock()
    private var models: [ModelLanguage: CharNgramModel] = [:]
    private var failed: Set<ModelLanguage> = []

    public init() {}

    /// The bundled model for `language`, or nil when it is missing or invalid.
    public func model(for language: ModelLanguage) -> CharNgramModel? {
        lock.lock()
        defer { lock.unlock() }
        if let model = models[language] { return model }
        if failed.contains(language) { return nil }
        guard let url = Self.resourceURL(for: language),
              let data = try? Data(contentsOf: url),
              let model = try? NgramBinaryFormat.decode(data),
              model.language == language else {
            failed.insert(language)
            return nil
        }
        models[language] = model
        return model
    }

    public static func load(contentsOf url: URL) throws -> CharNgramModel {
        try NgramBinaryFormat.decode(Data(contentsOf: url))
    }

    static func resourceURL(for language: ModelLanguage) -> URL? {
        let bundleName = "SwitchFix_LanguageModel.bundle"
        let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
            executableDirectory?.appendingPathComponent(bundleName),
        ]
        for case let candidate? in candidates {
            guard let bundle = Bundle(url: candidate) else { continue }
            if let url = bundle.url(forResource: language.rawValue, withExtension: "sfng") {
                return url
            }
            if let url = bundle.url(forResource: language.rawValue, withExtension: "sfng", subdirectory: "Resources") {
                return url
            }
            // Flat bundles on Linux have no Info.plist; look at the path directly.
            for path in ["\(language.rawValue).sfng", "Resources/\(language.rawValue).sfng", "Contents/Resources/\(language.rawValue).sfng"] {
                let url = candidate.appendingPathComponent(path)
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }
}
