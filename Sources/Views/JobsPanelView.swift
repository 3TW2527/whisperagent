import SwiftUI

/// Bar above the detail area that summarises transcription jobs and expands to show each one.
public struct JobsPanelView: View {
    @ObservedObject private var service = WhisperTranscriptionService.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var isExpanded = false

    public init() {}

    private var running: Int { service.jobs.filter { $0.phase.isRunning }.count }
    private var queued: Int { service.jobs.filter { $0.phase == .queued }.count }
    private var failed: Int { service.jobs.filter { if case .failed = $0.phase { return true } else { return false } }.count }

    public var body: some View {
        if !service.jobs.isEmpty {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: running > 0 ? "waveform.circle.fill" : (failed > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill"))
                        .foregroundColor(running > 0 ? .accentColor : (failed > 0 ? .red : .green))
                        .font(.body)

                    Text(summary)
                        .font(.subheadline.bold())

                    Spacer()

                    if !service.finishedJobs.isEmpty {
                        Button("Clear Finished") { service.clearFinished() }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)

                if isExpanded {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(service.jobs) { job in
                                JobRowView(job: job, showsCourse: true)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                    .frame(maxHeight: 150)
                }
            }
            .background(Color.accentColor.opacity(0.08))
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color.accentColor.opacity(0.2)), alignment: .bottom)
        }
    }

    private var summary: String {
        var parts: [String] = []
        if running > 0 { parts.append("\(running) transcribing") }
        if queued > 0 { parts.append("\(queued) queued") }
        let done = service.finishedJobs.count - failed
        if done > 0 { parts.append("\(done) finished") }
        if failed > 0 { parts.append("\(failed) failed") }
        return parts.joined(separator: " · ")
    }
}

public struct JobRowView: View {
    public let job: TranscriptionJob
    public let showsCourse: Bool

    @ObservedObject private var service = WhisperTranscriptionService.shared

    public init(job: TranscriptionJob, showsCourse: Bool) {
        self.job = job
        self.showsCourse = showsCourse
    }

    public var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(job.title)
                        .font(.caption.bold())
                        .lineLimit(1)
                    if showsCourse {
                        Text("\(job.courseName) · L\(String(format: "%02d", job.lectureNumber))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                if job.phase.isRunning {
                    ProgressView(value: job.progressFraction)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 260)
                }
                Text(job.statusDescription)
                    .font(.caption2)
                    .foregroundColor(isFailed ? .red : .secondary)
                    .lineLimit(2)
            }

            Spacer()

            if job.phase.isTerminal {
                if case .completed(let files) = job.phase, let first = files.first {
                    Button("Show") { CourseStorageService.shared.revealInFinder(url: first) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                } else {
                    Button("Retry") { service.retry(jobID: job.id) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
                Button {
                    service.dismiss(jobID: job.id)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Dismiss")
            } else {
                Button {
                    service.cancel(jobID: job.id)
                } label: {
                    Image(systemName: "stop.circle")
                }
                .buttonStyle(.borderless)
                .help("Cancel")
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var isFailed: Bool {
        if case .failed = job.phase { return true }
        return false
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.phase {
        case .queued:
            Image(systemName: "clock").foregroundColor(.secondary)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
        case .cancelled:
            Image(systemName: "xmark.circle").foregroundColor(.secondary)
        default:
            ProgressView().controlSize(.small)
        }
    }
}
