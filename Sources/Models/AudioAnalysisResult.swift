import Foundation

public struct AudioAnalysisResult: Equatable, Sendable {
    public let duration: TimeInterval
    public let samples: [Float] // Normalized 0.0 ... 1.0 for rendering waveform bars
    public let detectedSpeechStart: TimeInterval
    public let detectedSpeechEnd: TimeInterval
    public let leadingSilenceDuration: TimeInterval

    public init(
        duration: TimeInterval,
        samples: [Float],
        detectedSpeechStart: TimeInterval,
        detectedSpeechEnd: TimeInterval,
        leadingSilenceDuration: TimeInterval
    ) {
        self.duration = duration
        self.samples = samples
        self.detectedSpeechStart = detectedSpeechStart
        self.detectedSpeechEnd = detectedSpeechEnd
        self.leadingSilenceDuration = leadingSilenceDuration
    }

    public static var empty: AudioAnalysisResult {
        AudioAnalysisResult(
            duration: 0,
            samples: [],
            detectedSpeechStart: 0,
            detectedSpeechEnd: 0,
            leadingSilenceDuration: 0
        )
    }
}
