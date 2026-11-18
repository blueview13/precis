# Precis App Features

This document describes the features implemented in the Precis macOS app, based on the application source and its in-app Help. Product specifications and build plans also mention ideas that are not yet part of the shipped app; those are called out separately at the end.

## What Precis does

Precis is a Mac RSS and Atom reader. It collects subscriptions in one place, organizes incoming articles, and provides a focused reading view with summaries and tools for following coverage across sources. The app targets Apple Silicon and macOS 26 or later.

## Subscriptions and feed organization

- Add a feed by entering or pasting a feed or website URL. Precis can offer a URL detected on the clipboard and can browse suggested feeds by category.
- Discover feeds from supported site URLs, including YouTube channel and subreddit sources, through feed discovery.
- Refresh feeds manually or on a configurable background schedule. Feed parsing, fetching, deduplication, and refresh scheduling are handled by dedicated services.
- Import and export subscriptions using OPML.
- Organize feeds into regular categories, or leave them uncategorized. Categories can be renamed, recolored, and deleted; deleting a category can preserve its feeds.
- Create Smart Categories from nested rule groups. Rules can match article title, content, author, feed, category, read state, starred state, and publication date. Groups support all/any matching.
- Use feed context menus to refresh, rename, move, or delete feeds. Feedbin feeds additionally support tag management and unsubscribe actions.
- Fetch and cache feed favicons and show unread counts in the sidebar when enabled.

## Reading and article management

- Read in a three-column workspace with a sidebar, headline list, and reading pane. A layout control switches the headline presentation, and the sidebar can be hidden or shown.
- Filter the headline list with its search field, choose the default sort order, and configure thumbnails and related-story stacking.
- Mark articles read or unread, star or unstar them, and navigate the list with keyboard shortcuts. Opening a headline marks it read.
- Related-story groups connect coverage from different feeds. Their source strip can be expanded to inspect other articles in the group.
- The reading pane presents article content in a configurable width and typeface, with optional images and reading-time estimates. Content is sanitized for display without rewriting the stored feed HTML.
- Open article links in Precis's in-app browser or choose another browser, including the macOS default. The in-app browser can attempt to accept common cookie banners.
- Share article links with the macOS share menu when available.

## Summaries and language tools

- Generate concise article summaries automatically on open or manually from the summary card. Automatic generation can be disabled in Settings.
- Summaries use Apple's on-device Foundation Models when available. A local deterministic summarizer provides a fallback path when the model is unavailable; the app does not require a configured cloud AI account.
- Related coverage can be summarized as a digest, with a short synthesis and key takeaways where supported.
- Translate article text into a selected target language using Apple's Translation framework. macOS may need to download language models on first use.
- Read article or summary text aloud using a selected macOS voice.

## Story clustering

Precis groups articles that appear to cover the same story across feeds. Clustering uses local article evidence such as title and content terms, named entities, event signals, and semantic similarity, with story review support. These groups power related-story navigation and contribute to cross-source coverage in newspaper editions.

## Newspaper PDFs

Create a newspaper-style PDF covering articles from the last 24 hours for a selected feed, category, or Smart Category. The edition builder selects and lays out stories, can feature a lead story, reports progress while it builds, and saves the resulting PDF to a chosen location.

## Desktop headline panel

An optional compact panel can sit at the left or right edge of the desktop and show headlines from selected feeds or Smart Categories. Settings include its width, colors, opacity, and article limit; the panel can also be resized by dragging its edge.

## Accounts, sync, and local data

- Connect Feedbin to manage subscriptions and tags through the service.
- Connect The Old Reader for subscription integration.
- Precis stores feeds, articles, summaries, categories, and reading state in its local SwiftData-backed store.
- CloudKit sync support is present in the codebase for supported app data.

## Notifications and system integration

- Enable notifications for new articles; macOS controls the permission prompt.
- Precis includes an App Intent integration for selected app actions.
- Use keyboard shortcuts for article navigation, read/star toggles, Settings, and Help.

## Preferences and accessibility of the interface

Settings cover theme, interface language, reading font and width, browser choice, translation language, speech voice, article-list options, summary behavior, refresh interval, notifications, accounts, OPML, and desktop panel appearance and sources. The interface has English, German, Simplified Chinese, Hindi, Spanish, Arabic, French, Bengali, and Brazilian Portuguese choices; Arabic uses a right-to-left layout.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| Space | Open the next article |
| Up / Down | Move through headlines |
| D | Toggle read status |
| S | Toggle star status |
| Command-comma | Open Settings |
| Command-question mark | Open Help |

## Scope notes

The source tree contains planning documents with additional proposals. This feature overview does not treat arbitrary cloud AI providers, RSS.app feed generation, read-later queue, Siri headline-reading workflows, or cross-device tab handoff as current app features. Confirmed implementation details can evolve; this document is a codebase snapshot and should be updated as features change.
