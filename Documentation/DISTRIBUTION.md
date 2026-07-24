# Distribution

## Local DMG

The repository includes `Scripts/build-dmg.sh`, which builds the native Xcode app and creates a standard macOS disk image containing:

- `Cellium.app`
- an `Applications` alias for drag-to-install

Run it from the repository root:

```bash
./Scripts/build-dmg.sh
open Distribution/Cellium-0.1.9.dmg
```

The script targets Apple Silicon by default and signs the complete app bundle ad hoc for local/free distribution. This produces a valid bundle, but it is **not Apple-verified or notarized**. On the first launch, macOS may require **System Settings → Privacy & Security → Open Anyway**.

For a downloaded app that is known to come from this repository, the quarantine attribute can also be removed explicitly:

```bash
xattr -dr com.apple.quarantine "/Applications/Cellium.app"
open "/Applications/Cellium.app"
```

`xattr` only removes macOS's download quarantine for that copy; it does not make the app trusted or notarized. Use it only for an artifact you intentionally downloaded.

When a Developer ID identity is available, use it instead of ad-hoc signing:

```bash
SIGNING_MODE=developer-id \
CODE_SIGNING_ALLOWED=YES \
CODE_SIGNING_REQUIRED=YES \
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
./Scripts/build-dmg.sh
```

Apple notarization is the online Apple security check that lets Gatekeeper accept a Developer ID-signed app without the manual **Open Anyway** step. It requires Apple Developer credentials; signing and notarization credentials must stay outside the repository.

The script refuses to overwrite an existing disk image, verifies the app bundle and DMG, and leaves its isolated temporary staging directory for the operating system to clean up.

## GitHub releases

`.github/workflows/release.yml` runs for tags matching `v*`, builds the same valid ad-hoc-signed DMG on a macOS runner and uploads it to the corresponding GitHub Release. This free workflow does not claim Apple verification or notarization; users may need **Open Anyway** or the `xattr` command above. Create the release from a protected `main` commit after CI has passed.

## Update checks

The app checks `https://api.github.com/repos/Obed0101/Cellium/releases/latest` only when the user enables automatic checks or presses **Check now** in Settings. It compares semantic versions, shows the public release page when an update exists and never installs an artifact without an explicit user action.
