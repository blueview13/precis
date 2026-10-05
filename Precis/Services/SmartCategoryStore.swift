import Foundation
import AppKit
import Combine

/// Stores only rule definitions. A sync directory may be granted with the
/// folder picker; each installation writes its own file and merges by UUID.
@MainActor
public final class SmartCategoryStore: ObservableObject {
    public static let shared = SmartCategoryStore()
    @Published public private(set) var categories: [SmartCategory] = []
    private let localURL: URL
    private var presenter: SmartCategoryFilePresenter?
    private var activeSyncFolder: URL?
    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent("Precis", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        localURL = directory.appendingPathComponent("smart-categories.json")
        if let folder = syncFolderURL { startWatching(folder) }
        load()
    }
    public func load() {
        if let data = try? Data(contentsOf: localURL), let file = try? JSONDecoder().decode(SmartCategorySyncFile.self, from: data) {
            categories = Self.merge(categories, file.categories)
        }
        if let folder = syncFolderURL, let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for url in urls where url.lastPathComponent.hasPrefix("Precis-smart-categories-") && url.pathExtension == "json" {
                guard let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(SmartCategorySyncFile.self, from: data) else { continue }
                categories = Self.merge(categories, file.categories)
            }
            saveLocal()
        }
    }
    public func upsert(_ category: SmartCategory) {
        var saved = category
        saved.updatedAt = Date()
        saved.isDeleted = false
        if let index = categories.firstIndex(where: { $0.id == saved.id }) { categories[index] = saved }
        else { categories.append(saved) }
        categories.sort { $0.sortOrder == $1.sortOrder ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending : $0.sortOrder < $1.sortOrder }
        saveLocal(); writeSyncFile()
    }
    public func remove(id: UUID) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].isDeleted = true; categories[index].updatedAt = Date(); saveLocal(); writeSyncFile()
    }
    public func setColor(_ colorHex: String?, for id: UUID) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].colorHex = colorHex
        categories[index].updatedAt = Date()
        saveLocal(); writeSyncFile()
    }
    public func chooseSyncFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "Use for Smart Category Sync"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Persist a security-scoped bookmark so the sandbox can access the
        // ordinary iCloud Drive folder without CloudKit entitlements.
        guard let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        UserDefaults.standard.set(bookmark, forKey: "smartCategorySyncFolderBookmark")
        startWatching(url); load(); writeSyncFile()
    }
    private var syncFolderURL: URL? {
        guard let data = UserDefaults.standard.data(forKey: "smartCategorySyncFolderBookmark") else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], bookmarkDataIsStale: &stale)
    }
    private var syncFileURL: URL? {
        let id: String
        if let saved = UserDefaults.standard.string(forKey: "smartCategoryDeviceID") { id = saved }
        else { let created = UUID().uuidString; UserDefaults.standard.set(created, forKey: "smartCategoryDeviceID"); id = created }
        return syncFolderURL?.appendingPathComponent("Precis-smart-categories-\(id).json")
    }
    private func saveLocal() {
        guard let data = try? JSONEncoder().encode(SmartCategorySyncFile(categories: categories)) else { return }
        try? data.write(to: localURL, options: .atomic)
    }
    private func writeSyncFile() {
        guard let folder = syncFolderURL, let url = syncFileURL,
              folder.startAccessingSecurityScopedResource() else { return }
        defer { folder.stopAccessingSecurityScopedResource() }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(SmartCategorySyncFile(categories: categories)) else { return }
        try? data.write(to: url, options: .atomic)
    }
    private func startWatching(_ folder: URL) {
        if let activeSyncFolder { activeSyncFolder.stopAccessingSecurityScopedResource() }
        guard folder.startAccessingSecurityScopedResource() else { return }
        activeSyncFolder = folder
        presenter = nil
        presenter = SmartCategoryFilePresenter(url: folder) { [weak self] in Task { @MainActor in self?.load() } }
    }
    private static func merge(_ lhs: [SmartCategory], _ rhs: [SmartCategory]) -> [SmartCategory] {
        var result: [UUID: SmartCategory] = [:]
        for item in lhs + rhs {
            if let old = result[item.id], old.updatedAt > item.updatedAt { continue }
            result[item.id] = item
        }
        return result.values.sorted { $0.sortOrder == $1.sortOrder ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending : $0.sortOrder < $1.sortOrder }
    }
}

private struct SmartCategorySyncFile: Codable {
    var schemaVersion = 1
    var categories: [SmartCategory]
    init(categories: [SmartCategory]) { self.categories = categories }
}

private final class SmartCategoryFilePresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    private let changed: () -> Void
    init(url: URL, changed: @escaping () -> Void) {
        presentedItemURL = url; self.changed = changed; super.init()
        NSFileCoordinator.addFilePresenter(self)
    }
    deinit { NSFileCoordinator.removeFilePresenter(self) }
    func presentedSubitemDidChange(at url: URL) { changed() }
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) { changed() }
    func presentedItemDidChange() { changed() }
}
