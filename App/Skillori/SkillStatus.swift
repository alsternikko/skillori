import AppKit
import SkilloriCore
import SkilloriUI
import SwiftUI

/// The one status a skill shows: where it stands against its source, in the words the app uses.
enum SkillStatus: Equatable {
    /// The source has other content than what is installed.
    case updateAvailable(upstream: String)
    /// A skill the reader linked to a source, whose files differ from it. Without an installer
    /// record nobody can say whether the source is newer or the files were changed here.
    case differs(upstream: String)
    /// The reader chose to stay on the installed version. `sourceMoved` says whether that costs anything yet.
    case heldBack(sourceMoved: Bool)
    /// The files on this Mac differ from what the installer put there.
    case changedHere
    /// Installed content and source content are identical, as of the last check.
    case upToDate
    /// The source was asked and gave no usable answer.
    case cantCheck(UpstreamState.Reason)
    /// There is a source, but it has not been asked: checks are off or have not run yet.
    case notChecked
    /// The files on this Mac could not be hashed.
    case checkFailed
    case noSource
    case managed
    /// A Claude Code plugin whose marketplace has a newer version. Skillori can run Claude Code's update.
    case ownerUpdate(owner: String, upstream: String)
    /// A Cursor or Codex plugin whose source has a newer version than the one installed. The app
    /// brings new versions itself, once its own catalog has them, so there is nothing to do.
    case sourceAhead(owner: String, upstream: String)
    /// A plugin folder the app no longer reads: Codex does not count it as installed. `replacement`
    /// is the plugin id Codex offers it under now, when Codex has not added that one yet.
    case leftBehind(owner: String, replacement: String?)

    /// Owned by an app, whatever its source says.
    var isManaged: Bool {
        switch self {
        case .managed, .ownerUpdate, .sourceAhead, .leftBehind: true
        default: false
        }
    }

    var word: String {
        switch self {
        case .updateAvailable: "Update available"
        case .differs: "Differs from source"
        case .heldBack: "Held back"
        case .changedHere: "Changed here"
        case .upToDate: "Up to date"
        case .cantCheck: "Can't check"
        case .notChecked: "Not checked"
        case .checkFailed: "Check failed"
        case .noSource: "No source"
        case .managed: "Managed"
        case .ownerUpdate: "Plugin update"
        case .sourceAhead: "Newer at source"
        case .leftBehind: "Not read"
        }
    }

    /// A shape before the word, so the status does not rest on colour.
    var mark: String {
        switch self {
        case .updateAvailable: "▲"
        case .differs: "≠"
        case .heldBack: "◆"
        case .changedHere: "◐"
        case .upToDate: "●"
        case .cantCheck, .checkFailed: "✕"
        case .notChecked: "○"
        case .noSource: "◌"
        case .managed, .sourceAhead: "■"
        case .ownerUpdate: "▲"
        case .leftBehind: "◌"
        }
    }

    var chipKind: StatusChip.Kind {
        switch self {
        case .updateAvailable, .differs, .ownerUpdate: .new
        case .changedHere, .checkFailed, .leftBehind: .attention
        case .cantCheck, .notChecked, .noSource: .outline
        case .heldBack, .upToDate, .managed, .sourceAhead: .neutral
        }
    }

    /// The block colour for a skill in this state.
    var tone: Tone {
        switch self {
        case .updateAvailable, .differs, .ownerUpdate: .new
        case .changedHere, .checkFailed, .leftBehind: .attention
        case .upToDate, .heldBack: .rest
        case .cantCheck, .notChecked, .noSource, .managed, .sourceAhead: .quiet
        }
    }

    /// One plain sentence about what the status means for this skill.
    var sentence: String {
        switch self {
        case .updateAvailable: "The source has changed since you installed this."
        case .differs: "Differs from the source you linked. It may be older, or changed on this Mac."
        case .heldBack(let moved):
            moved ? "You are staying on this version. The source has moved on." : "You are staying on this version. The source has not changed."
        case .changedHere: "The files on this Mac differ from what was installed."
        case .upToDate: "Same content as the source."
        case .cantCheck(let reason): reason.sentence
        case .notChecked: "The source has not been asked yet."
        case .checkFailed: "The files on this Mac could not be read for comparison."
        case .noSource: "Nothing on this Mac says where this came from."
        case .managed: "The app that owns it keeps it up to date."
        case .ownerUpdate(let owner, _): "The plugin's marketplace has a newer version. Skillori can run \(owner)’s update."
        case .sourceAhead(let owner, _): "The plugin's source has a newer version. \(owner) brings it once its catalog has it."
        case .leftBehind(let owner, _): "\(owner) no longer reads this plugin, so its skills are not loaded."
        }
    }

