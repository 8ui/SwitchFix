import Foundation

/// Accumulates character n-gram counts from words and turns them into a smoothed
/// `CharNgramModel`. Lives in the runtime module (not the trainer) so tests can
/// round-trip a model without the trainer executable.
public struct NgramCounter {
    public let language: ModelLanguage
    public let order: Int
    private let symbolCount: Int
    private let symbolIndex: [UInt32: Int]
    /// counts[context * symbolCount + next] for full-order n-grams.
    private var counts: [Double]
    public private(set) var totalWeight: Double = 0

    public init(language: ModelLanguage, order: Int = 3) {
        precondition((2...4).contains(order), "supported n-gram orders are 2...4")
        self.language = language
        self.order = order
        let alphabet = language.alphabet
        self.symbolCount = alphabet.count + 1
        var index: [UInt32: Int] = [:]
        for (offset, scalar) in alphabet.enumerated() {
            index[scalar.value] = offset + 1
        }
        self.symbolIndex = index
        self.counts = Array(repeating: 0, count: Self.power(symbolCount, order))
    }

    /// Adds one word with the given weight (e.g. its corpus frequency). Words with
    /// symbols outside the alphabet are ignored.
    public mutating func add(word: String, weight: Double = 1) {
        var symbols: [Int] = []
        for scalar in TextNormalization.normalize(word).unicodeScalars {
            guard let symbol = symbolIndex[scalar.value] else { return }
            symbols.append(symbol)
        }
        guard !symbols.isEmpty else { return }
        symbols.append(0)

        var context = Array(repeating: 0, count: order - 1)
        for symbol in symbols {
            var index = 0
            for c in context { index = index * symbolCount + c }
            counts[index * symbolCount + symbol] += weight
            if !context.isEmpty {
                context.removeFirst()
                context.append(symbol)
            }
        }
        totalWeight += weight
    }

    /// Builds the model with interpolated Witten–Bell smoothing:
    ///
    ///     P_k(c | h) = (C(h c) + T(h) · P_{k-1}(c | h')) / (C(h) + T(h))
    ///
    /// where `h'` drops the oldest symbol of `h`, `T(h)` is the number of distinct
    /// symbols seen after `h`, and the unigram level is add-one smoothed. Contexts never
    /// seen fall back to the lower order entirely.
    public func makeModel(unknownSymbolLogProb: Float = -12) -> CharNgramModel {
        let k = symbolCount
        // countsByOrder[n] has k^(n) cells: n-gram counts of length n (context n-1 + next).
        var countsByOrder: [[Double]] = Array(repeating: [], count: order + 1)
        countsByOrder[order] = counts
        if order > 1 {
            for n in stride(from: order - 1, through: 1, by: -1) {
                // Marginalize the oldest context symbol.
                let higher = countsByOrder[n + 1]
                let size = Self.power(k, n)
                var lower = Array(repeating: 0.0, count: size)
                for i in 0..<higher.count {
                    lower[i % size] += higher[i]
                }
                countsByOrder[n] = lower
            }
        }

        // Unigram: add-one over all symbols.
        let unigramCounts = countsByOrder[1]
        let unigramTotal = unigramCounts.reduce(0, +)
        var probabilities = unigramCounts.map { ($0 + 1) / (unigramTotal + Double(k)) }

        if order >= 2 {
            for n in 2...order {
                let ngramCounts = countsByOrder[n]
                let contexts = Self.power(k, n - 1)
                var next = Array(repeating: 0.0, count: Self.power(k, n))
                for context in 0..<contexts {
                    var contextTotal = 0.0
                    var distinct = 0.0
                    for symbol in 0..<k {
                        let c = ngramCounts[context * k + symbol]
                        contextTotal += c
                        if c > 0 { distinct += 1 }
                    }
                    // Lower-order context = this context without its oldest symbol.
                    let lowerContext = context % Self.power(k, n - 2)
                    for symbol in 0..<k {
                        let lowerProbability = probabilities[lowerContext * k + symbol]
                        let probability: Double
                        if contextTotal > 0 {
                            probability = (ngramCounts[context * k + symbol] + distinct * lowerProbability)
                                / (contextTotal + distinct)
                        } else {
                            probability = lowerProbability
                        }
                        next[context * k + symbol] = probability
                    }
                }
                probabilities = next
            }
        }

        return CharNgramModel(
            language: language,
            order: order,
            unknownSymbolLogProb: unknownSymbolLogProb,
            table: probabilities.map { Float(log($0)) }
        )
    }

    static func power(_ base: Int, _ exponent: Int) -> Int {
        var result = 1
        for _ in 0..<exponent { result *= base }
        return result
    }
}
