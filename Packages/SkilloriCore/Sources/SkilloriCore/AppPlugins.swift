import Foundation

/// Reads what Cursor and Codex leave in their plugin folders: each installed plugin sits in
/// `plugins/cache/<marketplace>/<plugin>/<revision>/`, with a manifest that names its version
/// and often its repository. Cursor keeps many plugins as git checkouts, whose remote is
/// better evidence of the source than what a manifest says about itself.
///
/// Nothing is run: `.git/config` and the manifest are read as text. Codex's `config.toml` is
/// read only for its `[plugins."…"]` tables and their `enabled` line.
public enum AppPlugins {
    public struct App: Sendable {
        let name: String
        let idPrefix: String
        /// The app's folder under home, such as `.cursor`.
        let folder: String
        let manifestPath: String
    }

    public static let cursor = App(name: "Cursor", idPrefix: "cursor:", folder: ".cursor", manifestPath: ".cursor-plugin/plugin.json")
    public static let codex = App(name: "Codex", idPrefix: "codex:", folder: ".codex", manifestPath: ".codex-plugin/plugin.json")

    /// The plugins of one app, found under `appFolder` (`~/.cursor`, or where `CODEX_HOME` points).
    public static func records(of app: App, in appFolder: URL) -> [PluginRecord] {
        let cache = appFolder.appendingPathComponent("plugins/cache")
        let config = app.name == "Codex" ? codexConfig(appFolder.appendingPathComponent("config.toml")) : CodexConfig()
        var records: [PluginRecord] = []
        for marketplace in folders(in: cache) {
            for plugin in folders(in: marketplace) {
                for revision in folders(in: plugin) {
                    // An old version waiting to be removed is not installed.
                    if FileManager.default.fileExists(atPath: revision.appendingPathComponent(".orphaned_at").path) { continue }
                    let manifest = json(revision.appendingPathComponent(app.manifestPath))
                    let name = (manifest?["name"] as? String) ?? plugin.lastPathComponent
                    let checkout = gitRemote(of: revision)
                    let claimed = (manifest?["repository"] as? String).flatMap(repositoryName)
                    let key = "\(plugin.lastPathComponent)@\(marketplace.lastPathComponent)"
                    var record = PluginRecord(
                        id: app.idPrefix + key, name: name, marketplace: marketplace.lastPathComponent,
                        version: manifest?["version"] as? String,
                        commit: checkout?.commit ?? (isCommit(revision.lastPathComponent) ? revision.lastPathComponent : nil),
                        installPath: revision.path, scope: "user", projectPath: nil,
                        marketplaceRepository: nil, origin: nil)
                    record.app = app.name
                    // A marketplace kept as a local folder ships with the app and is updated with
                    // it; there is no source to ask, whatever its manifests claim.
                    let local = config.localMarketplaces.contains(marketplace.lastPathComponent)
                    record.repository = local ? nil : checkout?.repository ?? claimed
                    record.manifestPath = app.manifestPath
                    record.isCheckout = checkout != nil
                    record.enabled = config.enabled[key]
                    records.append(record)
                }
            }
        }
        return records
    }

    /// `owner/repo` from a GitHub address, with or without `.git`. Nil for anything else.
    static func repositoryName(_ text: String) -> String? {
        UpstreamSource(source: "", sourceURL: text).map(\.name)
    }

    static func isCommit(_ text: String) -> Bool {
        text.count == 40 && text.allSatisfy(\.isHexDigit)
    }

    /// The `origin` remote and checked-out commit of a git checkout, read from its files.
    static func gitRemote(of folder: URL) -> (repository: String, commit: String?)? {
        let git = folder.appendingPathComponent(".git")
        guard let config = try? String(contentsOf: git.appendingPathComponent("config"), encoding: .utf8) else { return nil }
        var inOrigin = false
        var url: String?
        for raw in config.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { inOrigin = line == "[remote \"origin\"]"; continue }
            if inOrigin, line.hasPrefix("url") , let equals = line.firstIndex(of: "=") {
                url = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            }
        }
        guard let url, let repository = repositoryName(url) else { return nil }
        let head = (try? String(contentsOf: git.appendingPathComponent("HEAD"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (repository, head.flatMap { isCommit($0) ? $0 : nil })
    }

    struct CodexConfig {
        /// `enabled` per `name@marketplace`.
        var enabled: [String: Bool] = [:]
        /// Marketplaces whose `source_type` is `local`.
        var localMarketplaces: Set<String> = []
    }

    /// What Codex's `config.toml` says about plugins. Only the `enabled` line of
    /// `[plugins."…"]` tables and the `source_type` line of `[marketplaces.…]` tables are
    /// looked at; every other setting in the file is skipped unread.
    static func codexConfig(_ url: URL) -> CodexConfig {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]), (values.fileSize ?? 0) < 1_000_000,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return CodexConfig() }
        var config = CodexConfig()
        var plugin: String?
        var marketplace: String?
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                plugin = tableName(line, prefix: "plugins.")
                marketplace = tableName(line, prefix: "marketplaces.")
                continue
            }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            if let plugin, parts[0] == "enabled" {
                if parts[1] == "true" { config.enabled[plugin] = true } else if parts[1] == "false" { config.enabled[plugin] = false }
            }
            if let marketplace, parts[0] == "source_type", parts[1] == "\"local\"" {
                config.localMarketplaces.insert(marketplace)
            }
        }
        return config
    }

    /// `x` from `[prefix"x"]` or `[prefixx]`.
    private static func tableName(_ line: String, prefix: String) -> String? {
        guard line.hasPrefix("[" + prefix), line.hasSuffix("]") else { return nil }
        var name = String(line.dropFirst(prefix.count + 1).dropLast())
        if name.hasPrefix("\""), name.hasSuffix("\""), name.count >= 2 { name = String(name.dropFirst().dropLast()) }
        return name.isEmpty ? nil : name
    }

    private static func folders(in url: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted().map { url.appendingPathComponent($0) }.filter {
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    private static func json(_ url: URL) -> [String: Any]? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]), (values.fileSize ?? 0) < 1_000_000,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
