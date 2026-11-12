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
    @State private var appearance = AppearanceSetting.current

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
            HStack(alignment: .top, spacing: 6) {
                VStack(spacing: 6) {
                    general
                    checking
                }
                privacy
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(EdgeInsets(top: ownChrome ? 0 : 6, leading: 6, bottom: 6, trailing: 6))
        .frame(width: 640)
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
        LabeledCard("Checking for changes", note: "Not built yet") {
            Text("Skillori reads this Mac and nothing else. Asking sources whether a skill has changed, and telling you about it, comes in a later version.")
                .font(TypeRole.sans(12))
                .lineSpacing(2)
                .foregroundStyle(Palette.ink2)
                .padding(.top, 6)
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
                SkilloriMark().fill(Tone.rest.foreground).frame(width: 14, height: 20)
                DataText("SKILLORI \(version)").foregroundStyle(Tone.rest.foreground.opacity(0.7))
                Spacer()
                DataText("RULES \(AdapterRules.rulesVersion.split(separator: " ").first.map(String.init)?.uppercased() ?? "")").foregroundStyle(Tone.rest.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
        .foregroundStyle(Tone.rest.foreground)
        .background(Tone.rest.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
