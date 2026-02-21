import SwiftUI

/// Displays the request log entries in a scrollable list, color-coded by success/failure.
struct RequestLogView: View {
    @ObservedObject var log: RequestLog
    @State private var showAll = false

    private static let defaultVisible = 5

    private var visibleEntries: [RequestLogEntry] {
        let all = Array(log.entries.reversed())
        return showAll ? all : Array(all.prefix(Self.defaultVisible))
    }

    private var hiddenCount: Int {
        max(0, log.entries.count - Self.defaultVisible)
    }

    var body: some View {
        Section {
            if log.entries.isEmpty {
                Text("No requests yet")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(visibleEntries) { entry in
                    RequestLogEntryRow(entry: entry)
                }

                if hiddenCount > 0 || showAll {
                    Button {
                        withAnimation {
                            showAll.toggle()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text(showAll ? "Show Less" : "Show More (\(hiddenCount) more)")
                                .font(.subheadline)
                                .foregroundStyle(Color.accentColor)
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
        } header: {
            HStack {
                Text("Request Log")
                Spacer()
                if !log.entries.isEmpty {
                    Button("Clear") {
                        showAll = false
                        log.clear()
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}

struct RequestLogEntryRow: View {
    let entry: RequestLogEntry
    @State private var isExpanded = false
    @State private var showCopied = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Single line: ● 09:13:26  /hooks/location        200  145ms
            HStack(spacing: 6) {
                Circle()
                    .fill(entry.isSuccess ? Color.green : Color.red)
                    .frame(width: 8, height: 8)

                Text(Self.timeFormatter.string(from: entry.timestamp))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)

                Text(entry.path)
                    .font(.caption.monospaced())
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if let code = entry.statusCode {
                    Text("\(code)")
                        .font(.caption.monospaced())
                        .foregroundStyle(entry.isSuccess ? Color.green : Color.red)
                } else if entry.errorMessage != nil {
                    Text("ERR")
                        .font(.caption.monospaced())
                        .foregroundStyle(Color.red)
                }

                Text("\(entry.responseTimeMs)ms")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            if isExpanded {
                if let error = entry.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }

                Text(entry.requestBody)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Color(.systemGray6))
                    .cornerRadius(4)

                Button {
                    UIPasteboard.general.string = entry.copyableText
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        Text(showCopied ? "Copied!" : "Copy")
                    }
                    .font(.caption)
                    .foregroundStyle(showCopied ? Color.green : Color.accentColor)
                }
                .buttonStyle(.borderless)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }
}
