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
        case .managed: "■"
        }
    }

    var chipKind: StatusChip.Kind {
        switch self {
        case .updateAvailable, .differs: .new
        case .changedHere, .checkFailed: .attention
        case .cantCheck, .notChecked, .noSource: .outline
        case .heldBack, .upToDate, .managed: .neutral
        }
    }

    /// The block colour for a skill in this state.
    var tone: Tone {
        switch self {
        case .updateAvailable, .differs: .new
        case .changedHere, .checkFailed: .attention
        case .upToDate, .heldBack: .rest
        case .cantCheck, .notChecked, .noSource, .managed: .quiet
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
    var owner: String
    var repository: String
    var ref: String?
    /// The folder inside the source; empty for the top of it.
    var subpath: String
    var linkedAt: Date
    /// The content hash of the files on this Mac when the source was last asked.
    var localHash: String?

    var source: UpstreamSource { UpstreamSource(owner: owner, repository: repository, ref: ref) }
}

extension UpstreamState.Reason {
    var sentence: String {
        switch self {
        case .notFound: "The source was not found. It is private, renamed or removed."
        case .folderGone: "The source no longer has this skill's folder."
        case .rateLimited: "GitHub asked Skillori to wait. It will ask again later."
        case .offline: "No contact with the source."
        case .cancelled: "The check was stopped before the source answered."
        case .unsupported: "Skillori can only ask GitHub sources so far."
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
        case .unsupported: "not GitHub"
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
