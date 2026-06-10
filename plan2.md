# plan2.md — From prototype to product: the Trust Loop (P0) + Table→CSV flagship (P1)

> Companion to `project2.md` (vision) and `STATE.md` (candid state). This is the
> staged execution plan for the next arc of work. The thesis it implements:
> **the capture tech is proven; what's missing is trust, legibility, and habit.**
> A user must be able to see what was captured, recover from a wrong capture,
> get back to an old capture, survive onboarding, and trust that the first
> capture in any app works. Then we crown it with one demo-grade flagship
> action (Table→CSV) instead of more catalog breadth.
>
> Stages are ordered by dependency and leverage. Each is a weekend-sized chunk
> with its own "definition of done" — shippable on its own, no stage requires a
> later one. Written 2026-06-10.

---

## The product problem each stage attacks

| # | Stage | Problem it kills |
|---|-------|------------------|
| 1 | HUD result legibility (preview + inspector) | "Did it get the thing I wanted?" is unanswerable until paste time |
| 2 | Escape hatch (revert + recall) | A wrong capture costs a re-lasso; the HUD is gone forever once dismissed |
| 3 | Capture history | Clipboard overwrite destroys the perfect capture from 10 minutes ago |
| 4 | Staged permissions onboarding | Two scary TCC prompts before any value → install funnel dies |
| 5 | AX reliability + honest degradation | "Second capture works" kills the magic; silence reads as failure |
| 6 | Table→CSV (P1 flagship) | Six okay actions don't sell; one psychic one does |

Cross-cutting rule for all stages: **no new TCC permissions, no network, no
accounts.** Everything below is local and deterministic.

---

## Stage 1 — HUD result legibility: payload preview + expandable inspector

**Goal:** the HUD answers "what did I get?" at a glance, and "show me
everything" on demand. This is the single highest-leverage change in the plan.

### 1a. Payload preview line (compact strip)

Add a one-line summary *above* the chip row in `ChipStripView`:

```
"Sign in to your account or create…"  ·  14 lines · 3 links · 2 entities   [AX] from Arc      ⌄
```

- First ~60 chars of `canonicalText` (or `"Image only"` when text is empty).
- Counts derived from the capture: text lines, link entities, other entities.
- A **source badge**: `AX` (ground truth), `OCR` (pixels only), or `AX+OCR` —
  this is the moat made visible, and it sets up Stage 5's honest degradation.
- App name from `CaptureSource.appName`.
- A chevron (`⌄`) affordance to expand (1c).

**Implementation**
- New `Sources/PasteBack/HUD/CaptureSummary.swift` — pure struct computed from
  `CapturedScreenshot`: `previewText`, `lineCount`, `linkCount`, `entityCount`,
  `sourceBadge` (`.ax`/.`ocr`/`.mixed`, derived from `axText.isEmpty` /
  `canonicalText` choice), `appName`. Pure + testable in `--selftest`.
- `HUDViewModel` gains `@Published var capture: CapturedScreenshot?` and
  `summary: CaptureSummary?`. The HUD currently only receives `[CaptureAction]`;
  thread the capture itself through: `AppDelegate`/coordinator already has it in
  `onCaptured`, so change `HUDPanelController.show(actions:selectedID:)` to
  `show(capture:actions:selectedID:)`.
- `ChipStripView`: a `VStack` — preview row on top (smaller, `.secondary`),
  chip row below. Keep `.fixedSize()` and the fresh-`NSHostingView`-per-show
  pattern (that's what fixed the clipping bugs; don't regress it).

### 1b. Inspector panel (expanded state)

Click the preview row / chevron (or press **Space** while the HUD is up) →
the panel expands in place into a small inspector (~480×360):

- **Text** section: the full `canonicalText`, scrollable, monospaced when a
  code/stack-trace entity is present. A copy button per section (avoid relying
  on text selection — see pitfalls).
