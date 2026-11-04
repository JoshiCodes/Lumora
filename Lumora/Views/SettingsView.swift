import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var library: VideoLibrary

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

            Section("Energy") {
                Toggle("Pause on battery power", isOn: $preferences.pauseOnBattery)
                Toggle("Pause in Low Power Mode", isOn: $preferences.pauseInLowPowerMode)
                Toggle("Pause when the desktop is hidden", isOn: $preferences.pauseWhenCovered)
            }

            Section("General") {
                Toggle("Open at login", isOn: $preferences.launchAtLogin)
                LabeledContent("Library folder") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.open(library.root)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
    }
}
