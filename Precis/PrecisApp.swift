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
    }
}
