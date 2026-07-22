# Cellium Threat Model and Safety Baseline

**Scope:** S0 discovery baseline; this is a design gate, not a claim that the future app has completed a security audit.

## Assets

- Local battery history and health trend.
- Bundle identifiers/categories used for optional attribution.
- Device capability information.
- User preferences and charge strategy.
- Shortcut action history.
- Local SQLite database and exports.
- Release artifacts and update channel.

## Trust boundaries

```text
macOS hardware/system APIs
        ↓ read-only adapters
CelliumDarwin
        ↓ validated Sendable snapshots
CelliumCore / Store / Intelligence
        ↓ explicit user action only
CelliumAutomation → allowlisted Apple Shortcuts
```

The UI and CLI are not trusted to bypass validators. Automation is not allowed to decide policy; it executes an already-approved action.

## Threats and controls

| Threat | Category | Control | Release gate |
|---|---|---|---|
| Malformed or missing IOKit values | Tampering / availability | Range validation, quality state, no zero fallback | Sensor fixtures pass |
| SMC write path accidentally introduced | Elevation / tampering | Read-only protocol, no write symbols, code audit | Blocking |
| Arbitrary shell/Shortcut execution | Injection | Fixed executable path, allowlisted args, no interpolation, timeout | Blocking |
| Shortcut changes wrong charge limit | Tampering | Consent, allowed values 80/85/90/95/100, post-action verification, audit | Blocking |
| Serial/path leakage in logs | Information disclosure | `os.Logger` privacy, redaction, no serial by default | Blocking |
| Process attribution captures content | Privacy | Opt-in bundle/category only; no title/document/path/text | Blocking |
| Symlink/path escape in DB/export | Tampering | Controlled Application Support path, canonicalization and safe file handling | Blocking |
| Corrupt/locked/full DB | Availability | Actor, migrations, rollback-safe recovery, diagnostics | Blocking |
| Malicious or unverified update | Supply chain | Developer ID, notarization, signed update verification | Release blocking |
| Excessive polling creates battery drain | Availability/resource | Central coordinator, energy regression gates, sleep cancellation | Release blocking |
| Network/WeatherKit leaks history | Information disclosure | Weather opt-in, no history upload, zero requests when off | Blocking |

## Entitlements baseline

The initial local build should request no privilege beyond what the app target requires. Do not add:

- root/helper privilege;
- kernel/system extension entitlements;
- unrestricted filesystem access;
- arbitrary automation access at startup;
- network capability for the battery monitor core.

Potential capabilities are enabled only in the phase that needs them and only after a user-facing explanation:

- notifications for useful recommendations;
- location/WeatherKit only if Weather is enabled;
- launch at login through `SMAppService` after explicit preference;
- process context only when attribution is enabled.

## Safe process policy

The only planned external command is `/usr/bin/shortcuts`, and only for a closed set of Cellium-owned shortcut names or an explicitly validated parameter. Every invocation must capture exit code, stdout, stderr, timeout and cancellation. Output is redacted before diagnostics.

No shell string is constructed from remote, database, UI text or model output.

## Privacy defaults

- No account.
- No cloud or remote LLM.
- No analytics or telemetry.
- No window titles, document names, keyboard, screenshots or content.
- No full serial export.
- No process list collection unless the user opts into attribution.
- Explicit export and delete-all-data operations.

## Safety test plan

Before enabling any automation or public release:

1. Run with a normal user account.
2. Exercise missing/invalid sensors.
3. Exercise DB locked, corrupt and disk-full states.
4. Exercise shortcut missing/error/timeout/unverified states.
5. Inspect process list for unexpected helpers.
6. Inspect logs and export for serials, paths and user data.
7. Run sleep/wake and Low Power tests.
8. Run Instruments energy regression tests.
9. Verify signature, entitlements and notarization status.

## S0 decision

The MVP is approved to proceed with read-only discovery and later sensor/UI implementation. Charge automation, WeatherKit, process attribution and distribution remain feature-gated and cannot silently expand the privilege or data boundary.
