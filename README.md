# Paste-Back

Select any region of your screen and get the **usable** form of what's in it —
real clickable links, exact text, the data behind it — instead of a flat picture.
**"Anything you can see, you can use."**

## What it does

A screenshot throws away everything the screen knew: links become pixels,
selectable text becomes an image, structured data becomes a flat grid. Paste-Back
*de-flattens* a region of your screen — it reconstructs the real, structured
content behind the pixels and puts it on your clipboard, ready to use.

Lasso a region and you get back:

- **Real hyperlinks** — the actual destination, not the visible text
- **Exact, copyable text** — selectable even from apps that won't let you select
- **Detected entities** — URLs, emails, phone numbers, addresses, dates, code, file paths
- **The image itself**, when a picture is what you want

A floating chip strip lets you act on the capture right away — open a link,
reveal a file, or copy any representation.

## How it works

Paste-Back reads more than pixels. When an app exposes an Accessibility tree
(native apps, browsers, most Electron apps), it recovers ground-truth links and
exact text straight from the app. When it can't (canvas apps, games, video,
remote desktop), it falls back to on-device OCR.

OCR is the floor that always runs, so you always get a result; Accessibility is
enrichment layered on top, so you get a *better* result whenever the structure is
available.

## Getting started

Paste-Back runs as a menu-bar app (no Dock icon). Press the capture hotkey
(default **⌃⌥⌘7**, rebindable in Settings), drag to select a region, and the
result lands on your clipboard.

It uses two macOS permissions:

- **Screen Recording** — to capture the selected region
- **Accessibility** — to recover real links and exact text

Both degrade gracefully: decline Accessibility and you still get OCR-based capture.
