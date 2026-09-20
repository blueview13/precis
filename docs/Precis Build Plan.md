# Precis Build Plan

## 1. Objective

Build a native macOS RSS reader for Apple Silicon Macs that delivers:

- fast, offline-first feed reading
- on-device AI summaries using Apple Intelligence / Foundation Models
- a distinct visual identity built around the marginalia metaphor
- a focused product tailored to the macOS-only market
- a clean path to App Store distribution, CloudKit sync, and future expansion

This plan turns the technical specification into a staged engineering roadmap and implementation sequence.

---

## 2. Product Strategy and Scope

### 2.1 Core product thesis

Precis is not a generic RSS client with AI bolted on. It is a reading-first app whose key differentiator is that summaries are treated as annotations beside the article, not as a detached chatbot panel.

The MVP should prioritize:

- feed ingestion and reading
- a polished reading experience
- on-device summarization
- smart folders and search
- macOS-native sync and background refresh
- a clear visual identity that looks distinct from generic reader apps

### 2.2 MVP target

The first shipped version should include:

- add feeds by URL or paste website URL
- YouTube/subreddit auto-discovery
- OPML import/export
- nested folders and smart folders
- article list and reading pane
- on-device summarization with default short length
- App Sandbox compliance
- CloudKit sync for feeds/folders/read-state on Mac-to-Mac
- background refresh and dock unread badge
- built-in browser
- full-text search
- star/read-later features
- cloud fallback provider architecture

Later phases (v2+) can add clustering, more advanced personalization, widget work, and deeper Siri/Spotlight integration.

---

## 3. Delivery Principles

1. Design is part of product definition, not a post-launch polish pass.
2. Preserve app privacy: the default AI path is local, cloud is explicit opt-in.
3. Keep background work off the UI thread.
4. Treat macOS 26+/Apple Silicon as design constraints from day one.
5. Build a clean architecture that supports swap-in providers and future features without refactoring core models.

---

## 4. Project Setup and Foundation

### Step 1: Initialize the Xcode project

Tasks:

- create a new macOS app project in Xcode
- target platform: macOS 26 minimum, Apple Silicon only
- set bundle ID and app metadata
- enable App Sandbox and required entitlements
- configure signing and Mac App Store readiness assumptions
- add Swift Package Manager dependencies

Required packages:

- FeedKit
- likely a small utility package for async networking or date handling if needed
- future additions for AI provider abstraction and CloudKit helper code if they remain internal

Outputs:

- working Xcode project
- signed but not yet shipped build configuration
- package manifest with dependencies

### Step 2: Set up the app architecture skeleton

Create the major application layers:

- App entry / lifecycle
- UI layer (SwiftUI + AppKit bridge points)
- Data layer (SwiftData / Core Data abstraction)
- Services layer (feed sync, parsing, AI, CloudKit)
- Utilities layer (logging, errors, formatting, date conversion)

Create the initial folder structure:

- App/
- Models/
- ViewModels/
- Views/
- Services/
- Persistence/
- AI/
- Sync/
- Background/
- Utilities/

Outputs:

- clean project structure
- basic dependency graph
- service boundaries ready for implementation

### Step 3: Define the data model

Implement the core entities from the spec:

- Feed
- Folder
- Article
- Summary
- Story (future placeholder)

Add initial fields and relationships:

- Feed: id, title, url, faviconData, folderId, muted, lastFetched
- Folder: id, name, parentFolderId, smartFolderQuery
- Article: id, feedId, title, author, publishedDate, link, rawContent, extractedContent, isRead, isStarred, imageURL
- Summary: id, articleId, tldr, bulletPoints, generatedBy, generatedAt

Decide whether to use:

- SwiftData for local persistence with CloudKit sync constraints in mind, or
- Core Data if CloudKit sync behavior becomes too limiting

Recommended initial path:

- use SwiftData if the app architecture can keep sync mapping straightforward
- keep the persistence layer abstracted enough to switch if needed

Outputs:

- working model schema
- migration-ready data model
- repository layer for feed/article CRUD operations

---

## 5. Design System and UI Foundation

### Step 4: Establish the visual design system

Before implementation, produce a short design plan and review it against the spec.

Required outputs:

