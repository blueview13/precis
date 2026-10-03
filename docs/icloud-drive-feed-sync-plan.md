# Plan: Automatic Feed + Category Sync via iCloud Drive (No Developer Account)

## Goal

Keep the user's RSS feed list **and their categories** in sync across multiple Macs, automatically, using iCloud Drive as the transport. No CloudKit, no server, no paid Apple Developer membership.

**Rules of the model:** users create their own categories; each feed belongs to **at most one** category (or none, i.e. "Uncategorized").

## Key constraint and approach

Without a paid developer account you cannot use the iCloud ubiquity container, CloudKit, or `NSUbiquitousKeyValueStore`. Those need entitlements tied to a team ID.

You *can*, however, read and write ordinary files inside the user's iCloud Drive folder, because to the OS it is just a folder on disk (`~/Library/Mobile Documents/com~apple~CloudDocs/`). macOS's own iCloud daemon syncs whatever is in there. Your app only needs to:

1. Create a default sync folder inside iCloud Drive automatically (one click, "Enable sync"), with a folder picker as an advanced alternative.
2. Write the feed list and categories there.
3. Watch that folder for changes arriving from other Macs.
4. Merge and reload.

**Assumptions:** the app is distributed outside the Mac App Store and is **not sandboxed**. If you do sandbox it, see "Sandboxing note" at the end.

---

## Design decision: one file per device

Do **not** have every Mac write the same `feeds.json`. iCloud resolves simultaneous writes by creating conflict versions, which are annoying to handle.

Instead:

```
iCloud Drive/
└── MyRSSReader/              <- user-chosen (or default) sync folder
    └── devices/
        ├── 6F1C...-MacBook.json
        └── A9D2...-iMac.json
```

- Each Mac writes **only its own file**, containing its full, post-merge view of categories and feeds.
- Each Mac **reads all files** and merges them.
- Since no two machines ever write the same file, conflicts essentially cannot happen.

---

## Data model

Categories are **their own synced records**, and feeds point to them **by ID**, never by name.

```swift
import Foundation

struct CategoryRecord: Codable, Identifiable, Equatable {
    let id: UUID              // random (UUID()), NOT derived from the name
    var name: String
    var sortOrder: Double
    var createdAt: Date
    var updatedAt: Date       // bump on rename / reorder / delete
    var isDeleted: Bool       // tombstone
}

struct FeedRecord: Codable, Identifiable, Equatable {
    let id: UUID              // derived from normalised URL (see below)
    var url: URL
    var title: String
    var categoryID: UUID?     // single category; nil = Uncategorized
    var sortOrder: Double     // order within its category
    var updatedAt: Date       // bump on ANY edit, including moving category
    var isDeleted: Bool       // tombstone
}

struct SyncFile: Codable {
    var schemaVersion: Int = 2
    var deviceID: String
    var deviceName: String
    var writtenAt: Date
    var categories: [CategoryRecord]
    var feeds: [FeedRecord]
}
```

### Why IDs and not names

If Mac A renames "Tech" to "Technology" while Mac B adds a feed to "Tech", a name-based model produces two categories after merging. With IDs, a rename touches only the category record, and every feed keeps pointing at it. Moving a feed between categories is just a feed edit (`categoryID` + `updatedAt`), which last-writer-wins already handles.

### Stable feed IDs

If Mac A and Mac B both add `https://example.com/feed.xml` independently, you want one record, not two. Generate the **feed** ID deterministically:

- Normalise the URL (lowercase scheme and host, strip trailing slash, strip fragment).
- Hash it (SHA-256) and use the first 16 bytes to build a `UUID`.

**Category** IDs are the opposite: random. Two Macs creating "News" independently get different IDs, and that case is handled explicitly in the merge (below).

### Tombstones

Deleting a feed or category sets `isDeleted = true` and bumps `updatedAt`. Never remove the record immediately, otherwise another Mac will resurrect it on the next merge. Prune tombstones older than ~90 days.

### Device ID

Generate a UUID on first launch, store it in `UserDefaults`, and use it for the filename. Do not use the hardware UUID or hostname, since those can change or collide.

---

## Merge

### Step 1: generic last-writer-wins union

One function handles both record types:

