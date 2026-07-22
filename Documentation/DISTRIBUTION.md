# Distribution

## Local DMG

The repository includes `Scripts/build-dmg.sh`, which builds the native Xcode app and creates a standard macOS disk image containing:

- `Cellium.app`
- an `Applications` alias for drag-to-install

Run it from the repository root:

```bash
./Scripts/build-dmg.sh
open Distribution/Cellium-0.1.2.dmg
```

The script targets Apple Silicon by default and uses an unsigned Release build for local testing. Override the build settings when a Developer ID identity is available:

```bash
CODE_SIGNING_ALLOWED=YES \
CODE_SIGNING_REQUIRED=YES \
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
./Scripts/build-dmg.sh
```

Signing and notarization credentials must stay outside the repository. The script refuses to overwrite an existing disk image and leaves its isolated temporary staging directory for the operating system to clean up.

## GitHub releases

`.github/workflows/release.yml` runs for tags matching `v*`, builds the same DMG on a macOS runner and uploads it to the corresponding GitHub Release. Create the release from a protected `main` commit after CI has passed.

## Update checks

The app checks `https://api.github.com/repos/Obed0101/Cellium/releases/latest` only when the user enables automatic checks or presses **Check now** in Settings. It compares semantic versions, shows the public release page when an update exists and never installs an artifact without an explicit user action.
