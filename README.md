# Lumora

Live video wallpapers for macOS. Bring your own clips or find new ones on MotionBGs, Pexels and Pixabay, and Lumora plays them behind your desktop icons on every display and every Space.

- **Now Playing:** live preview of what's on your desktop, with pause, stop and scaling
- **Library:** drag and drop your own videos, rename, sort and filter them
- **Rotation:** change the wallpaper every few minutes, hours or once a day, in order or shuffled
- **Smooth switching:** wallpapers cross-fade instead of cutting through black
- **Discover:** browse and search MotionBGs, Pexels and Pixabay, preview a clip and set it as your wallpaper in one click
- **Animated lock screen** (experimental): your wallpaper keeps moving on the lock screen
- **Screen Saver:** a matching screen saver that plays videos from your library
- **Performance:** live CPU, memory and GPU readings, details about the current video, and an impact test
- **Optimize:** new videos are converted to HEVC at up to 30 fps and your display's resolution, existing ones with one click
- **Automatic updates** from GitHub releases
- Lives in the menu bar, with a Dock icon only while the window is open

Requires macOS 15 or later, on Apple Silicon or Intel.

## Easy on the battery

- One decoder for all displays. Every screen and the in-app preview share the same player.
- Audio tracks are dropped before playback, so nothing is decoded that you can't hear.
- Downloads pick the smallest file that still covers your display instead of always grabbing 4K.
- Videos are optimized when you add them: HEVC, at most 30 fps and no larger than your widest display.
- Batch imports are encoded one at a time instead of all at once.
- Playback stops while the desktop is hidden behind full-screen apps, while the screen is locked, asleep or showing the screen saver, when you've been away for a few minutes and when the Mac runs hot. Optionally also on battery or in Low Power Mode.
- Reduce Motion in Accessibility settings is respected: Lumora shows a still picture instead.
- The blurred backdrop in the app is rendered once, not live.
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

## Deploying with Intune or another MDM

Releases include an installer package for MDM deployment, and every setting can be locked with a configuration profile. See [docs/Intune.md](docs/Intune.md).

## Video sources

| Source | Key needed | Good for |
| --- | --- | --- |
| [MotionBGs](https://motionbgs.com) | No | Live wallpapers from games, anime, films, nature and space |
| [Pexels](https://www.pexels.com/api/) | Yes, free | Polished stock footage in 4K |
| [Pixabay](https://pixabay.com/api/docs/) | Yes, free | Stock footage and motion backgrounds |

MotionBGs has no API, so Lumora reads its listing pages. Many of its wallpapers are fan-made from games, anime and films, so keep them on your own desktop.

Paste keys into **Settings → Video Sources** or straight into the Discover tab. They are stored locally and never bundled with the app. Check each source's license before using a video outside your own desktop.

## Performance

The **Performance** tab shows Lumora's CPU and memory, the system's GPU load and details about the current video, such as codec, resolution and whether it's hardware-decoded. It also gives hints when a clip is heavier than it needs to be.

If a clip runs above 30 fps, is larger than your display or uses a codec without hardware decoding, Lumora offers **Optimize This Video**. It re-encodes the clip to HEVC at up to 30 fps and your display's resolution, without audio. A 4K clip at 60 fps on a MacBook display ends up with less than half the decoding work. The same action is in the clip's context menu, and **Settings → Optimize Library** handles all clips at once.

Because macOS does part of the decoding and drawing in its own services, Lumora's process alone doesn't tell the whole story. The **impact test** measures the whole Mac for 10 seconds while playing and 10 seconds while paused and shows the difference. Sampling only runs while the tab is open.

## Screen saver

Open the **Screen Saver** tab, click **Install** and pick Lumora under **System Settings → Screen Saver**. Then choose which videos it should play.

macOS runs third-party screen savers in a sandbox that can't see Lumora's library. Lumora therefore hard-links the selected videos into the installed `Lumora.saver` bundle, which the screen saver can always read. Hard links take no extra disk space.

macOS keeps a separate screen saver for each display. With several screens, select Lumora for each one in System Settings.

## Animated lock screen

macOS only animates its own Aerial wallpapers on the lock screen, and there is no public API for anything else. Lumora therefore steps in for one of them:

1. Download any Aerial in **System Settings → Wallpaper**.
2. In Lumora's **Lock Screen** tab, pick that Aerial and click **Set Up**. Lumora keeps a backup of Apple's original. From macOS 27 on, Aerials live in your own Library and no password is needed. On macOS 14 and 15 they're in a system folder, so macOS asks for your password once and Lumora takes ownership of that single file.
3. Choose the same Aerial as your wallpaper in System Settings.

From then on the lock screen plays whatever is on your desktop and follows every change, converted to HEVC when needed. **Restore Apple's Video** puts the original back. While this is on, Lumora doesn't set a still desktop picture, since that would replace the Aerial.

This relies on how macOS stores Aerials internally, which has already moved once (from `/Library/Application Support/com.apple.idleassetsd` to `~/Library/Application Support/com.apple.wallpaper/aerials` in macOS 27). If macOS downloads the Aerial again, Lumora puts your video back automatically, or asks for the password again on older systems.

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
- `Lumora-X.Y.Z.pkg` for MDM deployment
- `Lumora-X.Y.Z.zip` and `appcast.xml` for [Sparkle](https://sparkle-project.org), which the app uses to update itself

The app reads the feed from `releases/latest/download/appcast.xml`, so updates need the repository to be public. Updates are signed with an EdDSA key. The private key lives in the `SPARKLE_PRIVATE_KEY` repository secret, and the public key is `SUPublicEDKey` in `project.yml`. Without the secret, releases are still published, just without the update feed.
