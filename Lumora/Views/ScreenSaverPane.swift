import SwiftUI

struct ScreenSaverPane: View {
    @EnvironmentObject private var saver: ScreenSaverManager
    @EnvironmentObject private var library: VideoLibrary

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                LockScreenSection()
                statusCard
                if saver.isInstalled {
                    picker
                }
                if NSScreen.screens.count > 1 {
                    Label {
                        Text("With several displays, macOS keeps a separate screen saver for each one. In System Settings › Screen Saver, switch to each display and choose Lumora there too.")
                    } icon: {
                        Image(systemName: "display.2")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                Label {
                    Text("When your Mac is locked and idle, the screen saver also plays on top of the lock screen. The lock screen picture itself is the first frame of your current wallpaper.")
                } icon: {
                    Image(systemName: "lock")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Lock Screen")
        .alert("Screen Saver", isPresented: errorBinding, presenting: saver.errorMessage) { _ in
            Button("OK") {}
        } message: { Text($0) }
    }

    private var statusCard: some View {
        HStack(spacing: 18) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(
                    LinearGradient(colors: [Color(red: 0.24, green: 0.14, blue: 0.50),
                                            Color(red: 0.82, green: 0.43, blue: 0.53)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if saver.isSyncing {
                ProgressView()
                    .controlSize(.small)
                    .help("Updating the screen saver…")
            }

            if saver.isInstalled {
                Button("Open System Settings") { saver.openSystemSettings() }
                Menu {
                    Button("Reinstall") { install() }
                    Button("Uninstall", role: .destructive) { saver.uninstall() }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            } else {
                Button("Install") { install() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.large)
        .padding(18)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var title: String {
        saver.isInstalled ? "Screen Saver" : "Bring your videos to the screen saver"
    }

    private var message: String {
        if !saver.isInstalled {
            return "Installs a screen saver that plays videos from your library. You choose it in System Settings afterwards."
        }
        if NSScreen.screens.count > 1, saver.selection.isEmpty {
            return "Choose which videos it should play. macOS sets the screen saver per display, so pick Lumora for each of your screens in System Settings."
        }
        if saver.selection.isEmpty {
            return "Choose which videos it should play."
        }
        return saver.selection.count == 1
            ? "Plays the selected video."
            : "Plays one of \(saver.selection.count) videos at random each time it starts."
    }

    @ViewBuilder
    private var picker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Videos")
                .font(.headline)
            if library.clips.isEmpty {
                Text("Your library is empty. Add videos first.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(library.clips) { clip in
                        ClipCard(clip: clip,
                                 thumbnailURL: library.thumbnailURL(for: clip),
                                 isChecked: saver.contains(clip))
                            .onTapGesture { saver.toggle(clip) }
                    }
                }
            }
        }
    }

    private func install() {
        do {
            try saver.install()
            saver.openSystemSettings()
        } catch {
            saver.errorMessage = "Couldn't install the screen saver: \(error.localizedDescription)"
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { saver.errorMessage != nil }, set: { if !$0 { saver.errorMessage = nil } })
    }
}
