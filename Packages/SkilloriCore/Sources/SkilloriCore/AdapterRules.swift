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
    /// The Claude desktop app (chat and Cowork), as distinct from Claude Code.
    public static let claudeDesktop = Agent("claude-desktop", "Claude")
    public static let cline = Agent("cline", "Cline")
    public static let roo = Agent("roo", "Roo Code")
    public static let kilo = Agent("kilo", "Kilo Code")
    public static let junie = Agent("junie", "Junie")
    public static let qwen = Agent("qwen-code", "Qwen Code")
    public static let crush = Agent("crush", "Crush")
    public static let augment = Agent("augment", "Augment")
    public static let warp = Agent("warp", "Warp")
    public static let letta = Agent("letta", "Letta Code")
    public static let qoder = Agent("qoder", "Qoder")
    public static let openHands = Agent("openhands", "OpenHands")
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

/// How a plugin says where its skills are.
public struct PluginLayout: Sendable {
    /// Manifest files, relative to the plugin folder. The first one that names skill paths wins.
    public let manifests: [String]
    /// Whether paths named in the manifest are read instead of `skills/`, or as well as it.
    public let customPathsReplaceDefault: Bool

    public init(manifests: [String], customPathsReplaceDefault: Bool) {
        self.manifests = manifests
        self.customPathsReplaceDefault = customPathsReplaceDefault
    }
}

/// A variable that moves an agent's settings folder away from its place under home.
public struct Relocation: Sendable {
    public let variable: String
    /// The folder, relative to home, that the variable's value stands in for.
    public let prefix: String
    /// A folder inside the variable's value, for a variable that stands in for home itself.
    public let subpath: String

    public init(variable: String, prefix: String, subpath: String = "") {
        self.variable = variable
        self.prefix = prefix
        self.subpath = subpath
    }
}

/// One place where skills live: `<root>/<skill-name>/SKILL.md`.
///
/// `pattern` is relative to the home directory (personal), the project root (project) or the
/// disk root (system) and may contain `*` path components, e.g. `.gemini/extensions/*/skills`.
/// With `plugin` set, the pattern names plugin folders instead, and each plugin's manifest says
/// where its skills are (`skills/` unless it says otherwise).
public struct RootRule: Sendable {
    public let pattern: String
    public let scope: RootScope
    public let agents: [Agent]
    public let ownership: Ownership
    /// A file whose presence in any matched ancestor means "inactive copy" (e.g. an old
    /// plugin version awaiting cleanup).
    public let inactiveMarker: String?
    public let plugin: PluginLayout?
    public let note: String

    public init(_ pattern: String, _ scope: RootScope, _ agents: [Agent], ownership: Ownership = .user,
                inactiveMarker: String? = nil, plugin: PluginLayout? = nil, note: String) {
        self.pattern = pattern
        self.scope = scope
        self.agents = agents
        self.ownership = ownership
        self.inactiveMarker = inactiveMarker
        self.plugin = plugin
        self.note = note
    }
}

/// Adapter rules. Sources: docs/research/kompatibilitetsmatris.md (checked 2026-11-11) and the
/// agents' own documentation plus the `npx skills` agent table (checked 2026-11-16). These are
/// data, not logic: adding an agent should only touch this file.
public enum AdapterRules {
    public static let rulesVersion = "0.2 (2026-11-16)"

    /// Agents documented to read the shared `.agents/skills` root.
    static let sharedAgents: [Agent] = [.codex, .cursor, .geminiCLI, .copilot, .openCode, .amp, .droid, .devin, .goose]
    /// Agents documented to read `.claude/skills` in addition to Claude Code itself.
    static let claudeCompatible: [Agent] = [.claudeCode, .cursor, .copilot, .openCode, .amp, .goose]

    /// Where the Claude desktop app keeps what it downloads for chat and Cowork.
    private static let claudeApp = "Library/Application Support/Claude/local-agent-mode-sessions"

    /// Claude Code adds manifest paths to `skills/`; Cursor and Codex read them instead of it.
    static let claudePlugin = PluginLayout(manifests: [".claude-plugin/plugin.json"], customPathsReplaceDefault: false)
    static let cursorPlugin = PluginLayout(manifests: [".cursor-plugin/plugin.json"], customPathsReplaceDefault: true)
    static let codexPlugin = PluginLayout(manifests: [".codex-plugin/plugin.json"], customPathsReplaceDefault: true)
    /// The documentation does not say which way Copilot goes, so nothing is left out.
    static let copilotPlugin = PluginLayout(manifests: ["plugin.json", ".github/plugin/plugin.json", ".claude-plugin/plugin.json"],
                                            customPathsReplaceDefault: false)

