import Foundation
import Synchronization

/// The reader's own GitHub sign-in on this Mac, for repositories GitHub shows only to them.
///
/// GitHub answers "not found" both for a repository that is gone and for one that is private,
/// such as a team's own skills. Skillori asks every source signed out first. Only after a
/// "not found" does it ask the same question as the reader, with the token the GitHub CLI
/// (`gh`) already keeps. The token is read when it's needed, kept in memory for a few minutes,
/// sent only to api.github.com, and never written anywhere.
public actor GitHubSignIn {
    public typealias TokenSource = @Sendable () async -> String?

    public static let shared = GitHubSignIn()

    /// How long a token read from `gh` is used before it is read again.
    static let keepFor: TimeInterval = 10 * 60

    private nonisolated let source: Mutex<TokenSource?>
    private var token: String?
    private var readAt: Date?
    private var reading: Task<String?, Never>?
    /// Repositories that answered only to the reader, by lowercased `owner/repo`.
    private var privateRepositories: Set<String> = []

    public init(source: TokenSource? = nil) {
        self.source = Mutex(source)
    }

    /// Where the token comes from. The app sets this once, at launch, before anything is asked.
    public nonisolated func use(_ source: @escaping TokenSource) {
        self.source.withLock { $0 = source }
    }

    /// The reader's token, or nil when they aren't signed in to GitHub on this Mac.
    func token(now: Date = Date()) async -> String? {
        if let readAt, now.timeIntervalSince(readAt) < Self.keepFor { return token }
        if let reading { return await reading.value }
        guard let source = source.withLock({ $0 }) else {
            Self.lastLook.withLock { $0 = false }
            return nil
        }
        let task = Task { await source() }
        reading = task
        let found = await task.value.flatMap { $0.isEmpty ? nil : $0 }
        reading = nil
        token = found
        readAt = now
        Self.lastLook.withLock { $0 = found != nil }
        return found
    }

    /// Drops the token, so the next question reads it again.
    func forget() {
        token = nil
        readAt = nil
    }

    func isPrivate(_ repository: String) -> Bool { privateRepositories.contains(repository) }
    func markPrivate(_ repository: String) { privateRepositories.insert(repository) }

    private static let lastLook = Mutex<Bool?>(nil)

    /// Whether the last look for a sign-in found one: nil before any look. Readable from
    /// anywhere, for saying what a "not found" means.
    public nonisolated static var signedIn: Bool? { lastLook.withLock { $0 } }
}
