import SwiftUI

struct SettingsPane: View {
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var library: VideoLibrary
    @EnvironmentObject private var keys: APIKeys
    @EnvironmentObject private var discover: DiscoverModel
    @EnvironmentObject private var updater: Updater

    @State private var storage = ""

    var body: some View {
        Form {
            Section("Display") {
                Picker("Scaling", selection: $preferences.scaling) {
                    ForEach(Scaling.allCases) { Text($0.title).tag($0) }
                }
                Toggle(isOn: $preferences.matchDesktopPicture) {
                    Text("Match desktop picture")
                    Text("Uses the first frame as your regular wallpaper, so Mission Control and the lock screen look the same.")
                }
            }

            Section {
                Toggle("Pause on battery power", isOn: $preferences.pauseOnBattery)
                Toggle("Pause in Low Power Mode", isOn: $preferences.pauseInLowPowerMode)
                Toggle(isOn: $preferences.pauseWhenCovered) {
                    Text("Pause when the desktop is hidden")
                    Text("For example behind full-screen apps.")
                }
            } header: {
                Text("Energy")
            } footer: {
                Text("Lumora always pauses while the screen is locked, asleep or showing the screen saver.")
                    .foregroundStyle(.secondary)
            }

            Section("Video Sources") {
                ForEach(ProviderID.allCases) { provider in
                    LabeledContent {
                        SecureField("Not set", text: keyBinding(for: provider))
                            .frame(maxWidth: 260)
                            .onSubmit {
                                if discover.provider == provider { discover.reload() }
                            }
                    } label: {
                        Text("\(provider.title) API key")
                        Link("Get a key", destination: provider.keySignupURL)
                    }
                }
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks)
                LabeledContent("Version \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))") {
                    Button("Check Now") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
            }

            Section("General") {
                Toggle("Open at login", isOn: $preferences.launchAtLogin)
                LabeledContent("Library") {
                    HStack {
                        Text(storage)
                            .foregroundStyle(.secondary)
                        Button("Show in Finder") {
                            NSWorkspace.shared.open(library.root)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .task(id: library.clips.count) {
            let bytes = library.storageSize()
            storage = "\(library.clips.count) videos, " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
    }

    private func keyBinding(for provider: ProviderID) -> Binding<String> {
        Binding(
            get: { keys.key(for: provider) ?? "" },
            set: { keys.setKey($0, for: provider) }
        )
    }
}