- palette definitions
- type hierarchy
- layout rules
- one or two distinguishing principles

Design principles to lock in:

1. The app reads as a reading tool, not a generic dashboard.
2. AI summaries are presented as marginal notes, not chat output.
3. The sidebar, article list, and reading pane should feel specific to Precis and not like standard Mail.app/News app chrome.

Required tokens from the spec:

- paper: #F3F0E8
- ink: #211F1A
- marginalia: #3C5A45
- flag: #A8672B
- rule: #D8D2C2
- surface: #EAE6DA

Dark mode must get a deliberate counterpart palette, not a naive inversion.

### Step 5: Build the core layout skeleton

Create the base UI shells:

- main window layout
- sidebar/favicon spine
- article list
- reading pane
- compact two-pane mode

Requirements:

- article list should use typographic differentiation rather than repeated card-style blocks
- reading pane should center text and reserve space for a marginal summary column
- keep the app visually quiet around the summary so the annotation remains the standout element

### Step 6: Design validation loop

Treat screenshots as a required artifact during development.

Checklist:

- review in light mode and dark mode
- test at several window sizes
- confirm the marginalia concept is clearly legible
- verify the UI is not generic or AI-dashboard-like
- fix design issues before moving to major feature expansion

Outputs:

- screenshot set for design review
- approved design baseline

---

## 6. Feed Ingestion and Parsing

### Step 7: Implement feed discovery and validation

Create a feed intake service that supports:

- direct RSS/Atom/JSON feed URLs
- pasted website URLs
- auto-discovery via <link rel="alternate">
- YouTube channel URL detection
- subreddit URL detection
- optional RSS.app integration behind a toggle

Implementation flow:

1. user enters URL or webpage URL
2. service normalizes input
3. candidate feed detection runs
4. feed URL is validated and parsed
5. feed metadata is stored
6. initial article set is imported

### Step 8: Integrate FeedKit

Use FeedKit as the canonical parser.

Tasks:

- add FeedKit via Swift Package Manager
- wrap parser calls in a feed service abstraction
- normalize feed entries into internal Article models
- handle malformed or partial feeds defensively
- handle timestamps, author fields, image URLs, and links consistently

Implementation responsibilities:

- parse RSS, Atom, JSON Feed uniformly
- map feed metadata to internal model objects
- preserve raw content and extracted content separately
- handle video, audio, and HTML content safely

### Step 9: Create the refresh pipeline

Build the backend feed refresh system:

- fetch active feeds on a timer
- diff new vs existing articles
- insert new article rows only
- update lastFetched timestamps
- maintain unread state and freshness data

Add:

- refresh scheduling options: 5, 15, 30, 60 minutes
- manual refresh trigger
- pause/mute feed support

Outputs:

- fully working feed ingestion and periodic updates
- feed health handling and logging

---

## 7. Article Reading Experience

### Step 10: Implement the article list and article metadata

Build:

- article rows with unread state and feed context
- title/metadata hierarchy
- read state toggling
- star/favorite state
- read-later queue
- compact and card density modes

Focus on a reading-first list that feels typographically intentional rather than card-heavy and generic.

### Step 11: Implement article reading pane

Reading pane responsibilities:

- display article title, metadata, and source
- render full article content with proper typography
- present summary as marginal annotation beside content
- allow loading of article content in a readable form
- support a clean article body layout that stays readable under 80 characters per line

Need to decide whether to use:

- SwiftUI rich text container with custom layout scaffolding, or
- AppKit NSTextView-based rendering for more precise layout control

Given the marginalia design requirement, the app likely needs a stronger text layout engine than a plain default SwiftUI stack.

### Step 12: Add full-text extraction

Implement a content extraction stage:

- use readability-like extraction to strip boilerplate
- store extracted text alongside raw HTML/text
- use extracted article text for summarization and search

Key requirement:

- keep the prompt compact and accurate
- preserve article source context and author metadata

### Step 13: Add the built-in browser with tabs

Implement a lightweight in-app browser using WKWebView:

- article link opens in an internal tab
- multiple tabs supported
- browser has a simple tab strip and navigation controls
- user can open external links without leaving the core app

---

## 8. AI Summarization Architecture

### Step 14: Design the summarization provider abstraction

