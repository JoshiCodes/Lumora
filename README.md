# Lumora

Live video wallpapers for macOS. Bring your own clips or find new ones on Pexels and Pixabay, and Lumora plays them behind your desktop icons on every display and every Space.

- **Now Playing:** live preview of what's on your desktop, with pause, stop and scaling
- **Library:** drag and drop your own videos, rename them, filter them
- **Discover:** browse and search Pexels and Pixabay, preview a clip and set it as your wallpaper in one click
- **Screen Saver:** a matching screen saver that plays videos from your library, also on top of the lock screen
- Lives in the menu bar, with a Dock icon only while the window is open

Requires macOS 15 or later on Apple Silicon.

## Easy on the battery

- One decoder for all displays. Every screen and the in-app preview share the same player.
- Audio tracks are dropped before playback, so nothing is decoded that you can't hear.
- Downloads pick the smallest file that still covers your display instead of always grabbing 4K.
- Playback stops while the desktop is hidden behind full-screen apps, while the screen is locked, asleep or showing the screen saver, and optionally on battery or in Low Power Mode.
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

You only need to do this once per version.

## Video sources

Discover uses the free APIs from [Pexels](https://www.pexels.com/api/) and [Pixabay](https://pixabay.com/api/docs/). Each needs a personal API key, which you paste into **Settings → Video Sources** or straight into the Discover tab. Keys are stored locally and are never bundled with the app.

## Screen saver

Open the **Screen Saver** tab and click **Install**. Then pick Lumora under **System Settings → Screen Saver** once. After that, choose which videos it should play.

macOS runs third-party screen savers in a sandbox, so Lumora hard-links the selected videos into the screen saver's container. This takes no extra disk space. The first time, macOS may ask whether Lumora can access data from other apps. Allow it.

A truly animated lock screen like Apple's Aerials isn't possible with public APIs. While the Mac is locked and idle, the screen saver plays on top of the lock screen, and the lock screen picture itself matches the first frame of your wallpaper.

## Building

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open Lumora.xcodeproj
```

## Releases

Every push to `main` is built and tested by GitHub Actions. If `MARKETING_VERSION` in `project.yml` hasn't been released yet, the workflow creates a GitHub release `vX.Y.Z` with the disk image attached. To publish a new version, bump the number and push.