- **Links** section: *every* link, not just the first — rows of
  `visible text → URL`, each with Open + Copy buttons. Sourced from `.url`
  entities (AX-seeded ones first; they're ground truth). This fixes the
  "first-URL lottery" — with 122 links in an Arc capture, "Open Link" guessing
  #1 is rarely right.
- **Entities** section: grouped chips (emails, phones, dates, addresses, ticket
  IDs, paths…), tap to copy, with the action where one exists (date → Add to
  Calendar etc., reusing the same closures `ActionResolver` builds).
- **Provenance** footer: app icon + name, page URL when known
  (`CaptureSource.url`), timestamp, capture size, source badge.

**Implementation**
- New `Sources/PasteBack/HUD/InspectorView.swift` (SwiftUI).
- `HUDPanelController`: an `isExpanded` state; on toggle, attach a fresh
  `NSHostingView` with `InspectorView` (same pattern as `show()`), call
  `positionPanel` keeping the panel's *bottom edge* anchored so it grows upward
  from the strip position.
- **Pause the auto-dismiss timer while expanded**; resume on collapse. The
  inspector is a deliberate "I'm reading this" mode.
- Keyboard: extend `handleKeyDown` — Space toggles expand; Esc collapses first,
  then dismisses; existing Tab/Return/1–9 keep working in both states.

### Pitfalls / decisions
- **Non-activating panel vs. interaction:** keep `.nonactivatingPanel` so focus
  never leaves the user's app. Buttons work without key status; selectable
  `NSTextView`s don't reliably. Decision: **copy buttons, not text selection**,
  in v1 of the inspector.
- **Sizing:** every state change attaches a fresh hosting view (the corner-clip
  lesson). Inspector gets a fixed frame, so no intrinsic-size surprises.
- Don't let the preview line make the *compact* strip taller than ~2 rows — it
  must stay glanceable.

### Verification
- `--selftest`: `CaptureSummary` from a fixture capture (counts, badge logic:
  AX text present → `.ax`; oversized-AX fallback → `.ocr`).
- Manual: capture in Arc → preview shows AX badge + link count; expand → all
  links listed with real hrefs; Esc collapses then dismisses; capture in Figma
  → OCR badge.

**Done when:** every capture shows what it got without a paste; the inspector
lists all links/entities; keyboard flow (Space/Esc/Tab/1–9) works; selftest
covers `CaptureSummary`.

---

## Stage 2 — Escape hatch: zero-cost wrongness

**Goal:** a wrong or prematurely-dismissed capture costs nothing.

1. **"Image" chip always present and always last** in the copy group — the
   universal revert. Audit `RepresentationBuilder.availableRepresentations` to
   guarantee `.image` is unconditional, and make `ActionResolver` pin it at the
   end of the chip list regardless of intent ranking (predictable position →
   muscle memory: "last chip is always the safe one").
2. **Recall the HUD**: menu-bar item **"Show Last Capture"** (above "Re-copy
   Last Capture As…" in `MenuBarController`) that re-runs
   `ActionResolver.resolve(lastCapture)` and re-shows the HUD/inspector.
   `CaptureCoordinator.lastCapture` already holds everything.
3. **Recall hotkey** (optional, settings-gated, default **⌃⌥⌘V** — left-hand
   reachable, mnemonic "view"): second Carbon hotkey via the existing
   `HotkeyManager(id:)` multi-hotkey support.

**Verification:** capture → dismiss HUD → menu/hotkey recall → identical chips
and inspector; clipboard untouched by recall until a chip is tapped.

**Done when:** dismissed ≠ gone; Image revert is always one predictable tap.

---

## Stage 3 — Capture history (captures-only, local, capped)

**Goal:** the app accumulates value instead of holding exactly one capture.
This is the retention surface and the safety net for clipboard overwrite.

**What it is NOT** (per `project2.md §4`): a clipboard manager. It records only
*our* captures, never the general pasteboard.

### Storage
- New `Sources/PasteBack/History/CaptureHistoryStore.swift`.
- Location: `~/Library/Application Support/PasteBack/History/<uuid>/` with
  `meta.json` + `capture.png` + `thumb.png` (~320px).
- `meta.json` via a **DTO** (`CaptureRecord: Codable`) — don't make the live
  model types Codable (`EntityType` has associated values; `CGImage` isn't
  Codable). Persist: id, timestamp, source (app/bundle/url), `ocrText`,
  `axText`, entities as `[{kind, value, sourceText, source}]` with a string
  `kind` (e.g. `"ticketID:JIRA"`, `"barcode:QR"`). Skip `axElements` (heavy,
  only needed live).
- Caps: default **20 captures** and **100 MB**, oldest-evicted. Mark the
  directory `isExcludedFromBackup`.
- Privacy controls from day one: Settings toggle **"Keep capture history"**
  (default ON, copy explains it's local-only), **Clear History** in the menu
  and Settings. History off → store is a no-op.

### Re-hydration
`CaptureRecord → CapturedScreenshot` (decode PNG → `CGImage`, entities back to
typed form; `captureRect`/`axElements` nil/empty). Re-hydrated captures flow
through the existing `ActionResolver`/`PasteboardWriter` unchanged — that's the
payoff of keeping the model central.

### UI
- **History window** (reuse the `WindowPresenter` pattern from Settings): a
  searchable list — thumbnail, preview line, app name, relative time. Row
  actions: **Re-copy as…** (submenu of available reps), **Show HUD**, **Delete**.
- Search filters over `canonicalText` + entity values (this is the seed of
  `project2.md §8`'s "find that error I shot last week").
- Menu bar: **"History…"** item (`⌘Y` equivalent within the window).

### Wiring
`CaptureCoordinator.process()` → after `onCaptured`, `historyStore.append(screenshot)`
(QoS utility queue; never block the capture path on disk I/O).

**Verification:** `--selftest` round-trips a `CaptureRecord` (encode → decode →
entities/text identical; eviction at cap). Manual: 3 captures → history shows
3 → re-copy an old one as RTF → paste has links → Clear History empties dir.

**Done when:** the last 20 captures are recoverable in any representation,
searchable, cap-enforced, and deletable — with history opt-out honored.

---

## Stage 4 — Staged permissions onboarding (show the delta, then ask)

**Goal:** a stranger's first five minutes survive TCC. Ask for one permission
up front, and attach the second request to a *visible, concrete loss*.

### Flow
1. **First run:** onboarding asks **only Screen Recording** (it's the one
   without which nothing works). One screen, one sentence of "why", one button.
   Remove the up-front Accessibility request from the first-run path
   (`PermissionsView` keeps both rows for the standalone Permissions window,
   but the *flow* stops after SR).
2. **First captures work immediately** — OCR floor. The product proves itself
   before asking for more.
3. **The AX upsell lives in the result:** when `hasAccessibility() == false`
   and a capture's OCR found ≥1 URL-shaped entity (or the capture came from a
   browser/Electron bundle ID), the HUD preview row (Stage 1) shows an extra
   accent chip:
   > ✨ **Get exact links** — 3 links here were guessed from pixels
   Tap → small explainer sheet → `requestAccessibility(prompt: true)` → after
   grant, offer "Re-capture" (just fires the normal capture flow).
4. **Frequency cap:** show the upsell at most once per app-launch, with a
   "Don't show again" affordance → `SettingsStore` flag
   (`axUpsellDismissed: Bool`, plus `hasCompletedOnboarding`).
5. **Regression detection** (the cert/TCC churn we personally hit): at capture
   time, if SR was previously granted but `hasScreenRecording()` is now false
   (signature change, OS revoke), show a notification-style alert linking to
   the Permissions window instead of failing silently into shell-out.

### Why this ordering is the moat made into onboarding
The architecture is "AX enrichment over an OCR floor" — this flow *is* that
sentence as UX. Nobody else can show a user exactly what a permission buys
using their own capture as the evidence.

**Verification:** `tccutil reset ScreenCapture com.pasteback.app && tccutil
reset Accessibility com.pasteback.app`, delete the settings flags, walk the
flow clean: SR prompt → capture works → upsell appears on a link-bearing
capture → grant → recapture shows the AX badge and real hrefs.

**Done when:** first value requires exactly one permission; the Accessibility
ask is contextual, evidenced, capped, and dismissible; revocation is detected
and explained.

---

## Stage 5 — AX reliability + honest degradation

**Goal:** the *first* capture in any app is the audition — make it pass, and
when AX genuinely can't help, say so instead of silently degrading.

1. **Nudge-and-retry for lazy web/Electron AX** (`STATE.md` gap #6): in
   `AXHarvester.harvest`, when the owning app is in the "web-view" class
   (browser/Electron bundle IDs, or a hit-test that finds an `AXWebArea`
   ancestor) and the walk yields 0 text elements, send the
   `AXManualAccessibility` nudge, wait ~200 ms, retry the walk **once**
   (bounded; we're already off-main in `CaptureCoordinator.process`). Log both
   attempts (`axRetry=1 elems 0→47`).
2. **Generalize the quirk table:** replace `shouldSkipAX`'s hardcoded Warp
   check with a data-driven `AppQuirks` struct
   (`Sources/PasteBack/Accessibility/AppQuirks.swift`):
   `skipAX: [bundle-substring]`, `needsNudge: [...]`,
   `oversizedLeafProne: [...]` (feeds the existing `canonicalText` guard).
   One place to grow per-app knowledge instead of scattered conditionals.
3. **Honest degradation in the HUD:** Stage 1's source badge gets a *reason*
   on hover/expand: "OCR only — Accessibility not granted" / "OCR only —
   <App> doesn't expose structure" / "OCR only — AX skipped for <App>".
   Plumb a small `AXOutcome` enum (`harvested(n)`, `noPermission`, `skipped`,
   `emptyTree`) from `harvestAX` through `CapturedScreenshot` (or sidecar) to
   `CaptureSummary`. Silence must never read as failure.
4. **Probe-driven regression list:** extend `--axprobe` to take a bundle list
   and print a coverage table (app → elems/links/retry-needed) so quirk
   entries are based on measurements, not vibes.

**Verification:** Chrome/Slack first-capture-after-launch yields elements
without a manual second capture (or logs the retry doing it); Figma capture
shows "OCR only — doesn't expose structure"; Warp shows "AX skipped".

**Done when:** zero known apps need a human-initiated second capture, and
every OCR-only result tells the user *why*.

---

## Stage 6 (P1) — Table→CSV: the flagship action

**Goal:** the 30-second demo. Lasso a table anywhere — a dashboard with no
export button, a web table, a finance UI — and paste it into a spreadsheet as
*data*. This is "de-flattening" made legible to non-developers, and AX gives
us ground truth most of the time.

### Detection ladder (fidelity order, same philosophy as text)

1. **AX structural truth.** Extend `AXHarvester.walk`: when an element with
   role `AXTable` or `AXOutline` intersects the rect, run a dedicated
   sub-harvest — rows (`AXRows`/children with role `AXRow`), cells
   (`AXCells`/children `AXCell`), header via `AXHeader`/`AXColumnHeaderUIElements`
   when exposed. Clip to rows intersecting the lasso (partial-table selection
   must work — that's the natural gesture). Reuse the existing depth/element
   caps and messaging timeout.
2. **AX geometry inference.** Many web "tables" are styled `div` grids with no
   table role. Infer from harvested leaves: reuse the Stage-"column-aware
   assembly" machinery (`clusterColumns` + row banding) and accept as a table
   when ≥2 columns × ≥3 rows align with consistent column intervals (≥80% of
   rows populate ≥2 columns).
3. **OCR floor.** Same geometry inference over `OCRLine.boundingBox` (convert
   Vision-normalized boxes to pixel space). Works on screenshots-of-tables,
   remote desktops, PDFs — the cases that sell the feature.

The three rungs all produce one type:

```swift
struct TableData {
    let headers: [String]?      // nil when no header row is distinguishable
    let rows: [[String]]        // rectangular; short rows padded with ""
    let source: EntitySource    // .ax or .ocr — show the badge here too
}
```

### Model & pipeline
- `CapturedScreenshot` gains `let tables: [TableData]` (default `[]` —
  additive, nothing breaks).
- New `Sources/PasteBack/Entities/TableRecognizer.swift` holding rungs 2–3
  (pure functions over `[AXElement]` / `[OCRLine]` → selftest-able without a
  screen). Rung 1 lives in `AXHarvester` (needs live AX calls) but returns the
  same `TableData`.
- `CaptureCoordinator.process()`: `tables = axTables ?? recognizer.infer(...)`,
  ladder short-circuits at the first rung that yields a confident table. Add
  `tables=NxM(src)` to the diagnostic log line.

### Output representations
- `Representation` gains `.csv` (and the markdown rep finally becomes real for
  tables: pipe-table from the same `TableData` — kills part of `STATE.md` gap #4).
- `RepresentationBuilder`: RFC-4180 CSV (quote fields containing `,` `"` `\n`;
  double embedded quotes; CRLF row endings). Also write **TSV to the plain-text
  flavor** when a table is primary — that's what Excel/Numbers/Sheets parse
  into cells on a bare ⌘V. (CSV-in-`public.utf8-plain-text` pastes as one
  column; TSV is the spreadsheet-native paste. The `.csv` rep is for explicit
  "Copy CSV".)
- `ActionResolver`:
  - Stateful copy chip **"Copy as Table (CSV)"** when `!capture.tables.isEmpty`,
    ranked first among copies (above code-first).
  - Intent chip **"Save CSV…"** — writes
    `~/Downloads/pasteback-table-<timestamp>.csv` and reveals in Finder
    (file-handoff pattern, same as `.ics`/`.vcf`; no save panel — a save panel
    would force activation and steal focus from a non-activating HUD).
  - Table presence counts as a "strong composite" (like QR/contact) so intent
    leads even for large selections.
- Inspector (Stage 1): a **Table** section rendering a mini grid preview with
  the row/column count and source badge — the trust loop applied to the
  flagship.

### Edge cases to handle (and test)
- Partial lasso of a long table → only intersecting rows.
- Merged/blank cells → pad to rectangular, never drop a row.
- Numeric alignment (right-aligned columns) — cluster on column *intervals*,
  not left edges only.
- Multi-column *prose* (the thing Stage "column-aware assembly" handles) must
  **not** be misread as a 2-column table: require short cell-like text runs
  (median cell length ≤ ~40 chars) and ≥3 aligned rows before claiming a table.
- A table plus surrounding prose in one lasso → table rep offered, text reps
  still built from full text.

### Verification
- `--selftest`: synthetic `AXElement` grid → `TableData` (rung 2); synthetic
  `OCRLine` grid (rung 3); CSV quoting matrix; TSV plain-text flavor when
  table-primary; the prose-vs-table false-positive fixture (two-column text
  from the Stage-reflow tests must yield **no** table).
- `test-fixtures/index.html`: add a real `<table>` card (pricing-style) and a
  `div`-grid card to the hosted test page.
- Manual demo run: lasso the web table → "Copy as Table" → ⌘V into Numbers →
  cells land correctly; lasso a *screenshot* of a table (image on the test
  page) → OCR rung produces the same; Save CSV → file in Downloads, revealed.

**Done when:** the 30-second demo works end-to-end on (a) a real web table,
(b) a styled div-grid, (c) a flat image of a table — and pasting into Numbers/
Sheets lands in cells, not one column.

---

## Sequencing, dependencies, and scope guards

```
Stage 1 (HUD legibility)  ──┬──► Stage 4 (onboarding upsell lives in the HUD)
                            ├──► Stage 5 (badge reasons surface in the HUD)
                            └──► Stage 6 (inspector Table section)
Stage 2 (escape hatch)    — independent, tiny; do immediately after 1
Stage 3 (history)         — independent of 1/2; needs only the model + WindowPresenter
Stage 6 (Table→CSV)       — only hard dependency is Stage 1's inspector for the preview;
                            the rep/chip work is independent
```

Recommended order: **1 → 2 → 4 → 5 → 3 → 6.** Rationale: 1+2 are the daily-feel
fixes; 4+5 make the app survivable for a stranger (and both plug into 1's HUD);
3 is self-contained and can slot anywhere; 6 lands last so the flagship ships
into a trust loop that can show it off. If eager for the demo, 6 can start
after 1 in parallel — `TableRecognizer` is pure and doesn't touch the HUD work.

**Explicitly out of scope for this plan** (tracked, not forgotten):
- Distribution (notarized DMG, Sparkle, launch-at-login, `Logger.swift` behind
  a debug flag) — the gate before *any* external user; schedule as its own
  stage right after Stage 6.
- Deep-link reconstruction (task #11) — strong second flagship; revisit after
  Table→CSV ships.
- Learned chip ranking / per-app defaults (P2), paste-side picker, M3 video,
  M4 shared asset, recognizer ecosystem.

**Scope guards (say no out loud):**
- History is captures-only — the moment it watches the general pasteboard,
  it's a clipboard manager (`project2.md §4` forbids it).
- The inspector is read-and-act, not edit — no annotation creep.
- Table extraction stays deterministic/on-device — no LLM rung in this pass.

## Cross-cutting: per-stage hygiene

For every stage: extend `--selftest` (it's the only CI we have), add a line to
the `/tmp/pasteback.log` diagnostics where pipeline behavior changed, update
`STATE.md` (gaps list + "what's built"), and keep `scripts/build.sh` (no-Xcode)
green — new files need no project surgery under SPM, so the only build risk is
new frameworks (none anticipated; everything here is AppKit/SwiftUI/Vision
already linked).
