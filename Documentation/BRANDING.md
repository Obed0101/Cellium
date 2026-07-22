# Cellium Branding Policy

Cellium uses a compact, geometric identity built around a seven-cell symbol for battery telemetry and stability. The public repository includes only the project-owned, production-facing artwork required for the README and application surfaces; internal source references and design workspaces are intentionally excluded.

## Public assets

- `Branding/Cellium_Branding_Assets/01_Master_Logo/Cellium_logo_horizontal_brand_4096.png` — README banner artwork.
- `Branding/Cellium_Branding_Assets/01_Master_Logo/Cellium_logo_horizontal_brand.svg` — scalable brand lockup.
- `App/Resources/Cellium_symbol_white.svg` — application menu-bar symbol.
- `App/Resources/Assets.xcassets/` — application icon resources.

The symbol and composition were reconstructed for Cellium. The wordmark is outlined artwork; no font files are distributed with the project.

## Usage rules

- Preserve the seven bars, their order, geometry and proportions.
- Keep clear space around the lockup.
- Do not add shadows, glow, 3D, glass, metal, gradients or taglines to the logo.
- Use the monochrome symbol as a template image in `NSStatusItem`.
- Keep decorative emerald effects in backgrounds or content surfaces, never inside the primary logo.

## Product direction

The product UI should feel native, precise, calm and technical. It should not become a generic AI dashboard, gamer interface or glass-heavy marketing surface.

- Product UI: SF Pro.
- Metrics and changing values: SF Mono or monospaced digits.
- State transitions: short 120–180 ms transitions.
- No animation while the popover is closed.
- Respect Reduce Motion with fade or immediate state replacement.

## Color tokens

| Token | Hex | Usage |
|---|---|---|
| `background` | `#0A130F` | Primary dark background |
| `surface` | `#0D1F19` | Panel surface |
| `surfaceElevated` | `#112820` | Elevated card/control |
| `border` | `#23352C` | Low-contrast separators |
| `foreground` | `#D9DBCC` | Primary text |
| `muted` | `#8C998F` | Secondary text |
| `accent` | `#9FB08E` | Calm emphasis |
| `accentStrong` | `#C1D2B2` | Strong emphasis |
| `atmosphereEmerald` | `#55F28C` | Decorative/positive atmosphere |
| `atmosphereTeal` | `#37C9B2` | Decorative/positive atmosphere |
| `warning` | `#E0A84B` | Warning state |
| `critical` | `#E40014` | Critical state |
| `info` | `#86A9C3` | Informational state |

The dark palette is the primary product expression. Light appearance must remain legible and use system-provided contrast behavior.
