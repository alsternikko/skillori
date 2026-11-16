import AppKit
import SkilloriCore
import SkilloriUI
import SwiftUI

/// Shows an agent by its logo: the icon of its installed app if there is one, else a bundled
/// logo if one has been added, else a plain tile with two letters.
struct AgentMark: View {
    let agent: Agent
    var size: CGFloat = 36

    var body: some View {
        if let image = AgentPresence.icon(for: agent) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .accessibilityLabel(agent.displayName)
                .help(agent.displayName)
        } else {
            Text(initials)
                .font(TypeRole.mono(size * 0.27))
                .tracking(0.4)
                .foregroundStyle(Palette.ink)
                .frame(width: size * 0.82, height: size * 0.82)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: size * 0.22, style: .circular))
                .frame(width: size, height: size)
                .accessibilityLabel(agent.displayName)
                .help(agent.displayName)
        }
    }

    private var initials: String {
        let words = agent.displayName.split(separator: " ")
        let letters = words.count > 1 ? words.prefix(2).compactMap(\.first).map(String.init).joined()
                                      : String(agent.displayName.prefix(2))
        return letters.uppercased()
    }
}

/// What is on this Mac for each agent: its app and its settings folder.
@MainActor
enum AgentPresence {
    /// App names to look for in the Applications folders.
    private static let appNames: [String: [String]] = [
        "claude-code": ["Claude"], "claude-desktop": ["Claude"], "cursor": ["Cursor"], "antigravity": ["Antigravity"],
        "codex": ["Codex"], "kiro": ["Kiro"], "devin": ["Windsurf", "Devin"], "goose": ["Goose"],
    ]

    /// Folders, relative to home, whose presence shows that the agent has been used here.
    private static let homeFolders: [String: [String]] = [
        "claude-code": [".claude"], "cursor": [".cursor"], "codex": [".codex"],
        "gemini-cli": [".gemini"], "antigravity": [".gemini/antigravity", ".antigravity"],
        "github-copilot": [".copilot"], "opencode": [".config/opencode"], "amp": [".config/amp"],
        "kiro": [".kiro"], "droid": [".factory"], "devin": [".codeium/windsurf"], "goose": [".config/goose"],
    ]

    private static var iconCache: [String: NSImage?] = [:]

    static func appURL(for agent: Agent) -> URL? {
        let folders = [URL(fileURLWithPath: "/Applications"),
                       FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        for name in appNames[agent.id] ?? [] {
            for folder in folders {
                let url = folder.appendingPathComponent("\(name).app")
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }

    static func icon(for agent: Agent) -> NSImage? {
        if let cached = iconCache[agent.id] { return cached }
        var image: NSImage?
        if let app = appURL(for: agent) {
            image = NSWorkspace.shared.icon(forFile: app.path)
        } else if let url = Bundle.main.url(forResource: "agent-\(agent.id)", withExtension: "png") {
            image = NSImage(contentsOf: url)
        }
        iconCache[agent.id] = image
        return image
    }

    /// The ids of the agents found on this Mac at the last reading. Empty until the first one.
    @MainActor static var installedIDs: Set<String> = []

    /// Looks again which of these agents are on this Mac. Run with every reading.
    @MainActor static func refresh(among agents: [Agent]) {
        installedIDs = Set(found(among: agents).map(\.id))
    }

    /// Agents with an app or a settings folder on this Mac, out of the ones Skillori knows.
    static func found(among agents: [Agent]) -> [Agent] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return agents.filter { agent in
            if appURL(for: agent) != nil { return true }
            return (homeFolders[agent.id] ?? []).contains {
                FileManager.default.fileExists(atPath: home.appendingPathComponent($0).path)
            }
        }
    }
}

extension Installation {
    /// The agents that read this skill's folders and are on this Mac. A folder the shared root
    /// documents for twelve agents says nothing to a reader who has two of them.
    @MainActor var installedAgents: [Agent] {
        let present = AgentPresence.installedIDs
        guard !present.isEmpty else { return agents }
        return agents.filter { present.contains($0.id) }
    }

    /// Agents documented to read this skill's folders that are not on this Mac.
    @MainActor var absentAgents: [Agent] {
        let present = AgentPresence.installedIDs
        guard !present.isEmpty else { return [] }
        return agents.filter { !present.contains($0.id) }
    }
}
