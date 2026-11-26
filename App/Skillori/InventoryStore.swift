import AppKit
import Foundation
import Observation
import SkilloriCore

/// Holds the latest inventory, the user's chosen project folders, and what the sources said
/// the last time they were asked.
///
/// Project paths and the on/off choice live in UserDefaults; source answers and held-back
/// skills live in one small JSON file. The app is not sandboxed (docs/beslut/0002), so a plain
/// path is enough to read a chosen folder.
@MainActor
@Observable
final class InventoryStore {
    private(set) var inventory: Inventory?
    /// Skills whose folder the installer replaced, from the id they had to the one they have now.
    /// An id is the folder's file identity, so an update gives a skill a new one; an open page
    /// follows the skill through this instead of losing it.
    private var replacedIDs: [Installation.ID: Installation.ID] = [:]
    private(set) var isScanning = false
    private(set) var projects: [URL]

    /// What each tracked skill's source last said, by `sourceKey`.
    private(set) var readings: [String: UpstreamReading] = [:]
    /// Skills the reader keeps on their installed version, and since when.
    private(set) var held: [String: Date] = [:]
    /// Sources the reader has pointed out for skills that came with no record, or whose recorded
    /// source is gone, by `sourceKey`.
    private(set) var links: [String: SourceLink] = [:]
    /// Skills the reader keeps as local copies, no longer checked against a source, and since
    /// when. By folder, like links.
    private(set) var keptLocal: [String: Date] = [:]
    /// Skills moved from a source the installer recorded to the one the reader linked, by folder.
    /// Kept, so the skill's page can tell where it came from before.
    private(set) var moves: [String: Move] = [:]

    struct Move: Codable, Equatable {
        let from: String
        let to: String
        let at: Date
    }
    /// Sources the reader unlinked, by folder: after they stopped answering, or while they still
    /// answered. Kept, so the trail isn't lost with the link: its page and Find sources can still
    /// say it, and Find sources can offer it again.
    private(set) var pastSources: [String: PastSource] = [:]

    struct PastSource: Codable, Equatable {
        /// The source as Skillori named it, such as `example.com/api/install-skills`.
        let name: String
        /// When the reader unlinked it.
        let until: Date
        /// What the source said when it stopped answering, if anything.
        let notice: SourceNotice?
        /// The reader unlinked it while it still answered. Nil in records from before this was kept.
        var byYou: Bool? = nil
        /// The installer package it was linked to, so Find sources can offer it again.
        var package: String? = nil
        /// The GitHub repository it was linked to (`owner/repo`), so Find sources can look there again.
        var repository: String? = nil
    }
    /// What each Claude Code plugin's marketplace last said, by plugin id (`name@marketplace`).
    private(set) var pluginReadings: [String: UpstreamReading] = [:]
    /// Folder hashes at installed plugin commits. They never change, so each is asked for once.
    private var pluginBaselines: [String: String] = [:]
    /// What Codex last said about which of its plugins it reads.
    private(set) var codexPlugins: CodexPluginList?
    private(set) var isAskingCodex = false
    private(set) var isChecking = false
    /// How many skills the check in progress asks about.
    private(set) var checkingCount = 0
    /// Set when a forced check was asked for while another was running.
    private var checkAgain = false
    /// Set when a rescan was asked for while another was running.
    private var scanAgain = false
    /// When sources last gave a real answer.
    private(set) var lastCheck: Date?
    /// Why the latest attempt got no answer, if it did not.
    private(set) var lastProblem: UpstreamState.Reason?
    /// The tracked skills, by `sourceKey`, whose source gave no answer the last time it was asked.
    private(set) var unanswered: Set<String> = []
    /// When a source that asked Skillori to wait may be asked again, if it said.
    private(set) var waitUntil: Date?
    /// When the latest attempt to ask the sources ended, answered or not.
    private(set) var lastAttempt: Date?
    /// Asks again once the wait is over, as the library says it will.
    @ObservationIgnored private var askAgain: Task<Void, Never>?
    /// An update that just went well, shown for a moment as a receipt before its line folds away.
    private(set) var receipt: Receipt?
    /// Installer packages whose arguments (the reader's key) are kept in the Keychain, so their
    /// skills can be checked by running the installer into a folder of its own.
    private(set) var keyedPackages: Set<String> = []
    /// What an installer printed last when a check with the reader's key went wrong, by package.
    private(set) var installerProblems: [String: String] = [:]

    /// What the reader just linked, said on the page they are on until they leave it.
    private(set) var linkReceipt: LinkReceipt?

    struct LinkReceipt: Equatable {
        /// The copies linked, by link key.
        var keys: Set<String>
        /// The skills' names, once each, in the order they were linked.
        var names: [String]
        /// The sources' names, once each.
        var sources: [String]
        let at: Date

        func contains(_ installation: Installation) -> Bool { keys.contains(InventoryStore.linkKey(for: installation)) }
    }

    // MARK: Installers run with the reader's key

    /// The installer this skill is linked to, when it is one run with the reader's key.
    func packageInstaller(of installation: Installation) -> PackageInstaller? {
        if case .package(let installer)? = link(for: installation)?.source { installer } else { nil }
    }

    func hasKey(for installation: Installation) -> Bool {
        packageInstaller(of: installation).map { keyedPackages.contains($0.package) } ?? false
    }

    /// Keeps the reader's arguments for this skill's installer in the Keychain and checks it now.
    @discardableResult
    func keepKey(_ arguments: [String], for installation: Installation) -> Bool {
        guard let installer = packageInstaller(of: installation), InstallerKeys.save(arguments, for: installer.package) else { return false }
        keyedPackages.insert(installer.package)
        installerProblems[installer.package] = nil
        Task { await checkSources(force: true, only: Set(keysLinked(to: installer.package))) }
        return true
    }

    /// Removes the key from the Keychain; the skills it fetched are no longer checked.
    func removeKey(for installation: Installation) {
        guard let installer = packageInstaller(of: installation) else { return }
        InstallerKeys.remove(for: installer.package)
        keyedPackages.remove(installer.package)
        installerProblems[installer.package] = nil
        for key in keysLinked(to: installer.package) { readings[key] = nil; held[key] = nil }
        save()
    }

    private func keysLinked(to package: String) -> [String] {
        links.filter { $0.value.package == package }.map(\.key)
    }

    /// Runs each installer with a kept key once, into a folder of its own, and compares what it
    /// wrote with each skill linked to it here. One run answers for every skill it installs.
    private func installerReadings(for installations: [Installation]) async -> [String: UpstreamReading] {
        var byPackage: [String: [Installation]] = [:]
        for installation in installations {
            guard let installer = packageInstaller(of: installation), keyedPackages.contains(installer.package) else { continue }
            byPackage[installer.package, default: []].append(installation)
        }
        var found: [String: UpstreamReading] = [:]
        for (package, members) in byPackage.sorted(by: { $0.key < $1.key }) {
            guard let arguments = InstallerKeys.arguments(for: package) else {
                keyedPackages.remove(package)
                continue
            }
            let result = await InstallerTrial.run(PackageInstaller(package: package), arguments: arguments)
            let now = Date()
            switch result {
            case .failure(let failure):
                installerProblems[package] = switch failure {
                case .noNode: "npx was not found. Checking needs Node."
                case .failed(let line): line ?? "The installer ended without saying why."
                }
                for installation in members {
                    found[Self.linkKey(for: installation)] = UpstreamReading(state: .cannotCheck(.failed), checkedAt: now)
                }
            case .success(let trial):
                installerProblems[package] = nil
                let paths = members.map(\.canonicalPath)
                let local = await Task.detached(priority: .utility) {
                    Dictionary(uniqueKeysWithValues: paths.map { ($0, try? GitTreeHash.hashDirectory(at: URL(fileURLWithPath: $0)).treeID) })
                }.value
                for installation in members {
                    let key = Self.linkKey(for: installation)
                    let here = local[installation.canonicalPath] ?? nil
                    links[key]?.localHash = here
                    let state: UpstreamState = switch trial.skills[installation.directoryName.lowercased()]
                        ?? trial.skills[installation.displayName.lowercased()] {
                    case nil: .cannotCheck(.folderGone)
                    case let id? where id == here: .upToDate
                    case let id?: .updateAvailable(upstreamHash: id)
                    }
                    found[key] = UpstreamReading(state: state, checkedAt: now)
                }
            }
        }
        return found
    }

    /// Notes a link for the receipt. Links made together, as Find sources makes them, are one receipt.
    private func noteLinked(_ installations: [Installation], to source: String) {
        let now = Date()
        var receipt = linkReceipt.flatMap { now.timeIntervalSince($0.at) < 2 ? $0 : nil }
            ?? LinkReceipt(keys: [], names: [], sources: [], at: now)
        for installation in installations {
            receipt.keys.insert(Self.linkKey(for: installation))
            if !receipt.names.contains(installation.displayName) { receipt.names.append(installation.displayName) }
        }
        if !receipt.sources.contains(source) { receipt.sources.append(source) }
        linkReceipt = receipt
    }

    /// The reader left the page that said it.
    func clearLinkReceipt() {
        if linkReceipt != nil { linkReceipt = nil }
    }

    struct Receipt {
        /// The skills as they were when the update ran.
        let installations: [Installation]
        /// The source's name, as the line said it before the update.
        let source: String
        let at: Date
        /// The installer's last lines stay in view for a moment, then fold away first.
        var showsOutput = true

