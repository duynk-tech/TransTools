import Foundation
import CryptoKit
import Accelerate
import OnnxRuntimeBindings

final class VieNeuModel {
    struct Voice: Decodable { let speaker_emb: [Float]; let codes: [[Int]]? }
    struct Presets: Decodable { let presets: [String: Voice] }
    private let env: ORTEnv
    private let prefill: ORTSession, decode: ORTSession, acoustic: ORTSession, codec: ORTSession
    private let tokenizer: VieNeuTokenizer
    private let phonemizer: VieNeuPhonemizer
    private let voices: [String: Voice]
    private let textEmb: [Float], audioEmb: [Float], projection: [Float], bias: [Float], lnW: [Float], lnB: [Float], epsilon: Float
    private let codecSpec: [String: Any]
    private let preNames: Set<String>, acNames: Set<String>, codecNames: Set<String>
    private let hidden = 768, channels = 16, audioVocab = 1024, layers = 12
    init(directory: URL, resources: URL) throws {
        try Self.verifyArtifacts(directory: directory, resources: resources)
        let graph = directory.appendingPathComponent("assets/VieNeu-TTS-v3-Turbo/onnx_update")
        let codecPath = directory.appendingPathComponent("assets/MOSS-Audio-Tokenizer-Nano-ONNX")
        tokenizer = try VieNeuTokenizer(url: graph.appendingPathComponent("tokenizer.json"))
        phonemizer = try VieNeuPhonemizer(libraryURL: resources.appendingPathComponent("libsea_g2p_rs.dylib"), dictionary: directory.appendingPathComponent("sea_g2p.bin"))
        voices = try JSONDecoder().decode(Presets.self, from: Data(contentsOf: resources.appendingPathComponent("voices_v3_turbo.json"))).presets
        let arrays = try VieNeuArrays(url: graph.appendingPathComponent("vieneu_v3_heads.npz"))
        textEmb = try arrays.required("text_emb", count: 419*768)
        audioEmb = try arrays.required("audio_emb", count: 16*1024*768)
        projection = try arrays.required("xvec_w", count: 768*192)
        bias = try arrays.required("xvec_b", count: 768)
        lnW = try arrays.required("xvec_ln_w", count: 768)
        lnB = try arrays.required("xvec_ln_b", count: 768)
        epsilon = try arrays.required("xvec_ln_eps", count: 1)[0]
        let meta = try JSONSerialization.jsonObject(with: Data(contentsOf: codecPath.appendingPathComponent("codec_browser_onnx_meta.json"))) as? [String: Any]
        guard let spec = meta?["streaming_decode"] as? [String: Any] else { throw vieNeuError("Thiếu cấu hình giải mã audio.") }
        codecSpec = spec
        env = try ORTEnv(loggingLevel: .error)
        let options = try ORTSessionOptions()
        try options.setIntraOpNumThreads(4)
        try options.setGraphOptimizationLevel(.all)
        try options.addConfigEntry(withKey: "session.intra_op.allow_spinning", value: "0")
        prefill = try ORTSession(env: env, modelPath: graph.appendingPathComponent("vieneu_prefill.onnx").path, sessionOptions: options)
        decode = try ORTSession(env: env, modelPath: graph.appendingPathComponent("vieneu_decode_step.onnx").path, sessionOptions: options)
        acoustic = try ORTSession(env: env, modelPath: graph.appendingPathComponent("vieneu_acoustic_cached.onnx").path, sessionOptions: options)
        codec = try ORTSession(env: env, modelPath: codecPath.appendingPathComponent("moss_audio_tokenizer_decode_step.onnx").path, sessionOptions: options)
        preNames = Set(try prefill.outputNames()); acNames = Set(try acoustic.outputNames()); codecNames = Set(try codec.outputNames())
    }
    /// Integrity is checked once when sessions are loaded, never during SwiftUI
    /// rendering or between streamed packets.
    private static func verifyArtifacts(directory: URL, resources: URL) throws {
        struct Manifest: Decodable { struct File: Decodable { let path: String; let size: Int64; let sha256: String }; let files: [File] }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: resources.appendingPathComponent("vieneu-native-manifest.json")))
        for file in manifest.files {
            try Task.checkCancellation()
            guard !file.path.hasPrefix("/"), !file.path.split(separator: "/").contains("..") else { throw vieNeuError("Đường dẫn mô hình không hợp lệ.") }
            let url = directory.appendingPathComponent(file.path)
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            guard (attrs[.type] as? FileAttributeType) == .typeRegular, (attrs[.size] as? NSNumber)?.int64Value == file.size else { throw vieNeuError("Dữ liệu VieNeu thiếu hoặc đã thay đổi. Hãy tải lại.") }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hash = SHA256()
            while let part = try handle.read(upToCount: 1048576), !part.isEmpty { try Task.checkCancellation(); hash.update(data: part) }
            guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == file.sha256 else { throw vieNeuError("Checksum VieNeu không khớp. Hãy tải lại mô hình.") }
        }
    }
    private func syllables(_ phonemes: String) -> Int {
        let vowels = Set("aeiouyæɐɑɒɔəɘɛɜɤɯɵøœʉʊʌɪɨɚɝᵻᵿ")
        let stripped = phonemes.replacingOccurrences(of: "</?en>", with: "", options: .regularExpression)
        return stripped.split(whereSeparator: { $0.isWhitespace }).reduce(0) { total, token in
            var groups = 0, inVowel = false, consonant = true
            for char in token {
                if vowels.contains(char) { if !inVowel && consonant { groups += 1 }; inVowel = true; consonant = false }
                else if "ːˈˌ".contains(char) || char.isNumber {
                    if "ˈˌ".contains(char) && groups > 0 { inVowel = false; consonant = true } else { inVowel = false }
                } else { inVowel = false; consonant = true }
            }
            return total + (token.contains(where: { $0.isLetter }) ? max(1,groups) : 0)
        }
    }
    private func float(_ values: [Float], _ shape: [Int]) throws -> ORTValue {
        try ORTValue(tensorData: NSMutableData(bytes: values, length: values.count*4), elementType: .float, shape: shape.map { NSNumber(value: $0) })
    }
    private func int64(_ values: [Int64], _ shape: [Int]) throws -> ORTValue {
        try ORTValue(tensorData: NSMutableData(bytes: values, length: values.count*8), elementType: .int64, shape: shape.map { NSNumber(value: $0) })
    }
    private func int32(_ values: [Int32], _ shape: [Int]) throws -> ORTValue {
        try ORTValue(tensorData: NSMutableData(bytes: values, length: values.count*4), elementType: .int32, shape: shape.map { NSNumber(value: $0) })
    }
    private func floats(_ value: ORTValue?) throws -> [Float] {
        guard let value else { throw vieNeuError("Thiếu đầu ra ONNX.") }
        let data = try value.tensorData() as Data
        return data.withUnsafeBytes { raw in (0..<(data.count/4)).map { raw.loadUnaligned(fromByteOffset: $0*4, as: Float.self) } }
    }
    private func dot(_ matrix: [Float], offset: Int = 0, rows: Int, columns: Int, vector: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: rows)
        matrix.withUnsafeBufferPointer { m in vector.withUnsafeBufferPointer { v in out.withUnsafeMutableBufferPointer { y in
            cblas_sgemv(CblasRowMajor, CblasNoTrans, Int32(rows), Int32(columns), 1, m.baseAddress! + offset, Int32(columns), v.baseAddress!, 1, 0, y.baseAddress!, 1)
        } } }
        return out
    }
    private func anchor(_ voice: Voice) throws -> [Float] {
        guard voice.speaker_emb.count == 192 else { throw vieNeuError("Giọng không có speaker embedding hợp lệ.") }
        var v = dot(projection, rows: hidden, columns: 192, vector: voice.speaker_emb)
        for i in v.indices { v[i] += bias[i] }
        let mean = v.reduce(0,+) / Float(hidden)
        let variance = v.reduce(Float(0)) { $0 + ($1-mean)*($1-mean) } / Float(hidden)
        let scale = sqrt(variance + epsilon)
        return v.indices.map { (v[$0]-mean)/scale*lnW[$0] + lnB[$0] }
    }
    private func embed(text: Int, codes: [Int], anchor: [Float]) throws -> [Float] {
        guard (0..<419).contains(text), codes.count == channels, codes.allSatisfy({ (0...audioVocab).contains($0) }) else { throw vieNeuError("Mã giọng không hợp lệ.") }
        var out = [Float](textEmb[(text*hidden)..<((text+1)*hidden)])
        for ch in 0..<channels where codes[ch] != audioVocab {
            let at = (ch*audioVocab+codes[ch])*hidden
            for i in 0..<hidden { out[i] += audioEmb[at+i] }
        }
        for i in 0..<hidden { out[i] += anchor[i] }
        return out
    }
    private func past(_ outputs: [String: ORTValue], layers: Int) throws -> [String: ORTValue] {
        var result: [String: ORTValue] = [:]
        for i in 0..<layers { for kind in ["k", "v"] {
            guard let value = outputs["present_\(kind)_\(i)"] else { throw vieNeuError("Thiếu KV cache.") }
            result["past_\(kind)_\(i)"] = value
        } }
        return result
    }
    private func sample(_ logits: [Float], previous: [Int], random: () -> Double) -> Int {
        var adjusted = logits
        for code in Set(previous) { adjusted[code] = adjusted[code] < 0 ? adjusted[code]*1.2 : adjusted[code]/1.2 }
        let indices = adjusted.indices.sorted { adjusted[$0] > adjusted[$1] }.prefix(25)
        let maxValue = adjusted[indices.first!] / 0.8
        var candidates = indices.map { ($0, Double(exp(adjusted[$0]/0.8-maxValue))) }
        let total = candidates.reduce(0) { $0 + $1.1 }
        var cumulative = 0.0
        candidates = candidates.filter { item in
            let keep = cumulative < total*0.95; cumulative += item.1; return keep
        }
        let cutoff = random()*candidates.reduce(0) { $0 + $1.1 }
        var value = 0.0
        for item in candidates { value += item.1; if value >= cutoff { return item.0 } }
        return candidates.last!.0
    }
    private func acousticFrame(_ h: [Float], history: inout [[Int]], check: () throws -> Void) throws -> ([Int], Bool) {
        var feed: [String: ORTValue] = ["token_emb": try float(h + textEmb[(5*hidden)..<(6*hidden)], [1,2,hidden]), "position_ids": try int64([0,1], [1,2])]
        feed["past_k_0"] = try float([], [1,8,0,96]); feed["past_v_0"] = try float([], [1,8,0,96])
        var output = try acoustic.run(withInputs: feed, outputNames: acNames, runOptions: nil)
        var values = try floats(output["hidden"])
        let slot0 = Array(values.prefix(hidden))
        var codes: [Int] = []
        for ch in 0..<channels {
            try check()
            let vec = ch == 0 ? Array(values.suffix(hidden)) : values
            let logits = dot(audioEmb, offset: ch*audioVocab*hidden, rows: audioVocab, columns: hidden, vector: vec)
            let code = sample(logits, previous: history[ch], random: { Double.random(in: 0..<1) })
            codes.append(code); history[ch].append(code)
            if history[ch].count > 64 { history[ch].removeFirst() }
            if ch < channels-1 {
                feed = try past(output, layers: 1)
                let at = (ch*audioVocab+code)*hidden
                feed["token_emb"] = try float(Array(audioEmb[at..<(at+hidden)]), [1,1,hidden])
                feed["position_ids"] = try int64([Int64(ch+2)], [1,1])
                output = try acoustic.run(withInputs: feed, outputNames: acNames, runOptions: nil)
                values = try floats(output["hidden"])
            }
        }
        let logits = dot(textEmb, rows: 419, columns: hidden, vector: slot0)
        return (codes, logits.indices.max(by: { logits[$0] < logits[$1] }) == 6)
    }
    private func initialCodecState() throws -> [String: ORTValue] {
        var state: [String: ORTValue] = [:]
        for entry in codecSpec["transformer_offsets"] as? [[String: Any]] ?? [] {
            let shape = entry["shape"] as! [Int]
            state[entry["input_name"] as! String] = try int32(Array(repeating: 0, count: shape.reduce(1,*)), shape)
        }
        for entry in codecSpec["attention_caches"] as? [[String: Any]] ?? [] {
            for (prefix, shapeKey, kind, initial) in [("offset", "offset_shape", "int", 0), ("cached_keys", "cache_shape", "float", 0), ("cached_values", "cache_shape", "float", 0), ("cached_positions", "positions_shape", "int", -1)] {
                let shape = entry[shapeKey] as! [Int], count = shape.reduce(1,*)
                state[entry[prefix+"_input_name"] as! String] = try kind == "float" ? float(Array(repeating: 0, count: count), shape) : int32(Array(repeating: Int32(initial), count: count), shape)
            }
        }
        return state
    }
    private func decodeFrames(_ frames: [[Int]], state: inout [String: ORTValue]) throws -> [Float] {
        var feed = state
        feed["audio_codes"] = try int32(frames.flatMap { $0.map(Int32.init) }, [1,frames.count,channels])
        feed["audio_code_lengths"] = try int32([Int32(frames.count)], [1])
        let output = try codec.run(withInputs: feed, outputNames: codecNames, runOptions: nil)
        for entry in codecSpec["transformer_offsets"] as? [[String: Any]] ?? [] { state[entry["input_name"] as! String] = output[entry["output_name"] as! String] }
        for entry in codecSpec["attention_caches"] as? [[String: Any]] ?? [] {
            for prefix in ["offset", "cached_keys", "cached_values", "cached_positions"] { state[entry[prefix+"_input_name"] as! String] = output[entry[prefix+"_output_name"] as! String] }
        }
        guard let value = output["audio"], let lengths = output["audio_lengths"] else { throw vieNeuError("Thiếu audio giải mã.") }
        let shape = try value.tensorTypeAndShapeInfo().shape.map { $0.intValue }, data = try floats(value)
        let lengthData = try lengths.tensorData() as Data
        let length = lengthData.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        guard shape.count == 3, shape[0] == 1, shape[1] == 2, length <= shape[2], data.count == 2*shape[2] else { throw vieNeuError("Định dạng audio không tương thích.") }
        return (0..<length).map { (data[$0] + data[shape[2]+$0])*0.5 }
    }
    func synthesize(text: String, voice name: String, check: () throws -> Void, emit: ([Float]) async throws -> Void) async throws {
        try check()
        guard text.count <= 500, let voice = voices[name] else { throw vieNeuError("Giọng hoặc đoạn đọc không hợp lệ.") }
        let phones = try phonemizer.phonemes(text)
        let ids = tokenizer.encode(phones)
        guard !ids.isEmpty, ids.count < 1024 else { throw vieNeuError("Đoạn đọc quá dài sau khi chuẩn hóa.") }
        let a = try anchor(voice), padding = Array(repeating: audioVocab, count: channels)
        var prompt: [Float] = []
        for id in [16,3]+ids+[4] { prompt += try embed(text: id, codes: padding, anchor: a) }
        var refs = voice.codes ?? []
        if refs.count > 1, refs.last?.first == 455 { refs.removeLast() }
        for codes in refs { prompt += try embed(text: 7, codes: codes, anchor: a) }
        let promptLength = prompt.count / hidden
        guard promptLength < 1536 else { throw vieNeuError("Ngữ cảnh giọng quá dài.") }
        var out = try prefill.run(withInputs: ["inputs_embeds": try float(prompt, [1,promptLength,hidden])], outputNames: preNames, runOptions: nil)
        var h = Array(try floats(out["hidden"]).suffix(hidden))
        var history = Array(repeating: [Int](), count: channels), frames: [[Int]] = [], state = try initialCodecState()
        // The upstream phoneme-length ceiling prevents endless generation.
        let syllableCount = max(1, syllables(phones))
        let length = phones.replacingOccurrences(of: "</?en>", with: "", options: .regularExpression).count
        let short = syllableCount <= 4 && length <= 24*syllableCount
        let ceiling = min(300, short ? min(24 + length*2, 13 + 5*(syllableCount-1)) : 24 + length*2)
        var shortAudio: [Float] = []
        for t in 0..<ceiling {
            try check()
            let (codes, eos) = try acousticFrame(h, history: &history, check: check)
            frames.append(codes)
            if !eos {
                var feed = try past(out, layers: layers)
                feed["inputs_embeds"] = try float(embed(text: 5, codes: codes, anchor: a), [1,1,hidden])
                feed["position_ids"] = try int64([Int64(promptLength+t)], [1,1])
                out = try decode.run(withInputs: feed, outputNames: preNames, runOptions: nil)
                h = try floats(out["hidden"])
            }
            if frames.count >= 6 || eos {
                let samples = try decodeFrames(frames, state: &state); frames.removeAll(keepingCapacity: true)
                try check(); if short { shortAudio += samples } else if !samples.isEmpty { try await emit(samples) }
            }
            if eos { if short && !shortAudio.isEmpty { try await emit(shortAudio) }; return }
        }
        // Do not silently commit a capped/hallucinated utterance.
        throw NSError(domain: "VieNeuNative", code: short ? 2 : 3, userInfo: [NSLocalizedDescriptionKey: "Mô hình chưa kết thúc đoạn đọc. Hãy thử chia đoạn ngắn hơn."])
    }
}