```swift
protocol Syncable {
    var id: UUID { get }
    var updatedAt: Date { get }
    var isDeleted: Bool { get }
}
extension CategoryRecord: Syncable {}
extension FeedRecord: Syncable {}

func mergeRecords<T: Syncable>(_ lists: [[T]]) -> [T] {
    var best: [UUID: T] = [:]
    for record in lists.joined() {
        if let existing = best[record.id] {
            if existing.updatedAt > record.updatedAt { continue }
            // deterministic tie-break so all Macs converge
            if existing.updatedAt == record.updatedAt,
               existing.id.uuidString >= record.id.uuidString { continue }
        }
        best[record.id] = record
    }
    let cutoff = Date().addingTimeInterval(-90 * 24 * 3600)
    return best.values.filter { !($0.isDeleted && $0.updatedAt < cutoff) }
}
```

For records that share an `id`, a stronger tie-break is to include `deviceID` in the comparison. Whatever you pick, it must be deterministic.

### Step 2: resolve duplicate category names (derived, not written)

Two Macs may each create a category called "News" while offline, giving two records with different IDs. Resolve this as a **pure function of the merged state**, applied at read time:

```swift
struct ResolvedState {
    var categories: [CategoryRecord]            // live, deduplicated
    var categoryRemap: [UUID: UUID]             // loser ID -> canonical ID
}

func resolveCategories(_ merged: [CategoryRecord]) -> ResolvedState {
    let live = merged.filter { !$0.isDeleted }
    let groups = Dictionary(grouping: live) {
        $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    var canonical: [CategoryRecord] = []
    var remap: [UUID: UUID] = [:]
    for (_, group) in groups {
        // earliest createdAt wins; tie -> smallest UUID string
        let winner = group.min {
            ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
        }!
        canonical.append(winner)
        for loser in group where loser.id != winner.id { remap[loser.id] = winner.id }
    }
    return ResolvedState(categories: canonical.sorted { $0.sortOrder < $1.sortOrder },
                         categoryRemap: remap)
}
```

**Why derived rather than "tombstone the losers and rewrite the feeds":** if every Mac rewrites records during dedupe, each stamps its own `Date()`, the Macs trigger each other's watchers, and you get exactly the ping-pong the "only write if changed" rule is meant to prevent. A pure function over merged state gives the same answer on every Mac with zero writes. Duplicates are cleaned up gradually: when the user next edits a feed, it is saved with the canonical `categoryID`.

### Step 3: resolve each feed's effective category

```swift
func effectiveCategoryID(for feed: FeedRecord,
                         remap: [UUID: UUID],
                         liveCategoryIDs: Set<UUID>) -> UUID? {
    guard var id = feed.categoryID else { return nil }
    if let mapped = remap[id] { id = mapped }
    return liveCategoryIDs.contains(id) ? id : nil   // orphan / deleted -> Uncategorized
}
```

This one function covers three cases:

- feed points at a **duplicate-name loser**: it follows the remap to the canonical category;
- feed points at a **tombstoned category**: it shows as Uncategorized;
- feed points at a category whose record **hasn't arrived yet** (the feed's file synced first): it shows as Uncategorized for now and snaps into place on the next sync. Do **not** rewrite the feed in this case.

---

## User actions and how they map to records

| User action | Records written |
|---|---|
| Create category | New `CategoryRecord` (random ID, `sortOrder` after the last one) |
| Rename category | Category: `name`, `updatedAt` |
| Reorder categories | Category: `sortOrder`, `updatedAt` (only the moved item, using a midpoint value) |
| Delete category | Category: `isDeleted = true`, `updatedAt`. **Also** every feed in it: `categoryID = nil`, `updatedAt` (all stamped with the same `Date`) |
| Add feed to category | New `FeedRecord` with `categoryID` |
| Move feed between categories | Feed: `categoryID`, `sortOrder`, `updatedAt` |
| Delete feed | Feed: `isDeleted = true`, `updatedAt` |

**Deleting a category never deletes its feeds.** They move to Uncategorized, since losing subscriptions is the worse failure. Make sure your UI confirms this wording.

**Ordering:** use a `Double` `sortOrder` and insert by taking the midpoint between neighbours. Array position gives bad merges. If the gap between neighbours becomes tiny (say under `1e-9`), renumber that group and bump `updatedAt` on the renumbered items.

---

## Components

### 1. Sync folder setup (one-time)

The app creates the folder itself, so most users never see a file picker. The picker stays available as an advanced option.

#### First-run flow

1. Show a prompt: "Sync your feeds across Macs using iCloud Drive."
2. Primary button **Enable sync** calls `createDefaultSyncFolder()` (below).
3. Small link underneath: **Choose a different folder...** opens `NSOpenPanel`.
4. Briefly explain in the onboarding text that macOS may ask permission to access iCloud Drive, so the system prompt doesn't look alarming.
5. On success, save the folder path in `UserDefaults` and run the first sync.

