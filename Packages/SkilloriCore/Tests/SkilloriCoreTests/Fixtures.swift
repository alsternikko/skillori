import Foundation

/// Builds throwaway directory trees under the system temp directory. Tests never touch the
/// developer's real skills.
struct TempTree {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillori-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func file(_ path: String, _ content: String = "", executable: Bool = false) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        return url
    }

    func dir(_ path: String) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
    }

    func link(_ path: String, to destination: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: destination)
    }

    func skill(_ path: String, name: String, extra: [String: String] = [:]) throws {
        try file("\(path)/SKILL.md", "---\nname: \(name)\ndescription: Test skill \(name)\n---\n\n# \(name)\n")
        for (rel, content) in extra { try file("\(path)/\(rel)", content) }
    }
}

/// Runs the real git binary with no user or system configuration, only to produce reference
/// hashes in tests.
func referenceTreeHash(of directory: URL) throws -> String {
    let gitDir = FileManager.default.temporaryDirectory.appendingPathComponent("skillori-git-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: gitDir) }
    let env = [
        "GIT_DIR": gitDir.path,
        "GIT_INDEX_FILE": gitDir.path + ".index",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "HOME": gitDir.path,
    ]
    defer { try? FileManager.default.removeItem(atPath: gitDir.path + ".index") }
    _ = try run(["git", "init", "-q", "--bare", gitDir.path], env: env, cwd: directory)
    _ = try run(["git", "--work-tree", directory.path, "add", "-A", "."], env: env, cwd: directory)
    return try run(["git", "write-tree"], env: env, cwd: directory).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func run(_ args: [String], env: [String: String], cwd: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = args
    process.environment = env.merging(["PATH": "/usr/bin:/bin:/opt/homebrew/bin"]) { a, _ in a }
    process.currentDirectoryURL = cwd
    let out = Pipe()
    process.standardOutput = out
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
}
