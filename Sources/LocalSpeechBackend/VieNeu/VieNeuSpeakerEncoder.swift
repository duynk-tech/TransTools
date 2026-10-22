import Foundation
import Accelerate
import OnnxRuntimeBindings

/// Matches the upstream 16 kHz, 80-bin Kaldi front end: snip edges,
/// DC removal, pre-emphasis, Povey window, power spectrum and mean normalization.
public enum VieNeuSpeakerEncoder {
    public static func features(_ samples: [Float]) throws -> [Float] {
        guard samples.count >= 48000, samples.count <= 16000 * 8, samples.allSatisfy({ $0.isFinite }) else {
            throw vieNeuError("Bản thu cần từ 3 đến 8 giây.")
        }
        let frames = (samples.count - 400) / 160 + 1
        guard let fft = vDSP_DFT_zop_CreateSetup(nil, 512, .FORWARD) else { throw vieNeuError("Không tạo được bộ phân tích giọng.") }
        defer { vDSP_DFT_DestroySetup(fft) }
        var real = [Float](repeating: 0, count: 512), imaginary = real, outR = real, outI = real
        let mel: (Double) -> Double = { 1127 * log(1 + $0 / 700) }
        let low = mel(20), step = (mel(8000) - low) / 81
        let weights = (0..<80).map { bin in
            (0..<256).map { k -> Float in
                let m = mel(Double(k) * 16000 / 512)
                let left = low + Double(bin) * step, center = left + step, right = center + step
                return Float(max(0, min((m-left)/(center-left), (right-m)/(right-center))))
            }
        }
        var result = [Float](); result.reserveCapacity(frames * 80)
        for frame in 0..<frames {
            try Task.checkCancellation()
            let offset = frame * 160
            let mean = samples[offset..<offset+400].reduce(0,+) / 400
            for i in 0..<400 {
                let value = samples[offset+i] - mean
                let previous = samples[offset+max(0,i-1)] - mean
                real[i] = (value - 0.97 * previous) * Float(pow(0.5 - 0.5 * cos(2 * Double.pi * Double(i) / 399), 0.85))
            }
            for i in 400..<512 { real[i] = 0 }
            vDSP_DFT_Execute(fft, &real, &imaginary, &outR, &outI)
            let power = (0..<256).map { outR[$0]*outR[$0] + outI[$0]*outI[$0] }
            for bin in 0..<80 {
                var energy: Float = 0
                for k in 0..<256 { energy += power[k] * weights[bin][k] }
                result.append(log(max(Float.ulpOfOne, energy)))
            }
        }
        for bin in 0..<80 {
            var mean: Float = 0
            for frame in 0..<frames { mean += result[frame*80+bin] }
            mean /= Float(frames)
            for frame in 0..<frames { result[frame*80+bin] -= mean }
        }
        return result
    }
    public static func extract(samples: [Float], encoder: URL) throws -> [Float] {
        let features = try features(samples)
        let env = try ORTEnv(loggingLevel: .error), options = try ORTSessionOptions()
        try options.setGraphOptimizationLevel(.all)
        try options.setIntraOpNumThreads(2)
        try options.addConfigEntry(withKey: "session.intra_op.allow_spinning", value: "0")
        let session = try ORTSession(env: env, modelPath: encoder.path, sessionOptions: options)
        let data = features.withUnsafeBytes { NSMutableData(bytes: $0.baseAddress!, length: $0.count) }
        let input = try ORTValue(tensorData: data, elementType: .float, shape: [1, NSNumber(value: features.count/80), 80])
        let output = try session.run(withInputs: ["input": input], outputNames: ["output"], runOptions: nil)
        guard let tensor = output["output"] else { throw vieNeuError("Thiếu dữ liệu giọng.") }
        let bytes = try tensor.tensorData() as Data
        let values = bytes.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        guard values.count == 192, values.allSatisfy({ $0.isFinite }), values.contains(where: { abs($0) > 0.00001 }) else {
            throw vieNeuError("Không trích xuất được giọng hợp lệ.")
        }
        return values
    }
}