        func contains(_ installation: Installation) -> Bool {
            installations.contains { $0.directoryName == installation.directoryName }
        }
    }
    /// Runs the installer's update command when the reader asks for it.
    let updater = UpdateRunner()
    /// Runs Claude Code's update for its plugins when the reader asks for it.
    let pluginUpdater = PluginUpdateRunner()
    /// Adds Codex plugins again from Codex's current catalog when the reader asks for it.
    let codexRunner = CodexPluginRunner()
    /// Asking sources is on unless the reader turns it off. Their choice is saved either way,
    /// so a no can be told from never having chosen.
    var checksEnabled: Bool {
        didSet {
            guard checksEnabled != oldValue else { return }
            UserDefaults.standard.set(checksEnabled, forKey: Self.checksKey)
            // During first start the asking waits for it to close; `firstStartEnded` begins it.
            if checksEnabled, !waitsForFirstStart { beginChecks() }
        }
    }
    /// An installation that has not finished first start asks nothing on its own while first start
    /// is up: neither macOS about notifications nor a source. First start's last step says what is
    /// sent and can turn the checks off. A check the reader asks for themselves still runs.
    private(set) var waitsForFirstStart: Bool
    #if DEBUG
    /// How many times the sources have been asked since the app opened. For the probes.
    @ObservationIgnored private(set) var checksStarted = 0
    #endif

    /// First start closed, by its last button or any other way. On a new installation this is
    /// when the choice is saved and, with checks on, when macOS is asked about notifications and
    /// the sources are asked for the first time.
    func firstStartEnded() {
        guard waitsForFirstStart else { return }
        waitsForFirstStart = false
        UserDefaults.standard.set(checksEnabled, forKey: Self.checksKey)
        if checksEnabled { beginChecks() }
    }

    private func beginChecks() {
        Notifier.shared.requestPermission()
        Task { await checkSources(force: true) }
    }

    /// The app opened. With checks on, macOS is asked about notifications, which it only puts to
    /// the reader if it never has. Checks turned on before Skillori had notifications (0.2.0)
    /// never led to that question, and neither did an answer that was never given. A new
    /// installation waits for first start instead (`firstStartEnded`).
    func appOpened() {
        guard checksEnabled, !waitsForFirstStart, !usesSampleReadings else { return }
        Notifier.shared.requestPermission()
    }

