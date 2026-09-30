import SwiftUI

public struct WaveformView: View {
    public let samples: [Float]
    public let duration: TimeInterval
    @Binding public var trimStart: TimeInterval
    @Binding public var trimEnd: TimeInterval
    @Binding public var currentPlayhead: TimeInterval
    public var onSeek: (TimeInterval) -> Void

    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false
    @State private var isDraggingPlayhead = false

    public init(
        samples: [Float],
        duration: TimeInterval,
        trimStart: Binding<TimeInterval>,
        trimEnd: Binding<TimeInterval>,
        currentPlayhead: Binding<TimeInterval>,
        onSeek: @escaping (TimeInterval) -> Void
    ) {
        self.samples = samples
        self.duration = duration
        self._trimStart = trimStart
        self._trimEnd = trimEnd
        self._currentPlayhead = currentPlayhead
        self.onSeek = onSeek
    }

    public var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let safeDuration = max(0.1, duration)

            let startX = CGFloat(trimStart / safeDuration) * width
            let endX = CGFloat(trimEnd / safeDuration) * width
            let playheadX = CGFloat(currentPlayhead / safeDuration) * width

            ZStack(alignment: .leading) {
                // Background waveform bars
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<samples.count, id: \.self) { index in
                        let sample = CGFloat(samples[index])
                        let barHeight = max(4, sample * (height - 30))
                        let barProgress = Double(index) / Double(max(1, samples.count - 1))
                        let barTime = barProgress * safeDuration

                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(barColor(for: barTime))
                            .frame(height: barHeight)
                    }
                }
                .frame(width: width, height: height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let clampedX = max(0, min(width, value.location.x))
                            let newTime = Double(clampedX / width) * safeDuration
                            currentPlayhead = newTime
                            onSeek(newTime)
                        }
                )

                // Leading Trimmed Shade (Muted / Excluded)
                if startX > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.45))
                        .frame(width: max(0, startX), height: height)
                }

                // Trailing Trimmed Shade (Muted / Excluded)
                if endX < width {
                    Rectangle()
                        .fill(Color.black.opacity(0.45))
                        .frame(width: max(0, width - endX), height: height)
                        .offset(x: endX)
                }

                // Trim Start Handle
                TrimHandle(
                    isStart: true,
                    height: height,
                    timeText: formatTime(trimStart),
                    isDragging: isDraggingStart
                )
                .position(x: startX, y: height / 2)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDraggingStart = true
                            let newX = max(0, min(endX - 10, value.location.x))
                            trimStart = Double(newX / width) * safeDuration
                            if currentPlayhead < trimStart {
                                currentPlayhead = trimStart
                                onSeek(trimStart)
                            }
                        }
                        .onEnded { _ in isDraggingStart = false }
                )

                // Trim End Handle
                TrimHandle(
                    isStart: false,
                    height: height,
                    timeText: formatTime(trimEnd),
                    isDragging: isDraggingEnd
                )
                .position(x: endX, y: height / 2)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDraggingEnd = true
                            let newX = max(startX + 10, min(width, value.location.x))
                            trimEnd = Double(newX / width) * safeDuration
                            if currentPlayhead > trimEnd {
                                currentPlayhead = trimEnd
                                onSeek(trimEnd)
                            }
                        }
                        .onEnded { _ in isDraggingEnd = false }
                )

                // Current Playhead Line
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: 2, height: height)
                    .position(x: playheadX, y: height / 2)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 120)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func barColor(for time: TimeInterval) -> Color {
        if time < trimStart || time > trimEnd {
            return Color.secondary.opacity(0.25)
        } else if time <= currentPlayhead {
            return Color.accentColor
        } else {
            return Color.accentColor.opacity(0.6)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

struct TrimHandle: View {
    let isStart: Bool
    let height: CGFloat
    let timeText: String
    let isDragging: Bool

    var body: some View {
        ZStack {
            // Vertical Guide Line
            Rectangle()
                .fill(isStart ? Color.green : Color.red)
                .frame(width: 3, height: height)

            // Top Cap Badge
            VStack(spacing: 0) {
                Text(timeText)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(isStart ? Color.green : Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .shadow(radius: 2)

                Image(systemName: isStart ? "chevron.right" : "chevron.left")
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(isStart ? .green : .red)
                    .padding(.top, 1)

                Spacer()
            }
            .frame(height: height + 24)
            .offset(y: -12)
        }
        .frame(width: 36)
        .contentShape(Rectangle())
        .cursor(isStart ? .resizeLeftRight : .resizeLeftRight)
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
