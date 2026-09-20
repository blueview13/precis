# Precis — macOS RSS Reader with AI Summarization
## Technical Specification

**App name:** Precis
**Platform:** macOS only, **Apple Silicon only — no Intel support**, no iOS/iPadOS companion in v1
**Target OS:** macOS 26 (Tahoe) minimum, built against macOS 27 SDK
**Distribution:** Mac App Store (sandboxed) — required for Apple Intelligence entitlements and Small Business Program cost benefits

---

## 1. Positioning

Precis is a native, fast, privacy-first Mac RSS reader whose core differentiator is on-device AI summarization — no server round-trip, no per-summary cost, works offline. Feature parity target is CMRSS (the closest direct competitor), plus Newsify and SmartRSS, with one added wedge feature: **cross-feed story clustering** (grouping related articles from multiple sources into one digest), which is rare even among AI-enabled readers.

Since CMRSS is a Mac **+ iOS/iPadOS** app with iCloud sync across all three, and this spec targets **macOS only**, Precis will deliberately drop CMRSS's cross-device tab/read-state sync as a selling point and instead lean on being a sharper, more focused single-platform tool — a plausible angle for users who only read on their Mac and don't want to pay for (or maintain) a multi-platform footprint.

**Visual design is a strict, non-negotiable requirement, not a polish pass.** Competing readers (CMRSS, Newsify, SmartRSS, NetNewsWire, Reeder) are functionally similar and largely visually interchangeable — default macOS three-pane chrome, generic card-based summaries. Precis's interface must be distinctive enough to be recognizable from a screenshot alone, and this must be treated as a first-class product requirement throughout design and development, not deferred to a later "make it pretty" pass. See section 4.

---

## 2. Functional Requirements

