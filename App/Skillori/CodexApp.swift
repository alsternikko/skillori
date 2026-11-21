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

    /// Runs Codex's tool with fixed text and plain arguments: the bundled tool when there is one,
    /// otherwise `codex` from the reader's shell. `arguments` become `"$@"` after `codex`.
    /// With `quiet`, what Codex writes to stderr is dropped, so only its answer is read.
    static func run(_ arguments: [String], codexHome: String?, timeout: TimeInterval, quiet: Bool = false,
                    control: ShellControl = ShellControl(), onOutput: @escaping @Sendable (String) -> Void) async -> Int32 {
        // Codex finds its folder through CODEX_HOME, which the shell may set and this app not.
        let home = codexHome ?? ""
        let errors = quiet ? " 2>/dev/null" : ""
        if let tool = bundledTool {
            return await Shell.run(
                script: #"tool="$1"; home="$2"; shift 2; [ -n "$home" ] && export CODEX_HOME="$home"; exec "$tool" "$@""# + errors,
                arguments: [tool.path, home] + arguments, timeout: timeout, control: control, onOutput: onOutput)
        }
        // Installed some other way, such as with npm: the reader's shell knows where.
        return await Shell.run(
            script: #"home="$1"; shift; [ -n "$home" ] && export CODEX_HOME="$home"; command -v codex >/dev/null || exit 127; exec codex "$@""# + errors,
            arguments: [home] + arguments, interactive: true, timeout: timeout, control: control, onOutput: onOutput)
    }

    /// Asks Codex which plugins it counts as installed and, with `available`, which ones its
    /// catalogs offer under `names`. Runs `codex plugin list --json`, which only reads; nothing
    /// from a skill or plugin folder is passed to it. Nil when Codex could not be asked.
    static func pluginList(names: Set<String>, available: Bool,
                           codexHome: String?) async -> (installed: Set<String>, offered: [String: [String]])? {
        let output = Protected("")
        let status = await run(["plugin", "list", "--json"] + (available ? ["--available"] : []),
                               codexHome: codexHome, timeout: 60, quiet: true) { text in output.with { $0 += text } }
        guard status == 0 else { return nil }
        return CodexPluginList.parse(output.with { $0 }, names: names)
    }
}

/// Adds Codex plugins again from the catalog Codex uses now, the way the reader would in
/// Terminal: `codex plugin add <name@marketplace>`. Codex writes the files; Skillori only starts
/// the command. Codex left these plugins behind when it moved them to a new catalog, so adding
/// one is what brings it back, at the catalog's version.
@MainActor
@Observable
final class CodexPluginRunner {
    enum Phase: Equatable {
        case idle
        case running
        case succeeded
        case failed(String)
    }

    private(set) var phase = Phase.idle
    /// The plugin ids of the current or latest run.
    private(set) var ids: [String] = []
    private(set) var output = ""
    private var control: ShellControl?

    var isRunning: Bool { phase == .running }

    func stop() { control?.stop() }

    /// How the latest run for exactly these plugins went, for a line still listed after it.
    /// After a run that went through, the line is still listed only when Codex, asked again,
    /// does not count the plugins as installed: that is said, rather than the line looking
    /// as if nothing ran.
    func note(for ids: [String]) -> String? {
        guard !isRunning, Set(self.ids) == Set(ids) else { return nil }
        switch phase {
        case .failed(let why): return "Codex couldn’t add them. " + why
        case .succeeded: return "Codex said it added them, but asked again it still doesn’t count them as installed. Skillori asks Codex again at the next check."
        default: return nil
        }
    }

    /// Adds these plugins, one after the other. True when every one was added.
    func run(_ ids: [String], codexHome: String?) async -> Bool {
        guard !isRunning, !ids.isEmpty else { return false }
        self.ids = ids
        output = ""
        guard ids.allSatisfy(PluginUpdateRunner.isSafeID) else {
            phase = .failed("A plugin's name cannot be passed to a command.")
            return false
        }
        phase = .running
        let control = ShellControl()
        self.control = control
        defer { self.control = nil }
        for id in ids {
            output += "$ codex plugin add \(id)\n"
            let status = await CodexApp.run(["plugin", "add", id], codexHome: codexHome, timeout: 300, control: control) { [weak self] text in
                Task { @MainActor in self?.output += text }
            }
            try? await Task.sleep(for: .milliseconds(120))
            guard status == 0 else {
                phase = .failed(control.didTimeOut ? "Stopped after five minutes without finishing."
                                : control.wasStopped ? "Stopped." : status == 127 ? "The codex command was not found."
                                : lastLine.map { "Codex said: \($0)" } ?? "Codex ended with code \(status).")
                return false
            }
        }
        phase = .succeeded
        return true
    }

    /// The last line Codex printed, when it is short enough to show.
    private var lastLine: String? {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("$ ") }
        return lines.last.flatMap { $0.count <= 160 ? $0 : nil }
    }
}
