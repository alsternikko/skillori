import AppKit
import Foundation
import Observation
import SkilloriCore
import SkilloriUI
import SwiftUI

/// Lets whoever started a shell command stop it, with everything it started.
final class ShellControl: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false
    private var timedOut = false

    var wasStopped: Bool { lock.withLock { stopped } }
    var didTimeOut: Bool { lock.withLock { timedOut } }

    fileprivate func attach(_ process: Process) -> Bool {
        lock.withLock {
            self.process = process
            return !stopped
        }
    }

    /// Stops the command and the processes it started (npx starts node, node starts git).
    func stop() { end(timedOut: false) }

    fileprivate func timeOut() { end(timedOut: true) }

    private func end(timedOut: Bool) {
        let running: Process? = lock.withLock {
            stopped = true
            if timedOut { self.timedOut = true }
            return process
        }
        guard let running, running.isRunning else { return }
        let pid = running.processIdentifier
        for child in Self.descendants(of: pid) { kill(child, SIGTERM) }
        running.terminate()
    }

    /// Every process below `pid`, found with `pgrep -P`, deepest first.
    private static func descendants(of pid: pid_t) -> [pid_t] {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-P", String(pid)]
        let out = Pipe()
        pgrep.standardOutput = out
        pgrep.standardError = FileHandle.nullDevice
        guard (try? pgrep.run()) != nil else { return [] }
        pgrep.waitUntilExit()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let children = text.split(whereSeparator: \.isNewline).compactMap { pid_t($0) }
        return children.flatMap { descendants(of: $0) + [$0] }
    }
}

/// Turns chunks of bytes into text without breaking a character that two chunks share.
struct UTF8Chunks {
    private var pending = Data()

    mutating func text(from chunk: Data) -> String {
        pending.append(chunk)
        guard !pending.isEmpty else { return "" }
        // A UTF-8 character is at most four bytes; keep an unfinished one for the next chunk.
        var cut = pending.count
        for back in 1...min(3, pending.count) {
            let byte = pending[pending.count - back]
            if byte & 0b1100_0000 == 0b1000_0000 { continue } // continuation byte
            let length = byte & 0b1000_0000 == 0 ? 1 : byte & 0b1110_0000 == 0b1100_0000 ? 2
                : byte & 0b1111_0000 == 0b1110_0000 ? 3 : 4
            if length > back { cut = pending.count - back }
            break
        }
        let text = String(decoding: pending.prefix(cut), as: UTF8.self)
        pending = Data(pending.suffix(from: pending.startIndex + cut))
        return text
    }

    mutating func rest() -> String {
        defer { pending = Data() }
        return String(decoding: pending, as: UTF8.self)
    }
}

/// Runs a command through the reader's login shell, the way Terminal would, and passes on
/// what it prints. The arguments are handed over as arguments, never pasted into a script.
enum Shell {
    /// `script` is fixed text from this app. `arguments` become `$1…` in it.
    static func run(script: String, arguments: [String] = [], interactive: Bool = false, timeout: TimeInterval = 180,
                    directory: URL? = nil, control: ShellControl = ShellControl(),
                    onOutput: @escaping @Sendable (String) -> Void = { _ in }) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [interactive ? "-lic" : "-lc", script, "skillori"] + arguments
            process.currentDirectoryURL = directory ?? FileManager.default.homeDirectoryForCurrentUser
            // Nothing can wait for typing: there is no keyboard behind this.
            process.standardInput = FileHandle.nullDevice
            var environment = ProcessInfo.processInfo.environment
            environment["NO_COLOR"] = "1"
            environment["FORCE_COLOR"] = "0"
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            let reader = pipe.fileHandleForReading
            let decoder = Protected(UTF8Chunks())
            reader.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let text = decoder.with { $0.text(from: data) }
                if !text.isEmpty { onOutput(text) }
            }
            process.terminationHandler = { finished in
                reader.readabilityHandler = nil
                // Read what is left without waiting: a process the command started in the
                // background may hold the pipe open long after the command itself ended.
                let fd = reader.fileDescriptor
                _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
                var buffer = [UInt8](repeating: 0, count: 65_536)
                var rest = Data()
                while rest.count < 1_000_000 {
                    let count = read(fd, &buffer, buffer.count)
                    guard count > 0 else { break }
                    rest.append(buffer, count: count)
                }
                let text = decoder.with { $0.text(from: rest) + $0.rest() }
                if !text.isEmpty { onOutput(text) }
                continuation.resume(returning: finished.terminationStatus)
            }
            guard control.attach(process) else {
                reader.readabilityHandler = nil
                continuation.resume(returning: SIGTERM)
                return
            }
            do {
                try process.run()
            } catch {
                reader.readabilityHandler = nil
                onOutput("Could not start the shell: \(error.localizedDescription)\n")
                continuation.resume(returning: -1)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { control.timeOut() }
        }
    }
}