#### Default folder creation

```swift
enum SyncError: Error {
    case iCloudDriveUnavailable
    case folderNotInICloud
}

let iCloudDriveURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)

func createDefaultSyncFolder() throws -> URL {
    let fm = FileManager.default

    // Only proceed if iCloud Drive is actually set up on this Mac.
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: iCloudDriveURL.path, isDirectory: &isDir), isDir.boolValue else {
        throw SyncError.iCloudDriveUnavailable
    }

    let folder = iCloudDriveURL.appendingPathComponent("MyRSSReader", isDirectory: true)
    try fm.createDirectory(at: folder.appendingPathComponent("devices", isDirectory: true),
                           withIntermediateDirectories: true)
    return folder
}
```

The folder appears in Finder under iCloud Drive as "MyRSSReader" and is synced by the iCloud daemon like any other folder.

#### Rules and edge cases

- **Never create the `com~apple~CloudDocs` path yourself.** If it does not exist, iCloud Drive is switched off or the user is not signed in. Creating it manually would produce a local folder that never syncs. Show a message instead: "Turn on iCloud Drive in System Settings, then try again," with a button that opens System Settings (`x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane`) and a **Try again** button.
- **Second Mac:** `createDirectory(... withIntermediateDirectories: true)` succeeds whether or not the folder already exists. If the first Mac's folder has not finished downloading yet, the second Mac creates an empty one. iCloud merges the two, so this is harmless, but the first sync may take a moment to bring in the other Mac's device file. Show "Waiting for iCloud to download your other devices..." and re-sync when the presenter fires.
- **Existing folder detection:** on first run, check whether `MyRSSReader/devices/` already contains files. If so, say "Found sync data from N other device(s)" so the user knows it is picking up their existing feeds rather than starting fresh.
- **Name collisions:** if `MyRSSReader` exists but is not ours (no `devices/` subfolder and it contains other files), either use `MyRSSReader Sync` or ask the user. Do not write into a folder you do not recognise.
- **Advanced: choose a different folder.** Use `NSOpenPanel` with `canChooseDirectories = true`, `canChooseFiles = false`, and `canCreateDirectories = true` so users can make a new folder from inside the dialog. Point it at iCloud Drive:
  ```swift
  panel.directoryURL = iCloudDriveURL
  panel.canCreateDirectories = true
  ```
- **Validate any chosen folder.** Warn if it is not inside iCloud Drive, since that would not sync via iCloud (it may still be fine if the user has Dropbox or Syncthing, so warn rather than block):
  ```swift
  let inICloud = url.path.contains("com~apple~CloudDocs")
  ```
  Then create `devices/` inside it if missing.
- **Changing the folder later:** in Settings, show the current folder with a "Change..." button. On change, stop the presenter, copy this device's file to the new folder's `devices/`, then start a presenter on the new location and run a sync. Leave the old folder untouched.
- **Settings display:** show the folder name, whether it is in iCloud Drive, the last sync time, and a "Reveal in Finder" button.

> macOS may show a one-time privacy prompt the first time the app touches iCloud Drive. That is expected.

### 2. Coordinated file I/O

Always go through `NSFileCoordinator`. It cooperates with the iCloud daemon, triggers downloads of not-yet-downloaded files, and avoids reading half-written files.

```swift
final class SyncStore: NSObject, NSFilePresenter {
    let folderURL: URL
    let presentedItemOperationQueue = OperationQueue()
    var presentedItemURL: URL? { folderURL }

    private lazy var coordinator = NSFileCoordinator(filePresenter: self)
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]  // stable output = fewer pointless writes
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(folderURL: URL) {
        self.folderURL = folderURL
        super.init()
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
    }

    func start() { NSFileCoordinator.addFilePresenter(self) }
    func stop()  { NSFileCoordinator.removeFilePresenter(self) }

    func readFile(at url: URL) -> SyncFile? {
        var result: SyncFile?
        var error: NSError?
        coordinator.coordinate(readingItemAt: url, options: [], error: &error) { readURL in
            if let data = try? Data(contentsOf: readURL) {
                result = try? decoder.decode(SyncFile.self, from: data)
            }
        }
        return result
    }

    func writeFile(_ file: SyncFile, to url: URL) {
        guard let data = try? encoder.encode(file) else { return }
        var error: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { writeURL in
            try? data.write(to: writeURL, options: .atomic)
        }
    }
}
```

