import SwiftUI

struct MenuPanel: View {
    @Environment(InventoryStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Skillori").font(.headline)
                Text(summary).font(.subheadline)
                Text(lastScanned).font(.caption).foregroundStyle(.secondary)
            }

            if let inventory = store.inventory {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    StatRow(label: "Tracked source", value: store.trackedCount, systemImage: "checkmark.seal")
                    StatRow(label: "Local changes", value: store.localChangeCount, systemImage: "pencil.circle",
                            highlight: store.localChangeCount > 0)
                    StatRow(label: "Source unknown", value: store.unknownCount, systemImage: "questionmark.circle")
                    StatRow(label: "Managed by an app", value: store.managedCount, systemImage: "shippingbox")
                }
                .font(.callout)
                Text("\(inventory.bindingCount) locations · \(inventory.roots.filter { $0.state == .found }.count) roots")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                PanelButton("Open Library…", systemImage: "books.vertical") {
                    NSApp.activate()
                    openWindow(id: WindowID.library)
                }
                PanelButton(store.isScanning ? "Scanning…" : "Scan Now", systemImage: "arrow.clockwise") {
                    Task { await store.rescan() }
                }
                .disabled(store.isScanning)
                PanelButton("Add Project Folder…", systemImage: "folder.badge.plus") { store.addProject() }
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                PanelButton("Settings…", systemImage: "gearshape") {
                    NSApp.activate()
                    openSettings()
                }
                PanelButton("Quit Skillori", systemImage: "power") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private var summary: String {
        guard let inventory = store.inventory else { return "Scanning…" }
        let n = inventory.installations.count
        return "\(n) skill\(n == 1 ? "" : "s") found"
    }

    private var lastScanned: String {
        guard let inventory = store.inventory else { return " " }
        let time = inventory.scannedAt.formatted(date: .omitted, time: .shortened)
        return "Last scanned \(time) · \(Int(inventory.duration * 1000)) ms"
    }
}

private struct StatRow: View {
    let label: String
    let value: Int
    let systemImage: String
    var highlight = false

    var body: some View {
        GridRow {
            Label(label, systemImage: systemImage)
                .foregroundStyle(highlight ? Color.orange : Color.primary)
            Text("\(value)").monospacedDigit().gridColumnAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PanelButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var hovering = false

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(hovering ? Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: 5))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
