# Precis — Project Guidelines

## Build and Test

- Generate the Xcode project from `project.yml` with `xcodegen generate` after adding/removing source or resource files (the `.xcodeproj` is generated, not hand-edited).
- Build: `xcodebuild -project Precis.xcodeproj -scheme Precis -destination 'platform=macOS' build`
- Test: `xcodebuild -project Precis.xcodeproj -scheme Precis -destination 'platform=macOS' test`

## Keeping Help in Sync

Whenever a user-facing feature, context menu item, or keyboard shortcut is **added, changed, or removed**, update the matching Help article in the same change:

- `Precis/Help/GettingStarted.md` — getting-started flows (adding feeds, categories, reading/marking).
- `Precis/Help/RightClickMenus.md` — every right-click menu item, using its exact UI label.
- `Precis/Help/HeaderIcons.md` — header-bar icon buttons and what each one does.
- `Precis/Help/KeyboardShortcuts.md` — the shortcuts table.

Help articles are bundled `.md` files rendered by `Precis/Views/HelpWindowView.swift`. Use exact menu labels from the code, keep entries to a one-line explanation, and leave out features that are not implemented. To show a UI icon in an article, embed its SF Symbol with `{{icon:symbol.name}}` (e.g. `{{icon:newspaper}}`), matching the symbol used in the code.
