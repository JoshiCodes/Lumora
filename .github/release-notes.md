Open the disk image and drag Lumora into Applications.

This build isn't notarized yet, so macOS will refuse the first launch. Open **System Settings → Privacy & Security** and click **Open Anyway**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/Lumora.app
```

