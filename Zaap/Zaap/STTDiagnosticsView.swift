import SwiftUI

struct STTDiagnosticsView: View {
    @ObservedObject var viewModel: STTDiagnosticsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Status bar
            HStack {
                statusIndicator
                Text(statusText)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                if let elapsed = viewModel.silenceTimerElapsed {
                    Text(String(format: "silence: %.1fs", elapsed))
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            // Partial transcript
            if !viewModel.partialTranscript.isEmpty {
                Text(viewModel.partialTranscript)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.horizontal, 8)
                    .lineLimit(2)
            }

            Divider()

            // Log entries
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.logEntries) { entry in
                            logEntryRow(entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .onChange(of: viewModel.logEntries.count) { _, _ in
                    if let last = viewModel.logEntries.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color.black.opacity(0.85))
        .foregroundColor(.green)
        .cornerRadius(8)
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private var statusIndicator: some View {
        switch viewModel.recognitionStatus {
        case .idle:
            Circle()
                .fill(Color.gray)
                .frame(width: 8, height: 8)
        case .listening:
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
        case .recognizing:
            Circle()
                .fill(Color.blue)
                .frame(width: 8, height: 8)
        }
    }

    private var statusText: String {
        switch viewModel.recognitionStatus {
        case .idle: return "Idle"
        case .listening: return "Listening"
        case .recognizing: return "Recognizing"
        }
    }

    // MARK: - Log Entry Row

    private func logEntryRow(_ entry: STTDiagnosticsLogEntry) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(timeString(entry.timestamp))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.gray)

            Text(eventIcon(entry.event))
                .font(.system(size: 9))

            Text(eventDescription(entry.event))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(eventColor(entry.event))
                .lineLimit(3)
        }
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    private func eventIcon(_ event: STTDiagnosticsEvent) -> String {
        switch event {
        case .partialTranscript: return "..."
        case .utteranceEmitted: return ">>>"
        case .silenceThresholdHit: return "---"
        case .recognitionStarted: return "[+]"
        case .recognitionStopped: return "[-]"
        case .recognitionError: return "[!]"
        case .silenceTimerReset: return " . "
        case .transcriptTooShort: return "<3>"
        }
    }

    private func eventDescription(_ event: STTDiagnosticsEvent) -> String {
        switch event {
        case .partialTranscript(let text):
            return "partial: \"\(text)\""
        case .utteranceEmitted(let text):
            return "EMIT: \"\(text)\""
        case .silenceThresholdHit(let elapsed):
            return String(format: "SILENCE CUT @ %.2fs", elapsed)
        case .recognitionStarted:
            return "Recognition started"
        case .recognitionStopped:
            return "Recognition stopped"
        case .recognitionError(let msg):
            return "ERROR: \(msg)"
        case .silenceTimerReset:
            return "silence timer reset"
        case .transcriptTooShort(let length):
            return "transcript too short (\(length) chars)"
        }
    }

    private func eventColor(_ event: STTDiagnosticsEvent) -> Color {
        switch event {
        case .partialTranscript: return .green
        case .utteranceEmitted: return .cyan
        case .silenceThresholdHit: return .yellow
        case .recognitionStarted: return .green
        case .recognitionStopped: return .orange
        case .recognitionError: return .red
        case .silenceTimerReset: return .gray
        case .transcriptTooShort: return .orange
        }
    }
}
