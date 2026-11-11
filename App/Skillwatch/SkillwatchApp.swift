import SwiftUI

@main
struct SkillwatchApp: App {
    @State private var store = InventoryStore()

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
                .environment(store)
        } label: {
            Label("Skillwatch", systemImage: store.needsAttention ? "sparkles.rectangle.stack.fill" : "sparkles.rectangle.stack")
        }
        .menuBarExtraStyle(.window)

        Window("Skillwatch Library", id: WindowID.library) {
            LibraryView()
                .environment(store)
                .frame(minWidth: 820, minHeight: 480)
        }
        .defaultSize(width: 1040, height: 640)

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}

enum WindowID {
    static let library = "library"
}