/// The token the GitHub CLI keeps for the reader, for repositories GitHub shows only to them.
/// Read with `gh auth token`, which takes it from the keychain or gh's own file; nil when gh
/// isn't installed or the reader isn't signed in.
enum GitHubCLI {
    @Sendable static func token() async -> String? {
        guard let gh = await location() else { return nil }
        return await Task.detached(priority: .utility) { () -> String? in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: gh)
            process.arguments = ["auth", "token", "--hostname", "github.com"]
            process.standardInput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let pipe = Pipe()
            process.standardOutput = pipe
            do { try process.run() } catch { return nil }
            DispatchQueue.global().asyncAfter(deadline: .now() + 8) { if process.isRunning { process.terminate() } }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !token.isEmpty, !token.contains(where: \.isWhitespace) else { return nil }
            return token
        }.value
    }

    /// Where gh is: Homebrew's folders first, then wherever the reader's login shell finds it.
    private static func location() async -> String? {
        for path in ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"] where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let mark = "__SKILLORI__"
        let output = Protected("")
        _ = await Shell.run(script: "print -r -- \"\(mark)$(command -v gh)\"", interactive: true, timeout: 8) { text in
            output.with { $0 += text }
        }
        let line = output.with { $0 }.split(whereSeparator: \.isNewline).last { $0.hasPrefix(mark) }
        guard let path = line.map({ String($0.dropFirst(mark.count)) }), path.hasPrefix("/"),
              FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }
}

