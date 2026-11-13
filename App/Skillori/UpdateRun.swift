import AppKit
import Foundation
import Observation
import SkilloriCore
import SkilloriUI
import SwiftUI

/// Runs a command through the reader's login shell, the way Terminal would, and passes on
/// what it prints. The arguments are handed over as arguments, never pasted into a script.
enum Shell {
    /// `script` is fixed text from this app. `arguments` become `$1…` in it.
    static func run(script: String, arguments: [String] = [], interactive: Bool = false, timeout: TimeInterval = 180,
                    onOutput: @escaping @Sendable (String) -> Void = { _ in }) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [interactive ? "-lic" : "-lc", script, "skillori"] + arguments
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            // Nothing can wait for typing: there is no keyboard behind this.
            process.standardInput = FileHandle.nullDevice
            var environment = ProcessInfo.processInfo.environment
            environment["NO_COLOR"] = "1"
            environment["FORCE_COLOR"] = "0"
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let text = String(data: data, encoding: .utf8) { onOutput(text) }
            }
            process.terminationHandler = { finished in
                pipe.fileHandleForReading.readabilityHandler = nil
                if let rest = try? pipe.fileHandleForReading.readToEnd(), !rest.isEmpty,
                   let text = String(data: rest, encoding: .utf8) { onOutput(text) }
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                onOutput("Could not start the shell: \(error.localizedDescription)\n")
                continuation.resume(returning: -1)
                return
            }
            nonisolated(unsafe) let running = process
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if running.isRunning { running.terminate() }
            }
        }
    }
}

/// One run of the installer's update command, and what it printed.
///
/// Skillori does not change a skill. When the reader presses Run, this starts the installer
/// (`npx skills`) and the installer does the work, as it would from Terminal.
@MainActor
@Observable
final class UpdateRunner {
    enum Phase: Equatable {
        case idle
        case running
        case succeeded
        /// The run ended badly; the text says how.
        case failed(String)
    }

    private(set) var phase = Phase.idle
    /// The skill folder names the current or latest run was for.
    private(set) var names: [String] = []
    private(set) var output = ""

    var isRunning: Bool { phase == .running }

    /// What is run, as it would be typed. `--yes` and `-y` keep it from asking questions;
    /// `-g` keeps it to the skills installed for every project, which are the ones Skillori tracks.
    nonisolated static func arguments(for names: [String]) -> [String] {
        ["--yes", "skills", "update"] + names + ["-g", "-y"]
    }

    nonisolated static func commandText(for names: [String]) -> String {
        (["npx", "skills", "update"] + names + ["-g", "-y"]).joined(separator: " ")
    }

    /// A skill's folder name is passed to a command, so only plain names are accepted.
    nonisolated static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix("-")
            && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }
    }

    /// Runs the update for these skills. True when the installer said it went well.
    func run(names: [String]) async -> Bool {
        guard !isRunning, !names.isEmpty else { return false }
        self.names = names
        output = ""
        guard names.allSatisfy(Self.isSafeName) else {
            phase = .failed("This skill's folder name cannot be passed to a command.")
            return false
        }
        phase = .running
        // Node is usually on the path the login shell sets; some setups only add it for interactive shells.
        var interactive = false
        if await Shell.run(script: "command -v npx >/dev/null", timeout: 20) != 0 {
            interactive = true
            if await Shell.run(script: "command -v npx >/dev/null", interactive: true, timeout: 20) != 0 {
                phase = .failed("npx was not found. Updating needs Node. You can still copy the command.")
                return false
            }
        }
        let status = await Shell.run(script: "exec npx \"$@\"", arguments: Self.arguments(for: names), interactive: interactive) { [weak self] text in
            Task { @MainActor in self?.append(text) }
        }
        // Let the last lines land before the verdict.
        try? await Task.sleep(for: .milliseconds(120))
        switch status {
        case 0: phase = .succeeded
        case 15: phase = .failed("Stopped after three minutes without finishing.")
        default: phase = .failed("The installer ended with code \(status).")
        }
        return status == 0
    }

    /// Adds printed text the way a terminal would show it: colour codes dropped, and a line
    /// that is redrawn in place (a spinner, a progress line) replaces itself.
    func append(_ text: String) {
        var clean = text.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
        clean = clean.replacingOccurrences(of: "\r\n", with: "\n")
        for piece in clean.split(separator: "\r", omittingEmptySubsequences: false).enumerated() {
            if piece.offset > 0, let lineStart = output.lastIndex(of: "\n") {
                output = String(output[...lineStart])
            } else if piece.offset > 0 {
                output = ""
            }
            output += piece.element
        }
        if output.count > 20_000 { output = String(output.suffix(16_000)) }
    }

    /// The last lines of what was printed, without blank ones.
    func lastLines(_ count: Int) -> [String] {
        output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.suffix(count).map { String($0) }
    }

    #if DEBUG
    /// A finished run for pictures.
    func setSample(names: [String], phase: Phase, output: String) {
        self.names = names
        self.phase = phase
        self.output = output
    }
    #endif
}