### 3. Detecting changes from other Macs

`NSFilePresenter` on the folder gets callbacks when files inside it change, appear, or disappear:

```swift
extension SyncStore {
    func presentedSubitemDidChange(at url: URL)  { syncRequested() }
    func presentedSubitemDidAppear(at url: URL)  { syncRequested() }
    func presentedSubitem(at url: URL, didMove destination: URL) { syncRequested() }
}
```

`syncRequested()` should **debounce** (about 1 second) and hop to a serial queue, since iCloud often fires several events for one logical change.

### 4. The sync routine

```
func performSync():
    1. Enumerate devices/*.json (including our own for the merge input).
    2. Make sure every file is downloaded (see "Eviction" below).
    3. Decode each; ignore files that fail to decode or have a newer
       schemaVersion than this app understands (log, don't crash).
    4. mergedCategories = mergeRecords(all categories + local categories)
       mergedFeeds      = mergeRecords(all feeds + local feeds)
    5. resolved = resolveCategories(mergedCategories)      // derived, no writes
    6. If merged state != local state -> update local database + UI
       (main thread), using effectiveCategoryID() for each feed.
    7. Build our SyncFile from the MERGED (not resolved) records.
       If its `categories` or `feeds` differ from what is currently in
       our own file on disk -> write it. Otherwise do nothing.
```

Step 7's "only write if different" is essential. Without it, Macs can trigger each other's watchers forever. Compare the arrays, **not** `writtenAt`. Write the *merged* records (not the deduplicated view) so the dedupe stays a derived concept and never causes writes.

### 5. When to trigger a sync

| Trigger | Why |
|---|---|
| App launch (before showing the feed list) | Catch up on anything that changed while closed |
| `NSApplication.didBecomeActiveNotification` | Safety net if watcher events were missed |
| `NSWorkspace.didWakeNotification` | Watchers can be unreliable across sleep |
| `presentedSubitem...` callbacks | The normal live path |
| Local category/feed add, remove, edit, move (debounced ~2s) | Push local changes out |
| Optional: 5-minute timer while running | Cheap belt-and-braces |

### 6. iCloud eviction ("Optimize Mac Storage")

If the user has "Optimize Mac Storage" on, files may exist only as placeholders until downloaded.

- A coordinated read (`coordinate(readingItemAt:)`) normally triggers the download and blocks until it completes.
- To be proactive, when enumerating the folder:
  ```swift
  try? FileManager.default.startDownloadingUbiquitousItem(at: url)
  ```
  and check `url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])`.
- Placeholders may appear as hidden `.<name>.icloud` files on some macOS versions. Handle both: if you see one, strip the leading dot and `.icloud` suffix to get the real URL, then request the download.
- If a download hasn't finished, skip that file for now. The presenter will fire again when it lands.

### 7. Stale device files

If a Mac is retired, its file stays forever. That is harmless, because it only contributes old records that lose to newer ones. Optional cleanup:

- In Settings, list known devices with their `writtenAt` dates and a "Remove" button.
- Or auto-ignore (not delete) files untouched for over 1 year.

---

## Implementation order

1. **Models, `mergeRecords`, `resolveCategories`, `effectiveCategoryID`**, with unit tests (see below). This is pure logic and the most important part to get right.
2. **Stable feed ID generation** from normalised URLs.
3. **SyncStore** with coordinated read/write against a plain local temp folder first.
4. **First-run "Enable sync" flow** with `createDefaultSyncFolder()`, the iCloud-unavailable error state, the advanced folder picker, and persisting the path.
5. **Wire local edits to sync** (debounced write on any category or feed change), including the delete-category cascade.
6. **NSFilePresenter callbacks + triggers** (launch, activate, wake).
7. **Eviction handling.**
8. **Real two-Mac testing** on iCloud Drive.
9. **Polish:** "Last synced" label, manual "Sync now" button, error surfacing.

---

## Test cases

