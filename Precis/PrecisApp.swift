import SwiftUI
import SwiftData

@main
struct PrecisApp: App {
    private let modelContainer: ModelContainer = {
        do {
            return try ModelContainerProvider.makeContainer()
        } catch {
            fatalError("Unable to create the model container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainWindowLayout()
                .modelContainer(modelContainer)
        }

        Window("Settings", id: "settings") {
            SettingsView(
                onImportOPML: nil,
                onExportOPML: nil,
                hasFeeds: false
            )
            .modelContainer(modelContainer)
            .frame(width: 480, height: 560)
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
}
