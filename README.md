# Paste-Back (v2)

Select any region of your screen and get the **usable** form of what's in it —
real clickable links, exact text, the data behind it — not a flat picture.
"Anything you can see, you can use."

Vision & strategy: **`project2.md`** (source of truth). This README covers the build.

## Status

| Milestone | State |
|-----------|-------|
| M0 — Foundation (v2-first) | ✅ built + self-test green |
| M1 — AX ground-truth harvest (the moat) | ✅ built; manual AX acceptance pending |
| M2 — Action chips + intent routing | ⬜ next |
| M3 — Download-video action | ⬜ roadmap |
| M4 — Shared interactive asset + provenance | ⬜ roadmap |

## Architecture

```
Native overlay capture (rect-aware) → CGImage + captureRect + sourceApp
   ├─ OCRService (Vision)        floor — always runs
   └─ AXHarvester (rect ∩ tree)  enrichment — real hrefs/text/structure when available
        → merge (AX preferred) → CapturedScreenshot → entities → clipboard / HUD chips
```

Key idea: **AX is enrichment over an OCR floor.** When the app exposes an
Accessibility tree (native, web, most Electron), we recover ground-truth links and
exact text; when it doesn't (Figma canvas, games, video, remote desktop), we fall
back to OCR silently. `CapturedScreenshot.canonicalText` prefers AX text over OCR.

## Build & run (no Xcode required)

```sh
./scripts/build.sh        # SPM build + assemble PasteBack.app
./scripts/run.sh          # build + launch
```

Menu-bar agent (no Dock icon). Default hotkey **⌃⌥⌘7** (rebindable in Settings).
Two scary permissions: **Screen Recording** (native capture) and **Accessibility**
(AX harvest). Both degrade gracefully — decline Accessibility and you get OCR-only.

For stable permission grants across rebuilds, create a self-signed `PasteBack Dev`
code-signing cert (see `scripts/build.sh` header); else it ad-hoc signs.

## Verification

- **Headless:** `"$(swift build --show-bin-path)/PasteBack" --selftest`
  (OCR → entity → pasteboard; AX-preference; settings persistence).
- **AX coverage probe:** `… --axprobe` — focus an app within 4s; prints the roles,
  ground-truth URLs, and text it recovers. Measures coverage on your real apps.
- **M1 acceptance (manual):** in Safari/Chrome, lasso a link whose visible text is
  truncated/styled → click **First URL** → paste → it should be the *exact* href,
  not the visible text. Then lasso something in Figma/a video → confirm it silently
  falls back to OCR.

## Source layout

`Sources/PasteBack/{main, AppDelegate, Models/, Capture/, OCR/, Accessibility/,
Entities/, Pasteboard/, HUD/, Settings/, Onboarding/, MenuBar/}`.
