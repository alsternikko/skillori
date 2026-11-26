#if DEBUG
import AppKit
import SkilloriCore
import SkilloriUI
import SwiftUI

/// Debug builds only: `SKILLORI_SNAPSHOT_DIR=/some/dir` renders the main views to PNG files
/// and quits. Lets us check the UI without screen recording permission. With
/// `SKILLORI_SNAPSHOT_ONLY=share` it renders the share sheet alone, and asks no source;
/// with `first-start`, first start's last step alone, with checks on and turned off.
/// Debug builds only: `SKILLORI_UPDATE_PLUGIN=<name@marketplace>` with `SKILLORI_UPDATE_LOG=<file>`
/// runs the real plugin update through the app's own runner, writes how it went, and quits.
@MainActor
enum DebugPluginUpdate {
    static func runIfRequested(store: InventoryStore) {
        let env = ProcessInfo.processInfo.environment
        guard let id = env["SKILLORI_UPDATE_PLUGIN"], let log = env["SKILLORI_UPDATE_LOG"] else { return }
        Task { @MainActor in
            while store.inventory == nil || store.isScanning { try? await Task.sleep(for: .milliseconds(100)) }
            guard let plugin = store.pluginRecords.first(where: { $0.id == id }) else {
                try? "no such plugin: \(id)\n".write(toFile: log, atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
                return
            }
            let before = "before: \(plugin.version ?? "?") \(plugin.commit ?? "?") state \(String(describing: store.pluginReadings[id]?.state))\n"
            await store.updatePlugins([plugin])
            while store.isChecking || store.isScanning { try? await Task.sleep(for: .milliseconds(200)) }
            let after = store.pluginRecords.first { $0.id == id }
            let text = before + "phase: \(store.pluginUpdater.phase)\n"
                + "after: \(after?.version ?? "?") \(after?.commit ?? "?") state \(String(describing: store.pluginReadings[id]?.state))\n"
                + "--- output\n" + store.pluginUpdater.output
            try? text.write(toFile: log, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }
}

/// Debug builds only: `SKILLORI_TRIAL=<package>` with `SKILLORI_TRIAL_ARGS` (space-separated)
/// and `SKILLORI_TRIAL_LOG=<file>` runs the installer check once, writes what it found, and quits.
@MainActor
enum DebugInstallerTrial {
    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        if let log = env["SKILLORI_KEYCHAIN_TEST"] {
            // Saves, reads and removes a key for a package no one uses.
            let package = "@skillori-test/install"
            let saved = InstallerKeys.save(["--token=test-value", "--agent", "x"], for: package)
            let has = InstallerKeys.has(package)
            let read = InstallerKeys.arguments(for: package) ?? []
            InstallerKeys.remove(for: package)
            let gone = !InstallerKeys.has(package) && InstallerKeys.arguments(for: package) == nil
            try? "saved \(saved) has \(has) read \(read == ["--token=test-value", "--agent", "x"]) removed \(gone)\n"
                .write(toFile: log, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
            return
        }
        guard let package = env["SKILLORI_TRIAL"], let log = env["SKILLORI_TRIAL_LOG"] else { return }
        let arguments = (env["SKILLORI_TRIAL_ARGS"] ?? "").split(separator: " ").map(String.init)
        Task { @MainActor in
            let started = Date()
            let result = await InstallerTrial.run(PackageInstaller(package: package), arguments: arguments)
            let text = switch result {
            case .success(let trial): "success: \(trial.skills.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.prefix(7))" })"
            case .failure(.noNode): "failure: no node"
            case .failure(.failed(let line)): "failure: \(line ?? "(no line)")"
            }
            try? (text + "\nseconds: \(Int(Date().timeIntervalSince(started)))\n").write(toFile: log, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }
}

@MainActor
enum DebugSnapshots {
    static func runIfRequested(store: InventoryStore, statusPanel: StatusPanelController?) {
        guard let dir = ProcessInfo.processInfo.environment["SKILLORI_SNAPSHOT_DIR"] else { return }
        Task { @MainActor in
            while store.inventory == nil || store.isScanning { try? await Task.sleep(for: .milliseconds(100)) }
            // Give the source answers (sample ones in pictures) a moment to land.
            try? await Task.sleep(for: .milliseconds(400))
            while store.isChecking || store.isAskingCodex { try? await Task.sleep(for: .milliseconds(100)) }
            let out = URL(fileURLWithPath: dir)
            // `SKILLORI_SNAPSHOT_ONLY=share` renders the share sheet alone: no source is asked.
            if ProcessInfo.processInfo.environment["SKILLORI_SNAPSHOT_ONLY"] == "share" {
                sharePictures(store: store, to: out)
                NSApp.terminate(nil)
                return
            }
            // `SKILLORI_SNAPSHOT_ONLY=first-start` renders first start's last step alone.
            if ProcessInfo.processInfo.environment["SKILLORI_SNAPSHOT_ONLY"] == "first-start" {
                for (off, scheme, name) in [(false, ColorScheme.light, "first-start-4"), (true, .light, "first-start-4-off"),
                                            (false, .dark, "first-start-4-dark")] {
                    picture(PanelBackdrop { FirstStartView(step: 4, previewsChecksOff: off) }
                        .environment(store).environment(\.colorScheme, scheme),
                            size: CGSize(width: 400, height: 580), to: out.appendingPathComponent("\(name).png"))
                }
                NSApp.terminate(nil)
                return
            }
            let states: [(String, PanelModel?, ColorScheme)] = [
                ("panel-live", nil, .light), ("panel-live-dark", nil, .dark),
                ("panel-updates", .sampleUpdates, .light), ("panel-in-sync", .sampleInSync, .light),
                ("panel-no-contact", .sampleNoContact, .light), ("panel-updates-dark", .sampleUpdates, .dark),
                ("panel-in-sync-dark", .sampleInSync, .dark),
                ("state-no-reading", .sampleNoReading, .light), ("state-nothing-found", .sampleNothingFound, .light),
                ("state-no-access", .sampleNoAccess, .light),
            ]
            for (name, model, scheme) in states {
                picture(PanelBackdrop { MenuPanel(fixedModel: model).frame(width: StatusPanelController.panelWidth) }
                    .environment(store).environment(\.colorScheme, scheme),
                        size: CGSize(width: 420, height: 560), to: out.appendingPathComponent("\(name).png"))
            }
            // Where each of the live panel's links leads, one per line.
            let links = PanelModel.skills(from: store).rows.compactMap { row -> String? in
                guard case let .link(text, label, command) = row else { return nil }
                return "\(text) · \(label) → \(command)"
            }
            try? (links.joined(separator: "\n") + "\nunsourced: \(store.unsourced.map(\.displayName))\n").write(to: out.appendingPathComponent("panel-links.txt"), atomically: true, encoding: .utf8)
            for (step, scheme, name) in [(1, ColorScheme.light, "first-start-1"), (2, .light, "first-start-2"),
                                         (3, .light, "first-start-3"), (4, .light, "first-start-4"),
                                         (2, .dark, "first-start-2-dark")] {
                let view = PanelBackdrop { FirstStartView(step: step) }
                    .environment(store).environment(\.colorScheme, scheme)
                let size = CGSize(width: 400, height: 580), file = out.appendingPathComponent("\(name).png")
                // Step 2 has app icons, which only the AppKit display draws right; the others have light.
                if step == 2 { render(view, size: size, to: file) } else { picture(view, size: size, to: file) }
            }
            picture(PanelBackdrop { FirstStartView(step: 3, previewsEmpty: true) }.environment(store),
                    size: CGSize(width: 400, height: 580), to: out.appendingPathComponent("first-start-3-empty.png"))
            picture(PanelBackdrop { FirstStartView(step: 4, previewsChecksOff: true) }.environment(store),
                    size: CGSize(width: 400, height: 580), to: out.appendingPathComponent("first-start-4-off.png"))
            if ProcessInfo.processInfo.environment["SKILLORI_SNAPSHOT_OPEN_PANEL"] != nil {
                statusPanel?.open()
                try? await Task.sleep(for: .seconds(6))
            }
            let lib = CGSize(width: 1120, height: 800)
            // The library and the pages it clicks through to. AppKit draws the lists and icons but
            // not the light; `picture` draws the light but no scrolling list, so the first has both.
            for (index, (name, view)) in LibraryView.snapshots(store: store).enumerated() {
                render(view.environment(store), size: lib, to: out.appendingPathComponent("\(name).png"))
                if index == 0 { picture(view.environment(store), size: lib, to: out.appendingPathComponent("\(name)-light.png")) }
                if index == 0 || name == "library-skill-twice" {
                    render(view.environment(store).environment(\.colorScheme, .dark), size: lib,
                           to: out.appendingPathComponent("\(name)-dark.png"))
                }
            }
            // Your skills with every source folded out, light and dark.
            let opened = store.openSources
            store.openSources = Set(Assist.mineBySource(store).compactMap { entry in
                if case .source(let name, _) = entry { name.lowercased() } else { nil }
            })
            render(LibraryView(path: [.mine]).environment(store), size: lib, to: out.appendingPathComponent("library-mine-open.png"))
            render(LibraryView(path: [.mine]).environment(store).environment(\.colorScheme, .dark), size: lib,
                   to: out.appendingPathComponent("library-mine-open-dark.png"))
            store.openSources = opened
            let installs = store.inventory?.installations ?? []
            render(SettingsView(ownChrome: true).environment(store), size: CGSize(width: 640, height: 680),
                   to: out.appendingPathComponent("settings.png"))
            render(SettingsView(ownChrome: true).environment(store).environment(\.colorScheme, .dark),
                   size: CGSize(width: 640, height: 680), to: out.appendingPathComponent("settings-dark.png"))
            let unknown = installs.first { $0.provenance == .unknown }
            if let unknown {
                let found = InventoryStore.LinkSearch(
                    source: .github(UpstreamSource(owner: "example", repository: "skills")), localHash: "aaa",
                    candidates: [SourceCandidate(subpath: "skills/" + unknown.directoryName, hash: "bbb", match: .sameName),
                                 SourceCandidate(subpath: "skills/docx", hash: "c", match: .other),
                                 SourceCandidate(subpath: "skills/pdf", hash: "d", match: .other),
                                 SourceCandidate(subpath: "skills/xlsx", hash: "e", match: .other)],
                    suggested: nil)
                render(LinkSourceSheet(installation: unknown).environment(store),
                       size: CGSize(width: 520, height: 250), to: out.appendingPathComponent("link-source.png"))
                render(LinkSourceSheet(installation: unknown, preview: found, text: "example/skills").environment(store),
                       size: CGSize(width: 520, height: 440), to: out.appendingPathComponent("link-source-found.png"))
            }
            // Finding sources, with real answers: this asks mdskills.ai and GitHub.
            var answered: [(InventoryStore.UnlinkedGroup, SourceFinder.Search)] = []
            let finder = SourceFinder()
            // With every skill linked already, the linked ones stand in, so the sheet can still be seen.
            var unlinked = await store.unlinkedGroups()
            if unlinked.isEmpty { unlinked = await store.unlinkedGroups(includingLinked: true) }
            for group in unlinked { answered.append((group, await store.proposals(for: group, using: finder))) }
            if !answered.isEmpty {
                render(FindSourcesSheet(preview: answered).environment(store),
                       size: CGSize(width: 600, height: 640), to: out.appendingPathComponent("find-sources.png"))
            }
            sharePictures(store: store, to: out)
            // The update command: waiting to be run, and after a run that printed something.
            if let target = store.updatable.first {
                // The panel with a source opened, and after a run for that source.
                let first = PanelModel.live(from: store).groups.first
                let open = PanelBackdrop { MenuPanel(opened: Set([first?.id].compactMap { $0 })).frame(width: StatusPanelController.panelWidth) }
                picture(open.environment(store), size: CGSize(width: 420, height: 760), to: out.appendingPathComponent("panel-live-open.png"))
                // The same through AppKit: no light in the block, but the scrolling list of skills is drawn.
                render(open.environment(store), size: CGSize(width: 420, height: 760), to: out.appendingPathComponent("panel-live-open-list.png"))
                store.updater.setSample(names: (first?.updatable ?? []).map(\.directoryName), phase: .succeeded,
                                        output: "Checking 1 skill for updates\nUpdating \(target.directoryName) from its source\nUpdated 1 skill\n")
                picture(open.environment(store), size: CGSize(width: 420, height: 820), to: out.appendingPathComponent("panel-update-ran.png"))
                store.updater.setSample(names: (first?.updatable ?? []).map(\.directoryName), phase: .failed("The installer ended with code 1."),
                                        output: "Checking 18 skills for updates\nCould not reach the source\n")
                picture(PanelBackdrop { MenuPanel().frame(width: StatusPanelController.panelWidth) }.environment(store),
                        size: CGSize(width: 420, height: 820), to: out.appendingPathComponent("panel-update-failed.png"))
                // One skill run from its own button: while it runs, and when it went wrong.
                store.updater.setSample(names: [target.directoryName], phase: .running, output: "Checking 1 skill for updates\n")
                render(open.environment(store), size: CGSize(width: 420, height: 820), to: out.appendingPathComponent("panel-update-one-running.png"))
                store.updater.setSample(names: [target.directoryName], phase: .failed("The installer ended with code 1."),
                                        output: "Checking 1 skill for updates\nCould not reach the source\n")
                render(open.environment(store), size: CGSize(width: 420, height: 820), to: out.appendingPathComponent("panel-update-one-failed.png"))
                store.updater.setSample(names: [], phase: .idle, output: "")
            }
            // When the sources gave no answer: asked to wait with a time, the same right after an
            // update went through, and no contact at all, where Try again can help.
            let inAnHour = Date().addingTimeInterval(60 * 60)
            store.setSampleTrouble(.rateLimited, until: inAnHour)
            render(LibraryView().environment(store), size: lib, to: out.appendingPathComponent("library-asked-to-wait.png"))
            picture(PanelBackdrop { MenuPanel().frame(width: StatusPanelController.panelWidth) }.environment(store),
                    size: CGSize(width: 420, height: 760), to: out.appendingPathComponent("panel-asked-to-wait.png"))
            if let one = store.inventory?.installations.first(where: { store.sourceKey(for: $0) != nil }) {
                store.updater.setSample(names: [one.directoryName], phase: .succeeded, output: "Updated 1 skill\n")
                store.setSampleTrouble(.rateLimited, until: inAnHour)
                render(LibraryView().environment(store), size: lib, to: out.appendingPathComponent("library-updated-then-wait.png"))
                store.updater.setSample(names: [], phase: .idle, output: "")
            }
            store.setSampleTrouble(.offline)
            render(LibraryView().environment(store), size: lib, to: out.appendingPathComponent("library-no-contact.png"))
            store.setSampleTrouble(nil)
            // A skill whose recorded source is gone: its page and the panel, the link sheet, kept
            // as a local copy, and linked to a new home.
            if let lost = store.lostSources.first {
                let page = { LibraryView(path: [.skill(lost.id)]).environment(store) }
                render(page(), size: lib, to: out.appendingPathComponent("library-source-gone.png"))
                render(page().environment(\.colorScheme, .dark), size: lib, to: out.appendingPathComponent("library-source-gone-dark.png"))
                picture(PanelBackdrop { MenuPanel().frame(width: StatusPanelController.panelWidth) }.environment(store),
                        size: CGSize(width: 420, height: 760), to: out.appendingPathComponent("panel-source-gone.png"))
                render(LinkSourceSheet(installation: lost).environment(store), size: CGSize(width: 600, height: 420),
                       to: out.appendingPathComponent("link-source-gone.png"))
                store.keepLocal(lost)
                render(page(), size: lib, to: out.appendingPathComponent("library-kept-local.png"))
                render(LibraryView(path: [.mine]).environment(store), size: lib, to: out.appendingPathComponent("library-mine-kept-local.png"))
                store.stopKeepingLocal(lost)
                store.setSampleLink(lost, owner: "example", repository: "plugins", subpath: lost.directoryName + "/skills/" + lost.directoryName)
                render(page(), size: lib, to: out.appendingPathComponent("library-source-relinked.png"))
                try? "relinked: \(store.status(for: lost)) · \(store.updateCommandText(for: [lost]))\n"
                    .write(to: out.appendingPathComponent("relinked.txt"), atomically: true, encoding: .utf8)
                store.setSampleLink(lost, owner: "", repository: "", subpath: nil)
            }
            // A skill linked to an install script that answered "gone" and said where it went.
            if let unknown = installs.first(where: { $0.provenance == .unknown }) {
                let said = SourceNotice(body: "#!/bin/sh\nprintf '%s\\n' \"This installer has moved.\"\n"
                    + "printf '%s\\n' \"Members can copy their new install command from the Library:\"\n"
                    + "printf '%s\\n' \"https://www.example.com/library/skills\"\nexit 1\n")
                store.setSampleMovedInstaller(unknown, notice: said)
                let page = { LibraryView(path: [.mine, .skill(unknown.id)]).environment(store) }
                render(page(), size: lib, to: out.appendingPathComponent("library-source-moved.png"))
                render(page().environment(\.colorScheme, .dark), size: lib, to: out.appendingPathComponent("library-source-moved-dark.png"))
                // The same skill once unlinked: no source now, but the trail to the old one stays.
                store.unlink(unknown)
                try? "past: \(String(describing: store.pastSource(of: unknown)))\n"
                    .write(to: out.appendingPathComponent("past.txt"), atomically: true, encoding: .utf8)
                render(page(), size: lib, to: out.appendingPathComponent("library-source-past.png"))
                render(page().environment(\.colorScheme, .dark), size: lib, to: out.appendingPathComponent("library-source-past-dark.png"))
                let alone = await store.unlinkedGroups(only: [unknown.id])
                render(FindSourcesSheet(preview: alone.map { ($0, SourceFinder.Search(proposals: [], problem: nil)) }).environment(store),
                       size: CGSize(width: 600, height: 420), to: out.appendingPathComponent("find-sources-past.png"))
                // The site it came from has an installer on npm: offered, not ticked.
                let sited = PackageInfo(package: "@example/install", version: "0.1.0",
                                        summary: "Installs the Example members' agent skills.", site: URL(string: "https://www.example.com"))
                render(FindSourcesSheet(preview: alone.map { ($0, SourceFinder.Search(proposals: [], problem: nil)) }, installers: [sited])
                    .environment(store), size: CGSize(width: 600, height: 460), to: out.appendingPathComponent("find-sources-installer.png"))
                render(FindSourcesSheet(preview: alone.map { ($0, SourceFinder.Search(proposals: [], problem: nil)) }, installers: [sited])
                    .environment(store).environment(\.colorScheme, .dark),
                       size: CGSize(width: 600, height: 460), to: out.appendingPathComponent("find-sources-installer-dark.png"))
                try? "sites: \(alone.map { store.knownSites(of: $0) })\n"
                    .write(to: out.appendingPathComponent("sites.txt"), atomically: true, encoding: .utf8)
                store.forgetSamplePastSource(unknown)
                // The same skill linked to an installer run with the reader's own key: the sheet
                // with npm's answer, and the skill's page, which says how to update.
                let info = PackageInfo(package: "@example/install", version: "0.1.0",
                                       summary: "Installs the Example members' agent skills for the coding agents on your machine.",
                                       site: URL(string: "https://www.example.com"))
                render(LinkSourceSheet(installation: unknown, package: info, text: "npx @example/install@latest --token=…").environment(store),
                       size: CGSize(width: 520, height: 400), to: out.appendingPathComponent("link-source-package.png"))
                // The page it was installed from, read for what it names.
                let html = """
                <pre>npx skills add example/agent-skills --skill \(unknown.directoryName)</pre>
                <pre>curl -fsSL https://www.example.com/install-skills | bash</pre>
                <pre>npx @example/install@latest --token=YOUR_KEY</pre>
                """
                let leads = SourcePage.leads(in: html)
                render(LinkSourceSheet(installation: unknown, text: "https://www.example.com/skills", page: ("example.com", leads)).environment(store),
                       size: CGSize(width: 520, height: 600), to: out.appendingPathComponent("link-source-page.png"))
                render(LinkSourceSheet(installation: unknown, package: info, text: leads[2].text, via: "example.com: " + leads[2].line)
                    .environment(store).environment(\.colorScheme, .dark),
                       size: CGSize(width: 520, height: 440), to: out.appendingPathComponent("link-source-page-followed-dark.png"))
                try? (leads.map { "\($0.line) → \($0.text)" }.joined(separator: "\n") + "\n")
                    .write(to: out.appendingPathComponent("page-leads.txt"), atomically: true, encoding: .utf8)
                store.link(unknown, toPackage: info)
                try? await Task.sleep(for: .milliseconds(600))
                try? "package: \(store.status(for: unknown)) · asked: \(store.sourceKey(for: unknown).map { store.readings[$0] != nil } ?? false)\n"
                    .write(to: out.appendingPathComponent("package.txt"), atomically: true, encoding: .utf8)
                render(page(), size: lib, to: out.appendingPathComponent("library-source-package.png"))
                render(page().environment(\.colorScheme, .dark), size: lib, to: out.appendingPathComponent("library-source-package-dark.png"))
                render(LibraryView(path: [.mine]).environment(store), size: lib, to: out.appendingPathComponent("library-mine-package.png"))
                picture(PanelBackdrop { MenuPanel().frame(width: StatusPanelController.panelWidth) }.environment(store),
                        size: CGSize(width: 420, height: 640), to: out.appendingPathComponent("panel-package.png"))
                let lines = PanelModel.skills(from: store).rows.compactMap { row -> String? in
                    if case let .line(text, data, _) = row { "\(text) · \(data)" } else { nil }
                }
                store.unlink(unknown)
                try? (lines.joined(separator: "\n") + "\nafter unlink: \(String(describing: store.pastSource(of: unknown)))\n")
                    .write(to: out.appendingPathComponent("package-unlinked.txt"), atomically: true, encoding: .utf8)
                render(LibraryView(path: [.skill(unknown.id)]).environment(store), size: lib,
                       to: out.appendingPathComponent("library-unlinked-by-you.png"))
                store.forgetSamplePastSource(unknown)
                // With that skill unlinked, where the panel's links lead.
                let unlinked = PanelModel.skills(from: store).rows.compactMap { row -> String? in
                    guard case let .link(text, label, command) = row else { return nil }
                    return "\(text) · \(label) → \(command)"
                }
                try? (unlinked.joined(separator: "\n") + "\nunsourced: \(store.unsourced.map(\.displayName))\n")
                    .write(to: out.appendingPathComponent("panel-links-unlinked.txt"), atomically: true, encoding: .utf8)
            }
            let icon = ImageRenderer(content: AppIconArt())
            icon.scale = AppIconArt.scale
            if let image = icon.cgImage {
                try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                    .write(to: out.appendingPathComponent("app-icon-1024.png"))
            }
            picture(MarkSheet(), size: CGSize(width: 1280, height: 460), to: out.appendingPathComponent("mark.png"))
            NSApp.terminate(nil)
        }
    }

    /// Passing skills on: the list, the receipts, and the text that is made for the real skills.
    private static func sharePictures(store: InventoryStore, to out: URL) {
        // The two ways in: the button above your skills, and the one on a skill's page.
        let lib = CGSize(width: 1120, height: 800)
        render(LibraryView(path: [.mine]).environment(store), size: lib, to: out.appendingPathComponent("share-entry-mine.png"))
        if let row = store.shareList().rows.first, let skill = Assist.mine(store).first(where: { $0.id == row.id })?.primary {
            render(LibraryView(path: [.mine, .skill(skill.id)]).environment(store), size: lib,
                   to: out.appendingPathComponent("share-entry-skill.png"))
        }
        let share = CGSize(width: 600, height: 780)
        render(ShareSheet(preview: nil).environment(store), size: share, to: out.appendingPathComponent("share.png"))
        let shared = store.shareList()
        // Most of the largest source left unticked, so a group shows as partly ticked.
        let fewer = Set(shared.groups.max { $0.rows.count < $1.rows.count }.map { $0.rows.dropFirst(2).map(\.id) } ?? [])
        render(ShareSheet(preview: nil, target: .agent, agent: store.shareAgents.first, unticked: fewer)
            .environment(store).environment(\.colorScheme, .dark), size: share, to: out.appendingPathComponent("share-some-dark.png"))
        render(ShareSheet(preview: .copied).environment(store), size: CGSize(width: 600, height: 460),
               to: out.appendingPathComponent("share-copied.png"))
        render(ShareSheet(preview: .copied, target: .agent, agent: store.shareAgents.first, unticked: fewer).environment(store),
               size: CGSize(width: 600, height: 460), to: out.appendingPathComponent("share-copied-agent.png"))
        render(ShareSheet(preview: .saved(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/skills.sh")))
            .environment(store), size: CGSize(width: 600, height: 300), to: out.appendingPathComponent("share-saved.png"))
        let everything = ShareCommand(shared.rows.map(\.skill))
        try? ([everything.line, ShareCommand(shared.rows.map(\.skill), agent: store.shareAgents.first).prompt, everything.script,
               shared.leftOutSentence ?? "Nothing left out.", "agents offered: \(store.shareAgents.map(\.id))"]
            .joined(separator: "\n-----\n") + "\n").write(to: out.appendingPathComponent("share.txt"), atomically: true, encoding: .utf8)
    }

    /// For views SwiftUI draws alone, such as the panel. Unlike a cached AppKit display this
    /// also draws shaders, so the light in a block shows in the picture.
    private static func picture(_ view: some View, size: CGSize, to url: URL) {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func render(_ view: some View, size: CGSize, to url: URL) {
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: size),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }
}

/// Stand-in for the desktop behind the panel.
private struct PanelBackdrop<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content
    var body: some View {
        ZStack(alignment: .top) {
            scheme == .dark ? Color(hex: 0x0E0E0F) : Color(hex: 0xE6E6E8)
            content.padding(.top, 28)
        }
        .clipped()
    }
}

/// The mark as app icon and as menu bar image, at real size and enlarged.
private struct MarkSheet: View {
    var body: some View {
        HStack(spacing: 32) {
            appIcon(side: 328)
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) { appIcon(side: 64); appIcon(side: 32); appIcon(side: 16) }
                bar(light: true, scale: 6)
                bar(light: false, scale: 6)
                bar(light: true, scale: 1)
                bar(light: false, scale: 1)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0xE6E6E8))
    }

    private func appIcon(side: CGFloat) -> some View {
        LightField(.meadow, radius: side * 100 / 820, still: true, easedThroughout: true)
            .overlay(SkilloriMark(safeZone: true).fill(.white))
            .frame(width: side, height: side)
    }

    private func bar(light: Bool, scale: CGFloat) -> some View {
        HStack(spacing: 8 * scale) {
            ForEach([SkilloriMark.MenuBarState.rest, .new, .attention, .stale], id: \.self) { state in
                // The image the menu bar really gets; template states take the bar's colour.
                Image(nsImage: SkilloriMark.menuBarImage(state, side: 22 * scale))
                    .foregroundStyle(light ? Color.white : Color.black)
            }
        }
        .padding(.horizontal, 8 * scale)
        .frame(height: 24 * scale)
        .background(light ? Color(hex: 0x8E8E93) : Color(hex: 0xD8D8DC))
    }
}

/// The app icon at 1024 px: macOS's standard plate (824 px, continuous corners) filled with the
/// Meadow light, with the mark's full grid on it in white, so the safe zone is the distance to
/// the plate's edge. It is drawn at a quarter of its pixel size and rendered at four times scale,
/// so the light's bevel has the proportions it has on a block in the app.
struct AppIconArt: View {
    static let scale: CGFloat = 4

    var body: some View {
        LightField(.meadow, radius: 185.4 / Self.scale, corners: .continuous, still: true, easedThroughout: true)
            .overlay(SkilloriMark(safeZone: true).fill(.white))
            .frame(width: 824 / Self.scale, height: 824 / Self.scale)
            .frame(width: 1024 / Self.scale, height: 1024 / Self.scale)
    }
}
#endif