    private static let projectsKey = "projectPaths"
    private static let checksKey = "asksSources"
    private static let minimumScanDisplay: TimeInterval = 0.45
    /// How long an answer stands before the sources are asked again.
    static let checkInterval: TimeInterval = 6 * 60 * 60
    private let usesSampleReadings: Bool
    /// The variables the scan reads. Starts as this app's own, which lack what the reader's
    /// shell sets when the app was opened from Finder; `followLoginShell` fills those in.
    private var environment = ProcessInfo.processInfo.environment

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.projectsKey) ?? []
        projects = paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
        #if DEBUG
        usesSampleReadings = ProcessInfo.processInfo.environment["SKILLORI_SAMPLE_READINGS"] != nil
        #else
        usesSampleReadings = false
        #endif
        // With no saved choice, checks are on for a new installation. One that finished first
        // start without a saved choice is older than 0.2.25, where "Not now" saved nothing: no
        // choice there may be a no, so it stays off.
        let chosen = UserDefaults.standard.object(forKey: Self.checksKey) as? Bool
        let finishedFirstStart = UserDefaults.standard.bool(forKey: FirstStartController.doneKey)
        checksEnabled = usesSampleReadings || (chosen ?? !finishedFirstStart)
        // Whatever was chosen on the last step, nothing is asked until first start has closed:
        // a choice made there is saved at once, and the app may be quit before Done.
        waitsForFirstStart = !usesSampleReadings && !finishedFirstStart
        if !usesSampleReadings { loadSaved() }
        Task {
            await rescan()
            await followLoginShell()
            // While the app runs, read again now and then, in case a change was not reported,
            // and ask the sources again when the last answer has grown old.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30 * 60))
                await rescan()
                await checkSources()
            }
        }
        // After sleep the last answer may be hours old and the folders may have changed.
        NotificationCenter.default.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                               queue: .main, using: { [weak self] _ in
            Task { @MainActor in
                // The network is often not back the moment the Mac wakes.
                try? await Task.sleep(for: .seconds(20))
                await self?.rescan()
                await self?.checkSources()
            }
        })
    }

    // MARK: Watching

    @ObservationIgnored private lazy var watcher = FolderWatcher { [weak self] in
        Task { @MainActor in await self?.rescan() }
    }

    /// The folders whose changes make the app read again: every folder that holds skills,
    /// and the folder of the installer's lock file. Folders inside another watched one are
    /// left out, since FSEvents reports changes in subfolders too.
    private func watchFolders(of inventory: Inventory) {
        guard ProcessInfo.processInfo.environment["SKILLORI_SNAPSHOT_DIR"] == nil else { return }
        var paths = inventory.roots.filter { $0.state == .found }
            .map { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path }
        if let lock = inventory.lockFile {
            paths.append(URL(fileURLWithPath: lock).deletingLastPathComponent().resolvingSymlinksInPath().path)
        }
        let sorted = Array(Set(paths)).sorted()
        var kept: [String] = []
        for path in sorted where !kept.contains(where: { path.hasPrefix($0 + "/") }) {
            kept.append(path)
        }
        watcher.watch(kept)
    }

    var needsAttention: Bool { localChangeCount > 0 }

    /// The latest attempt to ask the sources got no answer, so the statuses shown are older
    /// than they look. Only meaningful while checks are on and something has a source.
    var isStale: Bool { checksEnabled && (trackedCount > 0 || !pluginRecords.isEmpty) && lastProblem != nil && !isChecking }

    // MARK: Sources

    /// Identifies a tracked skill by where it comes from, so an answer survives a rescan.
    func sourceKey(for installation: Installation) -> String? {
        if keptLocal[Self.linkKey(for: installation)] != nil { return nil }
        switch installation.provenance {
        case .skillsLock(let source, _, let subpath, _, _):
            // Linked to a new home because the recorded one is gone: the link is asked instead.
            let key = Self.linkKey(for: installation)
            return links[key] == nil ? "\(source)#\(subpath ?? "")" : key
        case .unknown:
            let key = Self.linkKey(for: installation)
            return links[key] == nil ? nil : key
        case .managed: return nil
        }
    }

    nonisolated fileprivate static func linkKey(for installation: Installation) -> String { "link:" + installation.canonicalPath }

    /// The source the reader linked this skill to, if they did.
    func link(for installation: Installation) -> SourceLink? {
        if case .managed = installation.provenance { return nil }
        return links[Self.linkKey(for: installation)]
    }

    /// Why the source the installer recorded for this skill can't be used any more: it no longer
    /// answers, no longer has the folder, is of a kind Skillori can't ask, or left nothing to
    /// compare with. Nil for every other skill, and once the reader has linked or kept it.
    func lostSource(of installation: Installation) -> UpstreamState.Reason? {
        guard case .skillsLock = installation.provenance, link(for: installation) == nil,
              !isKeptLocal(installation) else { return nil }
        guard upstreamSource(for: installation) != nil else { return .unsupported }
        if case .cannotCheck(let reason)? = reading(for: installation)?.state, Self.lostReasons.contains(reason) { return reason }
        return nil
    }

    /// The answers that say the recorded source is no use, as opposed to a check that didn't get through.
    static let lostReasons: Set<UpstreamState.Reason> = [.notFound, .folderGone, .unsupported, .noBaseline]

    /// The source the installer recorded, as it wrote it, for saying which one is gone.
    func recordedSource(of installation: Installation) -> String? {
        if case .skillsLock(let source, _, _, _, _) = installation.provenance { source } else { nil }
    }

    /// Whether the reader can link this skill to a source: it has none, or its recorded one is gone.
    func canLink(_ installation: Installation) -> Bool {
        guard link(for: installation) == nil else { return false }
        return installation.provenance == .unknown || lostSource(of: installation) != nil
    }

    /// Where this skill moved from, while the installer's record still names the source it moved to.
    func move(of installation: Installation) -> Move? {
        guard let move = moves[Self.linkKey(for: installation)], recordedSource(of: installation) == move.to,
              link(for: installation) == nil else { return nil }
        return move
    }

    /// The source this skill was linked to until it stopped answering and the reader unlinked it,
    /// while it has no other.
    func pastSource(of installation: Installation) -> PastSource? {
        guard link(for: installation) == nil else { return nil }
        return pastSources[Self.linkKey(for: installation)]
    }

    func isKeptLocal(_ installation: Installation) -> Bool {
        keptLocal[Self.linkKey(for: installation)] != nil
    }

    /// Stops checking this skill against its source; it is the reader's local copy from now on.
    func keepLocal(_ installation: Installation) {
        keptLocal[Self.linkKey(for: installation)] = Date()
        save()
    }

    /// Checks it against the installer's recorded source again.
    func stopKeepingLocal(_ installation: Installation) {
        keptLocal[Self.linkKey(for: installation)] = nil
        save()
    }

    /// The reader's skills whose recorded source is gone, by name.
    var lostSources: [Installation] {
        own.filter { lostSource(of: $0) != nil }.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }

    func upstreamSource(for installation: Installation) -> SkillSource? {
        if let link = link(for: installation) { return link.source }
        guard case .skillsLock(let source, let url, _, _, _) = installation.provenance else { return nil }
        return UpstreamSource(source: source, sourceURL: url, ref: installation.sourceRef, sourceType: installation.sourceType)
            .map(SkillSource.github)
    }

    /// The folder inside the source that this skill is compared with.
    func sourceSubpath(for installation: Installation) -> String? {
        if let link = link(for: installation) { return link.subpath.isEmpty ? nil : link.subpath }
        guard case .skillsLock(_, _, let subpath, _, _) = installation.provenance else { return nil }
        return subpath
    }

    func reading(for installation: Installation) -> UpstreamReading? {
        sourceKey(for: installation).flatMap { readings[$0] }
    }

    /// What a gone source said along with its answer, such as where its installer moved to.
    func notice(for installation: Installation) -> SourceNotice? {
        guard let reading = reading(for: installation), case .cannotCheck(.notFound) = reading.state else { return nil }
        return reading.notice
    }

    func isHeld(_ installation: Installation) -> Bool {
        sourceKey(for: installation).map { held[$0] != nil } ?? false
    }

    func status(for installation: Installation) -> SkillStatus {
        switch installation.provenance {
        case .managed:
            guard checksEnabled, let plugin = installation.plugin else { return .managed }
            if plugin.app == "Codex", let codex = codexPlugins, codex.isLeftBehind(Self.codexKey(plugin)) {
                return .leftBehind(owner: plugin.app, replacement: codex.replacement(for: Self.codexKey(plugin)))
            }
            if case .updateAvailable(let upstream) = pluginReadings[plugin.id]?.state, Self.isAhead(upstream, of: plugin) {
                // Only Claude Code's update is one Skillori can run. Cursor and Codex bring theirs.
                return plugin.app == "Claude Code" ? .ownerUpdate(owner: plugin.app, upstream: upstream)
                    : .sourceAhead(owner: plugin.app, upstream: upstream)
            }
            return .managed
        case _ where isKeptLocal(installation):
            return .keptLocal
        case .unknown, .skillsLock where link(for: installation) != nil:
            guard let link = link(for: installation) else { return .noSource }
            // An installer run with the reader's own key: checked only when the reader keeps their key here.
            if case .package(let installer) = link.source, !keyedPackages.contains(installer.package) {
                return .byInstaller(source: installer.name)
            }
            // Linked by the reader: there is no installer baseline, so "differs" is all that can be said.
            let state = reading(for: installation)?.state
            if isHeld(installation) {
                if case .updateAvailable = state { return .heldBack(sourceMoved: true) }
                return .heldBack(sourceMoved: false)
            }
            switch state {
            // From GitHub the installer can take it over and bring the source's version; from
            // anywhere else, or in a folder it doesn't write, all Skillori can say is that it differs.
            // An installer run with the reader's key brings the new version itself.
            case .updateAvailable(let upstream):
                if case .package = link.source { return .updateAvailable(upstream: upstream) }
                return adoption(for: installation) == nil ? .differs(upstream: upstream) : .updateAvailable(upstream: upstream)
            case .upToDate: return .upToDate
            case .cannotCheck(let reason): return .cantCheck(reason)
            case nil: return .notChecked
            }
        case .skillsLock(_, _, _, let baseline, let local):
            if case .hashFailed = local { return .checkFailed }
            var state = reading(for: installation)?.state
            // Updated since the source was asked, for instance in Terminal: the installed
            // baseline is now what the source had, so there is nothing new to fetch.
            if case .updateAvailable(let upstream) = state, upstream == baseline { state = .upToDate }
            if isHeld(installation) {
                if case .updateAvailable = state { return .heldBack(sourceMoved: true) }
                return .heldBack(sourceMoved: false)
            }
            if case .modified = local { return .changedHere }
            switch state {
            case .updateAvailable(let upstream): return .updateAvailable(upstream: upstream)
            case .upToDate: return .upToDate
            case .cannotCheck(let reason): return .cantCheck(reason)
            case nil: return .notChecked
            }
        }
    }

    /// The reader's own skills, which are the ones a status says something about.
    private var own: [Installation] {
        (inventory?.installations ?? []).filter { if case .managed = $0.provenance { false } else { true } }
    }

    /// Skills whose source has other content: a known update, or a linked skill that differs.
    var updates: [Installation] {
        own.filter {
            switch status(for: $0) {
            case .updateAvailable, .differs: true
            default: false
            }
        }
    }

    /// The reasons behind the skills that cannot be checked right now.
    var cantCheckReasons: Set<UpstreamState.Reason> {
        Set(own.compactMap { if case .cantCheck(let reason) = status(for: $0) { reason } else { nil } })
    }
    /// The skills that can't be checked for a reason other than a lost source, and the reasons.
    var unansweredCantCheck: (count: Int, reasons: Set<UpstreamState.Reason>) {
        let reasons = own.compactMap { installation -> UpstreamState.Reason? in
            guard lostSource(of: installation) == nil, case .cantCheck(let reason) = status(for: installation) else { return nil }
            return reason
        }
        return (reasons.count, Set(reasons))
    }
    var updateCount: Int { updates.count }
    var upToDateCount: Int { own.filter { status(for: $0) == .upToDate }.count }
    /// Skills linked to an installer run with the reader's own key, which Skillori never asks.
    var byInstallerCount: Int { own.filter { if case .byInstaller = status(for: $0) { true } else { false } }.count }
    var heldCount: Int { own.filter { if case .heldBack = status(for: $0) { true } else { false } }.count }
    var cantCheckCount: Int { own.filter { if case .cantCheck = status(for: $0) { true } else { false } }.count }
    var unverifiedCount: Int { own.filter { status(for: $0).isUnverified }.count }

    /// Stay on the installed version of this skill until released.
    func hold(_ installation: Installation) {
        guard let key = sourceKey(for: installation) else { return }
        held[key] = Date()
        save()
    }

    func release(_ installation: Installation) {
        guard let key = sourceKey(for: installation) else { return }
        held[key] = nil
        save()
    }

    /// The skills the installer can update: it recorded them, or can take them over from the
    /// source they were linked to, and that source has moved on.
    var updatable: [Installation] {
        own.filter { if case .updateAvailable = status(for: $0) { true } else { false } }
    }

    /// How the skills of yours that share this skill's name compare with it.
    enum Copies: Equatable {
        /// Several folders, the same files in each.
        case identical(count: Int)
        /// Several folders with this name, and the files differ between them.
        case different(count: Int)
    }

    func copies(of installation: Installation) -> Copies? {
        let name = installation.displayName.lowercased()
        let same = own.filter { $0.displayName.lowercased() == name }
        guard same.count > 1 else { return nil }
        let hashes = Set(same.map { $0.contentHash ?? $0.id })
        return hashes.count == 1 ? .identical(count: same.count) : .different(count: same.count)
    }

    /// Names of yours that exist as more than one version.
    var differingCopyNames: [String] {
        let groups = Dictionary(grouping: own) { $0.displayName.lowercased() }
        return groups.compactMap { _, group in
            group.count > 1 && Set(group.map { $0.contentHash ?? $0.id }).count > 1 ? group[0].displayName : nil
        }.sorted()
    }

    /// The Claude Code plugins on this Mac, one record per plugin, whatever number of skills it brings.
    var pluginRecords: [PluginRecord] {
        var seen = Set<String>()
        return (inventory?.installations ?? []).compactMap(\.plugin).filter { seen.insert($0.id).inserted }
    }

    /// Claude Code plugins whose marketplace has a newer version: the plugin updates Skillori can
    /// run. Cursor and Codex bring new versions themselves, so theirs are not on this list.
    var pluginUpdates: [PluginRecord] {
        guard checksEnabled else { return [] }
        return pluginRecords.filter {
            guard $0.app == "Claude Code" else { return false }
            if case .updateAvailable(let upstream) = pluginReadings[$0.id]?.state { return Self.isAhead(upstream, of: $0) }
            return false
        }
    }

    /// Whether a newer version a source named is still ahead of the plugin on this Mac. An answer
    /// saved before the app updated the plugin can name the very version now installed.
    static func isAhead(_ upstream: String, of plugin: PluginRecord) -> Bool {
        guard let installed = plugin.version, !installed.isEmpty, Assist.isVersion(upstream) else { return true }
        return PluginChecker.isNewer(upstream, than: installed)
    }

    /// For a Codex plugin Codex left behind: the id it has the plugin installed under now, when
    /// it has added it again from its new catalog. The old folder is then only left over.
    func codexReplacement(of plugin: PluginRecord) -> String? {
        guard plugin.app == "Codex", let codex = codexPlugins else { return nil }
        let key = Self.codexKey(plugin)
        return codex.isLeftBehind(key) ? codex.installedReplacement(for: key) : nil
    }

    /// `name@marketplace`, the way Codex names a plugin.
    nonisolated static func codexKey(_ plugin: PluginRecord) -> String {
        plugin.id.hasPrefix("codex:") ? String(plugin.id.dropFirst("codex:".count)) : plugin.id
    }

    /// Codex plugins that Codex no longer reads and that its catalog offers anew, with the id to
    /// add. Codex moved its curated plugins to a new catalog and left the old folders behind.
    var codexMoved: [(plugin: PluginRecord, replacement: String)] {
        guard checksEnabled, let codex = codexPlugins else { return [] }
        return pluginRecords.filter { $0.app == "Codex" }.compactMap { plugin in
            let key = Self.codexKey(plugin)
            guard codex.isLeftBehind(key), let replacement = codex.replacement(for: key) else { return nil }
            return (plugin, replacement)
        }
        .sorted { $0.plugin.title.localizedCaseInsensitiveCompare($1.plugin.title) == .orderedAscending }
    }

    /// Adds these plugins again from Codex's current catalog, then reads this Mac and asks Codex
    /// again, so the lines show what is true afterwards.
    func addCodexPlugins(_ ids: [String]) async {
        guard !ids.isEmpty, !codexRunner.isRunning else { return }
        _ = await codexRunner.run(ids, codexHome: environment["CODEX_HOME"])
        await rescan()
        await askCodex(force: true)
    }

    /// Asks Codex which of its plugins it reads. Only while checks are on, since Codex may ask its
    /// own catalog online to answer; and only when the Codex plugins on this Mac are not the ones
    /// it was last asked about, that answer has grown old, or the reader asked for a check.
    func askCodex(force: Bool = false) async {
        guard checksEnabled, force || !waitsForFirstStart, !usesSampleReadings, !isAskingCodex else { return }
        let keys = Set(pluginRecords.filter { $0.app == "Codex" }.map(Self.codexKey))
        guard !keys.isEmpty else { return }
        let codexFolder = environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? Self.home.appendingPathComponent(".codex")
        let (folders, remote) = await Task.detached(priority: .utility) {
            (AppPlugins.cacheFolders(in: codexFolder), AppPlugins.remoteFolders(in: codexFolder))
        }.value
        if !force, let known = codexPlugins, known.asked == keys, known.folders == folders, known.remoteFolders == remote,
           Date().timeIntervalSince(known.askedAt) < Self.checkInterval { return }
        isAskingCodex = true
        defer { isAskingCodex = false }
        let home = environment["CODEX_HOME"]
        guard let listed = await CodexApp.pluginList(names: [], available: false, codexHome: home) else { return }
        var installed = listed.installed
        var offered: [String: [String]] = [:]
        let behind = keys.subtracting(installed)
        if !behind.isEmpty {
            // Only then is the catalog read: to find where Codex offers those plugins now.
            let names = Set(behind.compactMap { $0.split(separator: "@").first.map(String.init) })
            if let full = await CodexApp.pluginList(names: names, available: true, codexHome: home) {
                installed = full.installed
                offered = full.offered
            }
        }
        codexPlugins = CodexPluginList(installed: installed, offered: offered, asked: keys, askedAt: Date(), folders: folders,
                                       remoteFolders: remote)
        save()
    }

    /// Runs the installer's update for these skills, then reads this Mac and asks the sources
    /// again, so every status shows what is true afterwards. Skills the installer recorded get
    /// its `update`; skills the reader linked get `add` from their source, which also puts them
    /// on the installer's record.
    func update(_ installations: [Installation]) async {
        let names = installations.map(\.directoryName)
        guard !names.isEmpty, !updater.isRunning else { return }
        receipt = nil
        let source = installations.first.flatMap { upstreamSource(for: $0)?.name } ?? "its source"
        let plan = updatePlan(for: installations, withKeys: true)
        if plan.isEmpty {
            // Only a recorded skill with a name that can't be passed on gets here; the run says so.
            // One linked in place of a gone source is not updated from the old one.
            let recorded = installations.filter { if case .skillsLock = $0.provenance { link(for: $0) == nil } else { false } }
            guard !recorded.isEmpty else { return }
            _ = await updater.run(names: recorded.map(\.directoryName))
        } else {
            let finished = await updater.run(names: names, commands: plan.map(\.arguments))
            finishAdoptions(plan.prefix(finished).flatMap(\.adoptions))
        }
        Notifier.shared.runEnded(names: names, phase: updater.phase)
        if case .succeeded = updater.phase { showReceipt(Receipt(installations: installations, source: source, at: Date())) }
        // Read this Mac, then ask only the sources of the skills that ran. Asking every source
        // after every update used up GitHub's hourly allowance, and the reader then saw a
        // line about all their skills when they had updated one.
        await rescan()
        let keys = Set((inventory?.installations ?? []).filter { names.contains($0.directoryName) }.compactMap { sourceKey(for: $0) })
        await checkSources(force: true, only: keys.isEmpty ? nil : keys)
    }

    /// The installer commands an update of these skills runs, as they would be typed.
    func updateCommandText(for installations: [Installation]) -> String {
        let plan = updatePlan(for: installations)
        guard !plan.isEmpty else {
            let recorded = installations.filter { if case .skillsLock = $0.provenance { link(for: $0) == nil } else { false } }
            return recorded.isEmpty ? "" : UpdateRunner.commandText(for: recorded.map(\.directoryName))
        }
        return plan.map { $0.shown ?? (["npx"] + $0.arguments.dropFirst()).joined(separator: " ") }.joined(separator: " && ")
    }

    // MARK: Handing linked skills to the installer

    /// One linked skill the installer is to take over, with the links it replaces.
    struct LinkedAdoption {
        let plan: Adoption
        let linkKeys: [String]
        /// The source the installer recorded for each copy, when it had one: the skill moves from it.
        var recorded: [String: String] = [:]
    }

    private struct UpdateStep {
        let arguments: [String]
        let adoptions: [LinkedAdoption]
        /// How the step is shown, when its arguments hold the reader's key.
        var shown: String? = nil
    }

    /// `update` for the skills the installer recorded, then one `add` per source for linked ones.
    /// `withKeys` reads the reader's kept keys into installer steps, for running; without, the
    /// steps only say which installer runs, for showing.
    private func updatePlan(for installations: [Installation], withKeys: Bool = false) -> [UpdateStep] {
        var steps: [UpdateStep] = []
        // Installers run with the reader's key: run once each, as the reader would in Terminal.
        var packages: [PackageInstaller] = []
        for installation in installations {
            if let installer = packageInstaller(of: installation), keyedPackages.contains(installer.package),
               !packages.contains(where: { $0.package == installer.package }) { packages.append(installer) }
        }
        for installer in packages {
            let arguments = withKeys ? InstallerKeys.arguments(for: installer.package) : []
            guard let arguments else { continue }
            steps.append(UpdateStep(arguments: ["--yes", installer.package + "@latest"] + arguments, adoptions: [],
                                    shown: installer.command + " + your key"))
        }
        // A recorded skill linked to a new home is moved there with `add`, not updated from the old one.
        let recorded = installations.filter { if case .skillsLock = $0.provenance { link(for: $0) == nil } else { false } }.map(\.directoryName)
        if !recorded.isEmpty, recorded.allSatisfy(UpdateRunner.isSafeName) {
            steps.append(UpdateStep(arguments: UpdateRunner.arguments(for: recorded), adoptions: []))
        }
        var adoptions: [LinkedAdoption] = []
        for installation in installations where link(for: installation) != nil {
            guard let adoption = adoption(for: installation),
                  !adoptions.contains(where: { $0.plan == adoption.plan }) else { continue }
            adoptions.append(adoption)
        }
        for command in Adoption.commands(for: adoptions.map(\.plan), package: UpdateRunner.installerPackage) {
            steps.append(UpdateStep(arguments: command.arguments,
                                    adoptions: adoptions.filter { adoption in command.adoptions.contains(adoption.plan) }))
        }
        return steps
    }

    /// How the installer can take over this linked skill, with every copy of it linked to the
    /// same source. Nil when it can't: the source isn't a GitHub repository, a copy sits in a
    /// folder the installer doesn't write, or another skill has the name it would use.
    func adoption(for installation: Installation) -> LinkedAdoption? {
        guard let link = link(for: installation), case .github(let source) = link.source else { return nil }
        let name = installation.displayName.lowercased()
        let copies = own.filter { $0.displayName.lowercased() == name && self.link(for: $0)?.source == link.source }
        return adoption(of: copies, from: source, subpath: link.subpath)
    }

    /// The same for copies that are about to be linked to this source. With the skill's folder in
    /// the source, the installer is told the folder rather than the name.
    func adoption(of copies: [Installation], from source: UpstreamSource, subpath: String? = nil) -> LinkedAdoption? {
        guard let first = copies.first else { return nil }
        let ids = Set(copies.map(\.id))
        // A link into a copy's own folder follows what the installer puts there, as long as that
        // folder keeps its name; Antigravity's ~/.gemini/config/skills holds such links.
        let name = Adoption.installName(first.displayName)
        func follows(_ binding: AgentBinding, of copy: Installation) -> Bool {
            binding.viaSymlink && binding.discoveredPath != copy.canonicalPath
                && URL(fileURLWithPath: copy.canonicalPath).lastPathComponent == name
        }
        let folders = copies.flatMap { copy in copy.bindings.filter { !follows($0, of: copy) }.map(\.discoveredPath) + [copy.canonicalPath] }
        let links = copies.flatMap { copy in copy.bindings.filter { follows($0, of: copy) }.map(\.discoveredPath) }
        let taken = Set((inventory?.installations ?? []).filter { !ids.contains($0.id) }
            .flatMap { $0.bindings.map(\.discoveredPath) + [$0.canonicalPath] })
        guard let plan = Adoption.plan(skill: first.displayName, source: source, folders: folders,
                                       home: Self.home.path, taken: taken, subpath: subpath, links: links) else { return nil }
        var recorded: [String: String] = [:]
        for copy in copies { if let source = recordedSource(of: copy) { recorded[Self.linkKey(for: copy)] = source } }
        return LinkedAdoption(plan: plan, linkKeys: copies.map(Self.linkKey), recorded: recorded)
    }

    /// After the installer has put these skills in place: folders under an older name go to the
    /// Trash, and the links give way to the installer's record.
    private func finishAdoptions(_ adoptions: [LinkedAdoption]) {
        let files = FileManager.default
        for adoption in adoptions {
            for folder in adoption.plan.leftovers {
                let url = URL(fileURLWithPath: folder)
                // Only when the installer's folder is there beside it, and only what is still there.
                let placed = url.deletingLastPathComponent().appendingPathComponent(adoption.plan.folderName).path
                guard files.fileExists(atPath: placed), (try? files.attributesOfItem(atPath: folder)) != nil else { continue }
                try? files.trashItem(at: url, resultingItemURL: nil)
            }
            for key in adoption.linkKeys {
                links[key] = nil
                readings[key] = nil
                held[key] = nil
                if let from = adoption.recorded[key], from != adoption.plan.source.name {
                    moves[key] = Move(from: from, to: adoption.plan.source.name, at: Date())
                }
            }
        }
        if !adoptions.isEmpty { save() }
    }

    /// Runs Claude Code's update for these plugins, then reads this Mac and asks again.
    func updatePlugins(_ plugins: [PluginRecord]) async {
        guard !plugins.isEmpty, !pluginUpdater.isRunning else { return }
        _ = await pluginUpdater.run(plugins)
        let names = plugins.map(\.title)
        switch pluginUpdater.phase {
        case .succeeded: Notifier.shared.runEnded(names: names, phase: .succeeded)
        case .needsReview: Notifier.shared.runEnded(names: names, phase: .failed("Claude Code wants your approval. Run the update in Terminal."))
        case .failed(let why): Notifier.shared.runEnded(names: names, phase: .failed(why))
        default: break
        }
        await refresh()
        pluginUpdater.markSettled()
    }

    /// Hands the current updates to the notifier, which tells only about the new ones.
    private func notifyUpdates() {
        let found = updates.compactMap { installation -> Notifier.Found? in
            guard let key = sourceKey(for: installation) else { return nil }
            let upstream: String
            switch status(for: installation) {
            case .updateAvailable(let hash), .differs(let hash): upstream = hash
            default: return nil
            }
            return Notifier.Found(key: key, source: upstreamSource(for: installation)?.name ?? "A source", upstream: upstream)
        } + pluginUpdates.compactMap { plugin -> Notifier.Found? in
            guard case .updateAvailable(let upstream) = pluginReadings[plugin.id]?.state else { return nil }
            return Notifier.Found(key: "plugin:" + plugin.id, source: "\(plugin.app) plugin \(plugin.name)", upstream: upstream)
        }
        Notifier.shared.updatesFound(found)
    }

    /// Reads this Mac again and then asks the sources, whatever the age of the last answer.
    func refresh() async {
        await rescan()
        await checkSources(force: true)
    }

    /// Asks each source once whether its skills have changed. Does nothing while checks are off,
    /// and nothing on its own (without `force`) while a new installation's first start is up.
    /// With `only`, asks about just those skills (by `sourceKey`) and leaves the rest, the
    /// plugins and the time of the last full answer as they are.
    func checkSources(force: Bool = false, only: Set<String>? = nil) async {
        guard checksEnabled, force || !waitsForFirstStart else { return }
        if isChecking {
            // A check that started before this was asked for may use an old reading of this
            // Mac, such as the one before an update ran. Ask again as soon as it is done.
            if force { checkAgain = true }
            return
        }
        guard let inventory else { return }
        if !force, let lastCheck, Date().timeIntervalSince(lastCheck) < Self.checkInterval { return }
        #if DEBUG
        if usesSampleReadings, links.isEmpty,
           let unknown = inventory.installations.filter({ $0.provenance == .unknown }).min(by: { $0.displayName < $1.displayName }) {
            // One linked skill in the pictures, so that state can be looked at too.
            links[Self.linkKey(for: unknown)] = SourceLink(owner: "example", repository: "skills", ref: nil,
                                                           subpath: "skills/" + unknown.directoryName, linkedAt: Date(),
                                                           localHash: "83b528722eed2d5663a7fa843be58369c7a0235c")
        }
        #endif
        let tracked = inventory.installations.filter { installation in
            guard let key = sourceKey(for: installation) else { return false }
            return only?.contains(key) ?? true
        }
        let plugins = only == nil ? pluginRecords : []
        guard !tracked.isEmpty || !plugins.isEmpty else { return }
        isChecking = true
        checkingCount = tracked.count
        defer { isChecking = false }
        #if DEBUG
        checksStarted += 1
        #endif

        #if DEBUG
        if usesSampleReadings {
            applySampleReadings(to: tracked)
            return
        }
        #endif

        // A linked skill has no installer baseline; its own files, hashed now, stand in for one.
        let linked = tracked.filter { link(for: $0) != nil }
        let localHashes = await Task.detached(priority: .utility) {
            Dictionary(uniqueKeysWithValues: linked.map { installation in
                (installation.id, try? GitTreeHash.hashDirectory(at: URL(fileURLWithPath: installation.canonicalPath)).treeID)
            })
        }.value
        let questions = tracked.compactMap { installation -> UpstreamQuestion? in
            guard let key = sourceKey(for: installation) else { return nil }
            // Behind the reader's own key: never asked, so never counted as unanswered.
            if case .package? = link(for: installation)?.source { return nil }
            if link(for: installation) != nil {
                let local = localHashes[installation.id] ?? nil
                links[key]?.localHash = local
                return UpstreamQuestion(key: key, source: upstreamSource(for: installation),
                                        subpath: sourceSubpath(for: installation), baseline: local)
            }
            guard case .skillsLock(_, _, let subpath, let baseline, _) = installation.provenance else { return nil }
            return UpstreamQuestion(key: key, source: upstreamSource(for: installation), subpath: subpath, baseline: baseline)
        }
        let answers = await UpstreamChecker.answers(to: questions)
        var baselines = pluginBaselines
        let pluginAnswers = plugins.isEmpty ? [:] : await PluginChecker().check(plugins, baselines: &baselines)
        pluginBaselines = baselines
        let now = Date()
        var problem: UpstreamState.Reason?
        var answered = false
        var nextPlugins = pluginReadings
        for (id, state) in pluginAnswers {
            switch state {
            case .cannotCheck(.cancelled):
                continue
            case .cannotCheck(let reason) where reason == .offline || reason == .rateLimited:
                problem = reason
                if nextPlugins[id] == nil { nextPlugins[id] = UpstreamReading(state: state, checkedAt: now) }
            default:
                answered = true
                nextPlugins[id] = UpstreamReading(state: state, checkedAt: now)
            }
        }
        let installedPlugins = Set(plugins.map(\.id))
        pluginReadings = nextPlugins.filter { installedPlugins.contains($0.key) }
        // Start from what is known now, not from before the network wait: a link made while
        // the sources were being asked keeps the answer its search gave.
        var next = readings
        var failed: Set<String> = []
        var heard: Set<String> = []
        for question in questions {
            guard let answer = answers[question.key] else { continue }
            let state = answer.state
            switch state {
            case .cannotCheck(.cancelled):
                // Withdrawn, not answered: leave the last reading as it is.
                continue
            case .cannotCheck(let reason) where reason == .offline || reason == .rateLimited || reason == .failed:
                // No answer this time. Keep the last real one, with its own date, so it reads as old.
                problem = reason
                failed.insert(question.key)
                if next[question.key] == nil { next[question.key] = UpstreamReading(state: state, checkedAt: now) }
            default:
                answered = true
                heard.insert(question.key)
                next[question.key] = UpstreamReading(state: state, checkedAt: now, notice: answer.notice)
            }
        }
        // Installers run with the reader's key answer for their skills by being run.
        for (key, reading) in await installerReadings(for: tracked) {
            if case .cannotCheck = reading.state { failed.insert(key) } else { answered = true; heard.insert(key) }
            next[key] = reading
        }
        // Forget answers only for skills that this scan read and that no longer have a source.
        // A hold is the reader's own choice and is only dropped when they release it or unlink.
        // A folder that could not be read this time is not proof that its skills are gone.
        let current = self.inventory ?? inventory
        let scanWasComplete = !current.roots.contains { if case .unreadable = $0.state { true } else { false } }
        let asked = Set(questions.map(\.key))
        let present = Set(current.installations.compactMap { sourceKey(for: $0) })
        next = next.filter { asked.contains($0.key) || present.contains($0.key) || !scanWasComplete }
        readings = next
        if only == nil {
            unanswered = failed
            lastProblem = problem
            if answered { lastCheck = now }
        } else {
            // A few skills asked again say nothing about the rest, which keep what they had.
            unanswered = unanswered.subtracting(heard).union(failed)
            lastProblem = problem ?? lastProblem
        }
        lastAttempt = now
        await planAskingAgain()
        save()
        if only == nil { await askCodex(force: force) }
        notifyUpdates()
        if checkAgain {
            // This check started before something changed, such as an update. Ask again now;
            // the flag is cleared first, or the second check would only queue a third.
            checkAgain = false
            isChecking = false
            await checkSources(force: true)
        }
    }

    /// The receipt shows the installer's last lines for a second, then only the sentence, and
    /// folds away after three more. By then this Mac has been read again, so the line it stood
    /// in for is gone and doesn't come back for a moment.
    private func showReceipt(_ new: Receipt) {
        receipt = new
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, self.receipt?.at == new.at else { return }
            self.receipt?.showsOutput = false
            try? await Task.sleep(for: .seconds(2.2))
            while self.isScanning { try? await Task.sleep(for: .milliseconds(100)) }
            guard self.receipt?.at == new.at else { return }
            self.receipt = nil
        }
    }

    /// When a source asked Skillori to wait and said until when, the sources are asked again
    /// right after that, as the library says they will be.
    private func planAskingAgain() async {
        askAgain?.cancel()
        askAgain = nil
        waitUntil = nil
        guard lastProblem == .rateLimited, let date = await GitHubBudget.shared.retryAt, date > Date() else { return }
        waitUntil = date
        askAgain = Task { [weak self] in
            try? await Task.sleep(for: .seconds(date.timeIntervalSinceNow + 5))
            guard !Task.isCancelled, let self else { return }
            // Cleared first: the check below plans the next one, which must not cancel this.
            self.askAgain = nil
            await self.checkSources(force: true)
        }
    }

    /// The source asked Skillori to wait and said until when, so there is nothing to try before then.
    var isWaiting: Bool { lastProblem == .rateLimited && (waitUntil.map { $0 > Date() } ?? false) }

    /// How many of the reader's tracked skills show an answer older than the latest attempt.
    var unansweredCount: Int { own.filter { sourceKey(for: $0).map(unanswered.contains) ?? false }.count }

    /// Who did not answer, when that is one service: GitHub, or the site of an install script.
    var unansweredBy: String? {
        let names = Set(own.filter { sourceKey(for: $0).map(unanswered.contains) ?? false }.compactMap { installation -> String? in
            switch upstreamSource(for: installation) {
            case .github?: "GitHub"
            case .installer(let script)?: script.name
            case .package?, nil: nil
            }
        })
        // Plugins are asked at GitHub too, and have no keys of their own here.
        if names.isEmpty { return pluginRecords.isEmpty ? nil : "GitHub" }
        return names.count == 1 ? names.first : nil
    }

    /// The reader's latest update went well, and the check that followed it is the one that got
    /// no answer. Said once, for half an hour, so the line about the sources isn't read as the
    /// update having failed.
    var updateWentThrough: Bool {
        guard case .succeeded = updater.phase, let ended = updater.endedAt, let lastAttempt else { return false }
        return lastAttempt >= ended && Date().timeIntervalSince(ended) < 30 * 60
    }

    // MARK: What an update changes

    /// The files an update would add, change or remove, told by comparing file ids in the
    /// source with the files on this Mac. Asks the source again, which GitHub answers from
    /// its "unchanged" reply when nothing moved since the last check.
    func fileChanges(for installation: Installation) async -> Result<[FileChange], UpstreamState.Reason> {
        guard let source = upstreamSource(for: installation) else { return .failure(.unsupported) }
        let subpath = sourceSubpath(for: installation)
        let path = installation.canonicalPath
        async let local = Task.detached(priority: .utility) {
            try? GitTreeHash.hashDirectory(at: URL(fileURLWithPath: path)).entries
        }.value
        switch await Self.tree(of: source) {
        case .failure(let reason): return .failure(reason)
        case .success(let tree):
            guard let entries = await local else { return .failure(.failed) }
            if tree.truncated, tree.hash(of: subpath) == nil { return .failure(.failed) }
            return .success(FileChanges.compare(local: entries, upstream: tree, subpath: subpath))
        }
    }

    /// One question to one source, whichever kind it is.
    private static func tree(of source: SkillSource) async -> Result<SourceTree, UpstreamState.Reason> {
        switch source {
        case .github(let repository): await GitHubTrees.app.tree(of: repository)
        case .installer(let script): await InstallerScripts().tree(of: script)
        case .package: .failure(.unsupported)
        }
    }

    // MARK: Linking a source

    /// What a look at a source found for one skill.
    struct LinkSearch {
        let source: SkillSource
        let localHash: String?
        let candidates: [SourceCandidate]
        /// The folder the pasted address pointed at, if it pointed at one.
        let suggested: String?
    }

    enum LinkProblem: Error {
        case unreadable
        case source(UpstreamState.Reason, installer: Bool)
        case noSkills(installer: Bool)

        var sentence: String {
            switch self {
            case .unreadable:
                "That is neither a GitHub repository nor a script address. Use owner/repository, an address on github.com, or the https address of an install script."
            case .source(.failed, installer: true):
                "Skillori could not read which files that script writes. It only reads scripts that carry their files, and never runs them."
            case .source(let reason, _): reason.sentence
            case .noSkills(installer: false): "That repository has no folder with a SKILL.md."
            case .noSkills(installer: true): "That script writes no SKILL.md that Skillori can read."
            }
        }
    }

    /// Asks the source the reader named for its skill folders and ranks them against this skill.
    /// This is a direct action by the reader, so it runs whether or not regular checks are on.
    func searchSource(_ text: String, for installation: Installation) async -> Result<LinkSearch, LinkProblem> {
        guard let (source, subpath) = SkillSource.parse(text) else { return .failure(.unreadable) }
        let isInstaller = if case .installer = source { true } else { false }
        let path = installation.canonicalPath
        async let local = Task.detached(priority: .utility) {
            try? GitTreeHash.hashDirectory(at: URL(fileURLWithPath: path)).treeID
        }.value
        switch await Self.tree(of: source) {
        case .failure(let reason): return .failure(.source(reason, installer: isInstaller))
        case .success(let tree):
            let localHash = await local
            let names = [installation.directoryName, installation.displayName]
            let candidates = SourceMatcher.candidates(localHash: localHash, names: names, in: tree)
            guard !candidates.isEmpty else { return .failure(.noSkills(installer: isInstaller)) }
            return .success(LinkSearch(source: source, localHash: localHash, candidates: candidates, suggested: subpath))
        }
    }

    /// Remembers that this skill comes from `candidate` in the searched source.
    func link(_ installation: Installation, to candidate: SourceCandidate, in search: LinkSearch) {
        guard canLink(installation) else { return }
        let key = Self.linkKey(for: installation)
        let now = Date()
        links[key] = switch search.source {
        case .github(let source):
            SourceLink(owner: source.owner, repository: source.repository, ref: source.ref,
                       subpath: candidate.subpath, linkedAt: now, localHash: search.localHash)
        case .installer(let script):
            SourceLink(owner: "", repository: "", ref: nil, installer: script.url.absoluteString,
                       subpath: candidate.subpath, linkedAt: now, localHash: search.localHash)
        case .package(let installer):
            SourceLink(owner: "", repository: "", ref: nil, package: installer.package, site: installer.site?.absoluteString,
                       subpath: "", linkedAt: now, localHash: search.localHash)
        }
        // The search already has the answer a check would give.
        let state: UpstreamState = candidate.hash == search.localHash ? .upToDate : .updateAvailable(upstreamHash: candidate.hash)
        readings[key] = UpstreamReading(state: state, checkedAt: now)
        pastSources[key] = nil
        save()
        noteLinked([installation], to: search.source.name)
    }

    /// Reads a page the reader named for the ways it gives to install skills. Only the request
    /// for the page is sent; nothing on it is run.
    func readPage(_ url: URL) async -> Result<[PageLead], UpstreamState.Reason> {
        await PageReader().leads(at: url)
    }

    /// Asks npm whether the installer the reader pasted exists, and which site it names. Only
    /// the package's name is sent; the key on the pasted line was dropped when it was read.
    func lookUpPackage(_ installer: PackageInstaller) async -> Result<PackageInfo, UpstreamState.Reason> {
        await NpmRegistry().info(for: installer.package)
    }

    /// Remembers that this skill comes from an installer run with the reader's own key. There is
    /// nothing to compare, so it is never asked; its page says how to get a new version.
    func link(_ installation: Installation, toPackage info: PackageInfo) {
        guard canLink(installation) else { return }
        let key = Self.linkKey(for: installation)
        let path = installation.canonicalPath
        links[key] = SourceLink(owner: "", repository: "", ref: nil, package: info.package, site: info.site?.absoluteString,
                                subpath: "", linkedAt: Date(), localHash: nil)
        readings[key] = nil
        held[key] = nil
        pastSources[key] = nil
        save()
        if InstallerKeys.has(info.package) { keyedPackages.insert(info.package) }
        noteLinked([installation], to: info.package)
        // The files' hash, for the type plate: read off the main thread, kept once it is there.
        Task { [weak self] in
            let hash = await Task.detached(priority: .utility) {
                try? GitTreeHash.hashDirectory(at: URL(fileURLWithPath: path)).treeID
            }.value
            guard let self, self.links[key]?.package == info.package else { return }
            self.links[key]?.localHash = hash
            self.save()
        }
    }

    // MARK: Finding sources

    /// Skills of yours with no source, or whose recorded source is gone, as one group per name and
    /// content: identical copies in several folders are found and linked together.
    struct UnlinkedGroup: Identifiable {
        let name: String
        let installations: [Installation]
        let local: LocalSkill?
        var id: String { name + "#" + (local?.treeID ?? installations.map(\.canonicalPath).joined()) }
    }

    /// `includingLinked` also takes skills that are linked already, for pictures of the sheet.
    /// `only` keeps the search to these skills (by id) and their copies.
    func unlinkedGroups(includingLinked: Bool = false, only: Set<String>? = nil) async -> [UnlinkedGroup] {
        let names = only.map { ids in Set(own.filter { ids.contains($0.id) }.map { $0.displayName.lowercased() }) }
        let unlinked = own.filter { installation in
            if let names, !names.contains(installation.displayName.lowercased()) { return false }
            return includingLinked ? installation.provenance == .unknown : canLink(installation)
        }
        let read = await Task.detached(priority: .utility) {
            unlinked.map { installation in
                (installation, try? LocalSkill(name: installation.directoryName, folder: URL(fileURLWithPath: installation.canonicalPath)))
            }
        }.value
        var groups: [String: UnlinkedGroup] = [:]
        var order: [String] = []
        for (installation, local) in read {
            let key = installation.directoryName.lowercased() + "#" + (local?.treeID ?? installation.canonicalPath)
            if let group = groups[key] {
                groups[key] = UnlinkedGroup(name: group.name, installations: group.installations + [installation], local: group.local)
            } else {
                groups[key] = UnlinkedGroup(name: installation.directoryName, installations: [installation], local: local)
                order.append(key)
            }
        }
        return order.compactMap { groups[$0] }.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// The repositories other skills on this Mac come from: likely places for the rest.
    var yourSources: [UpstreamSource] {
        var seen: [UpstreamSource] = []
        for installation in own {
            if case .github(let source)? = upstreamSource(for: installation) {
                let bare = UpstreamSource(owner: source.owner, repository: source.repository)
                if !seen.contains(bare) { seen.append(bare) }
            }
        }
        return seen
    }

    /// Looks for one group's source. A direct action by the reader, so it runs whether or not
    /// regular checks are on. Sends skill and repository names, nothing else.
    /// Pass the same finder for every group of one search: it asks each repository once.
    func proposals(for group: UnlinkedGroup, using finder: SourceFinder, pages: [PageLead] = []) async -> SourceFinder.Search {
        guard let local = group.local else { return SourceFinder.Search(proposals: [], problem: nil) }
        // A repository the reader unlinked it from is looked in again, with their other sources.
        var yours = yourSources
        for installation in group.installations {
            if let name = pastSource(of: installation)?.repository, let source = UpstreamSource(source: name, sourceURL: nil),
               !yours.contains(where: { $0.name == source.name }) {
                yours.insert(source, at: 0)
            }
        }
        var repositories: [UpstreamSource] = []
        for lead in pages {
            if case .github(let source) = lead.source, !repositories.contains(where: { $0.name == source.name }) {
                repositories.append(UpstreamSource(owner: source.owner, repository: source.repository))
            }
        }
        let via = knownSites(of: group).first.map { "\($0)’s page" } ?? "its site"
        return await finder.search(for: local, yourSources: yours, pageSources: repositories, pageVia: via)
    }

    /// What the pages of the sites a group came from name for installing: the page the old
    /// source pointed to, and the site's front page. Only the requests for the pages are sent.
    func pageLeads(for group: UnlinkedGroup) async -> [PageLead] {
        var pages: [URL] = []
        for installation in group.installations {
            if let url = pastSource(of: installation)?.notice?.url, !pages.contains(url) { pages.append(url) }
        }
        for site in knownSites(of: group) {
            if let url = URL(string: "https://\(site)/"), !pages.contains(where: { $0.host.map(NpmRegistry.siteHost) == site && $0.path == "/" }) {
                pages.append(url)
            }
        }
        var leads: [PageLead] = []
        for page in pages.prefix(3) {
            if case .success(let found) = await PageReader().leads(at: page) {
                leads += found.filter { lead in !leads.contains { $0.id == lead.id } }
            }
        }
        return leads
    }

    /// The sites a group's skills are known to have come from: a source they were linked to
    /// before, and the page that source pointed to.
    func knownSites(of group: UnlinkedGroup) -> [String] {
        var sites: [String] = []
        for installation in group.installations {
            guard let past = pastSource(of: installation) else { continue }
            let hosts = [URL(string: past.name.contains("://") ? past.name : "https://" + past.name)?.host, past.notice?.url?.host]
            for host in hosts.compactMap({ $0 }) where host.contains(".") {
                let site = NpmRegistry.siteHost(host)
                if !sites.contains(site) { sites.append(site) }
            }
        }
        return sites
    }

    /// Installers on npm from the sites a group came from, and those the sites' pages name.
    /// Sends only the sites' and packages' names.
    func installers(for group: UnlinkedGroup, pages: [PageLead] = []) async -> Result<[PackageInfo], UpstreamState.Reason> {
        var found: [PackageInfo] = []
        // The installer it was linked to before, then those the site's pages name.
        let unlinked = group.installations.compactMap { pastSource(of: $0)?.package }.map { PackageInstaller(package: $0) }
        let named = pages.compactMap { lead -> PackageInstaller? in if case .package(let installer) = lead.source { installer } else { nil } }
        for installer in unlinked + named where !found.contains(where: { $0.package == installer.package }) {
            if case .success(let info) = await NpmRegistry().info(for: installer.package) { found.append(info) }
        }
        for site in knownSites(of: group) {
            switch await NpmRegistry().installers(from: site) {
            case .success(let list): found += list.filter { info in !found.contains { $0.package == info.package } }
            case .failure(let reason): return .failure(reason)
            }
        }
        return .success(found)
    }

    /// Links every copy in the group to an installer run with the reader's own key.
    func link(_ group: UnlinkedGroup, toPackage info: PackageInfo) {
        for installation in group.installations { link(installation, toPackage: info) }
    }

    /// Links every copy in the group to the proposed folder, with how it was found.
    func link(_ group: UnlinkedGroup, to proposal: SourceProposal) {
        let now = Date()
        let state: UpstreamState = if proposal.folderGone {
            .cannotCheck(.folderGone)
        } else if let upstream = proposal.upstreamHash, upstream != group.local?.treeID {
            .updateAvailable(upstreamHash: upstream)
        } else {
            .upToDate
        }
        for installation in group.installations where canLink(installation) {
            let key = Self.linkKey(for: installation)
            links[key] = SourceLink(owner: proposal.source.owner, repository: proposal.source.repository, ref: nil,
                                    subpath: proposal.subpath, linkedAt: now, localHash: group.local?.treeID,
                                    note: proposal.sentence)
            readings[key] = UpstreamReading(state: state, checkedAt: now)
            pastSources[key] = nil
        }
        save()
        noteLinked(group.installations.filter { links[Self.linkKey(for: $0)] != nil }, to: proposal.source.name)
    }

    func unlink(_ installation: Installation) {
        let key = Self.linkKey(for: installation)
        if linkReceipt?.keys.contains(key) == true { linkReceipt = nil }
        // Remember the source, and what it said if it stopped answering, so the trail stays.
        if let link = links[key] {
            let lost = if case .cannotCheck(let reason)? = readings[key]?.state { Self.lostReasons.contains(reason) } else { false }
            let repository: String? = if case .github(let source) = link.source { source.name } else { nil }
            pastSources[key] = PastSource(name: link.source.name, until: Date(), notice: lost ? readings[key]?.notice : nil,
                                          byYou: lost ? nil : true, package: link.package, repository: repository)
        }
        let package = links[key]?.package
        links[key] = nil
        readings[key] = nil
        held[key] = nil
        // A key no linked skill uses any more is not kept.
        if let package, !links.values.contains(where: { $0.package == package }) {
            InstallerKeys.remove(for: package)
            keyedPackages.remove(package)
            installerProblems[package] = nil
        }
        save()
    }

    // MARK: Saved state

    private struct Saved: Codable {
        var readings: [String: UpstreamReading]
        var held: [String: Date]
        var lastCheck: Date?
        var links: [String: SourceLink]?
        var pluginReadings: [String: UpstreamReading]?
        var pluginBaselines: [String: String]?
        var codexPlugins: CodexPluginList?
        var keptLocal: [String: Date]?
        var moves: [String: Move]?
        var pastSources: [String: PastSource]?
    }

    private static var savedURL: URL? {
        #if DEBUG
        if let test = testHome { return test.appendingPathComponent("skillori-sources.json") }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Skillori/sources.json")
    }

    /// The home folder skills are read from and installed under.
    static var home: URL {
        #if DEBUG
        if let test = testHome { return test }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
    }

    #if DEBUG
    /// Debug builds only: `SKILLORI_TEST_HOME` makes another folder the home for a test run, with
    /// its own saved answers and links. Start the app with `HOME` set to the same folder, so the
    /// installer it runs writes there too.
    static var testHome: URL? {
        ProcessInfo.processInfo.environment["SKILLORI_TEST_HOME"].map { URL(fileURLWithPath: $0) }
    }
    #endif

    private func loadSaved() {
        guard let url = Self.savedURL, let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        readings = saved.readings
        held = saved.held
        lastCheck = saved.lastCheck
        links = saved.links ?? [:]
        pluginReadings = saved.pluginReadings ?? [:]
        pluginBaselines = saved.pluginBaselines ?? [:]
        codexPlugins = saved.codexPlugins
        keptLocal = saved.keptLocal ?? [:]
        moves = saved.moves ?? [:]
        pastSources = saved.pastSources ?? [:]
        // Which installers have a key kept; the keys themselves stay in the Keychain until a check runs.
        keyedPackages = Set(links.values.compactMap(\.package).filter(InstallerKeys.has))
    }

    private func save() {
        guard !usesSampleReadings, let url = Self.savedURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let saved = Saved(readings: readings, held: held, lastCheck: lastCheck, links: links,
                          pluginReadings: pluginReadings, pluginBaselines: pluginBaselines, codexPlugins: codexPlugins,
                          keptLocal: keptLocal, moves: moves, pastSources: pastSources)
        try? JSONEncoder().encode(saved).write(to: url, options: .atomic)
    }

    #if DEBUG
    /// Pictures of a skill whose recorded source is gone, once linked to its new home: the new
    /// home has a newer version. Nil `subpath` takes the link away again.
    func setSampleLink(_ installation: Installation, owner: String, repository: String, subpath: String?) {
        let key = Self.linkKey(for: installation)
        guard let subpath else { links[key] = nil; readings[key] = nil; return }
        links[key] = SourceLink(owner: owner, repository: repository, ref: nil, subpath: subpath, linkedAt: Date(),
                                localHash: installation.contentHash)
        readings[key] = UpstreamReading(state: .updateAvailable(upstreamHash: "2f14c7791e51007344512e80d8634ad913660af2"), checkedAt: Date())
    }

    /// Forgets the old source a picture of an unlinked skill left behind.
    func forgetSamplePastSource(_ installation: Installation) {
        pastSources[Self.linkKey(for: installation)] = nil
    }

    /// Pictures of a skill linked to an install script that has moved and says where to.
    func setSampleMovedInstaller(_ installation: Installation, notice: SourceNotice?) {
        let key = Self.linkKey(for: installation)
        guard let notice else { links[key] = nil; readings[key] = nil; return }
        links[key] = SourceLink(owner: "", repository: "", ref: nil, installer: "https://www.example.com/api/install-skills",
                                subpath: installation.directoryName, linkedAt: Date(), localHash: installation.contentHash)
        readings[key] = UpstreamReading(state: .cannotCheck(.notFound), checkedAt: Date(), notice: notice)
    }

    /// Pictures of the library when sources gave no answer: every tracked skill unanswered, and
    /// a wait until `until` when the reason is that a source asked Skillori to wait.
    func setSampleTrouble(_ reason: UpstreamState.Reason?, until: Date? = nil) {
        lastProblem = reason
        unanswered = reason == nil ? [] : Set(own.compactMap { sourceKey(for: $0) })
        waitUntil = until
        lastAttempt = Date()
        if lastCheck == nil { lastCheck = Date().addingTimeInterval(-20 * 60) }
    }

    /// Fixed answers for pictures and tests, so they need no network: one update, one held back
    /// with the source moved on, one source that cannot be found, the rest up to date.
    private func applySampleReadings(to tracked: [Installation]) {
        let now = Date()
        let sorted = tracked.sorted { $0.displayName < $1.displayName }
        var next: [String: UpstreamReading] = [:]
        for (index, installation) in sorted.enumerated() {
            guard let key = sourceKey(for: installation) else { continue }
            let state: UpstreamState = if link(for: installation) != nil {
                .updateAvailable(upstreamHash: "9c2e77aa00000000000000000000000000000000")
            } else {
                switch index {
                case 0, 3: .updateAvailable(upstreamHash: "4f1a02d9c0ffee00000000000000000000000000")
                case 5: .cannotCheck(.notFound)
                default: .upToDate
                }
            }
            next[key] = UpstreamReading(state: state, checkedAt: now)
            if index == 3 { held[key] = now }
        }
        readings = next
        lastCheck = now
    }

    /// Plays an update for pictures and probes, without the installer: its lines arrive one by
    /// one, and then it fails, or it goes well and the skills read as current, as after a real one.
    func playSampleUpdate(_ installations: [Installation], fails: Bool = false) async {
        let names = installations.map(\.directoryName)
        let source = installations.first.flatMap { upstreamSource(for: $0)?.name } ?? "its source"
        receipt = nil
        var output = ""
        updater.setSample(names: names, phase: .running, output: output)
        let lines = fails ? ["◇  Checking 1 skill for updates", "◇  Fetching \(source)", "✗  Could not reach github.com"]
            : ["◇  Checking 1 skill for updates", "◇  Fetching \(source)", "◇  Updating \(names.joined(separator: ", "))", "✓  Updated 1 skill"]
        for line in lines {
            try? await Task.sleep(for: .milliseconds(800))
            output += line + "\n"
            updater.setSample(names: names, phase: .running, output: output)
        }
        try? await Task.sleep(for: .milliseconds(260))
        guard !fails else {
            updater.setSample(names: names, phase: .failed("The installer ended with code 1."), output: output)
            return
        }
        updater.setSample(names: names, phase: .succeeded, output: output)
        for installation in installations {
            if let key = sourceKey(for: installation) { readings[key] = UpstreamReading(state: .upToDate, checkedAt: Date()) }
        }
        showReceipt(Receipt(installations: installations, source: source, at: Date()))
    }
    #endif

    /// Skills with a source that can be asked: recorded by the installer, or linked by the reader.
    var trackedCount: Int { own.filter { sourceKey(for: $0) != nil }.count }
    /// Skills with no source, counting identical-name copies once.
    var unknownNameCount: Int {
        Set(unsourced.map { $0.directoryName.lowercased() }).count
    }

    /// Your skills with no source: not recorded by an installer and not linked by you.
    var unsourced: [Installation] { own.filter { $0.provenance == .unknown && link(for: $0) == nil } }
    var unknownCount: Int { unsourced.count }
    var managedCount: Int { count { if case .managed = $0 { true } else { false } } }
    var localChangeCount: Int {
        count { if case .skillsLock(_, _, _, _, .modified) = $0 { true } else { false } }
    }

    private func count(where predicate: (Provenance) -> Bool) -> Int {
        inventory?.installations.filter { predicate($0.provenance) }.count ?? 0
    }

    /// The skill with this id, or the one in the same folder when the installer has replaced it since.
    func installation(id: Installation.ID) -> Installation? {
        let installations = inventory?.installations ?? []
        if let found = installations.first(where: { $0.id == id }) { return found }
        guard let now = replacedIDs[id] else { return nil }
        return installations.first { $0.id == now }
    }

    private func noteReplacedFolders(from old: Inventory?, to new: Inventory) {
        guard let old else { return }
        let ids = Set(new.installations.map(\.id))
        let byPath = Dictionary(new.installations.map { ($0.canonicalPath, $0.id) }, uniquingKeysWith: { first, _ in first })
        for installation in old.installations where !ids.contains(installation.id) {
            guard let now = byPath[installation.canonicalPath] else { continue }
            replacedIDs[installation.id] = now
            // Pages opened on an even older id follow along.
            for (from, to) in replacedIDs where to == installation.id { replacedIDs[from] = now }
        }
    }

    func rescan() async {
        if isScanning {
            // Something changed after the running read began (a folder added, an update run).
            // Read again once it is done, and let this call return only after that.
            scanAgain = true
            while isScanning { try? await Task.sleep(for: .milliseconds(50)) }
            return
        }
        isScanning = true
        let started = Date()
        let engine = DiscoveryEngine(home: Self.home,
                                     projects: projects,
                                     environment: environment,
                                     system: URL(fileURLWithPath: "/"))
        // Disk work stays off the main actor.
        var result = await Task.detached(priority: .utility) { engine.scan() }.value
        while scanAgain {
            scanAgain = false
            let again = DiscoveryEngine(home: engine.home, projects: projects, environment: environment, system: engine.system)
            result = await Task.detached(priority: .utility) { again.scan() }.value
        }
        // Which agents are here decides which agent marks a skill shows.
        AgentPresence.refresh(among: Array(Set(result.installations.flatMap(\.agents))))
        noteReplacedFolders(from: inventory, to: result)
        inventory = result
        watchFolders(of: result)
        Task {
            await checkSources()
            // A plugin added or removed in Codex since it was last asked: ask again.
            await askCodex()
        }
        // A read takes about 150 ms. Hold the "reading" state a little longer so it can be seen.
        let shown = Date().timeIntervalSince(started)
        if shown < Self.minimumScanDisplay {
            try? await Task.sleep(for: .seconds(Self.minimumScanDisplay - shown))
        }
        isScanning = false
        // Asked for during that pause, for instance by an update that just ended: the read above
        // may be from before it. Read again; a caller waiting for it sees the read start at once.
        if scanAgain {
            scanAgain = false
            await rescan()
        }
    }

    /// Asks the reader's login shell for the variables that move an agent's settings folder,
    /// and reads again if any of them says something this app did not already know.
    private func followLoginShell() async {
        let own = ProcessInfo.processInfo.environment
        guard own["SKILLORI_SNAPSHOT_DIR"] == nil, own["SKILLORI_SELFTEST"] == nil else { return }
        let names = AdapterRules.relocations.map(\.variable) + ["XDG_STATE_HOME"]
        let found = await Self.loginShellValues(of: names)
        let changed = found.filter { environment[$0.key] != $0.value }
        guard !changed.isEmpty else { return }
        environment.merge(changed) { _, new in new }
        while isScanning { try? await Task.sleep(for: .milliseconds(100)) }
        await rescan()
    }

    /// The values the login shell gives the named variables. Unset and empty ones are left out.
    nonisolated static func loginShellValues(of names: [String]) async -> [String: String] {
        let mark = "__SKILLORI__"
        let output = OutputBox()
        // The names are passed as arguments; the script itself is fixed.
        _ = await Shell.run(script: "for name in \"$@\"; do print -r -- \"\(mark)${name}=${(P)name}\"; done",
                            arguments: names, interactive: true, timeout: 8) { output.append($0) }
        var values: [String: String] = [:]
        for line in output.text.split(whereSeparator: \.isNewline) where line.hasPrefix(mark) {
            let pair = line.dropFirst(mark.count).split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2, names.contains(String(pair[0])), !pair[1].isEmpty else { continue }
            values[String(pair[0])] = String(pair[1])
        }
        return values
    }

    func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add Project"
        panel.message = "Choose project folders. Skillori reads their skill folders only."
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        let new = panel.urls.filter { url in !projects.contains { $0.standardizedFileURL == url.standardizedFileURL } }
        guard !new.isEmpty else { return }
        projects.append(contentsOf: new)
        persistProjects()
        Task { await rescan() }
    }

    func removeProject(_ url: URL) {
        projects.removeAll { $0 == url }
        persistProjects()
        Task { await rescan() }
    }

    private func persistProjects() {
        UserDefaults.standard.set(projects.map(\.path), forKey: Self.projectsKey)
    }
}

/// Collects what a shell prints, from whichever thread it arrives on.
private final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var collected = ""

    func append(_ text: String) {
        lock.lock()
        collected += text
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return collected
    }
}
