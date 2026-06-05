# Paste-Back v2: Core Vision Document

> A base document for implementing the evolved concept. This supersedes the
> framing in `project.md` (which scoped a screenshot-OCR-paste utility). The
> product underneath is bigger and sharper than "screenshots that paste as text."

---

## 1. The product in one sentence

**Select any region of your screen and get the *usable* form of what's in it —
clickable links, real copyable text, the file you're looking at, the data behind
a chart, a downloadable video — instead of a flat picture of it.**

Behavioral hook: **"Use this, don't screenshot it."**

Headline value prop: **Anything you can see, you can use.**

---

## 2. The core idea: de-flattening

A screen is the *final rasterized frame* of an enormous amount of structured
state — DOM nodes, hyperlinks, file paths, process metadata, vector art, live
data feeds, document models. Rasterizing it throws almost all of that away.

**"Flat" is not the truth of the environment — it's the truth of human vision.**
The machine still knows (or can re-derive) the structure underneath.

So the product's real job is not OCR. It is **de-flattening**: reconstructing,
re-deriving, or augmenting the structure that the pixels used to have — and
handing the user the thing they actually wanted, not a screenshot of it.

Three questions organize the entire idea space:

1. **Where does the lost structure come from?** → sources of recoverable context
2. **What can we reconstruct from it?** → the entity / object catalog
3. **What does the user actually want to *do*?** → actions, not just representations

---

## 3. The vacuum logic — why this space is open

**The felt pain (universal, many times a day):** *Your screen is full of things
you can see but can't touch.* A URL inside a video. A code on a screen-share. An
error you need to act on. A phone number in an image a friend sent. A table in a
dashboard with no export. Text in an app that won't let you select. Every one is
the same micro-defeat: *I can see it, so I should be able to use it — but I can't,
so I retype it, rebuild it, or give up.*

**Why nobody owns this:** the primitives are all mature, free, public APIs
(Apple Vision OCR, the Accessibility API, `NSDataDetector`, multi-representation
`NSPasteboard`), but **nobody has assembled them around the "visible but trapped"
job.** Everyone built adjacent things:

- **macOS Live Text / Apple Vision** — selectable text in images, viewer-side
  only, Apple platforms only, no "do something with it" layer.
- **Windows Snipping Tool / PowerToys Advanced Paste** — post-capture OCR and
  "paste as X," but as separate actions on existing content, no understanding of
  *what* you selected, no entity routing.
- **CleanShot X / Shottr / Xnapper** — capture tools; OCR is a side feature,
  entities are used only for redaction/beautification, output is plain text.
- **Raycast Clipboard History** — replays formats the *source* already supplied;
  can't generate structure from a fresh visual capture.
- **Rewind.ai** — acquired and shut down (Dec 2025); the "smart screen" category
  is unusually open.

**The gap, precisely:** no shipping product treats *region selection as the
universal "I want this" gesture* and returns the **real, structured, actionable
thing** — using both live OS introspection and pixel inference — and lets that
travel to other people.

**The commoditization risk** (Apple/MS shipping OCR or a "copy text from image"
menu) is real — which is exactly why the moat must NOT be OCR. See §5.

---

## 4. Core focus — and what this is NOT

**Core focus:** the bridge across the "visible but trapped" gap. Selection is the
gesture; the clipboard (and later, actions/sharing) is the bus; de-flattening is
the engine; *"use this, don't screenshot it"* is the behavior change.

**This is NOT** (say no out loud — these blur the one job):

- an annotation / markup tool
- a screenshot beautifier / background-adder
- a clipboard-history manager
- a general "AI that summarizes your screen"
- a Rewind-style always-on archive

The discipline: one job done so well it becomes a reflex. Everything else is an
expansion of *the same* job, added only after the habit exists (see §9).

---

## 5. The moat — why this is defensible

### 5a. Live harvest beats inference (the core technical edge)

At capture time, on the user's own machine, **we have access to far more than
pixels.** OCR is the fallback for what we *can't* introspect. Fidelity hierarchy:

1. **Accessibility (AX) tree** — `AXUIElement` API, system-wide, one permission,
   no per-app integration. Hit-test the lassoed rect → real elements with real
   `AXURL` hrefs, exact text (not OCR-guessed), roles, table structure.