    /// Plugins Claude Code has installed. Also used for the folders its install record names.
    static let claudeCodePlugins = RootRule(
        ".claude/plugins/cache/*/*/*", .personal, [.claudeCode, .amp],
        ownership: .managed(by: "Claude Code plugin"), inactiveMarker: ".orphaned_at", plugin: claudePlugin,
        note: "Installed Claude Code plugin versions")

    /// Variables that move a settings folder. A set variable adds a place to read; the usual
    /// place is still read, since other agents keep using it.
    public static let relocations: [Relocation] = [
        Relocation(variable: "CLAUDE_CONFIG_DIR", prefix: ".claude"),
        Relocation(variable: "CLAUDE_CODE_PLUGIN_CACHE_DIR", prefix: ".claude/plugins"),
        Relocation(variable: "CODEX_HOME", prefix: ".codex"),
        Relocation(variable: "COPILOT_HOME", prefix: ".copilot"),
        Relocation(variable: "XDG_CONFIG_HOME", prefix: ".config"),
        // This one stands in for home itself: Gemini CLI makes a `.gemini` folder inside it.
        Relocation(variable: "GEMINI_CLI_HOME", prefix: ".gemini", subpath: ".gemini"),
    ]

    public static let personal: [RootRule] = [
        RootRule(".agents/skills", .personal, sharedAgents, note: "Shared root; canonical copy for `npx skills`"),
        RootRule(".agent/skills", .personal, [.droid], note: "Shared root, older spelling"),
        RootRule(".claude/skills", .personal, claudeCompatible, note: "Claude Code personal skills"),
        RootRule(".claude/skills/synced", .personal, [.claudeCode], ownership: .managed(by: "claude.ai"),
                 note: "Synced from claude.ai; overwritten by Claude Code"),
        claudeCodePlugins,
        RootRule("\(claudeApp)/skills-plugin/*/*/skills", .personal, [.claudeDesktop],
                 ownership: .managed(by: "Claude app"), note: "Downloaded by the Claude app from your account"),
        RootRule("\(claudeApp)/*/*/rpm/*", .personal, [.claudeDesktop],
                 ownership: .managed(by: "Claude app plugin"), plugin: claudePlugin,
                 note: "Plugins installed in the Claude app"),
        RootRule(".cursor/skills", .personal, [.cursor], note: "Cursor personal skills"),
        RootRule(".cursor/skills-cursor", .personal, [.cursor], ownership: .managed(by: "Cursor"),
                 note: "Built into Cursor"),
        RootRule(".cursor/plugins/cache/*/*/*", .personal, [.cursor],
                 ownership: .managed(by: "Cursor plugin"), plugin: cursorPlugin, note: "Installed Cursor plugins"),
        RootRule(".cursor/plugins/local/*", .personal, [.cursor],
                 ownership: .managed(by: "Cursor plugin"), plugin: cursorPlugin, note: "Local Cursor plugins"),
        RootRule(".codex/skills", .personal, [.codex, .cursor], note: "Codex skill-installer target"),
        RootRule(".codex/skills/.system", .personal, [.codex], ownership: .managed(by: "Codex"),
                 note: "Built into Codex"),
        RootRule(".codex/plugins/cache/*/*/*", .personal, [.codex],
                 ownership: .managed(by: "Codex plugin"), plugin: codexPlugin, note: "Installed Codex plugins"),
        RootRule(".gemini/skills", .personal, [.geminiCLI, .antigravity], note: "Gemini CLI personal skills"),
        RootRule(".gemini/config/skills", .personal, [.antigravity], note: "Antigravity global skills"),
        RootRule(".gemini/config/plugins/*/skills", .personal, [.antigravity],
                 ownership: .managed(by: "Antigravity plugin"), note: "Antigravity plugins"),
        RootRule(".gemini/antigravity/skills", .personal, [.antigravity], note: "Antigravity skills, older place"),
        RootRule(".gemini/antigravity-cli/skills", .personal, [.antigravity], note: "Antigravity CLI skills"),
        RootRule(".gemini/extensions/*/skills", .personal, [.geminiCLI],
                 ownership: .managed(by: "Gemini CLI extension"), note: "Gemini CLI extensions"),
        RootRule(".copilot/skills", .personal, [.copilot], note: "GitHub Copilot personal skills"),
        RootRule(".copilot/installed-plugins/*/*", .personal, [.copilot],
                 ownership: .managed(by: "GitHub Copilot plugin"), plugin: copilotPlugin,
                 note: "Installed GitHub Copilot plugins"),
        RootRule(".config/opencode/skills", .personal, [.openCode], note: "OpenCode personal skills"),
        RootRule(".config/agents/skills", .personal, [.amp], note: "Amp (`amp skill add --global`)"),
        RootRule(".config/amp/skills", .personal, [.amp], note: "Amp personal skills"),
        RootRule(".config/goose/skills", .personal, [.goose], note: "goose personal skills"),
        RootRule(".config/devin/skills", .personal, [.devin], note: "Devin Desktop / Windsurf"),
        RootRule(".codeium/windsurf/skills", .personal, [.devin], note: "Windsurf personal skills"),
        RootRule(".codeium/windsurf-next/skills", .personal, [.devin], note: "Windsurf Next personal skills"),
        RootRule(".factory/skills", .personal, [.droid], note: "Factory Droid personal skills"),
        RootRule(".kiro/skills", .personal, [.kiro], note: "Kiro personal skills"),
        RootRule(".cline/skills", .personal, [.cline], note: "Cline personal skills"),
        RootRule(".roo/skills", .personal, [.roo], note: "Roo Code personal skills"),
        RootRule(".kilo/skills", .personal, [.kilo], note: "Kilo Code personal skills"),
        RootRule(".junie/skills", .personal, [.junie], note: "Junie personal skills"),
        RootRule(".qwen/skills", .personal, [.qwen], note: "Qwen Code personal skills"),
        RootRule(".config/crush/skills", .personal, [.crush], note: "Crush personal skills"),
        RootRule(".augment/skills", .personal, [.augment], note: "Augment personal skills"),
        RootRule(".warp/skills", .personal, [.warp], note: "Warp personal skills"),
        RootRule(".letta/skills", .personal, [.letta], note: "Letta Code personal skills"),
        RootRule(".qoder/skills", .personal, [.qoder], note: "Qoder personal skills"),
        RootRule(".openhands/skills", .personal, [.openHands], note: "OpenHands personal skills"),
    ] + others.compactMap { other in
        other.personal.map { RootRule($0, .personal, [Agent(other.id, other.name)], note: "\(other.name) personal skills") }
    }

