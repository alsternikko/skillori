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
    private(set) var isChecking = false
    /// When sources last gave a real answer.
    private(set) var lastCheck: Date?
    /// Why the latest attempt got no answer, if it did not.
    private(set) var lastProblem: UpstreamState.Reason?
    /// Asking sources is the reader's choice and is off until they turn it on.
    var checksEnabled: Bool {
        didSet {
            guard checksEnabled != oldValue else { return }
            UserDefaults.standard.set(checksEnabled, forKey: Self.checksKey)
            if checksEnabled { Task { await checkSources(force: true) } }
        }
    }

    private static let projectsKey = "projectPaths"
    private static let checksKey = "asksSources"
    private static let minimumScanDisplay: TimeInterval = 0.45
    /// How long an answer stands before the sources are asked again.
    static let checkInterval: TimeInterval = 6 * 60 * 60
    private let usesSampleReadings: Bool

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
            // While the app runs, ask again when the last answer has grown old.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30 * 60))
                await checkSources()
            }
        }
    }

    var needsAttention: Bool { localChangeCount > 0 }

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
        return UpstreamSource(source: source, sourceURL: url, ref: installation.sourceRef)
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
        case .managed: return .managed
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
        case .skillsLock(_, _, _, _, let local):
            if case .hashFailed = local { return .checkFailed }
            let state = reading(for: installation)?.state
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

    /// Reads this Mac again and then asks the sources, whatever the age of the last answer.
    func refresh() async {
        await rescan()
        await checkSources(force: true)
    }

    /// Asks each source once whether its skills have changed. Does nothing while checks are off.
    func checkSources(force: Bool = false) async {
        guard checksEnabled, !isChecking, let inventory else { return }
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
        guard !tracked.isEmpty else { return }
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
        let now = Date()
        var problem: UpstreamState.Reason?
        var answered = false
        var next: [String: UpstreamReading] = [:]
        for question in questions {
            guard let state = answers[question.key] else { continue }
            switch state {
            case .cannotCheck(let reason) where reason == .offline || reason == .rateLimited || reason == .failed:
                // No answer this time. Keep the last real one, with its own date, so it reads as old.
                problem = reason
                next[question.key] = readings[question.key] ?? UpstreamReading(state: state, checkedAt: now)
            default:
                answered = true
                next[question.key] = UpstreamReading(state: state, checkedAt: now)
            }
        }
        readings = next
        held = held.filter { next[$0.key] != nil }
        lastProblem = problem
        if answered { lastCheck = now }
        save()
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
        switch await GitHubTrees().tree(of: source) {
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
    }

    private func save() {
        guard !usesSampleReadings, let url = Self.savedURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let saved = Saved(readings: readings, held: held, lastCheck: lastCheck, links: links)
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
        guard !isScanning else { return }
        isScanning = true
        let started = Date()
        let engine = DiscoveryEngine(home: FileManager.default.homeDirectoryForCurrentUser,
                                     projects: projects,
                                     environment: ProcessInfo.processInfo.environment)
        // Disk work stays off the main actor.
        let result = await Task.detached(priority: .utility) { engine.scan() }.value
        inventory = result
        Task { await checkSources() }
        // A read takes about 150 ms. Hold the "reading" state a little longer so it can be seen.
        let shown = Date().timeIntervalSince(started)
        if shown < Self.minimumScanDisplay {
            try? await Task.sleep(for: .seconds(Self.minimumScanDisplay - shown))
        }
        isScanning = false
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
