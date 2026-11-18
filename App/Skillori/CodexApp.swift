import AppKit
import Foundation
import SkilloriCore

/// Codex as an app on this Mac: what opens its `codex://` links, the command line tool that
/// comes with it, and what Codex says about its plugins. Codex may be an app of its own or
/// live inside ChatGPT, so it is found by the links it opens rather than by a name.
enum CodexApp {
    /// The app that opens `codex://` links: Codex, or ChatGPT with Codex inside.
    static var appURL: URL? {
        guard let probe = URL(string: "codex://") else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: probe)
    }

    /// Codex's command line tool inside that app, when the app ships one.
    static var bundledTool: URL? {
        guard let app = appURL else { return nil }
        let tool = app.appendingPathComponent("Contents/Resources/codex-cli/bin/codex")
        return FileManager.default.isExecutableFile(atPath: tool.path) ? tool : nil
    }

    /// Opens Codex on one plugin's own page, where it can be added and signed in to.
    static func pluginLink(_ id: String) -> URL? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "codex://plugins/" + encoded)
    }

    /// Asks Codex which plugins it counts as installed and, with `available`, which ones its
    /// catalogs offer under `names`. Runs `codex plugin list --json`, which only reads; nothing
    /// from a skill or plugin folder is passed to it. Nil when Codex could not be asked.
    static func pluginList(names: Set<String>, available: Bool,
                           codexHome: String?) async -> (installed: Set<String>, offered: [String: [String]])? {
        let flags = available ? ["--available"] : []
        let output = Protected("")
        let collect: @Sendable (String) -> Void = { text in output.with { $0 += text } }
        // Codex finds its folder through CODEX_HOME, which the shell may set and this app not.
        let home = codexHome ?? ""
        let status: Int32
        if let tool = bundledTool {
            status = await Shell.run(
                script: #"tool="$1"; home="$2"; shift 2; [ -n "$home" ] && export CODEX_HOME="$home"; exec "$tool" plugin list --json "$@" 2>/dev/null"#,
                arguments: [tool.path, home] + flags, timeout: 60, onOutput: collect)
        } else {
            // Installed some other way, such as with npm: the reader's shell knows where.
            status = await Shell.run(
                script: #"home="$1"; shift; [ -n "$home" ] && export CODEX_HOME="$home"; command -v codex >/dev/null || exit 127; exec codex plugin list --json "$@" 2>/dev/null"#,
                arguments: [home] + flags, interactive: true, timeout: 60, onOutput: collect)
        }
        guard status == 0 else { return nil }
        return CodexPluginList.parse(output.with { $0 }, names: names)
    }
}