### 2.1 Feed Management
- Add feeds by URL, or by pasting a website URL (auto-discover `<link rel="alternate">` feed).
- **Non-RSS source auto-discovery (matches CMRSS):** paste a YouTube channel URL or a subreddit URL and have the app resolve it to the underlying feed automatically (YouTube channels and most subreddits expose native RSS/Atom endpoints; detect and convert on paste rather than requiring the user to know the feed URL format).
- **Optional RSS.app integration:** for sites/social pages with no native feed, offer an opt-in integration with the RSS.app API (or an equivalent feed-generation service) to synthesize a feed from an arbitrary URL. Keep this behind a toggle since it's a paid third-party dependency, not a core requirement.
- OPML import and export.
- Organize feeds into nested folders.
- **Smart Folders (matches CMRSS's rule depth):** saved filters combining conditions on **title, content, feed, article age, and read state**, composable into **nested AND/OR ("any/all") groups** rather than a single flat filter. Smart Folders always show a live, accurate unread count and sync like regular folders.
- Manual feed refresh + **configurable background refresh interval — offer 5, 15, 30, and 60-minute options** (matching CMRSS's granularity) rather than a single fixed interval.
- Feed favicon fetching and caching.
- Mute/pause a feed without deleting it.

### 2.2 Article List & Reading
- Three-pane layout: sidebar (feeds/folders) → article list → reading pane, with a compact two-pane mode. (See section 4 for the distinctive treatment of this layout — it should not read as a default Mail.app clone.)
- List view density options (compact / cards with image preview).
- Mark read/unread, star/favorite, read-later queue.
- Full-text extraction (Readability-style) for feeds that publish only excerpts.
- Built-in in-app browser (WKWebView) with tabs, for opening links without leaving the app.
- Keyboard-driven navigation (j/k, space to scroll, arrow keys) for power users.

### 2.3 AI Summarization
- **Primary engine:** Apple's Foundation Models framework (on-device Apple Intelligence model).
  - Per-article "Summarize" action, on demand or auto-generated when an article is opened.
  - **Default summary length: one or two sentences** (matching CMRSS's stated behavior — a deliberately terse skim-length summary, not a multi-paragraph digest), with an optional expanded bullet key-points mode as a secondary view, using `@Generable` structured generation rather than free-text parsing.
  - Runs fully offline once the model is downloaded; no article content leaves the device — this "nothing ever leaves your device" framing is CMRSS's core marketing claim and should be stated just as plainly in Precis's own onboarding/marketing copy.
- **Fallback / opt-in cloud engine:** pluggable model provider (Claude, GPT, Gemini) via the Foundation Models model-abstraction layer, for:
  - Devices/regions where Apple Intelligence isn't available (EU/China at initial rollout, Intel Macs).
  - Users who want higher-quality synthesis than the on-device model provides.
  - Users below the on-device model's context/quality bar (very long articles).
- **Availability check:** graceful degradation — if Apple Intelligence is unavailable, show a clear "enable in System Settings" prompt or offer the cloud fallback.
- **Cross-feed clustering (differentiator):** periodically group same-story articles from different feeds (via embedding similarity or keyword/entity overlap) into a single "story" with one synthesized summary and links to each source. Ships as v2, not MVP.
- **Ask-a-follow-up:** lightweight chat affordance under a summary to ask a clarifying question about the article, scoped to that article's text only.
- **Presentation of the summary is a design-critical surface, not an afterthought — see section 4's marginalia treatment.**

### 2.4 Sync
- **Scope note:** CMRSS syncs feeds, folders, read-state, and *open browser tabs* across Mac, iPhone, and iPad via iCloud. Since Precis is macOS-only in v1, there's no cross-device tab handoff to build — sync here exists purely to protect against **data loss / Mac migration**, not cross-device continuity. This meaningfully shrinks the CloudKit surface area versus CMRSS.
- iCloud (CloudKit) sync of: feed list, folders, read/starred state, cached AI summaries — scoped to multiple Macs the user owns, rather than multiple device types.
- No third-party account required for core sync.
- Optional integration with external RSS backends (Feedbin, FreshRSS, Inoreader, Miniflux) for users who already run one, so switching costs nothing.

### 2.5 Siri / System Integration
- App Intents exposing: "Summarize my unread [feed/folder]", "Read me today's headlines", "Add feed [URL]".
- Entity schemas for articles/feeds so Spotlight and Siri can reference specific content ("summarize this article" while it's on screen), using View Annotations.

### 2.6 Notifications & Unread Badging
- **Configurable notification granularity**, mirroring CMRSS's three modes:
  1. One notification per sync (a single "N new articles" summary per refresh cycle).
  2. One notification per feed (grouped by source).
  3. Per-article alerts, but scoped to feeds the user explicitly marks as "must-see" — avoids notification fatigue on high-volume feeds while still allowing real-time alerts for a handful of priority sources.
- **Dock badge** showing current total unread count, kept in sync with the same background-refresh cycle as section 2.1.
- (No Home Screen widget in v1 — that's an iOS-only CMRSS feature and out of scope for a macOS-only app; a macOS Notification Center widget showing unread count could be a low-cost v2 addition.)

### 2.7 Text-to-Speech
- System TTS (AVSpeechSynthesizer) to read articles or summaries aloud, with playback queue.

### 2.8 Search
- Local full-text search across all cached articles and summaries.

---

## 3. Non-Functional Requirements
- **Privacy:** on-device summarization is the default; cloud fallback is explicit opt-in with clear disclosure of what leaves the device.
- **Performance:** feed refresh and summarization must not block the UI thread; summarization runs as background `Task`s with cancellation support.
- **Offline-first:** cached articles and summaries remain readable with no network.
- **Sandboxing:** full App Sandbox compliance for Mac App Store distribution.
- **Accessibility:** VoiceOver support, Dynamic Type, full keyboard navigation.
- **Visual distinctiveness (strict requirement):** the interface must be identifiable as Precis from a single screenshot, without relying on the app icon or window title. This is treated with the same priority as functional requirements — a feature-complete but visually generic build does not meet spec. See section 4 for the concrete design direction this requirement resolves to.

---

## 4. Visual Design & UI Requirements

This section is a strict requirement, not a suggestion. The goal is a Mac app that a design-literate user would screenshot unprompted — the way people used to screenshot Reeder or Sparrow. Genuinely default treatments (see the "avoid" list below) do not satisfy this spec even if every functional requirement is met.

### 4.1 Concept: the marginalia metaphor

"Précis" is, historically, the kind of concise summary a reader writes in the margin of a book. The whole interface should lean into that metaphor rather than treating the AI summary as a generic "AI card" bolted onto a standard reading pane:

- The on-device summary is presented as an **annotation in the margin beside the article**, not a boxed callout above it — visually closer to a handwritten marginal note or an editor's précis than a chatbot response bubble.
- This single idea is the "spend your boldness in one place" move for the whole app: everything else in the UI should be quiet and disciplined around it, so the marginalia treatment reads as considered rather than as one gimmick among many.

### 4.2 Design tokens

**Color** (named, not default AI-generated palette choices — explicitly avoids the warm-cream-plus-terracotta and near-black-plus-neon defaults common in generated UI):
- `paper` `#F3F0E8` — base background; warm but closer to true paper stock than a cream/latte tone
- `ink` `#211F1A` — primary text and chrome; warm near-black, not a tinted `#0B0B0B`/`#111`
- `marginalia` `#3C5A45` — deep bottle-green accent used *only* for the AI summary annotation, its connecting rule, and the "Summarize" affordance — nowhere else, so it stays meaningful
- `flag` `#A8672B` — muted ochre, used only for starred/must-see items and unread indicators
- `rule` `#D8D2C2` — hairline dividers and card borders, warm grey rather than a generic cool `rgba(0,0,0,.1)` shadow-grey
- `surface` `#EAE6DA` — sidebar and list-row background, one step off `paper` for depth without a drop shadow

**Type:**
- **Reading serif** for article body text and headlines in the reading pane — a humanist serif (e.g. Newsreader or Fraunces), justified by actual content: this is a long-form reading app, so serif body text is a functional choice, not decoration.
- **UI sans** for sidebar, list rows, toolbar, and settings — a distinct grotesque (e.g. system SF Pro with tightened tracking, or Inter) so reading content and app chrome are never visually confused.
- **Marginalia italic** — the reading serif's italic cut, at a slightly reduced size, reserved exclusively for the AI summary text. This is the one place italics carry real meaning (this text is the machine's annotation, not the author's), rather than italics used decoratively.
- No tracked-out ALL-CAPS eyebrows, no middle-dot-joined metadata strings, no monospace for data labels — these are the generic "template chrome" tells to avoid explicitly.

**Layout:**
- Not a rigid three-column grid of equal-weight panes. Sidebar is a narrow **favicon spine** (feed icons only, labels on hover/focus) rather than a full-width text list — visually distinct from CMRSS/NetNewsWire's standard sidebar.
- Article list uses **typographically differentiated rows** (title weight/size varies with unread state and feed importance) instead of identical bordered/shadowed cards — avoids the generic "SaaS card" sameness.
- Reading pane: article text in a centered column under 80 characters per line; the précis annotation sits in a **fixed left or right margin column alongside it** at normal window widths, and collapses into an expandable strip above the article only when the window is narrow.

**Motion:**
- One deliberate, orchestrated moment: when a summary finishes generating, the marginalia text animates in as though being written — a single considered reveal tied directly to the "annotation" metaphor, not a generic fade-slide-up.
- Everything else (hover states, pane transitions, list selection) is minimal and functional — motion answers a user action, not decoration on every element.

### 4.3 Native materials, used deliberately

- Use macOS vibrancy/translucency in the favicon spine only, to keep it feeling like a native system surface. Avoid applying blur/vibrancy everywhere, which reads as an unconsidered default rather than a choice.
- Respect the system's light/dark appearance, with the `paper`/`ink`/`marginalia`/`flag`/`rule`/`surface` tokens each given a dark-mode counterpart designed on their own terms — not a naive value inversion.

### 4.4 Process requirement

Before implementation, produce a short design plan (palette, type, layout, and the one or two principles that make this specific to Precis) and review it against this spec: if any part of it would be indistinguishable from a generic reader or a generic AI-generated dashboard, revise it before writing UI code. Take and review screenshots during build as a standing part of the workflow, not only at the end.

---

## 5. Architecture

### 5.1 Stack
- **UI:** SwiftUI (primary), with AppKit interop where SwiftUI gaps exist (e.g. advanced NSTextView-based reading pane if needed — likely required for the marginalia layout in section 4, since precise text-column-plus-margin layout may exceed default SwiftUI text container support).
- **Data layer:** SwiftData (or Core Data if SwiftData's CloudKit sync proves too limiting) for local persistence, backed by CloudKit for sync.
- **Networking:** URLSession for fetching.
- **Feed parsing: `nmdias/FeedKit` (Swift Package Manager)** — see recommendation in section 8.
- **AI layer:**
  - `FoundationModels` framework for on-device generation (`LanguageModelSession`, `@Generable` structs for structured summaries).
  - A thin `SummarizationProvider` protocol abstraction so on-device and cloud providers (Claude/OpenAI/Gemini APIs) are interchangeable behind one interface — mirrors Apple's own model-abstraction approach.
- **Background work:** `BGTaskScheduler`-equivalent on macOS via a background `NSBackgroundActivityScheduler` or a lightweight XPC helper for periodic feed refresh.
- **Article extraction:** a readability/content-extraction pass (strip boilerplate) before feeding text to the summarizer, to keep prompts small and summaries accurate.

### 5.2 Data Model (core entities)
- `Feed`: id, title, url, faviconData, folderId, muted, lastFetched
- `Folder`: id, name, parentFolderId (nesting), smartFolderQuery (optional)
- `Article`: id, feedId, title, author, publishedDate, link, rawContent, extractedContent, isRead, isStarred, imageURL
- `Summary`: id, articleId, tldr, bulletPoints[], generatedBy (on-device/cloud/provider name), generatedAt
- `Story` (v2, clustering): id, memberArticleIds[], synthesizedSummary, topic

### 5.3 Key Flows
1. **Add feed:** URL entered → discover/validate → parse initial articles → insert `Feed` + `Article` rows → background summarization queue picks up new articles.
2. **Open article:** load `extractedContent` → if no `Summary` exists, trigger on-device summarization → render reading pane with the marginalia annotation appearing beside the full text (section 4.1).
3. **Background refresh:** on interval or system wake → fetch all active feeds → diff new articles → queue summarization for new items only (avoid re-summarizing).
4. **Cloud fallback:** if `FoundationModels` reports the model unavailable, `SummarizationProvider` routes to the configured cloud provider (only if the user has opted in and supplied an API key).

---

## 6. MVP Scope (v1)

In scope:
- Feed add/organize/read, OPML import/export
- YouTube channel / subreddit auto-discovery on paste
- Three-pane native UI, **built to the section 4 design direction from the start — not a placeholder UI to be re-skinned later**
- On-device AI summaries (on-demand + auto), one-to-two-sentence default length, rendered as marginalia (section 4.1)
- Smart Folders with nested any/all rule groups (title, content, feed, age, read state)
- Configurable background refresh (5/15/30/60 min)
- Notification granularity (per-sync / per-feed / per-article for must-see feeds) + dock badge
- iCloud sync of feeds/folders/read-state (Mac-to-Mac only)
- Built-in browser with tabs
- Search, star, read-later
- Cross-feed clustering
- Cloud model fallback / BYO API key
- Siri App Intents beyond basic "summarize"
- Text-to-speech
- Third-party backend sync (Feedbin/FreshRSS/etc.)
- RSS.app (or equivalent) integration for non-feed sources
- Notification Center widget

**Reference benchmark:** CMRSS ships at roughly 22 MB and is currently on version 1.0.6 as a young, actively-updated product — a useful sanity check that this feature set is achievable as a lean, single-developer-maintainable app rather than a large engineering effort. Note that CMRSS's own screenshots show fairly standard macOS list/reader chrome — this is precisely the gap section 4's design requirement is meant to exploit.

---

## 7. Distribution & Monetization
- Mac App Store, sandboxed.
- Enroll in the App Store Small Business Program (if eligible) for free access to Apple's next-gen Foundation Models on Private Cloud Compute where applicable.
- Pricing model to decide: one-time purchase vs. subscription (subscription likely needed if/when cloud fallback usage costs are incurred; one-time purchase is simpler and more defensible if summarization stays on-device only).
- A distinctive visual identity (section 4) is also a monetization lever: it is the primary asset for App Store screenshots, Product Hunt launch assets, and word-of-mouth sharing, all of which matter more for a paid utility app than incremental feature count.

---

## 8. Decisions & Recommendations

### 8.1 Feed parser — RESOLVED: use `nmdias/FeedKit`

**Recommendation:** adopt **`nmdias/FeedKit`** (https://github.com/nmdias/FeedKit) via Swift Package Manager rather than building a parser in-house.

Reasoning:
- **Actively maintained and current.** Unlike several abandoned forks of the same name that turn up in a quick search, the canonical `nmdias/FeedKit` repo is being pushed to on an ongoing basis and has a modern, `async/await`-native API (`try await Feed(urlString:)`), which fits a SwiftUI/Swift Concurrency codebase cleanly with no callback-to-async bridging needed.
- **Covers everything the spec needs out of the box:** parses RSS, Atom, *and* JSON Feed through one universal `Feed` enum with automatic format detection — useful since feeds discovered from arbitrary pasted URLs (section 2.1) won't always be RSS.
- **Native namespace support for YouTube and iTunes/Media RSS.** This directly de-risks the "paste a YouTube channel URL" auto-discovery feature (section 2.1) — YouTube's Atom feeds use extensions that a generic parser can choke on or ignore; FeedKit already models these.
- **No heavyweight dependencies.** It's pure Swift with no transitive dependency tree to audit for sandbox/notarization compliance — a meaningful factor for a solo developer shipping to the Mac App Store.
- **Low switching risk.** If it's ever abandoned, its `Feed` enum is a thin decoding layer over well-specified formats (RSS 2.0, Atom, JSON Feed spec) — replacing it later is a contained, mechanical change rather than a rewrite of app logic, so there's little downside to depending on it now instead of building an in-house parser pre-emptively.

Building an in-house parser is not recommended: RSS/Atom have enough real-world inconsistency (malformed dates, missing namespaces, encoding quirks) that a solo developer would end up re-deriving most of what FeedKit already handles, for no meaningful gain given the license and dependency profile are already clean.

### 8.2 Intel support — RESOLVED: Apple Silicon only

No Intel support. Since Apple Intelligence / the Foundation Models framework (the entire AI-summarization value proposition) requires Apple Silicon, shipping an Intel build would mean maintaining a second, cloud-only summarization code path for a shrinking, non-strategic slice of users. Apple Silicon–only from v1 keeps the codebase and QA matrix simpler and matches CMRSS's own minimum requirement (macOS 26.0).

### 8.3 Still open
- Exact clustering algorithm for v2 (embedding similarity via a small on-device embedding model vs. simpler keyword/entity overlap heuristics).
- Final palette/type token values in section 4.2 should be validated against real screenshots (light and dark mode, several window widths) before being treated as locked — token *names* and *roles* are the resolved part of this decision, exact hex values may shift slightly once seen in context.