    /// True for the states where nobody can say whether the skill is current.
    var isUnverified: Bool {
        switch self {
        case .cantCheck, .notChecked, .checkFailed, .noSource: true
        default: false
        }
    }
}

/// A source the reader pointed out for a skill that came with no installer record.
struct SourceLink: Codable, Equatable {
    /// Empty for an install script.
    var owner: String
    var repository: String
    var ref: String?
    /// The address of the install script, when the source is one rather than a repository.
    var installer: String?
    /// The folder inside the source; empty for the top of it.
    var subpath: String
    var linkedAt: Date
    /// The content hash of the files on this Mac when the source was last asked.
    var localHash: String?

    var source: SkillSource {
        if let installer, let script = InstallerSource(installer) { return .installer(script) }
        return .github(UpstreamSource(owner: owner, repository: repository, ref: ref))
    }
}

extension UpstreamState.Reason {
    var sentence: String {
        switch self {
        case .notFound: "The source was not found. It is private, renamed or removed."
        case .folderGone: "The source no longer has this skill's folder."
        case .rateLimited: "The source asked Skillori to wait. It will ask again later."
        case .offline: "No contact with the source."
        case .cancelled: "The check was stopped before the source answered."
        case .unsupported: "Skillori cannot ask this kind of source yet."
        case .noBaseline: "The installer left nothing to compare with."
        case .failed: "The source gave an answer Skillori could not read."
        }
    }

    /// Short, for a data column.
    var short: String {
        switch self {
        case .notFound: "source not found"
        case .folderGone: "gone from source"
        case .rateLimited: "asked to wait"
        case .offline: "no contact"
        case .cancelled: "stopped"
        case .unsupported: "unsupported source"
        case .noBaseline: "no baseline"
        case .failed: "unreadable answer"
        }
    }
}

// MARK: Acting on a status


/// Skillori never changes a skill. To update one, the reader runs the installer; this is its command.
enum UpdateCommand {
    static func text(for installation: Installation) -> String {
        UpdateRunner.commandText(for: [installation.directoryName])
    }
}

/// Copies the installer's update command and says so for a moment.
struct CopyUpdateCommandButton: View {
    let installation: Installation
    var prominent = true
    var tone: Tone?
    @State private var copied = false

    var body: some View {
        Button(copied ? "Copied" : "Copy update command") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(UpdateCommand.text(for: installation), forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                copied = false
            }
        }
        .buttonStyle(PillButtonStyle(prominent: prominent, on: tone))
        .help(UpdateCommand.text(for: installation))
    }
}

/// Copies the command an author gives for their install script. Skillori never runs it: a script
/// from a site runs with the reader's rights, so that stays the reader's own step in Terminal.
struct CopyInstallCommandButton: View {
    let script: InstallerSource
    var prominent = false
    var tone: Tone?
    @State private var copied = false

    var body: some View {
        Button(copied ? "Copied" : "Copy install command") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(script.installCommand, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                copied = false
            }
        }
        .buttonStyle(PillButtonStyle(prominent: prominent, on: tone))
        .help(script.installCommand)
    }
}

/// A status as a chip: a shape, the word, and colour only for the states that ask for something.
struct StatusBadge: View {
    let status: SkillStatus

    var body: some View {
        StatusChip(status.word, kind: status.chipKind, mark: status.mark)
    }
}

extension InventoryStore {
    /// "Checked 10:25", with the date when it was not today.
    static func stamp(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }

    /// One line about how fresh the source answers are.
    var checkStamp: String {
        guard checksEnabled else { return "Checks off" }
        if isChecking { return "Checking now" }
        guard let lastCheck else { return lastProblem == nil ? "Not checked yet" : "No contact" }
        return (lastProblem == nil ? "Checked " : "No contact · last ") + Self.stamp(lastCheck)
    }
}