**Unit tests (merge and categories):**
- Same feed on two devices, different titles -> newer `updatedAt` wins.
- Feed deleted on A (tombstone), still live on B with an older timestamp -> stays deleted.
- Feed deleted on A, edited on B *after* deletion -> feed comes back (newer edit wins). Decide if that is what you want.
- Same feed URL added independently on both -> exactly one record.
- **Category renamed on A, feed added to it on B -> one category with the new name, containing the new feed.**
- **"News" created independently on both Macs -> one visible "News"; feeds from both appear under it; no writes triggered by the dedupe.**
- **Duplicate-name resolution picks the same winner regardless of input order.**
- **Category deleted on A, feed moved into it on B (older timestamp than the delete) -> feed shows as Uncategorized, still exists.**
- **Category deleted on A (feeds reset to nil), feed concurrently moved by B into the deleted category with a newer timestamp -> feed shows as Uncategorized.**
- **Feed arrives referencing a category ID not yet present -> Uncategorized; after the category arrives, feed appears in it with no feed rewrite.**
- **Feed moved between categories on A and renamed on B -> last-writer-wins on the whole feed record. Check this is acceptable (it means the other edit is lost).**
- **Reorder categories on both Macs offline -> converge to the same order; midpoint insertion doesn't collide.**
- Merge is idempotent: `merge([merge(x)]) == merge(x)`.
- Merge is order-independent.
- Old tombstones pruned, recent ones kept.

**Manual (two Macs, or one Mac plus a second user account or VM signed into the same Apple ID):**
- Fresh install, iCloud Drive on -> "Enable sync" creates `MyRSSReader/devices/` and it appears in Finder under iCloud Drive.
- Fresh install, iCloud Drive off or signed out -> clear "Turn on iCloud Drive" message, no folder created, no crash.
- Second Mac enabling sync after the first -> finds the existing folder (or merges with an empty one), and picks up the first Mac's feeds and categories.
- Pre-existing non-app folder named `MyRSSReader` -> handled without writing into it.
- Change sync folder in Settings -> this device's file is carried over, sync resumes, no data lost.
- Add a category and feed on A -> both appear on B within about a minute, with B's app open.
- Same, with B's app closed, then launched.
- Move a feed to another category on A -> moves on B.
- Delete a category on A -> feeds land in Uncategorized on B, nothing is lost.
- Delete on A -> disappears from B and does not come back.
- Edit on both while offline, then reconnect -> converges, no duplicates, no crash.
- Corrupt or empty JSON file in `devices/` -> ignored gracefully.
- Sign out of iCloud or pause iCloud Drive -> app keeps working locally and shows a sync warning.
- No ping-pong: watch the folder for a minute after a sync settles and confirm no further writes occur.

---

## Gotchas and notes

- **Last-writer-wins is per record, not per field.** If A renames a feed while B moves it to another category, one edit wins and the other is lost. For a feed list this is normally acceptable. If it bothers you, add per-field timestamps (`titleUpdatedAt`, `categoryUpdatedAt`) later. The file format is versioned, so you can add them.
- **Sync is not instant.** Expect seconds to a minute or more. Say so in the UI ("Last synced 2 min ago").
- **Don't sync article content or caches.** Only categories and the feed list. Keep the file small.
- **Read/unread state:** if you add it later, use a **separate file per device** (`state-<deviceID>.json`) so frequent writes never touch the feed list. Sync lists of read article IDs with timestamps, and prune old entries.
- **Schema versioning:** keep `schemaVersion` in the file. If a file has a *newer* version than the app understands, ignore it and tell the user to update rather than overwriting it.
- **Dates:** always UTC and ISO-8601. Clock skew between Macs can make last-writer-wins pick the "wrong" winner by a few seconds, which is acceptable here.
- **Don't write on every launch.** Only write when the merged result differs from your file on disk.
- **User moves or deletes the sync folder:** detect a missing folder, stop the presenter, and offer to recreate the default folder ("Enable sync") or choose another. Local data is never lost, because the app keeps its own database and the sync folder is only a transport.
- **OPML export** remains a worthwhile manual fallback and for migrating to other readers. OPML supports nested `<outline>` elements for categories, which map directly onto your single-category model.

## Sandboxing note

If you later sandbox the app (for example for the Mac App Store, which would also require the paid account):

- Enable "User Selected File: Read/Write".
- Convert the chosen folder to a **security-scoped bookmark** (`url.bookmarkData(options: .withSecurityScope)`), store the bookmark data, and resolve it on launch with `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`.
- `NSFilePresenter` and `NSFileCoordinator` work the same.

## Distribution reminder

Without a developer account you cannot notarize, so users will need to right-click -> Open the first time (or remove the quarantine attribute). The sync approach in this plan is unaffected by that.

## Future upgrade path

If you later get a paid account, you can swap the transport for CloudKit (or the proper iCloud ubiquity container) without changing the `CategoryRecord` / `FeedRecord` models or the merge functions. Only `SyncStore` needs replacing.
