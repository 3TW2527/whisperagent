import Foundation

/// Combines a course (or the whole library) into a single Markdown file for chat apps that take
/// uploads rather than folders, such as ChatGPT Projects, claude.ai Projects and Gemini Notebook.
public enum StudyBundleExporter {
    /// Material files whose text is inlined. Other materials (PDF, slides) are only listed,
    /// since they're best uploaded alongside the bundle.
    static let inlineMaterialExtensions: Set<String> = ["md", "txt"]

    public static func bundle(for courses: [Course]) -> String {
        var parts: [String] = []
        if courses.count > 1 {
            parts.append("# Study Library Bundle\n\nCourses: \(courses.map(\.displayName).joined(separator: "; "))\n")
        }
        for course in courses {
            parts.append(courseSection(course))
        }
        return parts.joined(separator: "\n\n---\n\n")
    }

    static func courseSection(_ course: Course) -> String {
        var lines: [String] = []
        lines.append("# \(course.kind.displayName): \(course.displayName)")
        lines.append("")
        if !course.tags.isEmpty {
            lines.append("Tags: \(course.tags.joined(separator: ", "))")
            lines.append("")
        }
        let unit = course.kind.unitName.lowercased()
        lines.append("This file bundles every \(unit) transcript of the \(course.kind.displayName.lowercased()). Transcripts are automatic and may mishear names, terms and numbers. Paragraphs start with `[mm:ss]` (or `[h:mm:ss]`) timestamps measured from the start of each recording. Cite answers as `\(course.kind.unitLetter)<\(unit)> [mm:ss]`.")
        lines.append("")

        lines.append("## \(course.kind.unitName) List")
        lines.append("")
        for lecture in course.lectures {
            lines.append("- \(lecture.label): \(lecture.title.isEmpty && lecture.series == nil ? "(untitled)" : lecture.shortTitle) — \(DateFormats.isoMinute.string(from: lecture.date))")
        }
        lines.append("")

        for lecture in course.lectures {
            let groups = course.recordingGroups(for: lecture)
            lines.append("## \(lecture.label) — \(lecture.displayTitle) (\(DateFormats.isoMinute.string(from: lecture.date)))")
            lines.append("")
            if groups.isEmpty {
                lines.append("_No transcript._")
                lines.append("")
            }
            for group in groups {
                guard let file = readableFile(group) else { continue }
                lines.append("### \(group.baseName)")
                lines.append("")
                lines.append(stripFrontMatter(file.content).trimmingCharacters(in: .whitespacesAndNewlines))
                lines.append("")
            }
        }

        let unassigned = course.unassignedRecordingGroups
        if !unassigned.isEmpty {
            lines.append("## Other Transcripts")
            lines.append("")
            for group in unassigned {
                guard let file = readableFile(group) else { continue }
                lines.append("### \(group.baseName)")
                lines.append("")
                lines.append(stripFrontMatter(file.content).trimmingCharacters(in: .whitespacesAndNewlines))
                lines.append("")
            }
        }

        if !course.materials.isEmpty {
            lines.append("## Course Materials")
            lines.append("")
            let listed = course.materials.filter { !inlineMaterialExtensions.contains($0.fileExtension) }
            if !listed.isEmpty {
                lines.append("These files aren't included here. Upload them separately if needed:")
                lines.append("")
                for file in listed {
                    lines.append("- \(file.name)")
                }
                lines.append("")
            }
            for file in course.materials where inlineMaterialExtensions.contains(file.fileExtension) {
                lines.append("### Material: \(file.name)")
                lines.append("")
                lines.append(((try? String(contentsOf: file.url, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Markdown preferred, then plain text. Subtitle formats are too noisy to bundle.
    static func readableFile(_ group: RecordingGroup) -> TranscriptFile? {
        group.file(for: .markdown) ?? group.file(for: .plainText)
    }

    /// Drops the YAML block, title and disclaimer of a generated transcript. The bundle carries
    /// that context in its own headings.
    static func stripFrontMatter(_ text: String) -> String {
        var body = Substring(text)
        if body.hasPrefix("---\n"), let end = body.dropFirst(4).range(of: "\n---\n") {
            body = body[end.upperBound...]
        }
        return body.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("# ") && !$0.hasPrefix("> Automatic transcript.") }
            .joined(separator: "\n")
    }
}