Create a provider abstraction that allows interchangeable backends.

Protocol should include:

- summarize(articleText:)
- summarize(article:)
- availability checks
- error handling and fallback hooks
- provider metadata for generatedBy values

Built-in implementations:

- OnDeviceAppleIntelligenceProvider
- CloudProviderPlaceholder
- optional provider adapters for OpenAI/Claude/Gemini

This architecture keeps the UI independent of the concrete model choice.

### Step 15: Implement Apple Intelligence on-device generation

Tasks:

- integrate Foundation Models usage
- model availability checks
- safe prompt construction
- `@Generable` structured output models
- default summary length: one or two sentences
- optional expanded bullet-point view

Implementation details:

- summary generation should run in a background task
- cancellation support
- no article text should leave the device by default
- graceful fallback when Apple Intelligence is unavailable

### Step 16: Create summary data model and storage

Store:

- summary text
- bullet points if generated
- provider name
- generation timestamp
- article association

Keep a cached summary with article-linked source so articles do not re-summarize unnecessarily.

### Step 17: Implement summarization UX

Add:

- summarize action in article UI
- auto-summarize when article is opened if missing
- summary load state and failure handling
- optional expand/collapse of bullet-point mode
- design treatment as a marginal annotation with a visible rule connection

### Step 18: Add fallback cloud strategy

Implement a clean fallback path:

- if Apple Intelligence is not available, show clear guidance
- if user opts into cloud summarization, route through configured provider
- keep the fallback explicit and transparent

This must be implemented as a user-controlled stack, not silent runtime substitution.

---

## 9. Smart Folders, Search, and Discovery

### Step 19: Implement smart folders

Build the filtering engine for:

- title
- content
- feed
- article age
- read state

Allow nested rule groups with:

- all / any composition
- filtering by feed folder or individual feed
- live unread counts
- update as data changes

This is a major feature and should be implemented with clear query evaluation and test coverage.

### Step 20: Add local search

Implement full-text search across:

- cached article content
- titles
- summaries

Search should:

- run locally
- be fast enough for a large article corpus
- support filtering by feed or folder when relevant

### Step 21: Build feed and article discovery UX

Create the add-feed flow:

- paste URL
- validate feed or website
- discover alternate feed if needed
- confirm import and then add feed

This is a primary user entry point and should feel polished and trustworthy.

---

## 10. Sync, Persistence, and Background Work

### Step 22: Implement CloudKit sync

Set up sync for:

- feeds
- folders
- read state
- starred/favorite state
- cached AI summaries

Scope this to:

- multiple Mac ownership, not cross-device sync
- no third-party account requirement
- safe merge logic for folder/feed metadata

### Step 23: Add background refresh scheduler

Implement periodic refresh tasks using macOS background scheduling patterns.

Responsibilities:

- refresh active feeds on schedule
- update unread counts and notifications
- keep app state consistent across wakes and idle periods

### Step 24: Add unread badge and notification logic

Implement the three granularity modes:

1. one notification per sync
2. one notification per feed
3. per-article alerts for must-see feeds

Also implement:

- dock badge count
- unread badge updates based on refresh cycle
- explicit must-see feed configuration

### Step 25: Add TTS support

Integrate AVSpeechSynthesizer-based playback for:

- article reading
- summary reading
- queue-based playback control

---

## 11. App Intents, Siri, and System Integration

### Step 26: Add App Intents

Implement user-facing intents:

- summarize unread items from feed/folder
- read today's headlines
- add feed by URL

These should use a clean app-intent layer and be app-specific rather than generic.

### Step 27: Add Spotlight / Siri-compatible entities

Model article and feed entities in a way that can be referenced by Siri or Spotlight.

Requirements:

- article references must be specific and scannable
- support user actions without leaving the app
- align with system semantics and app intent design patterns

---

## 12. Notifications, Browser, and App Polish

### Step 28: Build polish and interaction quality

At this stage, focus on polish that supports the product pitch:

- keyboard navigation (j/k, arrows, space)
- accessibility support for VoiceOver and Dynamic Type
- focus behavior and user feedback
- smooth data transitions and loading behavior

### Step 29: Fix the frontend to match the design identity

Before launch, verify the app looks like Precis rather than a generic reader.

