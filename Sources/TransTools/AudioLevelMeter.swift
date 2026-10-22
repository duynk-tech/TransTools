import Foundation
import Combine
import AVFoundation
import CoreMedia
import Accelerate

final class AudioLevelMeter {
    // Only the meter subscribes. No Published property on MeetingModel.
    let level = CurrentValueSubject<Double, Never>(0)
    private var lastEmission = Date.distantPast
    private let lock = NSLock()
    func update(_ rms: Double?) {
        guard let rms, rms.isFinite else { return }
        lock.lock()
        let now = Date()
        let emit = now.timeIntervalSince(lastEmission) >= 0.1
        if emit { lastEmission = now }
        lock.unlock()
        if emit { level.send(min(1, max(0, rms))) }
    }
    static func rms(_ sample: CMSampleBuffer) -> Double? {
        guard let description = CMSampleBufferGetFormatDescription(sample),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              asbd.mFormatID == kAudioFormatLinearPCM else { return nil }
        var needed = 0
        var block: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample, bufferListSizeNeededOut: &needed,
            bufferListOut: nil, bufferListSize: 0, blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, blockBufferOut: &block) == noErr,
            needed >= MemoryLayout<AudioBufferList>.size, needed < 65536 else { return nil }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: needed, alignment: 16)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample, bufferListSizeNeededOut: &needed,
            bufferListOut: list, bufferListSize: needed, blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault, flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &block) == noErr else { return nil }
        return withExtendedLifetime(block) {
            rms(UnsafeMutableAudioBufferListPointer(list), bits: asbd.mBitsPerChannel, flags: asbd.mFormatFlags)
        }
    }
    static func rms(_ buffer: AVAudioPCMBuffer) -> Double? {
        let asbd = buffer.format.streamDescription.pointee
        return rms(UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList), bits: asbd.mBitsPerChannel, flags: asbd.mFormatFlags)
    }
    private static func rms(_ buffers: UnsafeMutableAudioBufferListPointer, bits: UInt32, flags: UInt32) -> Double? {
        var sum: Double = 0
        var count = 0
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let n = Int(buffer.mDataByteSize) / max(1, Int(bits / 8))
            guard n > 0 else { continue }
            if flags & kAudioFormatFlagIsFloat != 0 && bits == 32 && flags & kAudioFormatFlagIsBigEndian == 0 {
                var mean: Float = 0
                vDSP_measqv(data.assumingMemoryBound(to: Float.self), 1, &mean, vDSP_Length(n))
                sum += Double(mean) * Double(n)
            } else if flags & kAudioFormatFlagIsSignedInteger != 0 && bits == 16 && flags & kAudioFormatFlagIsBigEndian == 0 {
                let values = data.assumingMemoryBound(to: Int16.self)
                for i in 0..<n { let v = Double(values[i]) / 32768; sum += v * v }
            } else { return nil }
            count += n
        }
        return count > 0 ? sqrt(sum / Double(count)) : nil
    }
}

import SwiftUI

struct IsolatedAudioMeterView: View {
    let meter: AudioLevelMeter
    @State private var level: Double = 0
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(TransToolsTheme.accent)
                    .frame(width: 2, height: max(2, min(12, CGFloat(level * 60) * CGFloat([0.6, 1, 0.8, 0.5][index]))))
            }
        }
        .frame(width: 14, height: 12)
        .onReceive(meter.level.receive(on: DispatchQueue.main)) { level = $0 }
        .accessibilityLabel("Mức âm thanh")
    }
}
