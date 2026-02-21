import SwiftUI

/// Displays the request log entries in a scrollable list, color-coded by success/failure.
struct RequestLogView: View {
    @ObservedObject var log: RequestLog
    @State private var showAll = false

    private static let defaultVisible = 10

    private var visibleEntries: [RequestLogEntry] {
        let all = log.entries.reversed() as [RequestLogEntry]
        return showAll ? all : Array(all.prefix(Self.defaultVisible))
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

                if log.entries.count > Self.defaultVisible {
                    Button {
                        withAnimation {
                            showAll.toggle()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text(showAll
                                ? "Show Less"
                                : "Show More (\(log.entries.count - Self.defaultVisible) more)")
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
            HStack {
                Circle()
                    .fill(entry.isSuccess ? .green : .red)
                    .frame(width: 8, height: 8)

                Text(entry.path)
                    .font(.subheadline.monospaced())
                    .fontWeight(.medium)

                Spacer()

                if let code = entry.statusCode {
                    Text("\(code)")
                        .font(.caption.monospaced())
                        .foregroundStyle(entry.isSuccess ? .green : .red)
                }

                Text("\(entry.responseTimeMs)ms")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(Self.timeFormatter.string(from: entry.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let error = entry.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }

            if isExpanded {
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
