import Foundation

/// Parses RIFF chunks rather than assuming every WAV has a 44-byte header.
enum PCM16Wave {
    struct Payload { let sampleRate: UInt32; let channels: UInt16; let samples: Data }
    static func read(_ data: Data) throws -> Payload {
        func value(_ offset: Int, _ bytes: Int) throws -> UInt32 {
            guard offset >= 0, offset + bytes <= data.count else { throw URLError(.cannotDecodeContentData) }
            return (0..<bytes).reduce(UInt32(0)) { $0 | UInt32(data[offset + $1]) << ($1 * 8) }
        }
        guard data.count >= 44, data.prefix(4) == Data("RIFF".utf8), data[8..<12] == Data("WAVE".utf8) else { throw URLError(.cannotDecodeContentData) }
        var cursor = 12, rate: UInt32?, channels: UInt16?, samples: Data?
        while cursor + 8 <= data.count {
            let kind = data[cursor..<cursor + 4], size = Int(try value(cursor + 4, 4)), start = cursor + 8
            guard size <= data.count - start else { throw URLError(.cannotDecodeContentData) }
            if kind == Data("fmt ".utf8) {
                guard size >= 16, try value(start, 2) == 1, try value(start + 14, 2) == 16 else { throw URLError(.cannotDecodeContentData) }
                channels = UInt16(try value(start + 2, 2)); rate = try value(start + 4, 4)
            } else if kind == Data("data".utf8) { samples = Data(data[start..<start + size]) }
            cursor = start + size + (size % 2)
        }
        guard let rate, let channels, let samples, rate > 0, channels > 0, samples.count % (Int(channels) * 2) == 0 else { throw URLError(.cannotDecodeContentData) }
        return Payload(sampleRate: rate, channels: channels, samples: samples)
    }
    static func header(bytes: UInt32, sampleRate: UInt32, channels: UInt16) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        data.append(Data("RIFF".utf8)); append(bytes + 36); data.append(Data("WAVEfmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(channels); append(sampleRate); append(sampleRate * UInt32(channels) * 2)
        append(channels * 2); append(UInt16(16)); data.append(Data("data".utf8)); append(bytes)
        return data
    }
}
