# Lumora

Live video wallpapers for macOS. Drop in your own clips and Lumora plays them behind your desktop icons — on every display, on every Space.

- Lives in the menu bar, no Dock icon
- Seamless looping with hardware decoding
- Pauses automatically when the desktop is hidden, the screen is locked or the Mac sleeps
- Optional pause on battery and in Low Power Mode
- Sets the first frame as your regular desktop picture, so Mission Control and the lock screen match

Requires macOS 15 or later on Apple Silicon.

## Building

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open Lumora.xcodeproj
```

Every push to `main` is built by GitHub Actions. The app is attached to the workflow run as `Lumora.zip`.

## Installing a CI build

1. Open the latest successful run under **Actions** and download the `Lumora` artifact.
2. Unzip it, then unzip the `Lumora.zip` inside. GitHub wraps the file once more.
3. Move `Lumora.app` to `/Applications`.

CI builds are ad-hoc signed but not notarized by Apple. On first launch macOS shows *“Apple could not verify ‘Lumora’ is free of malware…”*. Pick one of these to allow it:

**System Settings**

1. Try to open Lumora once and close the warning with **Done**.
2. Go to **System Settings → Privacy & Security** and scroll down to the Security section.
3. Click **Open Anyway** next to the message about Lumora and confirm with your password.

**Terminal**

```sh
xattr -dr com.apple.quarantine /Applications/Lumora.app
```

This removes the quarantine flag that macOS adds to downloaded files. Run it on the app at its final location. If you move or re-download the app, do it again.

Either way you only need to do it once per build. Signed and notarized releases will make this step unnecessary.
