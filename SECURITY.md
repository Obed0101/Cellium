# Security Policy

## Supported versions

Cellium is currently pre-1.0. Security fixes are developed against the latest `main` branch and the latest tagged release.

| Version | Supported |
|---|---|
| Latest release | Yes |
| Older releases | Best effort |
| Development snapshots | Best effort |

## Reporting a vulnerability

Please report suspected vulnerabilities privately through [GitHub Security Advisories](https://github.com/Obed0101/Cellium/security/advisories/new). Include a concise description, affected commit or release, reproduction steps and the potential impact. GitHub will keep the report restricted while it is being triaged.

Do not open a public issue for an unpatched vulnerability. Do not include passwords, signing credentials, private battery history, database files or full device identifiers in a report.

## Security boundaries

Cellium is intended to:

- read power and thermal signals without writing hardware settings;
- keep history on the local machine;
- avoid accounts, analytics and remote services in the monitoring core;
- use explicit consent and allowlists for future automation;
- degrade to an unavailable state when a sensor is missing or invalid.

Changes that add network access, privileged helpers, arbitrary command execution, unrestricted filesystem access or silent data collection require a security review before merge.

## Release hygiene

Before a public release, maintainers should run tests, inspect the final diff for secrets, verify entitlements and signing configuration, and confirm that release artifacts were built from the intended tag.
