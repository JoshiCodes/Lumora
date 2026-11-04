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

## Running a CI build

Builds are ad-hoc signed and not notarized, so Gatekeeper will block the first launch. After unzipping:

```sh
xattr -dr com.apple.quarantine Lumora.app
```

Then move it to `/Applications` and open it.
