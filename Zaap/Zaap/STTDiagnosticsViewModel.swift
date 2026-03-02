import Foundation

// MARK: - Recognition Status

enum STTRecognitionStatus: Equatable {
    case idle
    case listening
    case recognizing
}

// MARK: - Diagnostics Log Event

enum STTDiagnosticsEvent: Equatable {
    case partialTranscript(String)
    case utteranceEmitted(String)
    case silenceThresholdHit(elapsed: TimeInterval)
    case recognitionStarted
    case recognitionStopped
    case recognitionError(String)
    case silenceTimerReset
    case transcriptTooShort(length: Int)
    case audioSessionInfo(String)
}

// MARK: - Diagnostics Log Entry

struct STTDiagnosticsLogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let event: STTDiagnosticsEvent

    static func == (lhs: STTDiagnosticsLogEntry, rhs: STTDiagnosticsLogEntry) -> Bool {
        lhs.id == rhs.id && lhs.timestamp == rhs.timestamp && lhs.event == rhs.event
    }
}

// MARK: - STTDiagnosticsViewModel

@MainActor
final class STTDiagnosticsViewModel: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var logEntries: [STTDiagnosticsLogEntry] = []
    @Published private(set) var recognitionStatus: STTRecognitionStatus = .idle
    @Published private(set) var partialTranscript: String = ""
    @Published private(set) var silenceTimerElapsed: TimeInterval?

    private let maxLogEntries = 500

    func activate() {
        isActive = true
    }

    func deactivate() {
        isActive = false
        recognitionStatus = .idle
        partialTranscript = ""
        silenceTimerElapsed = nil
    }

    func appendLog(_ event: STTDiagnosticsEvent) {
        let entry = STTDiagnosticsLogEntry(timestamp: Date(), event: event)
        logEntries.append(entry)
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst(logEntries.count - maxLogEntries)
        }
    }

    func clearLog() {
        logEntries.removeAll()
    }

    func updateRecognitionStatus(_ status: STTRecognitionStatus) {
        recognitionStatus = status
    }

    func updatePartialTranscript(_ text: String) {
        partialTranscript = text
    }

    func updateSilenceTimer(_ elapsed: TimeInterval) {
        silenceTimerElapsed = elapsed
    }

    func clearSilenceTimer() {
        silenceTimerElapsed = nil
    }
}
