import SwiftUI

struct SettingsPane: View {
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var library: VideoLibrary
    @EnvironmentObject private var keys: APIKeys
    @EnvironmentObject private var discover: DiscoverModel
    @EnvironmentObject private var updater: Updater

    @State private var storage = ""
    @State private var optimizingAll = false

    var body: some View {
        Form {
            Section("Display") {
                Picker("Scaling", selection: $preferences.scaling) {
                    ForEach(Scaling.allCases) { Text($0.title).tag($0) }
                }
                .disabled(preferences.isManaged(\Preferences.scaling))
                Toggle(isOn: $preferences.matchDesktopPicture) {
                    Text("Match desktop picture")
                    Text("Uses the first frame as your regular wallpaper, so Mission Control and the lock screen look the same. Turn this off when you use the animated lock screen.")
                }
                .disabled(preferences.isManaged(\Preferences.matchDesktopPicture))
            }

            Section("Rotation") {
                Picker("Change wallpaper", selection: $preferences.rotationMinutes) {
                    Text("Never").tag(0)
                    Divider()
                    Text("Every 15 minutes").tag(15)
                    Text("Every 30 minutes").tag(30)
                    Text("Every hour").tag(60)
                    Text("Every 3 hours").tag(180)
                    Text("Every day").tag(1440)
                }
                .disabled(preferences.isManaged(\Preferences.rotationMinutes))
                if preferences.rotationMinutes > 0 {
                    Toggle("Random order", isOn: $preferences.rotationShuffle)
                        .disabled(preferences.isManaged(\Preferences.rotationShuffle))
                }
            }

            Section {
                Toggle("Pause on battery power", isOn: $preferences.pauseOnBattery)
                    .disabled(preferences.isManaged(\Preferences.pauseOnBattery))
                Toggle("Pause in Low Power Mode", isOn: $preferences.pauseInLowPowerMode)
                    .disabled(preferences.isManaged(\Preferences.pauseInLowPowerMode))
                Toggle(isOn: $preferences.pauseWhenCovered) {
                    Text("Pause when the desktop is hidden")
                    Text("For example behind full-screen apps.")
                }
                .disabled(preferences.isManaged(\Preferences.pauseWhenCovered))
                Toggle("Pause when you're away", isOn: $preferences.pauseWhenIdle)
                    .disabled(preferences.isManaged(\Preferences.pauseWhenIdle))
                if preferences.pauseWhenIdle {
                    Picker("Away after", selection: $preferences.idleMinutes) {
                        ForEach([1, 2, 5, 10, 15, 30], id: \.self) { minutes in
                            Text(minutes == 1 ? "1 minute" : "\(minutes) minutes").tag(minutes)
                        }
                    }
                    .disabled(preferences.isManaged(\Preferences.idleMinutes))
                }
                Toggle(isOn: $preferences.respectReduceMotion) {
                    Text("Respect Reduce Motion")
                    Text("Shows a still picture while Reduce Motion is on in Accessibility settings.")
                }
                .disabled(preferences.isManaged(\Preferences.respectReduceMotion))
                Toggle(isOn: $preferences.pauseWhenHot) {
                    Text("Pause when the Mac runs hot")
                    Text("Gives the system room to cool down under heavy load.")
                }
                .disabled(preferences.isManaged(\Preferences.pauseWhenHot))
            } header: {
                Text("Energy")
            } footer: {
                Text("Lumora always pauses while the screen is locked, asleep or showing the screen saver.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $preferences.optimizeNewClips) {
                    Text("Optimize new videos")
                    Text("Converts videos you add to HEVC, at most 30 fps and no larger than your display. Takes a moment after adding, then plays with far less effort.")
                }
                .disabled(preferences.isManaged(\Preferences.optimizeNewClips))
                LabeledContent("Existing videos") {
                    if optimizingAll || !library.optimizing.isEmpty {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Optimize Library") {
                            optimizingAll = true
                            Task {
                                await library.optimizeAll()
                                optimizingAll = false
                            }
                        }
                    }
                }
            } header: {
                Text("Optimization")
            } footer: {
                Text("Videos that are already efficient are left untouched.")
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
                if updater.isAvailable {
                    Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks)
                    LabeledContent("Version \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))") {
                        Button("Check Now") { updater.checkForUpdates() }
                            .disabled(!updater.canCheckForUpdates)
                    }
                } else {
                    LabeledContent("Version \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))") {
                        Text("Managed by your organization")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("General") {
                Toggle("Open at login", isOn: $preferences.launchAtLogin)
                    .disabled(preferences.isManaged(\Preferences.launchAtLogin))
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
