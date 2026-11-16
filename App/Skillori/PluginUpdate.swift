import AppKit
import Foundation
import Observation
import SkilloriCore

/// Runs Claude Code's own update for its plugins, the way the reader would in Terminal:
///
///     claude plugin marketplace update <marketplace>
///     claude plugin update <name@marketplace> --scope <scope>
///
/// Claude Code writes the files; Skillori only starts the command. `-y` is never passed: it
/// would accept a changed install command from the marketplace without asking. When Claude
/// Code wants that approval, the run stops and the reader is asked to run it in Terminal.
@MainActor
@Observable
final class PluginUpdateRunner {
    enum Phase: Equatable {
        case idle
        case running
        case succeeded
        /// Claude Code wants the reader to approve something; the text is the command to run.
        case needsReview(String)
        case failed(String)
    }

    private(set) var phase = Phase.idle
    /// The plugin ids of the current or latest run.
    private(set) var ids: [String] = []
    private(set) var output = ""
    private var control: ShellControl?

    var isRunning: Bool { phase == .running }

    /// Scopes Claude Code's `--scope` takes that a reader's own install can have.
    nonisolated static let scopes: Set<String> = ["user", "project", "local"]

    /// A plugin id or marketplace name goes to a command, so only plain names are accepted.
    nonisolated static func isSafeName(_ text: String) -> Bool {
        !text.isEmpty && !text.hasPrefix("-") && text != "." && text != ".."
            && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }
    }

    nonisolated static func isSafeID(_ id: String) -> Bool {
        let parts = id.split(separator: "@", omittingEmptySubsequences: false).map(String.init)
        return parts.count == 2 && parts.allSatisfy(isSafeName)
    }

    /// The commands, as they would be typed, one per line.
    nonisolated static func commandText(for plugins: [PluginRecord]) -> String {
        let marketplaces = Array(Set(plugins.map(\.marketplace))).sorted()
        return (marketplaces.map { "claude plugin marketplace update \($0)" }
            + plugins.map { "claude plugin update \($0.id) --scope \($0.scope ?? "user")" }).joined(separator: "\n")
    }

    func stop() { control?.stop() }

    /// Updates these Claude Code plugins. True when every command went well.
    func run(_ plugins: [PluginRecord]) async -> Bool {
        guard !isRunning, !plugins.isEmpty else { return false }
        ids = plugins.map(\.id)
        output = ""
        guard plugins.allSatisfy({ $0.app == "Claude Code" && Self.isSafeID($0.id) && Self.isSafeName($0.marketplace)
                                   && Self.scopes.contains($0.scope ?? "user") }) else {
            phase = .failed("This plugin's name or scope cannot be passed to a command.")
            return false
        }
        phase = .running
        let control = ShellControl()
        self.control = control
        defer { self.control = nil }

        var interactive = false
        if await Shell.run(script: "command -v claude >/dev/null", timeout: 20, control: control) != 0 {
            interactive = true
            if await Shell.run(script: "command -v claude >/dev/null", interactive: true, timeout: 20, control: control) != 0 {
                phase = .failed(control.wasStopped ? "Stopped." : "The claude command was not found. You can still copy the commands.")
                return false
            }
        }
        // Each marketplace once, so the update sees what the source has now.
        for marketplace in Array(Set(plugins.map(\.marketplace))).sorted() {
            let status = await step(script: "exec claude plugin marketplace update \"$1\"", arguments: [marketplace],
                                    interactive: interactive, directory: nil, control: control)
            guard status == 0 else { return finish(status, control: control, plugins: plugins) }
        }
        for plugin in plugins {
            let scope = plugin.scope ?? "user"
            // A project's plugin is updated from inside that project.
            let directory = scope == "user" ? nil : plugin.projectPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
            let status = await step(script: "exec claude plugin update \"$1\" --scope \"$2\"", arguments: [plugin.id, scope],
                                    interactive: interactive, directory: directory, control: control)
            guard status == 0 else { return finish(status, control: control, plugins: plugins) }
        }
        phase = .succeeded
        return true
    }

    private func step(script: String, arguments: [String], interactive: Bool, directory: URL?,
                      control: ShellControl) async -> Int32 {
        append("$ claude " + script.dropFirst("exec claude ".count).replacingOccurrences(of: "\"$1\"", with: arguments[0])
            .replacingOccurrences(of: "\"$2\"", with: arguments.count > 1 ? arguments[1] : "") + "\n")
        let status = await Shell.run(script: script, arguments: arguments, interactive: interactive, timeout: 300,
                                     directory: directory, control: control) { [weak self] text in
            Task { @MainActor in self?.append(text) }
        }
        try? await Task.sleep(for: .milliseconds(120))
        return status
    }

    private func finish(_ status: Int32, control: ShellControl, plugins: [PluginRecord]) -> Bool {
        if control.didTimeOut {
            phase = .failed("Stopped after five minutes without finishing.")
        } else if control.wasStopped {
            phase = .failed("Stopped. Claude Code may have updated some of it; Skillori reads it again now.")
        } else if Self.asksForApproval(output) {
            phase = .needsReview(Self.commandText(for: plugins))
        } else {
            phase = .failed("Claude Code ended with code \(status).")
        }
        return false
    }

    /// Claude Code asks for `--yes` when a marketplace changed how a plugin installs.
    nonisolated static func asksForApproval(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("--yes") || lower.contains(" -y") || lower.contains("confirm")
    }

    private func append(_ text: String) {
        output += text.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
        if output.count > 20_000 { output = String(output.suffix(16_000)) }
    }

    /// The last lines of what was printed, without blank ones.
    func lastLines(_ count: Int) -> [String] {
        output.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.suffix(count)
    }
}