    /// Places set up by an administrator, relative to the disk root.
    public static let system: [RootRule] = [
        RootRule("Library/Application Support/ClaudeCode/.claude/skills", .personal, [.claudeCode],
                 ownership: .managed(by: "your organization"), note: "Claude Code skills set by an administrator"),
        RootRule("etc/codex/skills", .personal, [.codex],
                 ownership: .managed(by: "your organization"), note: "Codex skills set by an administrator"),
    ]

    public static let project: [RootRule] = [
        RootRule(".agents/skills", .project, sharedAgents, note: "Shared project root"),
        RootRule(".agent/skills", .project, [.droid, .antigravity], note: "Shared project root, older spelling"),
        RootRule(".claude/skills", .project, claudeCompatible, note: "Claude Code project skills"),
        RootRule(".cursor/skills", .project, [.cursor], note: "Cursor project skills"),
        RootRule(".codex/skills", .project, [.cursor, .codex], note: "Codex compatibility root"),
        RootRule(".github/skills", .project, [.copilot], note: "GitHub Copilot project skills"),
        RootRule(".gemini/skills", .project, [.geminiCLI], note: "Gemini CLI workspace skills"),
        RootRule(".opencode/skills", .project, [.openCode], note: "OpenCode project skills"),
        RootRule(".kiro/skills", .project, [.kiro], note: "Kiro workspace skills"),
        RootRule(".factory/skills", .project, [.droid], note: "Factory Droid project skills"),
        RootRule(".devin/skills", .project, [.devin], note: "Devin Desktop project skills"),
        RootRule(".windsurf/skills", .project, [.devin], note: "Windsurf (legacy) project skills"),
        RootRule(".goose/skills", .project, [.goose], note: "goose project skills"),
        RootRule(".cline/skills", .project, [.cline], note: "Cline project skills"),
        RootRule(".clinerules/skills", .project, [.cline], note: "Cline project skills"),
        RootRule(".roo/skills", .project, [.roo], note: "Roo Code project skills"),
        RootRule(".kilo/skills", .project, [.kilo], note: "Kilo Code project skills"),
        RootRule(".kilocode/skills", .project, [.kilo], note: "Kilo Code (legacy) project skills"),
        RootRule(".junie/skills", .project, [.junie], note: "Junie project skills"),
        RootRule(".qwen/skills", .project, [.qwen], note: "Qwen Code project skills"),
        RootRule(".crush/skills", .project, [.crush], note: "Crush project skills"),
        RootRule(".augment/skills", .project, [.augment], note: "Augment project skills"),
        RootRule(".warp/skills", .project, [.warp], note: "Warp project skills"),
        RootRule(".qoder/skills", .project, [.qoder], note: "Qoder project skills"),
        RootRule(".openhands/skills", .project, [.openHands], note: "OpenHands project skills"),
    ] + others.compactMap { other in
        other.project.map { RootRule($0, .project, [Agent(other.id, other.name)], note: "\(other.name) project skills") }
    }

