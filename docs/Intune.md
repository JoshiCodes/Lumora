# Deploying Lumora with Microsoft Intune

Lumora ships everything an MDM needs: an installer package, a preference domain that can be locked with a profile, and a switch to turn off its own updater. This guide uses Intune, but the same files work with Jamf, Kandji, Mosyle and others.

**Requirements:** macOS 15 or later, Apple Silicon or Intel (the app is universal).

## 1. Install the app

Every [release](../../../releases) contains `Lumora-X.Y.Z.pkg`. Pick one of two ways to get it onto Macs.

### Option A: Upload the package (recommended)

1. **Apps → macOS → Add → macOS app (PKG)**.
2. Upload `Lumora-X.Y.Z.pkg`.
3. **Included apps** should list `com.joshicodes.Lumora` with the release version. Intune uses it to detect the install.
4. Leave the pre- and post-install scripts empty. The package already quits a running copy before installing and starts Lumora for the logged-in user afterwards.
5. Assign it to your device group as **Required**.

The package is not signed with a Developer ID. That's fine for this app type: Intune's *macOS app (PKG)* accepts unsigned packages, and apps installed by a package don't get the quarantine flag, so Gatekeeper doesn't block the first launch. The older *macOS line-of-business app* type requires a signed package and won't work.

To roll out a new version, upload the new package to the same app.

### Option B: Shell script that follows GitHub releases

If you'd rather not upload every release:

1. **Devices → macOS → Shell scripts → Add**.
2. Upload [`deploy/intune/install-lumora.sh`](../deploy/intune/install-lumora.sh).
3. Run as signed-in user: **No**. Script frequency: e.g. **Every 1 day**.

The script compares the installed version with the latest release and only downloads when there's a newer one. The repository has to be public for this.

## 2. Configure it

Lumora reads its settings from the preference domain `com.joshicodes.Lumora`. Anything set through a profile wins over the user's choice and shows up greyed out in the app.

1. **Devices → macOS → Configuration → Create → Templates → Preference file**.
2. Preference domain: `com.joshicodes.Lumora`.
3. Upload [`deploy/com.joshicodes.Lumora.plist`](../deploy/com.joshicodes.Lumora.plist) after removing the keys you don't want to lock.

| Key | Type | Effect |
| --- | --- | --- |
| `DisableUpdates` | Boolean | Turns off Lumora's built-in updater. Set this when Intune delivers new versions. |
| `LaunchAtLogin` | Boolean | Registers or removes Lumora as a login item on every launch. |
| `pauseOnBattery` | Boolean | Pause while running on battery. |
| `pauseInLowPowerMode` | Boolean | Pause in Low Power Mode. |
| `pauseWhenCovered` | Boolean | Pause while the desktop is hidden, e.g. behind full-screen apps. |
| `pauseWhenIdle` | Boolean | Pause when nobody has used the Mac for a while. |
| `idleMinutes` | Integer | Minutes until the user counts as away. |
| `pauseWhenHot` | Boolean | Pause while macOS reports a serious thermal state. |
| `respectReduceMotion` | Boolean | Show a still picture while Reduce Motion is on. |
| `optimizeNewClips` | Boolean | Convert added videos to HEVC at up to 30 fps and display resolution. |
| `rotationMinutes` | Integer | Change the wallpaper every n minutes. `0` turns rotation off. |
| `rotationShuffle` | Boolean | Pick the next wallpaper at random. |
| `scaling` | String | `fill`, `fit` or `fitBlurred`. |
| `matchDesktopPicture` | Boolean | Set the clip's first frame as the regular desktop picture. |

## 3. Allow the login item

Since macOS 13 users can switch off login items in System Settings, and macOS shows a notification when an app adds one. To keep Lumora allowed without that notification, deploy a managed login item rule:

- **Settings catalog:** *Login → Service Management - Managed Login Items*, rule type **Bundle Identifier**, value `com.joshicodes.Lumora`.
- Or upload [`deploy/Lumora.mobileconfig`](../deploy/Lumora.mobileconfig) as a custom profile. It contains both the settings above and the login item rule.

## Good to know

- **Per-user content.** Each user's library lives in `~/Library/Application Support/Lumora`. The app doesn't ship with videos, so users add their own or pick from Discover.
- **Screen saver and lock screen** are set up by each user from the Lock Screen tab. On macOS 27 and later the animated lock screen needs no administrator rights. On macOS 14 and 15 it asks for an administrator password once, which standard users don't have.
- **Network.** Discover talks to `motionbgs.com`, `api.pexels.com` and `pixabay.com`. The updater, if not disabled, reads from `github.com`.
- **Uninstalling.** Delete `/Applications/Lumora.app` and, per user, `~/Library/Application Support/Lumora` and `~/Library/Screen Savers/Lumora.saver`.
