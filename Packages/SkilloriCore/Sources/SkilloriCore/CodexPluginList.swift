import Foundation

/// What Codex itself says about its plugins, from `codex plugin list --json`.
///
/// The folders in Codex's plugin cache are not proof that Codex reads a plugin: when Codex
/// moved its curated plugins to a new catalog, the folders from the old one stayed behind,
/// and Codex no longer counts them as installed or loads their skills. Only Codex can say
/// which folders it reads, so it is asked.
public struct CodexPluginList: Sendable, Codable, Equatable {
    /// `name@marketplace` of every plugin Codex counts as installed.
    public var installed: Set<String>
    /// The ids Codex lists each plugin name under, installed or not, for the names asked about.
    public var offered: [String: [String]]
    /// The Codex plugins (`name@marketplace`) on this Mac when Codex was asked. A plugin that
    /// arrived after that is not judged by this answer.
    public var asked: Set<String>
    public var askedAt: Date
    /// Every plugin folder in Codex's cache when Codex was asked, skills or not. A plugin from
    /// the remote catalog may bring no skill files, so only this shows that one was added.
    public var folders: Set<String>?

    public init(installed: Set<String>, offered: [String: [String]], asked: Set<String>, askedAt: Date,
                folders: Set<String>? = nil) {
        self.installed = installed
        self.offered = offered
        self.asked = asked
        self.askedAt = askedAt
        self.folders = folders
    }

    /// The id Codex has this left-behind plugin installed under now, if it has added it again.
    public func installedReplacement(for key: String) -> String? {
        guard let name = key.split(separator: "@", maxSplits: 1).first.map(String.init) else { return nil }
        return (offered[name] ?? []).first { $0 != key && installed.contains($0) }
    }

    /// Codex was asked about this plugin and does not count it as installed.
    public func isLeftBehind(_ key: String) -> Bool {
        asked.contains(key) && !installed.contains(key)
    }

    /// The id Codex offers a left-behind plugin under now, when Codex has not installed that
    /// one either. Nil when Codex offers no such plugin, already has it, or offers several and
    /// none is plainly the same plugin's new home: that is not guessed.
    public func replacement(for key: String) -> String? {
        let parts = key.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let (name, marketplace) = (parts[0], parts[1])
        let candidates = (offered[name] ?? []).filter { $0 != key }
        if candidates.contains(where: installed.contains) { return nil }
        if candidates.count == 1 { return candidates[0] }
        // `openai-curated` → `openai-curated-remote`: the catalog that took over from the old one.
        let successors = candidates.filter { $0.split(separator: "@").last.map { $0.hasPrefix(marketplace) } ?? false }
        return successors.count == 1 ? successors[0] : nil
    }

    /// The installed ids and, for `names`, every id Codex lists, read from what
    /// `codex plugin list --json [--available]` printed. Nil when the output holds no such list.
    public static func parse(_ output: String, names: Set<String>) -> (installed: Set<String>, offered: [String: [String]])? {
        // A login shell may print something of its own before the command does.
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"), start < end,
              let object = (try? JSONSerialization.jsonObject(with: Data(output[start...end].utf8))) as? [String: Any],
              let installedList = object["installed"] as? [[String: Any]] else { return nil }
        let available = object["available"] as? [[String: Any]] ?? []
        var installed = Set<String>()
        var offered: [String: [String]] = [:]
        for (entry, isInstalled) in installedList.map({ ($0, true) }) + available.map({ ($0, false) }) {
            guard let id = entry["pluginId"] as? String else { continue }
            if isInstalled || entry["installed"] as? Bool == true { installed.insert(id) }
            let name = (entry["name"] as? String) ?? String(id.split(separator: "@").first ?? "")
            if names.contains(name), !(offered[name]?.contains(id) ?? false) { offered[name, default: []].append(id) }
        }
        return (installed, offered.mapValues { $0.sorted() })
    }
}
