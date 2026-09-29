import Foundation

/// `SFNGRAM1` — on-disk format of a `CharNgramModel`. All integers and floats are
/// little-endian.
///
///     offset  size  field
///     0       8     magic "SFNGRAM1"
///     8       4     format version (1)
///     12      4     order (n)
///     16      4     language code, ASCII, zero-padded ("en\0\0")
///     20      4     alphabet byte count A
///     24      A     alphabet, UTF-8 (without the boundary symbol)
///     24+A    4     unknown-symbol log-probability (Float32)
///     28+A    4     table count T (= (alphabet.count + 1)^n)
///     32+A    4T    table, Float32 natural-log probabilities
///     32+A+4T 8     FNV-1a 64 checksum of all preceding bytes
public enum NgramBinaryFormat {
    public static let magic = Array("SFNGRAM1".utf8)
    public static let version: UInt32 = 1

    public enum DecodeError: Error, Equatable {
        case truncated
        case badMagic
        case unsupportedVersion(UInt32)
        case unknownLanguage(String)
        case alphabetMismatch
        case badOrder(UInt32)
        case badTableCount
        case checksumMismatch
        case trailingBytes
    }

    public static func encode(_ model: CharNgramModel) -> Data {
        var bytes: [UInt8] = []
        bytes.append(contentsOf: magic)
        append(version, to: &bytes)
        append(UInt32(model.order), to: &bytes)
        var code = Array(model.language.rawValue.utf8.prefix(4))
        while code.count < 4 { code.append(0) }
        bytes.append(contentsOf: code)
        let alphabet = Array(String(String.UnicodeScalarView(model.language.alphabet)).utf8)
        append(UInt32(alphabet.count), to: &bytes)
        bytes.append(contentsOf: alphabet)
        append(model.unknownSymbolLogProb.bitPattern, to: &bytes)
        append(UInt32(model.table.count), to: &bytes)
        bytes.reserveCapacity(bytes.count + model.table.count * 4 + 8)
        for value in model.table {
            append(value.bitPattern, to: &bytes)
        }
        append(fnv1a(bytes), to: &bytes)
        return Data(bytes)
    }

    public static func decode(_ data: Data) throws -> CharNgramModel {
        let bytes = [UInt8](data)
        var reader = Reader(bytes: bytes)

        guard bytes.count >= 8 + 8 else { throw DecodeError.truncated }
        guard try reader.read(8) == magic else { throw DecodeError.badMagic }
        let fileVersion = try reader.uint32()
        guard fileVersion == version else { throw DecodeError.unsupportedVersion(fileVersion) }
        let order = try reader.uint32()
        guard (2...4).contains(order) else { throw DecodeError.badOrder(order) }
        let codeBytes = try reader.read(4).filter { $0 != 0 }
        let code = String(decoding: codeBytes, as: UTF8.self)
        guard let language = ModelLanguage(rawValue: code) else { throw DecodeError.unknownLanguage(code) }
        let alphabetCount = Int(try reader.uint32())
        let alphabet = String(decoding: try reader.read(alphabetCount), as: UTF8.self)
        guard Array(alphabet.unicodeScalars) == language.alphabet else { throw DecodeError.alphabetMismatch }
        let unknown = Float(bitPattern: try reader.uint32())
        let tableCount = Int(try reader.uint32())
        let expected = NgramCounter.power(language.alphabet.count + 1, Int(order))
        guard tableCount == expected else { throw DecodeError.badTableCount }
        var table: [Float] = []
        table.reserveCapacity(tableCount)
        for _ in 0..<tableCount {
            table.append(Float(bitPattern: try reader.uint32()))
        }
        let checksumOffset = reader.offset
        let checksum = try reader.uint64()
        guard reader.offset == bytes.count else { throw DecodeError.trailingBytes }
        guard fnv1a(bytes[0..<checksumOffset]) == checksum else { throw DecodeError.checksumMismatch }

        return CharNgramModel(language: language, order: Int(order), unknownSymbolLogProb: unknown, table: table)
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to bytes: inout [UInt8]) {
        withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
    }

    static func fnv1a<C: Collection>(_ bytes: C) -> UInt64 where C.Element == UInt8 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0

        mutating func read(_ count: Int) throws -> [UInt8] {
            guard count >= 0, offset + count <= bytes.count else { throw DecodeError.truncated }
            defer { offset += count }
            return Array(bytes[offset..<(offset + count)])
        }

        mutating func uint32() throws -> UInt32 {
            let b = try read(4)
            return UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
        }

        mutating func uint64() throws -> UInt64 {
            let low = UInt64(try uint32())
            let high = UInt64(try uint32())
            return low | high << 32
        }
    }
}