/// The update, as the command it is: shown in a code frame with a button that runs it.
/// What the installer prints appears under the command.
struct CommandFrame: View {
    @Environment(InventoryStore.self) private var store
    let installations: [Installation]
    /// In the menu bar panel: a slim bar, no copy button and fewer lines of output.
    var compact = false

    var body: some View {
        let runner = store.updater
        let names = installations.map(\.directoryName)
        let mine = runner.names == names
        // In the panel one frame stands for a whole source, so a run of some of its skills reports here too.
        let partial = compact && !mine && !runner.names.isEmpty && Set(runner.names).isSubset(of: Set(names))
        let phase = mine ? runner.phase : .idle
        let reported = mine || partial ? runner.phase : .idle
        let lines = mine || partial ? runner.lastLines(compact ? 3 : 8) : []
        let tone = Tone.rest
        let inset: CGFloat = compact ? 10 : 14
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("$").foregroundStyle(tone.secondary)
                Text(UpdateRunner.commandText(for: names))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                if !compact, let first = installations.first, installations.count == 1 {
                    CopyUpdateCommandButton(installation: first, prominent: false, tone: tone)
                }
                Button(label(for: phase)) { Task { await store.update(installations) } }
                    .buttonStyle(PillButtonStyle(prominent: phase != .succeeded, on: tone, compact: compact))
                    .disabled(runner.isRunning || phase == .succeeded)
            }
            .font(TypeRole.mono(compact ? 10.5 : 11.5))
            .padding(compact ? EdgeInsets(top: 5, leading: inset, bottom: 5, trailing: 5)
                     : EdgeInsets(top: 8, leading: inset, bottom: 8, trailing: 8))

            if case .failed(let why) = reported {
                tone.foreground.opacity(0.14).frame(height: 1)
                // After a run of one skill, say which: the command above is the whole source's.
                Text(partial ? "\(runner.names.joined(separator: ", ")): \(why)" : why)
                    .font(TypeRole.sans(12))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(EdgeInsets(top: 8, leading: inset, bottom: lines.isEmpty ? 10 : 2, trailing: inset))
            }
            if !lines.isEmpty {
                if case .failed = reported {} else { tone.foreground.opacity(0.14).frame(height: 1) }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line).lineLimit(1).truncationMode(.tail)
                    }
                }
                .font(TypeRole.mono(10.5))
                .foregroundStyle(tone.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 8, leading: inset, bottom: 10, trailing: inset))
                .textSelection(.enabled)
            }
        }
        .foregroundStyle(tone.foreground)
        .background(tone.background, in: RoundedRectangle(cornerRadius: compact ? Radius.row : Radius.block, style: .circular))
        .animation(Motion.swap, value: reported)
        .accessibilityElement(children: .contain)
    }

    private func label(for phase: UpdateRunner.Phase) -> String {
        switch phase {
        case .idle: "▶ Run"
        case .running: "Running…"
        case .succeeded: "Updated"
        case .failed: "▶ Run again"
        }
    }
}
