# Lumora

Live video wallpapers for macOS. Bring your own clips or find new ones from NASA, the Internet Archive, Pexels and Pixabay, and Lumora plays them behind your desktop icons on every display and every Space.

- **Now Playing:** live preview of what's on your desktop, with pause, stop and scaling
- **Library:** drag and drop your own videos, rename them, filter them
- **Discover:** browse and search NASA, the Internet Archive, Pexels and Pixabay, preview a clip and set it as your wallpaper in one click
- **Screen Saver:** a matching screen saver that plays videos from your library, also on top of the lock screen
- **Performance:** live CPU, memory and GPU readings, details about the current video, and an impact test
- **Optimize:** new videos are converted to HEVC at up to 30 fps and your display's resolution, existing ones with one click
- **Automatic updates** from GitHub releases
- Lives in the menu bar, with a Dock icon only while the window is open

Requires macOS 15 or later on Apple Silicon.

## Easy on the battery

- One decoder for all displays. Every screen and the in-app preview share the same player.
- Audio tracks are dropped before playback, so nothing is decoded that you can't hear.
- Downloads pick the smallest file that still covers your display instead of always grabbing 4K.
- Videos are optimized when you add them: HEVC, at most 30 fps and no larger than your widest display.
- Playback stops while the desktop is hidden behind full-screen apps, while the screen is locked, asleep or showing the screen saver, when you've been away for a few minutes and when the Mac runs hot. Optionally also on battery or in Low Power Mode.
- Video views never redraw on the CPU. Everything on screen comes straight from the video layer.
- The Mac can still go to sleep while a wallpaper is playing.

## Install

Grab the latest `.dmg` from [Releases](../../releases), open it and drag Lumora into Applications.

The builds are signed ad hoc but not notarized by Apple yet. On first launch macOS says *“Apple could not verify ‘Lumora’ is free of malware…”*. To allow it, use one of these:

**System Settings**

1. Try to open Lumora once and close the warning with **Done**.
2. Go to **System Settings → Privacy & Security** and scroll down to the Security section.
3. Click **Open Anyway** next to the message about Lumora and confirm with your password.

**Terminal**

```sh
xattr -dr com.apple.quarantine /Applications/Lumora.app
```

You only need to do this once. Later versions arrive through the built-in updater, which takes care of this for you.

## Video sources

| Source | Key needed | Good for |
| --- | --- | --- |
| [NASA Image and Video Library](https://images.nasa.gov) | No | Earth from orbit, auroras, launches, planets |
| [Internet Archive](https://archive.org/details/movies) | No | Time-lapses, aerials, public domain footage |
| [Pexels](https://www.pexels.com/api/) | Yes, free | Polished stock footage in 4K |
| [Pixabay](https://pixabay.com/api/docs/) | Yes, free | Stock footage and motion backgrounds |

Paste keys into **Settings → Video Sources** or straight into the Discover tab. They are stored locally and never bundled with the app. Check each source's license before using a video outside your own desktop.

## Performance

The **Performance** tab shows Lumora's CPU and memory, the system's GPU load and details about the current video, such as codec, resolution and whether it's hardware-decoded. It also gives hints when a clip is heavier than it needs to be.

If a clip runs above 30 fps, is larger than your display or uses a codec without hardware decoding, Lumora offers **Optimize This Video**. It re-encodes the clip to HEVC at up to 30 fps and your display's resolution, without audio. A 4K clip at 60 fps on a MacBook display ends up with less than half the decoding work. The same action is in the clip's context menu, and **Settings → Optimize Library** handles all clips at once.

Because macOS does part of the decoding and drawing in its own services, Lumora's process alone doesn't tell the whole story. The **impact test** measures the whole Mac for 10 seconds while playing and 10 seconds while paused and shows the difference. Sampling only runs while the tab is open.

## Screen saver

Open the **Screen Saver** tab, click **Install** and pick Lumora under **System Settings → Screen Saver**. Then choose which videos it should play.

macOS runs third-party screen savers in a sandbox that can't see Lumora's library. Lumora therefore hard-links the selected videos into the installed `Lumora.saver` bundle, which the screen saver can always read. Hard links take no extra disk space.

A truly animated lock screen like Apple's Aerials isn't possible with public APIs. While the Mac is locked and idle, the screen saver plays on top of the lock screen, and the lock screen picture itself matches the first frame of your wallpaper.

## Building

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open Lumora.xcodeproj
```

## Releases and updates

Every push to `main` is built and tested by GitHub Actions. If `MARKETING_VERSION` in `project.yml` hasn't been released yet, the workflow creates a GitHub release `vX.Y.Z`. To publish a new version, bump the number and push.

Each release contains:

- `Lumora-X.Y.Z.dmg` for new installs
- `Lumora-X.Y.Z.zip` and `appcast.xml` for [Sparkle](https://sparkle-project.org), which the app uses to update itself

The app reads the feed from `releases/latest/download/appcast.xml`, so updates need the repository to be public. Updates are signed with an EdDSA key. The private key lives in the `SPARKLE_PRIVATE_KEY` repository secret, and the public key is `SUPublicEDKey` in `project.yml`. Without the secret, releases are still published, just without the update feed.
