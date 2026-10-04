// VieNeu v3 Turbo native host. Architecture follows the Apache-2.0 upstream
// onnx_runtime_lite.py; SEA-G2P keeps the upstream pronunciation rules intact.
import Foundation
import Darwin

func vieNeuError(_ message: String) -> NSError {
    NSError(domain: "VieNeuNative", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

/// Loads only stored NPZ members (the pinned upstream export uses ZIP_STORED).
/// No shell, temporary extraction or Python is involved.
struct VieNeuArrays {
    let arrays: [String: [Float]]
    init(url: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        func u16(_ i: Int) -> Int { Int(data[i]) | Int(data[i+1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i+2) << 16 }
        guard data.count > 22 else { throw vieNeuError("Dữ liệu trọng số không hợp lệ.") }
        var end = data.count - 22
        while end >= max(0, data.count - 65557), u32(end) != 0x06054b50 { end -= 1 }
        guard end >= 0, u32(end) == 0x06054b50 else { throw vieNeuError("Không đọc được trọng số NPZ.") }
        var at = u32(end + 16), values: [String: [Float]] = [:]
        for _ in 0..<u16(end + 10) {
            guard at + 46 <= data.count, u32(at) == 0x02014b50 else { throw vieNeuError("Trọng số NPZ bị cắt.") }
            let length = u32(at + 24), nameLength = u16(at + 28), extra = u16(at + 30), comment = u16(at + 32), local = u32(at + 42)
            guard u16(at + 10) == 0, at + 46 + nameLength <= data.count, local + 30 <= data.count else { throw vieNeuError("Định dạng trọng số chưa hỗ trợ.") }
            let name = String(decoding: data[(at+46)..<(at+46+nameLength)], as: UTF8.self)
            let start = local + 30 + u16(local+26) + u16(local+28)
            guard length > 10, start + length <= data.count, data[start] == 0x93 else { throw vieNeuError("Mảng trọng số không hợp lệ.") }
            let major = data[start+6], headerLength = major == 1 ? u16(start+8) : u32(start+8)
            let headerStart = start + (major == 1 ? 10 : 12), payload = headerStart + headerLength
            guard payload <= start + length else { throw vieNeuError("Header trọng số bị cắt.") }
            let header = String(decoding: data[headerStart..<payload], as: UTF8.self)
            guard header.contains("'<f4'"), header.contains("False") else { throw vieNeuError("Trọng số phải là Float32 little-endian.") }
            let count = (start + length - payload) / 4
            values[String(name.dropLast(4))] = data[payload..<(payload+count*4)].withUnsafeBytes { raw in
                (0..<count).map { raw.loadUnaligned(fromByteOffset: $0*4, as: Float.self) }
            }
            at += 46 + nameLength + extra + comment
        }
        arrays = values
    }
    func required(_ key: String, count: Int) throws -> [Float] {
        guard let value = arrays[key], value.count == count else { throw vieNeuError("Trọng số \(key) không tương thích.") }
        return value
    }
}

/// Exact byte-level BPE used by the pinned VieNeu tokenizer export.
public struct VieNeuTokenizer {
    private let vocab: [String: Int]
    private let ranks: [String: Int]
    private let byteMap: [String]
    private let regex: NSRegularExpression
    public init(url: URL) throws {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        guard let model = object?["model"] as? [String: Any], let vocab = model["vocab"] as? [String: Int],
              let merges = model["merges"] as? [[String]] else { throw vieNeuError("Tokenizer không hợp lệ.") }
        self.vocab = vocab
        self.ranks = Dictionary(uniqueKeysWithValues: merges.enumerated().map { ($0.element.joined(separator: "\u{0}"), $0.offset) })
        // GPT-2's missing byte sequence starts at U+0100, independently of the printable count.
        var map = Array(repeating: "", count: 256), next: UInt32 = 256
        let printable = Set(Array(33...126) + Array(161...172) + Array(174...255))
        for byte in 0...255 {
            let scalar: UInt32 = printable.contains(byte) ? UInt32(byte) : next
            if !printable.contains(byte) { next += 1 }
            map[byte] = String(UnicodeScalar(scalar)!)
        }
        byteMap = map
        regex = try NSRegularExpression(pattern: "(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\\r\\n\\p{L}\\p{N}]?\\p{L}+|\\p{N}| ?[^\\s\\p{L}\\p{N}]+[\\r\\n]*|\\s*[\\r\\n]+|\\s+(?!\\S)|\\s+")
    }
    public func encode(_ source: String) -> [Int] {
        let text = source.precomposedStringWithCanonicalMapping, ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).flatMap { match -> [Int] in
            var pieces = ns.substring(with: match.range).utf8.map { byteMap[Int($0)] }
            while pieces.count > 1 {
                var winner: Int?, rank = Int.max
                for i in 0..<(pieces.count-1) {
                    if let candidate = ranks[pieces[i] + "\u{0}" + pieces[i+1]], candidate < rank { winner = i; rank = candidate }
                }
                guard let index = winner else { break }
                pieces[index] += pieces.remove(at: index+1)
            }
            return pieces.map { vocab[$0] ?? 43 }
        }
    }
}

final class VieNeuPhonemizer {
    typealias Open = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?
    typealias Close = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias Convert = @convention(c) (UnsafeRawPointer?, UnsafePointer<CChar>, Int32) -> UnsafeMutablePointer<CChar>?
    typealias Free = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
    private let library: UnsafeMutableRawPointer
    private let handle: UnsafeMutableRawPointer
    private let close: Close
    private let convert: Convert
    private let free: Free
    init(libraryURL: URL, dictionary: URL) throws {
        guard let library = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL) else { throw vieNeuError("Chưa có bộ chuyển âm native.") }
        func symbol<T>(_ name: String, _ type: T.Type) throws -> T {
            guard let pointer = dlsym(library, name) else { throw vieNeuError("Bộ chuyển âm không tương thích.") }
            return unsafeBitCast(pointer, to: type)
        }
        do {
            let abi = try symbol("sea_g2p_abi_version", (@convention(c) () -> Int32).self)
            guard abi() == 1 else { throw vieNeuError("Phiên bản bộ chuyển âm không tương thích.") }
            let open = try symbol("sea_g2p_open", Open.self)
            close = try symbol("sea_g2p_close", Close.self)
            convert = try symbol("sea_g2p_phonemize", Convert.self)
            free = try symbol("sea_g2p_string_free", Free.self)
            guard let handle = dictionary.path.withCString({ open($0) }) else { throw vieNeuError("Không đọc được dữ liệu phát âm.") }
            self.handle = handle; self.library = library
        } catch { dlclose(library); throw error }
    }
    deinit { close(handle); dlclose(library) }
    func phonemes(_ text: String) throws -> String {
        guard let result = text.withCString({ convert(handle, $0, 1) }) else { throw vieNeuError("Không chuyển được văn bản sang âm vị.") }
        defer { free(result) }
        return String(cString: result)
    }
}