    /// Agents known only from the `npx skills` agent table (vercel-labs/skills, `src/agents.ts`):
    /// each has one folder of its own under home and, mostly, one in a project.
    static let others: [(id: String, name: String, personal: String?, project: String?)] = [
        ("adal", "AdaL", ".adal/skills", ".adal/skills"),
        ("aider-desk", "AiderDesk", ".aider-desk/skills", ".aider-desk/skills"),
        ("astrbot", "AstrBot", ".astrbot/data/skills", nil),
        ("autohand", "Autohand Code", ".autohand/skills", ".autohand/skills"),
        ("bob", "IBM Bob", ".bob/skills", ".bob/skills"),
        ("codearts", "CodeArts Agent", ".codeartsdoer/skills", ".codeartsdoer/skills"),
        ("codebuddy", "CodeBuddy", ".codebuddy/skills", ".codebuddy/skills"),
        ("codemaker", "Codemaker", ".codemaker/skills", ".codemaker/skills"),
        ("codestudio", "Code Studio", ".codestudio/skills", ".codestudio/skills"),
        ("commandcode", "Command Code", ".commandcode/skills", ".commandcode/skills"),
        ("continue", "Continue", ".continue/skills", ".continue/skills"),
        ("cortex", "Cortex Code", ".snowflake/cortex/skills", ".cortex/skills"),
        ("deepagents", "Deep Agents", ".deepagents/agent/skills", nil),
        ("firebender", "Firebender", ".firebender/skills", nil),
        ("forge", "ForgeCode", ".forge/skills", ".forge/skills"),
        ("grok", "Grok Build", ".grok/skills", ".grok/skills"),
        ("hermes", "Hermes Agent", ".hermes/skills", ".hermes/skills"),
        ("iflow", "iFlow CLI", ".iflow/skills", ".iflow/skills"),
        ("inferencesh", "inference.sh", ".inferencesh/skills", ".inferencesh/skills"),
        ("jazz", "Jazz", ".jazz/skills", ".jazz/skills"),
        ("kimchi", "Kimchi", ".config/kimchi/harness/skills", ".kimchi/skills"),
        ("kode", "Kode", ".kode/skills", ".kode/skills"),
        ("lingma", "Lingma", ".lingma/skills", ".lingma/skills"),
        ("mcpjam", "MCPJam", ".mcpjam/skills", ".mcpjam/skills"),
        ("minimax", "MiniMax Code", ".minimax/skills", ".minimax/skills"),
        ("moxby", "Moxby", ".moxby/skills", ".moxby/skills"),
        ("mux", "Mux", ".mux/skills", ".mux/skills"),
        ("neovate", "Neovate", ".neovate/skills", ".neovate/skills"),
        ("ona", "Ona", ".ona/skills", ".ona/skills"),
        ("openclaw", "OpenClaw", ".openclaw/skills", nil),
        ("pi", "Pi", nil, ".pi/skills"),
        ("pochi", "Pochi", ".pochi/skills", ".pochi/skills"),
        ("posit", "Posit Assistant", ".posit/assistant/skills", ".posit/assistant/skills"),
        ("qoder-cn", "Qoder CN", ".qoder-cn/skills", nil),
        ("reasonix", "Reasonix", ".reasonix/skills", ".reasonix/skills"),
        ("rovodev", "Rovo Dev", ".rovodev/skills", ".rovodev/skills"),
        ("tabnine", "Tabnine CLI", ".tabnine/agent/skills", ".tabnine/agent/skills"),
        ("terramind", "Terramind", ".terramind/skills", ".terramind/skills"),
        ("tinycloud", "Tinycloud", ".tinycloud/skills", ".tinycloud/skills"),
        ("trae", "Trae", ".trae/skills", ".trae/skills"),
        ("trae-cn", "Trae CN", ".trae-cn/skills", nil),
        ("vibe", "Mistral Vibe", ".vibe/skills", ".vibe/skills"),
        ("zcode", "ZCode", ".zcode/skills", ".zcode/skills"),
        ("zencoder", "Zencoder", ".zencoder/skills", ".zencoder/skills"),
    ]
}
