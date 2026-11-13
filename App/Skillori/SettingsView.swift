import AppKit
import SkilloriCore
import SkilloriUI
import SwiftUI

/// How the app should look. Stored in user defaults and applied to the whole app.
enum AppearanceSetting: String, CaseIterable {
    case system, light, dark
    static let key = "appearance"

    static var current: AppearanceSetting {
        AppearanceSetting(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
    }

    @MainActor
    func apply() {
        UserDefaults.standard.set(rawValue, forKey: Self.key)
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

struct SettingsView: View {
    @Environment(InventoryStore.self) private var store
    /// True in our own window, which has no system title bar.
    var ownChrome = false
    /// Reports the height the content needs, so the window can fit it exactly.
    var onHeight: ((CGFloat) -> Void)?
    @State private var appearance = AppearanceSetting.current

    private static let width: CGFloat = 640
    private static let columnWidth = (width - 6 * 3) / 2

    var body: some View {
        VStack(spacing: 6) {
            if ownChrome {
                HStack {
                    Text("Settings").font(TypeRole.sans(13, .medium))
                    Spacer()
                }
                .padding(.leading, 78)
                .frame(height: 52)
            }
            folders
            // The left column sets the height; the privacy block is laid over the space
            // beside it, so it is exactly as tall.
            VStack(spacing: 6) {
                general
                checking
            }
            .frame(width: Self.columnWidth)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) { privacy.frame(width: Self.columnWidth) }
            Text("All product names and logos belong to their owners. Skillori is not affiliated with or endorsed by them.")
                .font(TypeRole.sans(11))
                .foregroundStyle(Palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 8, leading: 14, bottom: 6, trailing: 14))
        }
        .padding(EdgeInsets(top: ownChrome ? 0 : 6, leading: 6, bottom: 6, trailing: 6))
        // Every part has a fixed height, so this is the height the window should have.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight?($0) }
        .frame(width: Self.width)
        // No minimum height of its own: the window is fitted to the measured height, and a
        // minimum here would have the system add the title bar's height on top of it.
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
        .background(Palette.panel)
        .foregroundStyle(Palette.ink)
        .font(TypeRole.sans(13))
        .ignoresSafeArea(edges: ownChrome ? .top : [])
    }

    // MARK: Folders

    private var folders: some View {
        let roots = store.inventory?.roots.filter { $0.state == .found } ?? []
        let shared = roots.first { $0.path.hasSuffix("/.agents/skills") }
        let agents = Array(Set((store.inventory?.installations ?? []).flatMap(\.agents))).sorted()
        return LabeledCard("Folders", note: "\(roots.count) read · \(store.projects.count) added by you") {
            if let shared {
                SettingRow {
                    titled("Shared skills", path: shared.path)
                } trailing: {
                    StatusChip("Found")
                }
            }
            if !agents.isEmpty {
                SettingRow {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(agentSummary(agents)).lineLimit(1)
                        DataText("Each agent's own skill folder").foregroundStyle(Palette.ink2)
                    }
                } trailing: {
                    StatusChip("Found")
                }
            }
            ForEach(store.projects, id: \.self) { url in
                SettingRow {
                    titled(url.lastPathComponent, path: url.path)
                } trailing: {
                    StatusChip("Added by you")
                    Button("Remove") { store.removeProject(url) }.buttonStyle(PillButtonStyle())
                }
            }
            SettingRow(isLast: true) {
                Text("Full Disk Access is not needed. Skillori reads only its known skill folders and the ones you add.")
                    .font(TypeRole.sans(12))
                    .foregroundStyle(Palette.ink2)
            } trailing: {
                Button("Add folder") { store.addProject() }.buttonStyle(PillButtonStyle())
            }
        }
    }

    private func titled(_ title: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).lineLimit(1)
            DataText((path as NSString).abbreviatingWithTildeInPath)
                .truncationMode(.middle)
                .foregroundStyle(Palette.ink2)
                .help(path)
        }
    }

    private func agentSummary(_ agents: [Agent]) -> String {
        let names = agents.map(\.displayName)
        guard names.count > 3 else { return names.joined(separator: ", ") }
        return names.prefix(3).joined(separator: ", ") + " and \(names.count - 3) more agents"
    }

    // MARK: General

    private var general: some View {
        LabeledCard("General") {
            SettingRow {
                Text("Appearance")
            } trailing: {
                SegmentedChoice([(.system, "System"), (.light, "Light"), (.dark, "Dark")], selection: $appearance)
            }
            SettingRow(isLast: true) {
                Text("First start")
            } trailing: {
                Button("Show again") { NotificationCenter.default.post(name: .showFirstStart, object: nil) }
                    .buttonStyle(PillButtonStyle())
            }
        }
        .onChange(of: appearance) { _, new in new.apply() }
    }

    private var checking: some View {
        LabeledCard("Checking for changes", note: store.checkStamp) {
            SettingRow {
                Text("Ask sources if a skill has changed")
            } trailing: {
                SegmentedChoice([(false, "Off"), (true, "On")],
                                selection: Binding(get: { store.checksEnabled }, set: { store.checksEnabled = $0 }))
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Asks github.com about each source, every 6 hours while Skillori runs. It sends the source's name and nothing about you or your files. No account. Skillori never updates a skill itself.")
                    .font(TypeRole.sans(12))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Palette.ink2)
                Button(store.isChecking ? "Checking…" : "Check now") { Task { await store.checkSources(force: true) } }
                    .buttonStyle(PillButtonStyle())
                    .disabled(!store.checksEnabled || store.isChecking)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
    }

    // MARK: Privacy

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                LabelText("Privacy")
                Spacer(minLength: 8)
                LabelText("No telemetry")
            }
            .foregroundStyle(Tone.rest.secondary)
            Text("Skillori reads skill folders on this Mac. It doesn't upload anything, and it doesn't run scripts from skills.")
                .font(TypeRole.sans(15, .medium))
                .tracking(-0.15)
                .lineSpacing(3)
            Spacer(minLength: 12)
            HStack(spacing: 12) {
                SkilloriMark().fill(Tone.rest.foreground).frame(width: 18, height: 18)
                DataText("SKILLORI \(version)").foregroundStyle(Tone.rest.foreground.opacity(0.7))
                Spacer()
                DataText("RULES \(AdapterRules.rulesVersion.split(separator: " ").first.map(String.init)?.uppercased() ?? "")").foregroundStyle(Tone.rest.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
        .foregroundStyle(Tone.rest.foreground)
        .background(Tone.rest.background, in: RoundedRectangle(cornerRadius: Radius.block, style: .continuous))
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
