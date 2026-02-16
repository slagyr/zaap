import SwiftUI

struct SettingsView: View {

    @Bindable var settings: SettingsManager

    @State private var isTokenVisible = false

    var body: some View {
        Form {
            Section {
                TextField("Webhook URL", text: $settings.webhookURL)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                HStack {
                    Group {
                        if isTokenVisible {
                            TextField("Bearer Token", text: $settings.authToken)
                        } else {
                            SecureField("Bearer Token", text: $settings.authToken)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Button {
                        isTokenVisible.toggle()
                    } label: {
                        Image(systemName: isTokenVisible ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Webhook")
            } footer: {
                Text("Location data is sent as a POST request with a Bearer authorization header.")
            }

            Section {
                Toggle("Location Tracking", isOn: $settings.locationTrackingEnabled)
                    .onChange(of: settings.locationTrackingEnabled) { _, enabled in
                        LocationDeliveryService.shared.setTracking(enabled: enabled)
                    }

                Toggle("Sleep Tracking", isOn: $settings.sleepTrackingEnabled)
                    .onChange(of: settings.sleepTrackingEnabled) { _, enabled in
                        SleepDeliveryService.shared.setTracking(enabled: enabled)
                    }

                Toggle("Workout Tracking", isOn: $settings.workoutTrackingEnabled)
                    .onChange(of: settings.workoutTrackingEnabled) { _, enabled in
                        WorkoutDeliveryService.shared.setTracking(enabled: enabled)
                    }

                Toggle("Heart Rate Tracking", isOn: $settings.heartRateTrackingEnabled)
                    .onChange(of: settings.heartRateTrackingEnabled) { _, enabled in
                        HeartRateDeliveryService.shared.setTracking(enabled: enabled)
                    }

                Toggle("Activity Tracking", isOn: $settings.activityTrackingEnabled)
                    .onChange(of: settings.activityTrackingEnabled) { _, enabled in
                        ActivityDeliveryService.shared.setTracking(enabled: enabled)
                    }
            } header: {
                Text("Data Sources")
            } footer: {
                if !settings.isConfigured && (settings.locationTrackingEnabled || settings.sleepTrackingEnabled || settings.workoutTrackingEnabled) {
                    Text("⚠️ Configure a valid webhook URL and token above to start sending data.")
                        .foregroundStyle(.orange)
                }
            }

            if settings.isConfigured {
                Section {
                    LabeledContent("Endpoint", value: settings.webhookURL)
                    LabeledContent("Status") {
                        Label(
                            settings.locationTrackingEnabled ? "Active" : "Inactive",
                            systemImage: settings.locationTrackingEnabled ? "location.fill" : "location.slash"
                        )
                        .foregroundStyle(settings.locationTrackingEnabled ? .green : .secondary)
                    }
                } header: {
                    Text("Summary")
                }
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView(settings: SettingsManager(defaults: .init(suiteName: "preview")!))
    }
}
