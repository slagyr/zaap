import SwiftUI

/// Displays the request log entries in a scrollable list, color-coded by success/failure.
struct RequestLogView: View {
    @ObservedObject var log: RequestLog

    var body: some View {
        Section {
            if log.entries.isEmpty {
                Text("No requests yet")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(log.entries.reversed()) { entry in
                    RequestLogEntryRow(entry: entry)
                }
            }
        } header: {
            HStack {
                Text("Request Log")
                Spacer()
                if !log.entries.isEmpty {
                    Button("Clear") {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(entry.isSuccess ? .green : .red)
                    .frame(width: 8, height: 8)

                Text(entry.summaryLine)
                    .font(.caption.monospaced())
                    .foregroundStyle(entry.isSuccess ? Color.primary : Color.red)
                    .lineLimit(1)
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
                    .foregroundStyle(showCopied ? .green : .accentColor)
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
