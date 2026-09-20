# Precis QA and Release Readiness Checklist

## Functional QA
- Feed add flow works for direct feeds, site pages, YouTube pages, and subreddit URLs.
- Feed parsing is reliable across RSS, Atom, and JSON Feed payloads.
- Article list reflects unread, read, starred, and read-later states correctly.
- Summary generation works on-device and degrades gracefully when unavailable.
- Background refresh updates unread state and available article counts reliably.
- CloudKit sync preserves feed and read-state information across Mac ownership.

## Accessibility review
- VoiceOver labels are present for all controls.
- Dynamic Type remains readable across article and summary layouts.
- Keyboard navigation supports list and reading traversals.
- Contrast remains strong in both light and dark mode.

## Performance review
- Feed refresh does not block the main thread.
- Summary generation runs off the UI thread.
- Search remains responsive for local article libraries.
- App remains usable on Apple Silicon hardware under expected load.

## Release gate
- No Intel-only code paths are accidentally shipped.
- AI features degrade gracefully with clear user messaging.
- All network access is explicit and safe.
- App Sandbox and Mac App Store assumptions are respected.
- Privacy claims remain accurate and transparent.
- Visual design remains distinct and aligned with the marginalia identity.
