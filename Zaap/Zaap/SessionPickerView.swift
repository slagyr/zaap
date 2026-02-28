import SwiftUI

struct SessionPickerView: View {
    @ObservedObject var viewModel: SessionPickerViewModel

    var body: some View {
        VStack(spacing: 8) {
            Picker("Session", selection: $viewModel.selectedSessionKey) {
                ForEach(viewModel.sessions) { session in
                    VStack(alignment: .leading) {
                        Text(session.title)
                        if let msg = session.lastMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .tag(session.key)
                }
            }
            .pickerStyle(.menu)

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}