2. **App / window metadata** — frontmost app, window title, owning process.
3. **Live-app interrogation** — browsers expose the current tab URL; terminals
   expose `cwd`; editors expose the open file path (via automation dictionaries).
4. **Pixels (OCR + vision)** — the universal floor: games, remote desktop, video,
   anything *received* from someone else.

This is the durable advantage. Anyone working from pixels alone — including
Apple's "copy text from image" or the recipient of a normal screenshot — is
strictly weaker than us-at-capture-time.

**Coverage is a gradient, not a guarantee** (design for this honestly):

| Source type | What AX gives | Strategy |
|---|---|---|
| Native AppKit/SwiftUI | Rich, mostly free | Prefer AX |
| Web in browsers | Often excellent, incl. real link URLs | Prefer AX (may need a nudge in Chrome) |
| Electron (Slack, VS Code, Discord) | Web-like, variable | Prefer AX, verify |
| Custom-drawn / canvas (Figma, games) | Little/nothing | OCR fallback |
| Remote desktop / video | Nothing | OCR fallback |

**Architecture rule: AX-first enrichment over an OCR floor.** OCR always runs and
guarantees a result. AX *upgrades* the same capture when available (real href
instead of guessed URL, exact text instead of recognized text). Per-app
"enhancers" (e.g. grab the browser tab URL) are optional sugar, never required.

### 5b. The screenshot as a self-describing container

Embed the harvested structure as a sidecar layer in the shared asset (the way a
PDF carries selectable text under the visual). **The recipient gets a live object
even though they only received "an image"**: hover reveals links, click downloads
the embedded video, text is selectable, tables export — all because the structure
traveled with the picture. Adds two properties normal screenshots can't have:

- **Provenance** — "captured from `youtube.com/…` at 14:03." Tamper-evident,
  verifiable captures: receipts, evidence, support tickets, journalism, moderation.
- **Recipient-chosen representation** — sender clicked "Image," but the asset
  carries text/links/data too; the recipient pulls whatever *they* need.

### 5c. The recognizer ecosystem (long-term)

A registry of "when a capture contains X, offer action Y" — community-contributed,
like ad-block filter lists but for screen entities. Ship a strong general model +
a few sharp first-party verticals; let the long tail be an ecosystem. Hard to
clone, compounds over time.

---

## 6. The two product surfaces

