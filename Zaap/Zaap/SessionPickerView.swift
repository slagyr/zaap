import SwiftUI

struct SessionPickerView: View {
    @ObservedObject var viewModel: SessionPickerViewModel

    var body: some View {
        VStack(spacing: 8) {
            if viewModel.isLoading {
                ProgressView()
                    .frame(height: 44)
            } else if viewModel.sessions.isEmpty {
                Text("New conversation")
                    .foregroundColor(.secondary)
                    .frame(height: 44)
            } else {
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
            }
        }
    }
}
