import SwiftUI

struct SettingsView: View {
    @Environment(InventoryStore.self) private var store

    var body: some View {
        Form {
            Section("Project Folders") {
                ForEach(store.projects, id: \.self) { url in
                    HStack {
                        PathText(url.path)
                        Spacer()
                        Button("Remove", role: .destructive) { store.removeProject(url) }
                    }
                }
                Button("Add Project Folder…") { store.addProject() }
            }
            Section("Privacy") {
                Text("Skillori reads skill folders on this Mac. It doesn't upload anything, and it doesn't run scripts from skills.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 320)
    }
}
