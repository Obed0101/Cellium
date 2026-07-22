# Contributing to Cellium

Thanks for helping improve Cellium. The project is early-stage, so small, well-tested changes are easier to review than broad rewrites.

## Before you start

1. Search existing issues and pull requests.
2. Open an issue for a new feature or a behavior change before investing in a large patch.
3. Never include credentials, signing files, database exports, private telemetry or machine-specific secrets.

## Development workflow

1. Fork the repository and create a focused branch from `dev`.
2. Make the smallest change that solves the problem.
3. Add or update tests for behavior that can be tested in isolation.
4. Run the relevant checks locally:

   ```bash
   swift test
   swift build --product cellium
   ```

5. Open a pull request against `dev` and describe the user-visible effect, validation performed and any platform limitations.

## Code guidelines

- Prefer clear Swift over clever abstractions.
- Keep macOS-specific reads inside `CelliumDarwin` adapters.
- Treat missing, invalid or device-specific sensor values as unavailable; do not silently substitute zero.
- Preserve the read-only and least-privilege boundaries described in `Documentation/THREAT_MODEL.md`.
- Keep UI changes native, accessible and respectful of Reduce Motion.
- Do not add network access, privileged helpers or automation without a documented user-facing reason and an explicit review of the trust boundary.

## Pull requests

Pull requests should have one purpose, a clear title and passing CI. Include screenshots or recordings for meaningful UI changes, and call out changes to permissions, data collection, persistence or release behavior.

## Reporting security issues

Please do not report vulnerabilities in a public issue. Follow [SECURITY.md](SECURITY.md) instead.
