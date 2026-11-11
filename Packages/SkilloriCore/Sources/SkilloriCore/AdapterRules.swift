import Foundation

/// An agent or tool that can load skills. Identified by a stable id, never by display text.
public struct Agent: Hashable, Sendable, Comparable {
    public let id: String
    public let displayName: String

    public init(_ id: String, _ displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    public static func < (a: Agent, b: Agent) -> Bool { a.displayName < b.displayName }

    public static let claudeCode = Agent("claude-code", "Claude Code")
    public static let cursor = Agent("cursor", "Cursor")
    public static let codex = Agent("codex", "Codex")
    public static let geminiCLI = Agent("gemini-cli", "Gemini CLI")
    public static let antigravity = Agent("antigravity", "Antigravity")
    public static let copilot = Agent("github-copilot", "GitHub Copilot")
    public static let openCode = Agent("opencode", "OpenCode")
    public static let amp = Agent("amp", "Amp")
    public static let kiro = Agent("kiro", "Kiro")
    public static let droid = Agent("droid", "Factory Droid")
    public static let devin = Agent("devin", "Devin Desktop")
    public static let goose = Agent("goose", "goose")
}

public enum RootScope: String, Sendable {
    case personal
    case project
}

/// Who controls the content under a root.
public enum Ownership: Sendable, Equatable {
    /// The user put it there (by hand or with an installer). May have a source to track.
    case user
    /// A product manages it (plugin cache, built-in, synced). Skillori only reads it.
    case managed(by: String)
}

/// One place where skills live: `<root>/<skill-name>/SKILL.md`.
///
/// `pattern` is relative to the home directory (personal) or the project root (project) and
/// may contain `*` path components, e.g. `.claude/plugins/cache/*/*/*/skills`.
public struct RootRule: Sendable {
    public let pattern: String
    public let scope: RootScope
    public let agents: [Agent]
    public let ownership: Ownership
    /// A file whose presence in any matched ancestor means "inactive copy" (e.g. an old
    /// plugin version awaiting cleanup).
    public let inactiveMarker: String?
    public let note: String

    public init(_ pattern: String, _ scope: RootScope, _ agents: [Agent], ownership: Ownership = .user,
                inactiveMarker: String? = nil, note: String) {
        self.pattern = pattern
        self.scope = scope
        self.agents = agents
        self.ownership = ownership
        self.inactiveMarker = inactiveMarker
        self.note = note
    }
}

/// Adapter rules, version 0 (spike). Sources: docs/research/kompatibilitetsmatris.md, checked
/// 2026-11-11. These are data, not logic: adding an agent should only touch this list.
public enum AdapterRules {
    public static let rulesVersion = "0.1-spike (2026-11-11)"

    /// Agents documented to read the shared `.agents/skills` root.
    static let sharedAgents: [Agent] = [.codex, .cursor, .geminiCLI, .copilot, .openCode, .amp, .droid, .devin, .goose]
    /// Agents documented to read `.claude/skills` in addition to Claude Code itself.
    static let claudeCompatible: [Agent] = [.claudeCode, .cursor, .copilot, .openCode, .amp, .goose]

    public static let personal: [RootRule] = [
        RootRule(".agents/skills", .personal, sharedAgents, note: "Shared root; canonical copy for `npx skills`"),
        RootRule(".claude/skills", .personal, claudeCompatible, note: "Claude Code personal skills"),
        RootRule(".claude/skills/synced", .personal, [.claudeCode], ownership: .managed(by: "claude.ai"),
                 note: "Synced from claude.ai; overwritten by Claude Code"),
        RootRule(".claude/plugins/cache/*/*/*/skills", .personal, [.claudeCode, .amp],
                 ownership: .managed(by: "Claude Code plugin"), inactiveMarker: ".orphaned_at",
                 note: "Installed Claude Code plugin versions"),
        RootRule(".cursor/skills", .personal, [.cursor], note: "Cursor personal skills"),
        RootRule(".cursor/skills-cursor", .personal, [.cursor], ownership: .managed(by: "Cursor"),
                 note: "Built into Cursor"),
        RootRule(".cursor/plugins/cache/*/*/*/skills", .personal, [.cursor],
                 ownership: .managed(by: "Cursor plugin"), note: "Installed Cursor plugins"),
        RootRule(".codex/skills", .personal, [.codex, .cursor], note: "Codex skill-installer target"),
        RootRule(".codex/skills/.system", .personal, [.codex], ownership: .managed(by: "Codex"),
                 note: "Built into Codex"),
        RootRule(".codex/plugins/cache/*/*/*/skills", .personal, [.codex],
                 ownership: .managed(by: "Codex plugin"), note: "Installed Codex plugins"),
        RootRule(".gemini/skills", .personal, [.geminiCLI, .antigravity], note: "Gemini CLI personal skills"),
        RootRule(".gemini/config/skills", .personal, [.antigravity], note: "Antigravity global skills"),
        RootRule(".gemini/extensions/*/skills", .personal, [.geminiCLI],
                 ownership: .managed(by: "Gemini CLI extension"), note: "Gemini CLI extensions"),
        RootRule(".copilot/skills", .personal, [.copilot], note: "GitHub Copilot personal skills"),
        RootRule(".config/opencode/skills", .personal, [.openCode], note: "OpenCode personal skills"),
        RootRule(".config/agents/skills", .personal, [.amp], note: "Amp (`amp skill add --global`)"),
        RootRule(".config/devin/skills", .personal, [.devin], note: "Devin Desktop / Windsurf"),
        RootRule(".factory/skills", .personal, [.droid], note: "Factory Droid personal skills"),
        RootRule(".kiro/skills", .personal, [.kiro], note: "Kiro personal skills"),
    ]

    public static let project: [RootRule] = [
        RootRule(".agents/skills", .project, sharedAgents, note: "Shared project root"),
        RootRule(".claude/skills", .project, claudeCompatible, note: "Claude Code project skills"),
        RootRule(".cursor/skills", .project, [.cursor], note: "Cursor project skills"),
        RootRule(".codex/skills", .project, [.cursor], note: "Codex compatibility root"),
        RootRule(".github/skills", .project, [.copilot], note: "GitHub Copilot project skills"),
        RootRule(".gemini/skills", .project, [.geminiCLI], note: "Gemini CLI workspace skills"),
        RootRule(".opencode/skills", .project, [.openCode], note: "OpenCode project skills"),
        RootRule(".kiro/skills", .project, [.kiro], note: "Kiro workspace skills"),
        RootRule(".factory/skills", .project, [.droid], note: "Factory Droid project skills"),
        RootRule(".devin/skills", .project, [.devin], note: "Devin Desktop project skills"),
        RootRule(".windsurf/skills", .project, [.devin], note: "Windsurf (legacy) project skills"),
    ]
}