1. **Live capture (capturer's machine):** rich context available → AX harvest,
   live-app interrogation, ground-truth de-flattening. Best solo experience.
2. **Shared asset (recipient's machine):** only pixels survive *unless we embedded
   structure*. The interactive container (§5b) makes a shared capture a live mini
   document. The viral / collaboration loop.

---

## 7. Chips are *actions*, not just representations

The current HUD changes the clipboard. The bigger product: **a chip is an action
an agent performs.** Not "here's the download link" but "✓ downloaded to
~/Downloads," "✓ added to your calendar," "✓ filed the Linear ticket from this
error," "✓ opened the PR."

**Intent is inferred from the selection itself** — geometry of the lasso +
foreground app + dominant entity → predict the single most-likely action and make
it the primary chip:

- Tight lasso around a video player → **Download video**
- Lasso a code block → **Copy as code** / **Run**
- Lasso an address → **Directions**
- Lasso a table → **Export CSV**

The HUD becomes a *predicted-intent* menu, with representations as fallback rows.

---

## 8. Example features — the entity / object catalog

Organized by the action each implies. This is the breadth to draw from; ship a
few razor-sharp ones first, not all of them.

**Media & assets**
- Video embed (YouTube/Vimeo/Loom) → download / open at timestamp / copy timestamped link
- `<img>` → recover *original-resolution* source (not the rendered thumbnail);
  reverse-image-search; "save original"
- Audio player, GIF, embedded PDF, downloadable file links

**Dev & technical**
- Stack trace → jump to `file:line` in your editor, or the GitHub permalink for that commit
- Git diff → apply as patch; terminal command → re-run / explain; package
  (`npm`/`pip`/`brew`) → the install command; JSON/SQL/curl → format / run / import
- Screenshot of a **GitHub PR / Jira / Linear / Google Sheet** → recognize the
  *chrome* visually, read the visible ID, **reconstruct the deep link** even if the
  URL bar isn't in the shot (a DM'd ticket screenshot → click → real ticket opens)

**Data & quantitative**
- Chart/graph → extract the underlying **data series** → CSV / re-plot / trend &
  anomaly analysis
- Table → typed structured data; math → LaTeX / solve / Wolfram; color palette →
  CSS vars; font sample → identify + install link

**Commerce & finance**
- Product → price-track / find cheaper; invoice/receipt → line items → accounting/CSV;
  price → currency convert; crypto address → explorer

**People, place, time**
- Profile card / email signature → vCard / CRM enrich; address → map pin + directions;
  map → coordinates + "open Maps at this viewport"; date/flight/itinerary → calendar
  (timezone-aware) / flight status; boarding pass / QR / barcode → decode

**Language & docs**
- Foreign text → translate in place; citation → BibTeX; form → fillable fields

**Defensive**
- API keys / tokens / passwords / PII → **warn before you share** + offer redaction

**Speculative / generative**
- Reconstruct original SVG of a logo; super-res a low-res capture; capture a UI →
  working HTML/React clone (design-to-code from a region); semantic diff of two
  captures ("what changed in this dashboard between 9am and 5pm")
- Capture-gated spatial memory: every capture → entity-indexed searchable corpus
  ("find that error I shot last week") — Rewind's value without always-on recording

---

## 9. The expansion path (one job, ever-widening)

You never re-pitch. You only widen what "use" means:

1. **Now:** "use this" = the real structured content on your clipboard.
2. **Sharing:** "use this" extended to the *recipient* (interactive asset, §5b).
3. **Agentic chips:** "use this" where *use* = *do it for me* (§7).
4. **Recognizer ecosystem:** more kinds of "things" the selection understands (§5c).

---

## 10. Beachhead

The *frame* is universal, but aim the first 1,000 users where the pain is most
acute and most frequent: **developers and support / CS people.** They live in
errors, codes, URLs buried in tickets, terminals, and screen-shares all day. Same
product, same pitch — point the demo at error→editor/ticket and download-the-thing.
(The phone-number-in-an-image moment sells the mass market later.)

---

## 11. What already exists (v1 foundation)

Built and verified (see `README.md`, `project.md` Weekends 1–4):

- macOS menu-bar agent, **SPM + bundle script build (no Xcode required)**
- Global hotkey via Carbon (**⌃⌥⌘7**, rebindable) — no dependency, no Accessibility needed
- Region capture (shell-out + native overlay), Apple Vision OCR (line-level)
- Entity detection (`NSDataDetector` + regex), multi-representation `NSPasteboard`
  (PNG / text / RTF+HTML with links / entity sub-pastes), floating HUD chip strip,
  Settings, onboarding

**The v2 leap from here:**

1. Add an **AX-harvest layer** alongside OCR, feeding the same capture model;
   prefer AX fields when present (real hrefs, exact text, structure). OCR stays the floor.
2. Reframe chips from **representations → predicted actions** with intent inference.
3. (Later) the **shared interactive asset** + provenance container.

---

## 12. Open decisions (to settle before/while building v2)

1. **Wedge:** one killer vertical done perfectly (dev/support) vs. the general
   "de-flatten anything" platform. (Recommendation: universal frame, dev/support beachhead.)
2. **Next surface:** AX ground-truth live capture vs. the shared interactive asset.
   (Recommendation: AX first — it strengthens the solo experience and is the moat.)
3. **Clipboard vs. agent:** do chips paste, or do they *act*? (Recommendation: start
   pasting, add high-confidence single actions like "download video" / "open ticket.")
4. **Inference location:** on-device deterministic first; cloud LLM only for the
   "explain / analyze / clone" tier (cost, latency, privacy).
5. **Recognizer strategy:** resist regex sprawl — one strong vision/LLM recognizer
   plus 3–4 razor-sharp verticals beats 40 brittle detectors.

---

**The test that the framing holds:** a 30-second demo where someone watches a few
captures and goes *"oh, I need this."* If a feature doesn't serve that moment for
the beachhead, it waits.
