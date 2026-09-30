import Foundation

public enum JobPhase: Equatable, Sendable {
    case trimming
    case downloadingModel(progress: Double)
    case transcribing(progress: Double)
    case completed(transcriptURL: URL)
    case failed(error: String)

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed:
            return true
        default:
            return false
        }
    }
}

public struct TranscriptionJob: Identifiable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public let originalFileName: String
    public let projectID: String
    public let projectTitle: String
    public let modelVariant: String
    public let trimStart: TimeInterval
    public let trimEnd: TimeInterval
    public var phase: JobPhase
    public let startTime: Date

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        originalFileName: String,
        projectID: String,
        projectTitle: String,
        modelVariant: String,
        trimStart: TimeInterval,
        trimEnd: TimeInterval,
        phase: JobPhase = .trimming,
        startTime: Date = Date()
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.originalFileName = originalFileName
        self.projectID = projectID
        self.projectTitle = projectTitle
        self.modelVariant = modelVariant
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.phase = phase
        self.startTime = startTime
    }

    public var statusDescription: String {
        switch phase {
        case .trimming:
            return "Trimming audio segment..."
        case .downloadingModel(let progress):
            return "Downloading model (\(Int(progress * 100))%)..."
        case .transcribing(let progress):
            return "Transcribing with Neural Engine (\(Int(progress * 100))%)..."
        case .completed:
            return "Transcript generated!"
        case .failed(let err):
            return "Failed: \(err)"
        }
    }

    public var progressFraction: Double {
        switch phase {
        case .trimming:
            return 0.05
        case .downloadingModel(let progress):
            return progress * 0.2
        case .transcribing(let progress):
            return 0.2 + (progress * 0.8)
        case .completed:
            return 1.0
        case .failed:
            return 0.0
        }
    }
}
