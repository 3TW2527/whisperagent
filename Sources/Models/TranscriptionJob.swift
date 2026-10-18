import Foundation

public enum JobPhase: Equatable, Sendable {
    case queued
    case trimming
    case downloadingModel(progress: Double)
    case loadingModel
    case transcribing(progress: Double)
    case saving
    case completed(files: [URL])
    case failed(error: String)
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: return true
        default: return false
        }
    }

    public var isRunning: Bool {
        !isTerminal && self != .queued
    }
}

public struct TranscriptionJob: Identifiable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public let courseID: String
    public let courseName: String
    public let lectureNumber: Int
    public let customName: String?
    public let modelVariant: String
    public let trimStart: TimeInterval
    public let trimEnd: TimeInterval
    public let formats: [TranscriptFormat]
    public var slot: RecordingSlot?
    public var phase: JobPhase
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        courseID: String,
        courseName: String,
        lectureNumber: Int,
        customName: String?,
        modelVariant: String,
        trimStart: TimeInterval,
        trimEnd: TimeInterval,
        formats: [TranscriptFormat],
        slot: RecordingSlot?,
        phase: JobPhase = .queued,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.courseID = courseID
        self.courseName = courseName
        self.lectureNumber = lectureNumber
        self.customName = customName
        self.modelVariant = modelVariant
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.formats = formats
        self.slot = slot
        self.phase = phase
        self.createdAt = createdAt
    }

    public var title: String {
        slot?.baseName ?? sourceURL.lastPathComponent
    }

    public var statusDescription: String {
        switch phase {
        case .queued: return "Waiting for a free slot..."
        case .trimming: return "Trimming audio..."
        case .downloadingModel(let progress): return "Downloading model (\(Int(progress * 100))%)..."
        case .loadingModel: return "Loading model..."
        case .transcribing(let progress): return "Transcribing (\(Int(progress * 100))%)..."
        case .saving: return "Saving transcript..."
        case .completed(let files): return "Saved \(files.map(\.pathExtension).joined(separator: ", "))"
        case .failed(let err): return "Failed: \(err)"
        case .cancelled: return "Cancelled"
        }
    }

    public var progressFraction: Double {
        switch phase {
        case .queued: return 0
        case .trimming: return 0.03
        case .downloadingModel(let progress): return 0.05 + progress * 0.15
        case .loadingModel: return 0.2
        case .transcribing(let progress): return 0.2 + progress * 0.78
        case .saving: return 0.99
        case .completed: return 1
        case .failed, .cancelled: return 0
        }
    }
}
