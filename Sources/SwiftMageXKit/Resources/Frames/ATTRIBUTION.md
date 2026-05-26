# Bundled device frames — attribution

The bezel PNGs in this directory are vendored from third-party projects whose
licenses permit redistribution. They are loaded at runtime via `Bundle.module`
and surfaced through `DeviceFrameCatalog`.

| File | Source | License | Notes |
| --- | --- | --- | --- |
| `iphone-6.5-pommeplate-spacegray.png` | [PommePlate](https://github.com/ephread/PommePlate) — *iPhone XS Max / 11 Pro Max Space Grey* | [CC0 1.0 Universal](LICENSE-PommePlate.txt) | 1411×2840, RGBA. Maps to the ASC `iphone-6.5` slot. **Derivative** of the upstream PNG: a rounded-rectangle screen cutout was punched at `x=40, y=29, w=1332, h=2781, r=103` because PommePlate renders the screen as a flat fill on top of the bezel rather than as a transparent hole, and SwiftMageX's `frameScreenshot` requires the latter. Reproduce with `scripts/punch-rounded-rect.swift` (see commit history). CC0 dedicates the work to the public domain, so derivatives carry no additional licence obligation. |

CC0 places the work in the public domain — no attribution is legally required —
but the LICENSE file is preserved alongside the assets as a courtesy and so that
the chain of provenance is auditable for downstream redistributors.

## Adding a new frame

1. Drop the PNG into this directory. It MUST carry an alpha channel and have a
   transparent rectangle where the screen goes.
2. Append an entry to `frames.json` matching the existing schema.
3. Add a row above (and reference the upstream license file if the asset is
   sourced from a third party).
4. Update `Tests/SwiftMageXKitTests/DeviceFrameCatalogTests.swift` so the new
   entry is exercised.

The catalog is intentionally decoupled from `ASCDeviceCatalog` — a device id may
have zero, one, or many bundled frames. The `deviceID` field on each entry maps
back to an `ASCDeviceSize.id`.
