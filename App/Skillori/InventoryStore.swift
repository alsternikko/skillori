import AppKit
import Foundation
import Observation
import SkilloriCore

/// Holds the latest inventory and the user's chosen project folders.
///
/// Spike scope: project paths live in UserDefaults and nothing else is persisted. The app is
/// not sandboxed (docs/beslut/0002), so a plain path is enough to read a chosen folder.
@MainActor
@Observable
final class InventoryStore {
    private(set) var inventory: Inventory?
    private(set) var isScanning = false
    private(set) var projects: [URL]

    private static let projectsKey = "projectPaths"
    private static let minimumScanDisplay: TimeInterval = 0.45

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.projectsKey) ?? []
        projects = paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
        Task { await rescan() }
    }

    var needsAttention: Bool { localChangeCount > 0 }

    var trackedCount: Int { count { if case .skillsLock = $0 { true } else { false } } }
    var unknownCount: Int { count { $0 == .unknown } }
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
