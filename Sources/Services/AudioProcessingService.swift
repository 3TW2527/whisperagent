import Foundation
import AVFoundation
import Accelerate

public final class AudioProcessingService: Sendable {
    public static let shared = AudioProcessingService()

    private init() {}

    /// Analyzes an audio file, extracting duration, waveform samples (normalized 0...1), and detecting leading silence.
    public func analyzeAudio(url: URL, targetSampleCount: Int = 120, silenceThresholdDB: Float = -35.0) async throws -> AudioAnalysisResult {
        return try await Task.detached(priority: .userInitiated) {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let frameCount = UInt32(file.length)
            let sampleRate = format.sampleRate
            let duration = Double(frameCount) / sampleRate

            guard duration > 0, frameCount > 0 else {
                return AudioAnalysisResult.empty
            }

            // Read samples in manageable chunks to avoid excessive memory usage
            let bufferSize = 4096
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(bufferSize)) else {
                return AudioAnalysisResult.empty
            }

            let framesPerBucket = max(1, frameCount / UInt32(targetSampleCount))
            var bucketEnergies: [Float] = []
            bucketEnergies.reserveCapacity(targetSampleCount)

            var currentBucketSum: Float = 0
            var currentBucketFrames: UInt32 = 0

            var detectedSpeechStart: TimeInterval = 0
            var foundSpeechStart = false
            var consecutiveSpeechFrames = 0
            let requiredConsecutiveFrames = 4 // ~0.3 - 0.4s to filter out single clicks/coughs

            file.framePosition = 0

            while file.framePosition < frameCount {
                let framesRemaining = frameCount - UInt32(file.framePosition)
                let framesToRead = min(UInt32(bufferSize), framesRemaining)
                try file.read(into: buffer, frameCount: framesToRead)

                guard let channelData = buffer.floatChannelData?[0] else { break }
                let readCount = Int(buffer.frameLength)

                // Calculate RMS for this chunk using Accelerate
                var rms: Float = 0
                vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(readCount))

                // Check for silence / speech onset
                let db = 20 * log10(max(rms, 1e-5))
                if !foundSpeechStart {
                    if db > silenceThresholdDB {
                        consecutiveSpeechFrames += 1
                        if consecutiveSpeechFrames >= requiredConsecutiveFrames {
                            let frameIndex = max(0, Int(file.framePosition) - (bufferSize * requiredConsecutiveFrames))
                            detectedSpeechStart = Double(frameIndex) / sampleRate
                            foundSpeechStart = true
                        }
                    } else {
                        consecutiveSpeechFrames = 0
                    }
                }

                // Waveform bucket aggregation
                currentBucketSum += rms * Float(readCount)
                currentBucketFrames += UInt32(readCount)

                if currentBucketFrames >= framesPerBucket {
                    bucketEnergies.append(currentBucketSum / Float(currentBucketFrames))
                    currentBucketSum = 0
                    currentBucketFrames = 0
                }
            }

            if currentBucketFrames > 0 {
                bucketEnergies.append(currentBucketSum / Float(currentBucketFrames))
            }

            // Normalize waveform samples between 0.05 and 1.0
            let maxEnergy = bucketEnergies.max() ?? 1.0
            let normalizedSamples: [Float] = bucketEnergies.map { val in
                if maxEnergy > 0 {
                    return max(0.05, min(1.0, val / maxEnergy))
                }
                return 0.1
            }

            // Fallback if no distinct silence or entire track is speech
            if !foundSpeechStart {
                detectedSpeechStart = 0
            }

            return AudioAnalysisResult(
                duration: duration,
                samples: normalizedSamples,
                detectedSpeechStart: max(0, detectedSpeechStart),
                detectedSpeechEnd: duration,
                leadingSilenceDuration: detectedSpeechStart
            )
        }.value
    }

    /// Trims an audio file to the exact start and end timestamps and exports to a temporary .m4a file.
    public func trimAudio(sourceURL: URL, startTime: TimeInterval, endTime: TimeInterval) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let totalDuration = try await asset.load(.duration).seconds
        let safeStart = max(0, startTime)
        let safeEnd = min(totalDuration, max(safeStart + 0.5, endTime))

        let exportSession = try await createExportSession(asset: asset)
        let tempDirectory = FileManager.default.temporaryDirectory
        let outputURL = tempDirectory.appendingPathComponent("trimmed_\(UUID().uuidString).m4a")

        // Ensure target doesn't already exist
        try? FileManager.default.removeItem(at: outputURL)

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        let timeRange = CMTimeRange(
            start: CMTime(seconds: safeStart, preferredTimescale: 600),
            end: CMTime(seconds: safeEnd, preferredTimescale: 600)
        )
        exportSession.timeRange = timeRange

        await exportSession.export()

        if let error = exportSession.error {
            throw error
        }

        guard exportSession.status == .completed else {
            throw NSError(
                domain: "AudioProcessingService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Audio trimming export failed with status \(exportSession.status.rawValue)"]
            )
        }

        return outputURL
    }

    private func createExportSession(asset: AVAsset) async throws -> AVAssetExportSession {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(
                domain: "AudioProcessingService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to initialize AVAssetExportSession for audio trimming"]
            )
        }
        return session
    }

    /// Wipes the temporary audio file immediately after transcription.
    public func deleteTemporaryAudio(at url: URL) {
        // Ensure we only delete from temporary directory
        if url.path.hasPrefix(FileManager.default.temporaryDirectory.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
