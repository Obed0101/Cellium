# Cellium Platform Constraints

## Verified environment

- Host: Apple Silicon `arm64`.
- macOS: `26.5.2` / build `25F84`.
- Xcode: `26.3` / build `17C529`.
- Swift: Apple Swift `6.2.4`.
- Swift target: `arm64-apple-macosx26.0`.
- macOS SDK: `26.2`.
- No simulator runtimes installed; they are not required for the macOS MVP.

These values describe the current development machine only. Compatibility must be feature-gated and tested on supported hardware.

## Hard constraints

- The MVP does not require root.
- The MVP does not install kernel extensions or privileged launch daemons.
- Cellium does not write SMC keys or control fans.
- External commands are not used as a normal sensor sampler.
- Shortcuts automation is optional, allowlisted and disabled until explicit user consent.
- WeatherKit is optional; with it disabled, normal operation performs zero network requests.
- Exact watts per process are not treated as a public macOS capability.
- Intel is not promised until a separate hardware matrix exists.

## API and sensor variability

`IOPowerSources`, `AppleSmartBattery`, SMC/IOReport, process data and power-limit capabilities can vary by Mac model and OS version. Every adapter must expose capability and quality, and missing data must degrade to `unavailable` without blocking the app.

`ProcessInfo.thermalState` is the official thermal-state signal. It must not be replaced with an alarm based on one heuristic temperature threshold. Battery temperature and ambient weather are separate signals.

## Lifecycle constraints

The coordinator must respond to power transitions, Low Power Mode, thermal changes, sleep/wake and panel visibility. Sleep gaps are recorded; missing samples are not reconstructed by integrating across sleep.

## Distribution constraints

Developer ID + Hardened Runtime + notarization is the preferred public distribution route while IOKit/sandbox requirements are validated. `SMAppService.mainApp` is the launch-at-login path. Signing/notarization credentials must never be committed or printed.

## Resource constraints

- No render loop or animation while the panel is closed.
- No 1 Hz background polling.
- Sensor reads are coalesced by one coordinator.
- SQLite writes are batched and retention-limited.
- Large branding backgrounds remain reference material unless a visible screen requires one.
- Instruments on hardware is the source of truth for CPU, memory, wakeups and energy.