/// A value several threads use, one at a time.
final class Protected<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func with<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
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

    private(set) var phase = Phase.idle {
        didSet {
            switch phase {
            case .succeeded, .failed: endedAt = Date()
            case .idle, .running: break
            }
        }
    }
    /// When the latest run ended, well or not.
    private(set) var endedAt: Date?
    /// The skill folder names the current or latest run was for.
    private(set) var names: [String] = []
    private(set) var output = ""

    var isRunning: Bool { phase == .running }
    /// Stops the run in progress. Nil when nothing runs.
    private var control: ShellControl?

    /// The version of the installer that runs. A fixed version, not whatever npm has today:
    /// npx runs the package with the reader's rights, so a new release is taken on only after
    /// it has been out for a while and its `update` still takes names, `-g` and `-y`.
    /// Checked in the package source: 1.7.6, released 2026-11-03.
    nonisolated static let installerVersion = "1.7.6"
    nonisolated static var installerPackage: String { "skills@\(installerVersion)" }

    /// What is run, as it would be typed. `--yes` and `-y` keep it from asking questions;
    /// `-g` keeps it to the skills installed for every project, which are the ones Skillori tracks.
    nonisolated static func arguments(for names: [String]) -> [String] {
        ["--yes", installerPackage, "update"] + names + ["-g", "-y"]
    }

    nonisolated static func commandText(for names: [String]) -> String {
        (["npx", installerPackage, "update"] + names + ["-g", "-y"]).joined(separator: " ")
    }

    /// Stops the installer and what it started. The run then reports that it was stopped.
    func stop() {
        control?.stop()
    }

    /// A skill's folder name is passed to a command, so only plain names are accepted.
    nonisolated static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix("-") && name != "." && name != ".."
            && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }
    }

    /// Runs the update for these skills. True when the installer said it went well.
    func run(names: [String]) async -> Bool {
        guard names.allSatisfy(Self.isSafeName) else {
            guard !isRunning else { return false }
            self.names = names
            output = ""
            phase = .failed("This skill's folder name cannot be passed to a command.")
            return false
        }
        return await run(names: names, commands: [Self.arguments(for: names)]) == 1
    }

    /// Runs the installer once for each list of arguments, one after the other, and stops at the
    /// first that ends badly. `names` are the skills the run is for, which the views go by.
    /// Returns how many of the commands went well.
    func run(names: [String], commands: [[String]]) async -> Int {
        guard !isRunning, !names.isEmpty, !commands.isEmpty else { return 0 }
        self.names = names
        output = ""
        phase = .running
        let control = ShellControl()
        self.control = control
        defer { self.control = nil }
        // Node is usually on the path the login shell sets; some setups only add it for interactive shells.
        var interactive = false
        if await Shell.run(script: "command -v npx >/dev/null", timeout: 20, control: control) != 0 {
            interactive = true
            if await Shell.run(script: "command -v npx >/dev/null", interactive: true, timeout: 20, control: control) != 0 {
                phase = .failed(control.wasStopped ? "Stopped." : "npx was not found. Updating needs Node. You can still copy the command.")
                return 0
            }
        }
        var finished = 0
        for arguments in commands {
            // A first run downloads the installer, which can take a while on a slow line.
            let status = await Shell.run(script: "exec npx \"$@\"", arguments: arguments,
                                         interactive: interactive, timeout: 300, control: control) { [weak self] text in
                Task { @MainActor in self?.append(text) }
            }
            // Let the last lines land before the verdict.
            try? await Task.sleep(for: .milliseconds(120))
            guard status == 0 else {
                if control.didTimeOut {
                    phase = .failed("Stopped after five minutes without finishing.")
                } else if control.wasStopped {
                    phase = .failed("Stopped. The installer may have updated some of the files; Skillori reads them again now.")
                } else {
                    phase = .failed("The installer ended with code \(status).")
                }
                return finished
            }
            finished += 1
        }
        phase = .succeeded
        return finished
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

    /// The last lines of what was printed, without blank ones, and without npm's own notices
    /// (a newer npm is out), which say nothing about the skills.
    func lastLines(_ count: Int) -> [String] {
        output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("npm notice") }.suffix(count).map { String($0) }
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
    /// Off where the line around the frame has its own run button, as in the library's list.
    var showsRun = true

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
                Text(store.updateCommandText(for: installations))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                if !compact, let first = installations.first, installations.count == 1 {
                    CopyUpdateCommandButton(installation: first, prominent: false, tone: tone)
                }
                if reported == .running {
                    Button("Stop") { runner.stop() }
                        .buttonStyle(PillButtonStyle(prominent: false, on: tone, compact: compact))
                        .help("Stops the installer and what it started")
                        .transition(.opacity)
                }
                if showsRun {
                    Button(label(for: phase)) { Task { await store.update(installations) } }
                        .buttonStyle(PillButtonStyle(prominent: phase != .succeeded, on: tone, compact: compact))
                        .disabled(runner.isRunning || phase == .succeeded)
                }
            }
            // Keeps the bar as tall with the run button gone as with it.
            .frame(minHeight: showsRun ? nil : (compact ? 22 : 28))
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
        // While the installer runs, a soft light goes along the lower edge.
        .overlay(alignment: .bottom) {
            if reported == .running { RunningEdge(color: tone.foreground).transition(.opacity) }
        }
        .clipShape(RoundedRectangle(cornerRadius: compact ? Radius.row : Radius.block, style: .circular))
        .animation(Motion.swap, value: reported)
        .accessibilityElement(children: .contain)
    }

    /// Something is happening: a band of light runs along the frame's lower edge, over and over.
    /// With Reduce Motion it is a still, faint line.
    private struct RunningEdge: View {
        let color: Color
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var start = Date()

        var body: some View {
            if reduceMotion {
                color.opacity(0.3).frame(height: 1.5)
            } else {
                TimelineView(.animation) { timeline in
                    GeometryReader { proxy in
                        let period = 1.4
                        let t = timeline.date.timeIntervalSince(start).truncatingRemainder(dividingBy: period) / period
                        // Eased in and out along the way, so it reads as a breath rather than a scan.
                        let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
                        let band = proxy.size.width * 0.38
                        LinearGradient(colors: [color.opacity(0), color.opacity(0.85), color.opacity(0)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: band)
                            .offset(x: -band + (proxy.size.width + band) * eased)
                    }
                }
                .frame(height: 2)
                .allowsHitTesting(false)
            }
        }
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