Check specifically:

- marginalia summary treatment is unmistakable
- sidebar is distinct and not a default browser-like list
- typography is intentionally reading-first and not generic app UI
- the app remains visually distinctive at a glance

This step is a non-negotiable acceptance gate.

---

## 13. QA and Release Readiness

### Step 30: Define feature acceptance criteria

Build a test matrix for:

- feed add and discovery
- parser reliability across RSS/Atom/JSON feed variants
- article reading on dark/light mode
- summary generation fallback behavior
- sync behavior for new/edited feeds
- unread counts and notifications
- background refresh behavior
- App Store sandbox compliance

### Step 31: Run validation passes

Perform:

- functional QA
- accessibility review
- performance review on Apple Silicon Macs
- battery / background refresh review
- visual screenshot review against the design spec
- app store readiness review

### Step 32: Ship readiness checklist

Before release, confirm:

- no Intel code paths are accidentally included
- AI features degrade gracefully when unavailable
- every network path is explicit and safe
- App Sandbox is respected
- no user-facing text undermines privacy claims
- screenshots align with the design principle of marginalia and distinctiveness

---

## 14. Suggested Delivery Phases

### Phase 1: Foundation and core UX

Duration: 2-3 weeks

- Xcode project and app skeleton
- data model and persistence layer
- base macOS layout
- feed input and parser integration
- article list and reading pane shell

### Phase 2: Feed pipeline and reading features

Duration: 3-4 weeks

- feed refresh pipeline
- OPML support
- folder organization
- smart folder basics
- read state and star/read-later logic
- search index baseline

### Phase 3: AI summarization

Duration: 3-4 weeks

- provider abstraction
- Apple Intelligence integration
- summary storage and display
- fallback logic and user prompts
- summary UX refinement

### Phase 4: Sync, background work, and polish

Duration: 3-4 weeks

- CloudKit layer
- background refresh scheduler
- dock badge and notifications
- App Intents and system integration
- accessibility and keyboard support
- screenshot-driven design tuning

### Phase 5: QA and beta preparation

Duration: 2-3 weeks

- bug fix pass
- release testing
- sandbox validation
- visual QA and final design review
- release build and App Store prep

---

## 15. Implementation Risks and Mitigations

### Risk: summary layout is harder than expected

Mitigation:

- prototype the marginalia layout early
- test against multiple window widths
- consider AppKit text rendering if SwiftUI is too limited

### Risk: feed parsing is inconsistent across real-world feeds

Mitigation:

- normalize all feeds through a single feed adapter
- store raw plus extracted versions
- add parser resilience and testing with sample feeds

### Risk: CloudKit sync introduces model churn

Mitigation:

- keep the persistence layer abstract and small
- implement sync mapping carefully
- validate with migration and merge test cases

### Risk: app feels generic despite good functionality

Mitigation:

- treat visual distinctiveness as a release gate
- run screenshot review regularly
- revise design before moving to scale-up features

---

## 16. Definition of Done

The project is ready to move beyond MVP when all of the following are true:

- feeds can be added and refreshed reliably
- article reading is smooth and readable
- summaries are generated locally and displayed with the marginalia treatment
- the app has a clear and distinctive design identity
- Smart Folders and search work reliably
- CloudKit sync preserves feed and read-state data across Macs
- background tasks and notifications are stable
- the app passes App Sandbox and Mac App Store readiness checks
- screenshots convey the product clearly and distinctly

---

## 17. Recommended First Milestone

The first milestone should focus on a complete internal alpha loop:

1. project and data model setup
2. feed parsing and refresh pipeline
3. article list and reading pane
4. basic summary generation and display
5. design review against the spec

This milestone is the first real proof that the app can feel like Precis instead of a default RSS client.

---

## 18. Summary

This plan is designed to build Precis as a disciplined, privacy-first macOS reading app with a clearly differentiated UI and an AI feature that feels native to the reading experience rather than bolted on.

The most important constraints are:

- Apple Silicon only
- on-device summarization by default
- visual identity as a first-class requirement
- architecture that supports clean cloud fallback and sync without compromising the core privacy story

If the team follows this roadmap in order, the app should reach a strong MVP with a coherent product identity, a stable architecture, and a realistic path to App Store release.
