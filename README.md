<div align="center">
  <img src="Branding/Cellium_Branding_Assets/07_Backgrounds/Cellium_Hero_02_1920x1080.png" alt="Cellium emerald signal banner" width="960">

  <p><strong>Native macOS battery telemetry for people who want useful power data without a cloud dashboard.</strong></p>

  <p>
    <a href="https://github.com/Obed0101/Cellium/actions/workflows/ci.yml"><img src="https://github.com/Obed0101/Cellium/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
    <a href="https://github.com/Obed0101/Cellium/blob/main/LICENSE"><img src="https://img.shields.io/github/license/Obed0101/Cellium" alt="MIT license"></a>
    <a href="https://github.com/Obed0101/Cellium/releases"><img src="https://img.shields.io/github/v/release/Obed0101/Cellium?display_name=tag" alt="Latest release"></a>
  </p>
</div>

Cellium is an early-stage, native macOS menu bar application that collects read-only battery and system power signals, presents them clearly, and keeps history local. It is designed to be calm, transparent and conservative about what macOS can actually report.

## Why Cellium

- **Native first** — built with Swift and AppKit/SwiftUI for the macOS menu bar.
- **Local by default** — no account, cloud sync, analytics or remote LLM.
- **Read-only sensors** — no SMC writes, kernel extensions or privileged helpers.
- **Honest data** — unavailable or device-specific values remain unavailable instead of becoming fabricated precision.
- **Inspectable code** — the core, Darwin adapters, store and automation boundaries are separate Swift packages.

## Current capabilities

- Battery percentage, charging state and power-source snapshots.
- Thermal-state and Low Power Mode signals where macOS exposes them.
- Local SQLite storage for samples and trends.
- A native dashboard with compact charts and status summaries.
- Explicit boundaries for future automation and optional integrations.

Cellium is still an MVP. Exact per-process wattage, Intel compatibility, charge automation, WeatherKit and distribution notarization are not promised by the current release.

## Requirements

- macOS 14 or later.
- Xcode with Swift 6 toolchain for development.
- Apple Silicon is the currently validated development target. Intel support is not yet a compatibility promise.

## Quick start

```bash
git clone https://github.com/Obed0101/Cellium.git
cd Cellium

# Run the package test suite.
swift test

# Build the command-line product.
swift build --product cellium
```

To run the menu bar application, open `Cellium.xcodeproj` in Xcode and launch the `Cellium` scheme. Code signing and notarization are intentionally outside the local development quick start.

## Install from a DMG

Build the standard macOS drag-to-Applications installer locally:

```bash
./Scripts/build-dmg.sh
open Distribution/Cellium-0.1.2.dmg
```

The disk image contains `Cellium.app` and an `Applications` shortcut. The default build is unsigned for local testing; Developer ID signing and notarization can be supplied through the script environment when release credentials are available. Tagged GitHub releases use the same packaging workflow.

## Updates

Cellium can optionally check the public GitHub Releases API once per day. The setting is disabled by default, and the app never downloads or executes a remote binary automatically. Enable it from **Settings → Updates**, or use **Check now** for a manual check.

## Architecture

```text
macOS power APIs
        │ read-only adapters
        ▼
CelliumDarwin
        │ validated snapshots
        ▼
CelliumCore ─── CelliumStore ─── local SQLite history
        │
        ├── CelliumApp
        └── CelliumAutomation (explicit, allowlisted actions)
```

See the [platform constraints](Documentation/PLATFORM_CONSTRAINTS.md), [sensor matrix](Documentation/SENSOR_MATRIX.md), [threat model](Documentation/THREAT_MODEL.md) and [branding policy](Documentation/BRANDING.md) for implementation boundaries.

## Privacy and security

Cellium is designed to operate without network access during normal battery monitoring. It does not need an account and does not collect window titles, document content, keyboard input, screenshots or full device serials. Optional capabilities must be user-facing, allowlisted and feature-gated.

Read [SECURITY.md](SECURITY.md) before reporting a vulnerability. Do not put credentials, private telemetry, database exports or signing material in an issue or pull request.

## Contributing

Contributions are welcome while the project is being shaped. Read [CONTRIBUTING.md](CONTRIBUTING.md), use the `dev` branch as the integration target, keep pull requests focused and run the test suite before opening a PR.

## Project status

The `main` branch is the stable public branch. Active development happens on `dev`. The project is intentionally conservative: a sensor or feature is not considered ready merely because a value can be read once on one Mac.

## Star history

[![Star History Chart](https://api.star-history.com/svg?repos=Obed0101/Cellium&type=Date)](https://star-history.com/#Obed0101/Cellium&Date)

## License

Cellium is available under the [MIT License](LICENSE).
