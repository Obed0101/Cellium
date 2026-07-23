# Changelog

All notable changes to Cellium are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows semantic versioning where practical.

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
