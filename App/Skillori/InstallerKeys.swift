import Foundation
import Security
import SkilloriCore

/// The reader's own arguments for an installer run with their key (`--token=…`), kept in the
/// login Keychain, one item per package, only when the reader asks for it. They are handed to
/// the installer as arguments and never shown, logged or sent anywhere by Skillori itself.
enum InstallerKeys {
    private static let service = "app.skillori.installer-arguments"

    private static func query(_ package: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: package]
    }

    /// Whether arguments are kept for this package. Reads no secret, so it never asks the reader.
    static func has(_ package: String) -> Bool {
        var attributes = query(package)
        attributes[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func arguments(for package: String) -> [String]? {
        var request = query(package)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
              let arguments = try? JSONDecoder().decode([String].self, from: data), !arguments.isEmpty else { return nil }
        return arguments
    }

    @discardableResult
    static func save(_ arguments: [String], for package: String) -> Bool {
        guard !arguments.isEmpty, let data = try? JSONEncoder().encode(arguments) else { return false }
        SecItemDelete(query(package) as CFDictionary)
        var item = query(package)
        item[kSecValueData as String] = data
        item[kSecAttrLabel as String] = "Skillori: \(package)"
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func remove(for package: String) {
        SecItemDelete(query(package) as CFDictionary)
    }
}

/// Runs an installer that fetches skills with the reader's key into a home folder of its own,
/// reads the content ids of the skills it wrote, and removes the folder. The reader's own
/// folders are never written: the installer sees the temporary folder as home. This is how a
/// skill behind a key is checked for new versions, since only the installer can fetch it.
enum InstallerTrial {
    struct Result: Sendable {
        /// Skill folder name → content id, for every skill the installer wrote.
        let skills: [String: String]
    }

    enum Failure: Error, Sendable {
        /// npx is not on the path the login shell sets.
        case noNode
        /// The installer ended badly; its last line says why.
        case failed(lastLine: String?)
    }

    /// Fixed text; the folder and the installer's arguments come in as `$1…`, never pasted in.
    /// npm keeps using the reader's own cache and settings; only the installer's home moves.
    private static let script = """
    export npm_config_cache="$HOME/.npm"
    export npm_config_userconfig="$HOME/.npmrc"
    export HOME="$1"
    shift
    exec npx --yes "$@"
    """

    static func run(_ installer: PackageInstaller, arguments: [String]) async -> Swift.Result<Result, Failure> {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("skillori-check-" + UUID().uuidString, isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)) != nil else {
            return .failure(.failed(lastLine: nil))
        }
        defer { try? FileManager.default.removeItem(at: home) }
        let command = [home.path, installer.package + "@latest"] + arguments
        let printed = Protected("")
        var status = await Shell.run(script: script, arguments: command, timeout: 180) { text in
            printed.with { $0 = String(($0 + text).suffix(4000)) }
        }
        if status == 127 {
            // Node is only on the path an interactive shell sets.
            printed.with { $0 = "" }
            status = await Shell.run(script: script, arguments: command, interactive: true, timeout: 180) { text in
                printed.with { $0 = String(($0 + text).suffix(4000)) }
            }
            if status == 127 { return .failure(.noNode) }
        }
        guard status == 0 else {
            let lines = printed.with { $0 }.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.lowercased().hasPrefix("npm") }
            // An installer often ends with where to go; the line before it says why.
            var said = lines.last
            if let last = lines.last, last.hasPrefix("https://"), lines.count >= 2 { said = lines[lines.count - 2] + " " + last }
            return .failure(.failed(lastLine: said.map { String($0.prefix(240)) }))
        }
        // Wherever this installer puts skills (`~/.agents/skills`, an agent's own folder): every
        // folder with a SKILL.md. Links are not followed, so a skill linked into several agents is read once.
        let skills = await Task.detached(priority: .utility) { () -> [String: String] in
            var found: [String: String] = [:]
            guard let walk = FileManager.default.enumerator(at: home, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return found }
            while let file = walk.nextObject() as? URL {
                if walk.level > 8 { walk.skipDescendants(); continue }
                guard file.lastPathComponent == "SKILL.md" else { continue }
                let folder = file.deletingLastPathComponent()
                let name = folder.lastPathComponent.lowercased()
                guard found[name] == nil, let id = try? GitTreeHash.hashDirectory(at: folder).treeID else { continue }
                found[name] = id
            }
            return found
        }.value
        return .success(Result(skills: skills))
    }
}
