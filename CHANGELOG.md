# Changelog

All notable changes to Cellium are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows semantic versioning where practical.

## [0.1.11] - 2026-07-24

### Added

- GitHub release updates can download, verify and install the signed release package after an explicit user action.
- Release automation now publishes an updater ZIP alongside the drag-to-Applications DMG.

### Changed

- History navigation loads only the data required by the selected page and avoids repeated derived-data work while scrolling.
- Removed the visible clear-alerts and clear-intelligence-log controls from the history and alerts surfaces.

## [0.1.10] - 2026-07-24

### Added

- Expanded AI evidence with the Mac model, macOS version, architecture, Cellium version, local date/time, timezone, UTC offset, weekday and daylight-saving state.
- Added weather-location timezone context with a macOS timezone fallback, plus a seven-day estimated computer-use profile with active hours, typical schedule, peak hour and hourly CPU/memory activity.
- Exposed additional Battery Plan and intelligence evidence for charge limits, external-power pauses, cycle pace, EFC usage and confidence details.

### Changed

- Process names sent in AI evidence are anonymized while preserving process kind, CPU, memory and estimated battery impact.
- AI instructions now keep health, hardware cycle count, EFC and computer-activity estimates separate, avoid unsupported damage claims and respect insufficient history.
- Battery history, cycle-plan presentation and deterministic local insight behavior now expose more evidence without clamping equivalent use at 100%.

## [0.1.9] - 2026-07-24

### Added

- Local Battery Plan with estimated equivalent full cycles (EFC), measured hardware-cycle deltas, personal pace baselines, weekly budgets and confidence-aware forecasts.
- SQLite schema v4 storage for 15-minute and daily cycle-usage buckets, tracker state and idempotent backfill from retained battery samples.
- Cycle-usage history, plan controls and elevated/critical pace alerts that distinguish heavy use from confirmed battery damage.
- Cycle pace and deterministic local classifications in the evidence supplied to battery intelligence.

### Fixed

- Assistant Markdown now preserves paragraph separation and renders headings, lists, quotes and code as independent blocks instead of joining sentences.
- Equivalent battery use is no longer visually capped at 100%, so values such as `1.59 EFC` appear as `159%`.

## [0.1.8] - 2026-07-23

### Added

- Historical Computer use navigation with selectable days and range-aware hourly timelines.
- Multi-day Computer use charts with compact hourly bars and localized date labels.
- Local battery intelligence with chat sessions, analysis history and encrypted provider secrets.
- Wi-Fi-aware intelligence setup and expanded battery, system and process telemetry.

### Fixed

- 24-hour Computer use charts no longer render future or unused hours.
- Seven-day ranges no longer collapse into a single 24-hour average.
- Intelligence analysis loading, local secret storage and SQLite schema migrations.
- macOS release bundles now include valid ad-hoc signatures for local distribution.

## [0.1.0] - 2026-07-22

### Added

- Native macOS menu bar application foundation.
- Read-only battery, thermal and power-source adapters.
- Local SQLite storage and package-level test coverage.
- Initial dashboard with battery summaries and compact trend charts.
- Public documentation, security policy and contribution workflow.

### Notes

- This is an early MVP release.
- Apple Silicon is the validated development target.
- Charge automation, exact per-process wattage, WeatherKit and notarized distribution are not part of this release.
