import Foundation

/// A character n-gram language model over one language's alphabet.
///
/// The model is a dense table of natural-log probabilities `log P(c | context)` for
/// every context of `order - 1` symbols and every next symbol, with smoothing already
/// applied, so scoring a word is `order` table lookups per character and never
/// allocates. Symbol 0 is the word boundary: contexts start as all-boundary and the
/// word ends by predicting the boundary.
public struct CharNgramModel: Sendable {
    public let language: ModelLanguage
    public let order: Int
    /// Log-probability charged for a character outside the alphabet (e.g. `,` inside
    /// what should be an English word). The context restarts after it.
    public let unknownSymbolLogProb: Float
    let table: [Float]
    let symbolCount: Int
    private let symbolIndex: [UInt32: Int]

    init(language: ModelLanguage, order: Int, unknownSymbolLogProb: Float, table: [Float]) {
        self.language = language
        self.order = order
        self.unknownSymbolLogProb = unknownSymbolLogProb
        self.table = table
        let alphabet = language.alphabet
        self.symbolCount = alphabet.count + 1
        var index: [UInt32: Int] = [:]
        for (offset, scalar) in alphabet.enumerated() {
            index[scalar.value] = offset + 1
        }
        self.symbolIndex = index
    }

    /// Total natural-log probability of `word` (including the end-of-word boundary).
    /// Case and typographic apostrophes are normalized first.
    public func logProbability(of word: String) -> Double {
        var context = Array(repeating: 0, count: order - 1)
        var total: Double = 0
        for scalar in TextNormalization.normalize(word).unicodeScalars {
            guard let symbol = symbolIndex[scalar.value] else {
                total += Double(unknownSymbolLogProb)
                for i in context.indices { context[i] = 0 }
                continue
            }
            total += Double(table[slot(context: context, next: symbol)])
            shift(&context, symbol)
        }
        total += Double(table[slot(context: context, next: 0)])
        return total
    }

    @inline(__always)
    private func slot(context: [Int], next: Int) -> Int {
        var index = 0
        for symbol in context {
            index = index * symbolCount + symbol
        }
        return index * symbolCount + next
    }

    @inline(__always)
    private func shift(_ context: inout [Int], _ symbol: Int) {
        guard !context.isEmpty else { return }
        for i in 0..<(context.count - 1) {
            context[i] = context[i + 1]
        }
        context[context.count - 1] = symbol
    }
}
