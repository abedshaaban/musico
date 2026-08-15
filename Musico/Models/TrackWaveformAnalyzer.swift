import AVFoundation
import Foundation

enum TrackWaveformAnalyzer {
    static let defaultBinCount = 512
    static let defaultWindowSeconds = 1.5
    static let defaultVisibleBars = 96

    static func resample(_ bars: [Float], toCount targetCount: Int) -> [Float] {
        guard !bars.isEmpty, targetCount > 1 else { return bars }
        let lastIndex = bars.count - 1
        return (0..<targetCount).map { index in
            let fraction = Double(index) / Double(targetCount - 1)
            let position = fraction * Double(lastIndex)
            return interpolate(bars, at: position)
        }
    }

    static func shapeForDisplay(_ bars: [Float]) -> [Float] {
        guard bars.count > 2 else { return bars }

        var smoothed = bars
        for index in 1..<(bars.count - 1) {
            smoothed[index] = bars[index - 1] * 0.22 + bars[index] * 0.56 + bars[index + 1] * 0.22
        }

        let minVal = smoothed.min() ?? 0
        let maxVal = smoothed.max() ?? 1
        let span = max(maxVal - minVal, 0.10)

        return smoothed.map { bar in
            let scaled = (bar - minVal) / span
            let eased = pow(min(max(scaled, 0), 1), 0.82)
            return min(max(0.12 + eased * 0.88, 0.12), 1)
        }
    }

    static func analyze(url: URL, binCount: Int = defaultBinCount) async -> [Float] {
        await Task.detached(priority: .utility) {
            analyzeSync(url: url, binCount: binCount)
        }.value
    }

    private static func analyzeSync(url: URL, binCount: Int) -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first else {
            return []
        }

        let duration = asset.duration.seconds
        guard duration.isFinite, duration > 0 else { return [] }

        guard let reader = try? AVAssetReader(asset: asset) else { return [] }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output), reader.startReading() else { return [] }

        var peaks = [Float](repeating: 0, count: binCount)
        var rmsSums = [Float](repeating: 0, count: binCount)
        var rmsCounts = [Int](repeating: 0, count: binCount)

        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer(),
                  CMSampleBufferGetNumSamples(sampleBuffer) > 0,
                  let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer),
                  let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
                  let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
            else { continue }

            let asbd = streamDescription.pointee
            let channelCount = max(Int(asbd.mChannelsPerFrame), 1)
            let sampleRate = asbd.mSampleRate
            guard sampleRate > 0 else { continue }

            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &dataPointer
            ) == noErr, let dataPointer else { continue }

            let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            let sampleCount = length / MemoryLayout<Float>.size

            dataPointer.withMemoryRebound(to: Float.self, capacity: sampleCount) { samples in
                let stride = max(1, frameCount / 512)
                var frame = 0
                while frame < frameCount {
                    let time = presentationTime + Double(frame) / sampleRate
                    let bin = min(max(Int((time / duration) * Double(binCount)), 0), binCount - 1)
                    var framePeak: Float = 0
                    var frameSquares: Float = 0
                    for channel in 0..<channelCount {
                        let index = frame * channelCount + channel
                        guard index < sampleCount else { continue }
                        let sample = samples[index]
                        framePeak = max(framePeak, abs(sample))
                        frameSquares += sample * sample
                    }
                    peaks[bin] = max(peaks[bin], framePeak)
                    rmsSums[bin] += frameSquares / Float(max(channelCount, 1))
                    rmsCounts[bin] += 1
                    frame += stride
                }
            }
        }

        let combined = zip(peaks.indices, peaks).map { index, peak in
            let rms: Float
            if rmsCounts[index] > 0 {
                rms = sqrt(rmsSums[index] / Float(rmsCounts[index]))
            } else {
                rms = 0
            }
            return max(peak, rms * 1.6)
        }

        return normalize(combined)
    }

    private static func normalize(_ peaks: [Float]) -> [Float] {
        guard let maxPeak = peaks.max(), maxPeak > 0.000_1 else { return [] }

        return peaks.map { peak in
            let normalized = peak / maxPeak
            let shaped = pow(normalized, 0.82)
            return min(max(0.05 + shaped * 0.95, 0.05), 1)
        }
    }

    static func silenceBars(count: Int) -> [Float] {
        Array(repeating: 0.05, count: max(count, 0))
    }

    static func windowSamples(
        from samples: [Float],
        at time: Double,
        duration: Double,
        windowSeconds: Double = defaultWindowSeconds,
        visibleBars: Int = defaultVisibleBars
    ) -> (bars: [Float], scrollPhase: CGFloat) {
        guard visibleBars > 1 else { return ([], 0) }
        guard duration.isFinite, duration > 0, !samples.isEmpty else {
            return (silenceBars(count: visibleBars), 0)
        }

        let halfWindow = windowSeconds * 0.5
        let startTime = max(0, time - halfWindow)
        let endTime = min(duration, time + halfWindow)
        let span = max(endTime - startTime, 0.001)
        let lastIndex = samples.count - 1
        let barDuration = span / Double(visibleBars - 1)
        let scrollPhase = barDuration > 0
            ? CGFloat((time - startTime).truncatingRemainder(dividingBy: barDuration) / barDuration)
            : 0

        let bars = (0..<visibleBars).map { index in
            let fraction = Double(index) / Double(visibleBars - 1)
            let sampleTime = startTime + fraction * span
            let position = (sampleTime / duration) * Double(lastIndex)
            return interpolate(samples, at: position)
        }

        return (bars, scrollPhase)
    }

    static func mergeLive(
        live: [Float],
        precomputed: [Float],
        visibleBars: Int = defaultVisibleBars
    ) -> [Float] {
        guard visibleBars > 1 else { return live.isEmpty ? precomputed : live }

        if precomputed.count != visibleBars {
            return live.count == visibleBars ? live : silenceBars(count: visibleBars)
        }

        guard !live.isEmpty else { return precomputed }

        let center = visibleBars / 2
        var merged = precomputed

        for index in 0...center {
            let offsetFromCenter = index - center
            let liveIndex = live.count - 1 + offsetFromCenter
            guard live.indices.contains(liveIndex) else { continue }
            merged[index] = min(max(live[liveIndex], 0.05), 1)
        }

        return merged
    }

    private static func interpolate(_ samples: [Float], at position: Double) -> Float {
        guard !samples.isEmpty else { return 0.05 }
        let clamped = min(max(position, 0), Double(samples.count - 1))
        let lower = Int(floor(clamped))
        let upper = min(lower + 1, samples.count - 1)
        let mix = Float(clamped - Double(lower))
        return samples[lower] * (1 - mix) + samples[upper] * mix
    }
}

actor TrackWaveformCache {
    static let shared = TrackWaveformCache()

    private var storage: [UUID: [Float]] = [:]

    func waveform(for itemID: UUID, url: URL, binCount: Int = TrackWaveformAnalyzer.defaultBinCount) async -> [Float] {
        if let cached = storage[itemID], !cached.isEmpty { return cached }
        let samples = await TrackWaveformAnalyzer.analyze(url: url, binCount: binCount)
        if !samples.isEmpty {
            storage[itemID] = samples
        } else {
            storage.removeValue(forKey: itemID)
        }
        return samples
    }

    func invalidate(itemID: UUID) {
        storage.removeValue(forKey: itemID)
    }
}
