# Precis Design System

## Design principles

1. The app reads as a reading tool rather than a dashboard. The interface should feel quiet, deliberate, and text-first.
2. AI summaries are treated as marginal notes beside the article instead of as a detached chat panel.
3. The sidebar, list, and reading pane should feel specific to Precis and not like Mail.app or a generic news client.

## Color palette

- paper: #F3F0E8
- ink: #211F1A
- marginalia: #3C5A45
- flag: #A8672B
- rule: #D8D2C2
- surface: #EAE6DA

Dark mode uses a deliberate counterpart palette instead of a naive inversion, with a warm near-black base and lighter paper-like foregrounds.

## Type hierarchy

- title: serif, 32pt, semibold
- headline: sans, 18pt, semibold
- body: sans, 15pt, regular
- metadata: sans, 12pt, medium
- caption: sans, 11pt, medium

## Layout rules

- Keep the reading pane centered and narrow enough for comfortable article flow.
- Reserve a side column for marginalia summaries so the content remains the primary reading focus.
- Use understated surfaces and clear spacing to keep the interface calm and typography-led.
- Treat summary annotation as the visual accent, not the app chrome.

## Implementation guidance

This system is intentionally quiet around the summary so the summary remains the standout element when opened in the reading pane.
