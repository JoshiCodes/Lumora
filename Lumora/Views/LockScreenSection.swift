import SwiftUI

struct LockScreenSection: View {
    @EnvironmentObject private var lockScreen: LockScreenManager
    @EnvironmentObject private var library: VideoLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if lockScreen.aerials.isEmpty {
                noAerials
            } else {
                content
            }

            switch lockScreen.state {
            case .idle:
                EmptyView()
            case .working(let message):
                ProgressView {
                    Text(message).font(.caption)
                }
                .progressViewStyle(.linear)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .padding(18)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(
                    LinearGradient(colors: [Color(red: 0.12, green: 0.20, blue: 0.48),
                                            Color(red: 0.45, green: 0.30, blue: 0.80)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Animated Lock Screen")
                        .font(.title3.weight(.semibold))
                    Text("Experimental")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                }
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var subtitle: String {
        if lockScreen.needsSetupAgain {
            return "macOS put its own video back, probably after an update. Set it up again to bring yours back."
        }
        if lockScreen.isEnabled, let clip = lockScreen.installedClip {
            return "Your lock screen plays “\(clip.name)” and follows your wallpaper from now on."
        }
        return "Plays your wallpaper on the lock screen by stepping in for one of Apple's Aerials."
    }

    private var noAerials: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("First download any Aerial: open System Settings › Wallpaper, pick one of the moving Landscape, Cityscape, Underwater or Earth wallpapers and wait until it's downloaded. Then come back here.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Wallpaper Settings") { lockScreen.openWallpaperSettings() }
                Button("Check Again") { lockScreen.refresh() }
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Aerial to replace", selection: $lockScreen.targetID) {
                ForEach(lockScreen.aerials) { aerial in
                    Text(aerial.name).tag(Optional(aerial.id))
                }
            }
            .disabled(lockScreen.isEnabled || lockScreen.isBusy)
            .frame(maxWidth: 380)

            VStack(alignment: .leading, spacing: 6) {
                step(1, "Click Set Up. macOS asks for your password once.")
                step(2, "In System Settings › Wallpaper, choose “\(lockScreen.target?.name ?? "that Aerial")” as your wallpaper.")
                step(3, "Lock your Mac. From now on the lock screen follows whatever plays on your desktop.")
            }
            .font(.callout)

            HStack {
                if lockScreen.isEnabled && !lockScreen.needsSetupAgain {
                    Button("Open Wallpaper Settings") { lockScreen.openWallpaperSettings() }
                    Button("Restore Apple's Video", role: .destructive) { lockScreen.restoreOriginal() }
                } else {
                    Button(lockScreen.needsSetupAgain ? "Set Up Again…" : "Set Up…") { lockScreen.setUp() }
                        .buttonStyle(.borderedProminent)
                        .disabled(library.activeClip == nil || lockScreen.isBusy)
                    if library.activeClip == nil {
                        Text("Start a wallpaper first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .controlSize(.large)

            Text("Lumora swaps the video file behind the chosen Aerial and keeps Apple's original to put it back anytime. While this is on, Lumora leaves your desktop picture alone, so the Aerial stays selected. A macOS update can restore Apple's video; Lumora notices and lets you set it up again.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 18, height: 18)
                .background(Color.accentColor.opacity(0.18), in: Circle())
                .foregroundStyle(Color.accentColor)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
