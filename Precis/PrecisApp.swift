import SwiftUI
import SwiftData

@main
struct PrecisApp: App {
    @AppStorage(PrecisTheme.storageKey) private var selectedThemeRawValue = PrecisTheme.standard.rawValue

    private let modelContainer: ModelContainer = {
        do {
            return try ModelContainerProvider.makeContainer()
        } catch {
            fatalError("Unable to create the model container: \(error)")
        }
    }()

    private var selectedTheme: PrecisTheme {
        PrecisTheme(rawValue: selectedThemeRawValue) ?? .standard
    }

    var body: some Scene {
        WindowGroup {
            MainWindowLayout()
                .modelContainer(modelContainer)
                .preferredColorScheme(selectedTheme.colorScheme)
                .tint(selectedTheme.accent)
        }

        Window("Settings", id: "settings") {
            SettingsView(
                onImportOPML: nil,
                onExportOPML: nil,
                hasFeeds: false
            )
            .modelContainer(modelContainer)
            .frame(width: 480, height: 560)
            .preferredColorScheme(selectedTheme.colorScheme)
            .tint(selectedTheme.accent)
        }
        .defaultSize(width: 480, height: 560)
        .commands {
            // Settings… in the Precis app menu (⌘,)
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .precisOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    /// Posted by the app menu's Settings command. The main window observes it
    /// and calls its `openWindow` action (commands have no window environment).
    static let precisOpenSettings = Notification.Name("PrecisOpenSettings")
    /// Posted after an OPML import completes in the Settings window so the
    /// main window reloads its sidebar feed list.
    static let precisFeedsImported = Notification.Name("PrecisFeedsImported")}
