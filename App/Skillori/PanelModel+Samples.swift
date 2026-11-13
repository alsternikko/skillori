#if DEBUG
import SkilloriUI

/// The three panel states from the design sketch (artboard 01), with its sample data.
/// Used only to compare the native panel with the sketch. Updates, sync and failed checks
/// need the source checks in backlog etapp 2 before they can be shown for real.
extension PanelModel {
    static let sampleUpdates = PanelModel(
        tone: .new, label: "Updates", stamp: "Checked 12 min ago", number: "2",
        lead: "skills changed upstream", note: "of the 29 you installed",
        groups: [UpdateGroup(title: "emilkowalski/skills", items: [.init(title: "emil-design-eng", data: "→ 4f1a02d")], count: "1 UPDATE"),
                 UpdateGroup(title: "vercel-labs/skills", items: [.init(title: "find-skills", data: "→ a93f0b2")], count: "1 UPDATE")],
        rows: [.link(text: "9 have no known source", label: "Link", command: .library)],
        buttons: [Button(title: "Review 2", prominent: true, command: .library),
                  Button(title: "Library", prominent: false, command: .library)],
        hint: "Check now ⌘R")

    static let sampleInSync = PanelModel(
        tone: .rest, label: "In sync", stamp: "Checked 12 min ago", number: "0",
        lead: "changes since Tuesday", note: "20 of your 29 skills match their source",
        rows: [.line(text: "20 match their source", data: "6 LOCATIONS", muted: false),
               .link(text: "9 have no known source", label: "Link", command: .library)],
        buttons: [Button(title: "Library", prominent: false, command: .library)],
        hint: "Check now ⌘R")

    static let sampleNoContact = PanelModel(
        tone: .attention, label: "No contact", stamp: "Last good check 3 days ago", number: "2", dimmed: true,
        lead: "sources could not be reached", note: "The number above is from Monday",
        rows: [.item(title: "GitHub rate limit reached", detail: "api.github.com", data: "RESETS 15:04"),
               .line(text: "Shown result is from", data: "2026-11-09 08:12", muted: true)],
        buttons: [Button(title: "Try again", prominent: true, command: .rescan),
                  Button(title: "Library", prominent: false, command: .library)],
        hint: "⌘R")

    // The states in artboard 11 that the panel shows.
    static let sampleNoReading = PanelModel(
        tone: .quiet, label: "No reading", stamp: "Reading now", number: "--", dimmed: true,
        lead: "Reading this Mac", note: "Looking in the skill folders Skillori knows.",
        rows: [], buttons: [Button(title: "Library", prominent: false, command: .library)],
        hint: "Reading…", hintEnabled: false)

    static let sampleNothingFound = PanelModel(
        tone: .quiet, label: "On this Mac", stamp: "Read 14:32", number: "0",
        lead: "skills on this Mac", note: "Looked in 55 folders.",
        rows: [.link(text: "Skills in a project folder?", label: "Add folder", command: .addFolder)],
        buttons: [Button(title: "Library", prominent: true, command: .library),
                  Button(title: "Settings", prominent: false, command: .settings)],
        hint: "Read again ⌘R")

    static let sampleNoAccess = PanelModel(
        tone: .attention, label: "No access", stamp: "Read 14:32", number: "1",
        lead: "folder could not be read", note: "Its skills are missing from the count.",
        rows: [.item(title: "client-app", detail: "~/Documents/client-app", data: "NO ACCESS")],
        buttons: [Button(title: "Open Privacy Settings", prominent: true, command: .privacySettings),
                  Button(title: "Library", prominent: false, command: .library)],
        hint: "⌘R")
}
#endif
