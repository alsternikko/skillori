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
    private(set) var isScanning = false
    private(set) var projects: [URL]

    /// What each tracked skill's source last said, by `sourceKey`.
    private(set) var readings: [String: UpstreamReading] = [:]
    /// Skills the reader keeps on their installed version, and since when.
    private(set) var held: [String: Date] = [:]
    /// Sources the reader has pointed out for skills that came with no record, by `sourceKey`.
    private(set) var links: [String: SourceLink] = [:]
    /// What each Claude Code plugin's marketplace last said, by plugin id (`name@marketplace`).
    private(set) var pluginReadings: [String: UpstreamReading] = [:]
    /// Folder hashes at installed plugin commits. They never change, so each is asked for once.
    private var pluginBaselines: [String: String] = [:]
    private(set) var isChecking = false
    /// Set when a forced check was asked for while another was running.
    private var checkAgain = false
    /// Set when a rescan was asked for while another was running.
    private var scanAgain = false
    /// When sources last gave a real answer.
    private(set) var lastCheck: Date?
    /// Why the latest attempt got no answer, if it did not.
    private(set) var lastProblem: UpstreamState.Reason?
    /// Runs the installer's update command when the reader asks for it.
    let updater = UpdateRunner()
    /// Asking sources is the reader's choice and is off until they turn it on.
    var checksEnabled: Bool {
        didSet {
            guard checksEnabled != oldValue else { return }
            UserDefaults.standard.set(checksEnabled, forKey: Self.checksKey)
            if checksEnabled {
                Notifier.shared.requestPermission()
                Task { await checkSources(force: true) }
            }
        }
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
        checksEnabled = usesSampleReadings || UserDefaults.standard.bool(forKey: Self.checksKey)
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
        switch installation.provenance {
        case .skillsLock(let source, _, let subpath, _, _): return "\(source)#\(subpath ?? "")"
        case .unknown:
            let key = Self.linkKey(for: installation)
            return links[key] == nil ? nil : key
        case .managed: return nil
        }
    }

    private static func linkKey(for installation: Installation) -> String { "link:" + installation.canonicalPath }

    /// The source the reader linked this skill to, if they did.
    func link(for installation: Installation) -> SourceLink? {
        guard installation.provenance == .unknown else { return nil }
        return links[Self.linkKey(for: installation)]
    }

    func upstreamSource(for installation: Installation) -> UpstreamSource? {
        if let link = link(for: installation) { return link.source }
        guard case .skillsLock(let source, let url, _, _, _) = installation.provenance else { return nil }
        return UpstreamSource(source: source, sourceURL: url, ref: installation.sourceRef, sourceType: installation.sourceType)
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

    func isHeld(_ installation: Installation) -> Bool {
        sourceKey(for: installation).map { held[$0] != nil } ?? false
    }

    func status(for installation: Installation) -> SkillStatus {
        switch installation.provenance {
        case .managed(let owner):
            if checksEnabled, let plugin = installation.plugin,
               case .updateAvailable(let upstream) = pluginReadings[plugin.id]?.state {
                return .ownerUpdate(owner: owner, upstream: upstream)
            }
            return .managed
        case .unknown:
            guard link(for: installation) != nil else { return .noSource }
            // Linked by the reader: there is no installer baseline, so "differs" is all that can be said.
            let state = reading(for: installation)?.state
            if isHeld(installation) {
                if case .updateAvailable = state { return .heldBack(sourceMoved: true) }
                return .heldBack(sourceMoved: false)
            }
            switch state {
            case .updateAvailable(let upstream): return .differs(upstream: upstream)
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
    var updateCount: Int { updates.count }
    var upToDateCount: Int { own.filter { status(for: $0) == .upToDate }.count }
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

    /// The skills the installer can update: it recorded them, and their source has moved on.
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

    /// Plugins whose marketplace has a newer version than the one installed.
    var pluginUpdates: [PluginRecord] {
        guard checksEnabled else { return [] }
        return pluginRecords.filter {
            if case .updateAvailable = pluginReadings[$0.id]?.state { true } else { false }
        }
    }

    /// Runs the installer's update for these skills, then reads this Mac and asks the sources
    /// again, so every status shows what is true afterwards.
    func update(_ installations: [Installation]) async {
        let names = installations.map(\.directoryName)
        guard !names.isEmpty, !updater.isRunning else { return }
        _ = await updater.run(names: names)
        Notifier.shared.runEnded(names: names, phase: updater.phase)
        await refresh()
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
            return Notifier.Found(key: "plugin:" + plugin.id, source: "Claude Code plugin \(plugin.name)", upstream: upstream)
        }
        Notifier.shared.updatesFound(found)
    }

    /// Reads this Mac again and then asks the sources, whatever the age of the last answer.
    func refresh() async {
        await rescan()
        await checkSources(force: true)
    }

    /// Asks each source once whether its skills have changed. Does nothing while checks are off.
    func checkSources(force: Bool = false) async {
        guard checksEnabled else { return }
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
        let tracked = inventory.installations.filter { sourceKey(for: $0) != nil }
        let plugins = pluginRecords
        guard !tracked.isEmpty || !plugins.isEmpty else { return }
        isChecking = true
        defer { isChecking = false }

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
            if link(for: installation) != nil {
                let local = localHashes[installation.id] ?? nil
                links[key]?.localHash = local
                return UpstreamQuestion(key: key, source: upstreamSource(for: installation),
                                        subpath: sourceSubpath(for: installation), baseline: local)
            }
            guard case .skillsLock(_, _, let subpath, let baseline, _) = installation.provenance else { return nil }
            return UpstreamQuestion(key: key, source: upstreamSource(for: installation), subpath: subpath, baseline: baseline)
        }
        let answers = await UpstreamChecker.check(questions)
        var baselines = pluginBaselines
        let pluginAnswers = await PluginChecker().check(plugins, baselines: &baselines)
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
        for question in questions {
            guard let state = answers[question.key] else { continue }
            switch state {
            case .cannotCheck(.cancelled):
                // Withdrawn, not answered: leave the last reading as it is.
                continue
            case .cannotCheck(let reason) where reason == .offline || reason == .rateLimited || reason == .failed:
                // No answer this time. Keep the last real one, with its own date, so it reads as old.
                problem = reason
                if next[question.key] == nil { next[question.key] = UpstreamReading(state: state, checkedAt: now) }
            default:
                answered = true
                next[question.key] = UpstreamReading(state: state, checkedAt: now)
            }
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
        lastProblem = problem
        if answered { lastCheck = now }
        save()
        notifyUpdates()
        if checkAgain {
            checkAgain = false
            await checkSources(force: true)
        }
    }

    // MARK: Linking a source

    /// What a look at a source found for one skill.
    struct LinkSearch {
        let source: UpstreamSource
        let localHash: String?
        let candidates: [SourceCandidate]
        /// The folder the pasted address pointed at, if it pointed at one.
        let suggested: String?
    }

    enum LinkProblem: Error {
        case unreadable
        case source(UpstreamState.Reason)
        case noSkills

        var sentence: String {
            switch self {
            case .unreadable: "That does not look like a GitHub repository. Use owner/repository or an address on github.com."
            case .source(let reason): reason.sentence
            case .noSkills: "That repository has no folder with a SKILL.md."
            }
        }
    }

    /// Asks the source the reader named for its skill folders and ranks them against this skill.
    /// This is a direct action by the reader, so it runs whether or not regular checks are on.
    func searchSource(_ text: String, for installation: Installation) async -> Result<LinkSearch, LinkProblem> {
        guard let (source, subpath) = UpstreamSource.parse(text) else { return .failure(.unreadable) }
        let path = installation.canonicalPath
        async let local = Task.detached(priority: .utility) {
            try? GitTreeHash.hashDirectory(at: URL(fileURLWithPath: path)).treeID
        }.value
        switch await GitHubTrees(budget: .shared).tree(of: source) {
        case .failure(let reason): return .failure(.source(reason))
        case .success(let tree):
            let localHash = await local
            let names = [installation.directoryName, installation.displayName]
            let candidates = SourceMatcher.candidates(localHash: localHash, names: names, in: tree)
            guard !candidates.isEmpty else { return .failure(.noSkills) }
            return .success(LinkSearch(source: source, localHash: localHash, candidates: candidates, suggested: subpath))
        }
    }

    /// Remembers that this skill comes from `candidate` in the searched source.
    func link(_ installation: Installation, to candidate: SourceCandidate, in search: LinkSearch) {
        guard installation.provenance == .unknown else { return }
        let key = Self.linkKey(for: installation)
        let now = Date()
        links[key] = SourceLink(owner: search.source.owner, repository: search.source.repository, ref: search.source.ref,
                                subpath: candidate.subpath, linkedAt: now, localHash: search.localHash)
        // The search already has the answer a check would give.
        let state: UpstreamState = candidate.hash == search.localHash ? .upToDate : .updateAvailable(upstreamHash: candidate.hash)
        readings[key] = UpstreamReading(state: state, checkedAt: now)
        save()
    }

    func unlink(_ installation: Installation) {
        let key = Self.linkKey(for: installation)
        links[key] = nil
        readings[key] = nil
        held[key] = nil
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
    }

    private static var savedURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Skillori/sources.json")
    }

    private func loadSaved() {
        guard let url = Self.savedURL, let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        readings = saved.readings
        held = saved.held
        lastCheck = saved.lastCheck
        links = saved.links ?? [:]
        pluginReadings = saved.pluginReadings ?? [:]
        pluginBaselines = saved.pluginBaselines ?? [:]
    }

    private func save() {
        guard !usesSampleReadings, let url = Self.savedURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let saved = Saved(readings: readings, held: held, lastCheck: lastCheck, links: links,
                          pluginReadings: pluginReadings, pluginBaselines: pluginBaselines)
        try? JSONEncoder().encode(saved).write(to: url, options: .atomic)
    }

    #if DEBUG
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
    #endif

    /// Skills with a source that can be asked: recorded by the installer, or linked by the reader.
    var trackedCount: Int { own.filter { sourceKey(for: $0) != nil }.count }
    var unknownCount: Int { own.filter { $0.provenance == .unknown && link(for: $0) == nil }.count }
    var managedCount: Int { count { if case .managed = $0 { true } else { false } } }
    var localChangeCount: Int {
        count { if case .skillsLock(_, _, _, _, .modified) = $0 { true } else { false } }
    }

    private func count(where predicate: (Provenance) -> Bool) -> Int {
        inventory?.installations.filter { predicate($0.provenance) }.count ?? 0
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
        let engine = DiscoveryEngine(home: FileManager.default.homeDirectoryForCurrentUser,
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
        inventory = result
        watchFolders(of: result)
        Task { await checkSources() }
        // A read takes about 150 ms. Hold the "reading" state a little longer so it can be seen.
        let shown = Date().timeIntervalSince(started)
        if shown < Self.minimumScanDisplay {
            try? await Task.sleep(for: .seconds(Self.minimumScanDisplay - shown))
        }
        isScanning = false
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
