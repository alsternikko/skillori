import CryptoKit
import Foundation

/// Computes the git tree object id (SHA-1 object format) for a directory, without running git.
///
/// This matches `git write-tree` for the same content and the directory SHA that GitHub's
/// contents API reports, which is also what `npx skills` stores as `skillFolderHash`.
/// See docs/beslut/0004-innehallshash-git-trad.md.
///
/// Nothing in the directory is executed or interpreted. Symbolic links inside the tree are
/// hashed as links (mode 120000) and never followed.
public enum GitTreeHash {
    public struct Entry: Sendable, Equatable {
        public enum Kind: String, Sendable { case file, executable, symlink, directory }
        public let path: String
        public let kind: Kind
        public let size: Int
        public let objectID: String
    }

    public struct Result: Sendable {
        public let treeID: String
        /// Every file and symlink, depth first, with paths relative to the hashed directory.
        public let entries: [Entry]
    }

    public enum HashError: Error, Sendable {
        case unreadable(String)
        case limitExceeded(String)
    }

    /// Names that are never part of a skill's content identity.
    /// `.DS_Store` is Finder metadata that never exists upstream; counting it would mark
    /// every skill opened in Finder as locally modified.
    public static let ignoredNames: Set<String> = [".git", ".DS_Store"]

    public struct Limits: Sendable {
        public var maxFiles = 5_000
        public var maxTotalBytes = 200 * 1024 * 1024
        public var maxDepth = 32
        public init() {}
    }

    public static func hashDirectory(at url: URL, limits: Limits = Limits()) throws -> Result {
        var state = WalkState()
        let id = try hashTree(at: url, relative: "", depth: 0, limits: limits, state: &state)
        // A directory with no hashable content still has the well-known empty tree id.
        return Result(treeID: (id ?? emptyTreeID).hex, entries: state.entries)
    }

    static let emptyTreeID = objectID(type: "tree", body: Data())

    // MARK: - Internals

    private struct WalkState {
        var entries: [Entry] = []
        var totalBytes = 0
    }

    private struct RawEntry {
        let name: String
        let mode: String
        let isTree: Bool
        let id: Data
    }

    /// Returns nil when the directory has no hashable entries (git omits empty trees).
    private static func hashTree(
        at url: URL, relative: String, depth: Int, limits: Limits, state: inout WalkState
    ) throws -> Data? {
        guard depth <= limits.maxDepth else { throw HashError.limitExceeded("depth at \(relative)") }
        let fm = FileManager.default
        let names: [String]
        do {
            names = try fm.contentsOfDirectory(atPath: url.path)
        } catch {
            throw HashError.unreadable(url.path)
        }

        var raw: [RawEntry] = []
        for diskName in names where !ignoredNames.contains(diskName) {
            let child = url.appendingPathComponent(diskName, isDirectory: false)
            // macOS file APIs may hand back decomposed (NFD) names. Git on macOS
            // (core.precomposeunicode, the default) and GitHub record precomposed (NFC) names,
            // so the tree must be built from NFC or every non-ASCII name breaks the hash.
            let name = diskName.precomposedStringWithCanonicalMapping
            let childRelative = relative.isEmpty ? name : relative + "/" + name
            var st = stat()
            guard lstat(child.path, &st) == 0 else { throw HashError.unreadable(child.path) }
            let type = st.st_mode & S_IFMT

            switch type {
            case S_IFDIR:
                if let id = try hashTree(at: child, relative: childRelative, depth: depth + 1, limits: limits, state: &state) {
                    raw.append(RawEntry(name: name, mode: "40000", isTree: true, id: id))
                }
            case S_IFLNK:
                let target = try fm.destinationOfSymbolicLink(atPath: child.path)
                let body = Data(target.utf8)
                let id = objectID(type: "blob", body: body)
                raw.append(RawEntry(name: name, mode: "120000", isTree: false, id: id))
                state.entries.append(Entry(path: childRelative, kind: .symlink, size: body.count, objectID: id.hex))
            case S_IFREG:
                let size = Int(st.st_size)
                state.totalBytes += size
                guard state.totalBytes <= limits.maxTotalBytes else { throw HashError.limitExceeded("size at \(childRelative)") }
                guard state.entries.count < limits.maxFiles else { throw HashError.limitExceeded("file count at \(childRelative)") }
                guard let body = fm.contents(atPath: child.path) else { throw HashError.unreadable(child.path) }
                // Git records only whether the owner execute bit is set.
                let executable = (st.st_mode & S_IXUSR) != 0
                let id = objectID(type: "blob", body: body)
                raw.append(RawEntry(name: name, mode: executable ? "100755" : "100644", isTree: false, id: id))
                state.entries.append(Entry(path: childRelative, kind: executable ? .executable : .file, size: size, objectID: id.hex))
            default:
                // FIFOs, sockets and devices are not content. Git skips them too.
                continue
            }
        }

        guard !raw.isEmpty else { return nil }

        // Git sorts tree entries bytewise, comparing a subtree's name as if it ended in "/".
        raw.sort { a, b in
            let ka = Array(a.name.utf8) + (a.isTree ? [0x2F] : [])
            let kb = Array(b.name.utf8) + (b.isTree ? [0x2F] : [])
            return ka.lexicographicallyPrecedes(kb)
        }

        var body = Data()
        for entry in raw {
            body.append(contentsOf: Array("\(entry.mode) \(entry.name)".utf8))
            body.append(0)
            body.append(entry.id)
        }
        return objectID(type: "tree", body: body)
    }

    static func objectID(type: String, body: Data) -> Data {
        var hasher = Insecure.SHA1()
        hasher.update(data: Data("\(type) \(body.count)\u{0}".utf8))
        hasher.update(data: body)
        return Data(hasher.finalize())
    }
}

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
