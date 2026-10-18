import Foundation

/// One timed piece of transcribed speech. Kept independent of WhisperKit so transcripts can be
/// re-exported to any format later from the saved segments file.
public struct TranscriptSegment: Codable, Hashable, Sendable {
    public var start: Double
    public var end: Double
    public var text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// Context written into transcript headers so each file is self-describing.
public struct TranscriptContext: Codable, Hashable, Sendable {
    public var courseName: String
    public var courseCode: String
    public var lectureNumber: Int
    public var lectureTitle: String
    public var lectureDate: Date
    public var recordingNumber: Int
    public var sourceAudio: String
    public var model: String
    public var transcribedAt: Date

    public init(courseName: String, courseCode: String, lectureNumber: Int, lectureTitle: String, lectureDate: Date, recordingNumber: Int, sourceAudio: String, model: String, transcribedAt: Date = Date()) {
        self.courseName = courseName
        self.courseCode = courseCode
        self.lectureNumber = lectureNumber
        self.lectureTitle = lectureTitle
        self.lectureDate = lectureDate
        self.recordingNumber = recordingNumber
        self.sourceAudio = sourceAudio
        self.model = model
        self.transcribedAt = transcribedAt
    }
}

/// The saved form of a transcription: context plus raw segments. Stored in `.whisperlectures/segments/`.
public struct SegmentsDocument: Codable, Sendable {
    public var context: TranscriptContext
    public var segments: [TranscriptSegment]

    public init(context: TranscriptContext, segments: [TranscriptSegment]) {
        self.context = context
        self.segments = segments
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum TranscriptFormatter {
    /// Paragraphs are split on pauses or after this many seconds, keeping Markdown compact for LLMs
    /// while still giving a timestamp to cite.
    static let paragraphMaxSeconds: Double = 60
    static let paragraphPauseSeconds: Double = 2.5

    public static func render(_ format: TranscriptFormat, segments: [TranscriptSegment], context: TranscriptContext) -> String {
        let cleaned = segments
            .map { TranscriptSegment(start: $0.start, end: $0.end, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.text.isEmpty }
        switch format {
        case .markdown: return markdown(cleaned, context: context)
        case .plainText: return plainText(cleaned)
        case .srt: return srt(cleaned)
        case .vtt: return vtt(cleaned)
        }
    }

    // MARK: - Markdown

    static func markdown(_ segments: [TranscriptSegment], context: TranscriptContext) -> String {
        var lines: [String] = []
        lines.append("---")
        lines.append("course: \(yamlString(context.courseName))")
        if !context.courseCode.isEmpty {
            lines.append("course_code: \(yamlString(context.courseCode))")
        }
        lines.append("lecture: \(context.lectureNumber)")
        if !context.lectureTitle.isEmpty {
            lines.append("lecture_title: \(yamlString(context.lectureTitle))")
        }
        lines.append("lecture_date: \(DateFormats.isoMinute.string(from: context.lectureDate))")
        lines.append("recording: \(context.recordingNumber)")
        lines.append("source_audio: \(yamlString(context.sourceAudio))")
        lines.append("model: \(yamlString(context.model))")
        lines.append("transcribed_at: \(DateFormats.isoMinute.string(from: context.transcribedAt))")
        if let last = segments.last {
            lines.append("duration: \"\(clock(last.end))\"")
        }
        lines.append("---")
        lines.append("")

        var heading = "# \(context.courseName) — Lecture \(context.lectureNumber)"
        if !context.lectureTitle.isEmpty { heading += ": \(context.lectureTitle)" }
        heading += " (Recording \(context.recordingNumber))"
        lines.append(heading)
        lines.append("")
        lines.append("> Automatic transcript. Names, terms and numbers may be misheard. Timestamps are `[mm:ss]` (or `[h:mm:ss]`) from the start of the recording.")
        lines.append("")

        for paragraph in paragraphs(segments) {
            guard let first = paragraph.first else { continue }
            let text = paragraph.map(\.text).joined(separator: " ")
            lines.append("**[\(clock(first.start))]** \(text)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func paragraphs(_ segments: [TranscriptSegment]) -> [[TranscriptSegment]] {
        var result: [[TranscriptSegment]] = []
        var current: [TranscriptSegment] = []
        for segment in segments {
            if let first = current.first, let last = current.last {
                let pause = segment.start - last.end
                if pause >= paragraphPauseSeconds || segment.end - first.start > paragraphMaxSeconds {
                    result.append(current)
                    current = []
                }
            }
            current.append(segment)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    // MARK: - Plain Text

    static func plainText(_ segments: [TranscriptSegment]) -> String {
        paragraphs(segments)
            .map { $0.map(\.text).joined(separator: " ") }
            .joined(separator: "\n\n") + "\n"
    }

    // MARK: - Subtitles

    static func srt(_ segments: [TranscriptSegment]) -> String {
        var blocks: [String] = []
        for (index, segment) in segments.enumerated() {
            blocks.append("\(index + 1)\n\(subtitleTime(segment.start, separator: ",")) --> \(subtitleTime(segment.end, separator: ","))\n\(segment.text)")
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    static func vtt(_ segments: [TranscriptSegment]) -> String {
        var blocks = ["WEBVTT"]
        for segment in segments {
            blocks.append("\(subtitleTime(segment.start, separator: ".")) --> \(subtitleTime(segment.end, separator: "."))\n\(segment.text)")
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    /// `HH:MM:SS,mmm` (SRT) or `HH:MM:SS.mmm` (VTT).
    static func subtitleTime(_ seconds: Double, separator: String) -> String {
        let totalMillis = Int((max(0, seconds) * 1000).rounded())
        let hrs = totalMillis / 3_600_000
        let mins = (totalMillis % 3_600_000) / 60_000
        let secs = (totalMillis % 60_000) / 1000
        let millis = totalMillis % 1000
        return String(format: "%02d:%02d:%02d%@%03d", hrs, mins, secs, separator, millis)
    }

    /// `mm:ss`, or `h:mm:ss` past an hour.
    public static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        return hrs > 0 ? String(format: "%d:%02d:%02d", hrs, mins, secs) : String(format: "%02d:%02d", mins, secs)
    }

    static func yamlString(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

public enum DateFormats {
    /// `2026-01-31 14:05` in the user's time zone. Readable by people and LLMs alike.
    public static let isoMinute: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    public static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public static let display: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
