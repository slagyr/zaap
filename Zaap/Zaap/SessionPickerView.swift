import SwiftUI

struct SessionPickerView: View {
    @ObservedObject var viewModel: SessionPickerViewModel

    var body: some View {
        VStack(spacing: 8) {
            Picker("Session", selection: $viewModel.selectedSessionKey) {
                Text("New conversation")
                    .tag(nil as String?)

                ForEach(viewModel.sessions) { session in
                    VStack(alignment: .leading) {
                        Text(session.title)
                        if let msg = session.lastMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .tag(session.key as String?)
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
