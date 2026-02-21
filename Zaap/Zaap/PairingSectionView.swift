import SwiftUI

/// Settings section for gateway pairing — enter address, pair/unpair, show status.
struct PairingSectionView: View {
    @Bindable var viewModel: PairingViewModel

    var body: some View {
        Section {
            if viewModel.isPaired {
                // Paired state
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text("Paired")
                            .font(.headline)
                        if !viewModel.gatewayAddress.isEmpty {
                            Text(viewModel.gatewayAddress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    connectionBadge
                }

                Button(role: .destructive) {
                    viewModel.unpair()
                } label: {
                    Label("Unpair", systemImage: "xmark.circle")
                }
            } else {
                // Unpaired state
                TextField("Gateway Address", text: $viewModel.gatewayAddress)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    viewModel.connect()
                } label: {
                    HStack {
                        if viewModel.isConnecting {
                            ProgressView()
                                .controlSize(.small)
                            Text("Connecting…")
                        } else {
                            Label("Pair with Gateway", systemImage: "link")
                        }
                    }
                }
                .disabled(viewModel.gatewayAddress.isEmpty || viewModel.isConnecting)
            }
        } header: {
            Text("Gateway Pairing")
        } footer: {
            if !viewModel.isPaired {
                Text("Enter your OpenClaw gateway hostname (e.g. myhost.ts.net) to enable voice features.")
            }
        }
    }

    @ViewBuilder
    private var connectionBadge: some View {
        switch viewModel.connectionStatus {
        case .connected:
            Text("Connected")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.2))
                .cornerRadius(8)
        case .connecting:
            ProgressView()
                .controlSize(.small)
        case .disconnected:
            Text("Offline")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
        }
    }
}
