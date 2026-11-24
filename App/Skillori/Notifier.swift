import AppKit
import Foundation
import UserNotifications

/// Says when something new turns up at a source, and how an update ended when no Skillori
/// window was in front. A notification only opens the app; it never runs an update.
///
/// One notification per check, however many skills and sources it covers, and never twice
/// for the same skill at the same upstream revision. Failed checks are not notified: the
/// panel and the menu bar item already show them.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// The reader's choice in Settings. On by default; macOS still asks before the first one.
    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if newValue { requestPermission() }
        }
    }

    /// Opens the library when a notification is clicked. Set by the app delegate.
    var openLibrary: () -> Void = {}

    private static let enabledKey = "notifiesUpdates"
    private static let toldKey = "notifiedUpdates"
    private static let updatesID = "app.skillori.updates"
    private static let runID = "app.skillori.update-run"

    /// Notifications need a bundled app; the command line tests and snapshots have none.
    private var center: UNUserNotificationCenter? {
        let env = ProcessInfo.processInfo.environment
        guard Bundle.main.bundleIdentifier != nil, env["SKILLORI_SNAPSHOT_DIR"] == nil,
              env["SKILLORI_SELFTEST"] == nil else { return nil }
        #if DEBUG
        // The first start probe only counts the asking, unless it is told to ask for real.
        if env["SKILLORI_FIRST_START_PROBE"] != nil, env["SKILLORI_FIRST_START_PROBE_NOTIFY"] != "real" { return nil }
        #endif
        return UNUserNotificationCenter.current()
    }

    #if DEBUG
    /// How many times macOS would have been asked for permission since the app opened. For the probes.
    private(set) var permissionAsks = 0
    /// What macOS answered the last time it was asked, once it has. For the probes.
    private(set) var permissionAnswer: String?
    #endif

    func start() {
        center?.delegate = self
    }

    /// Asks macOS, which puts the question to the reader once; later calls return what they chose.
    /// Called when checks begin and every time the app opens with checks on.
    func requestPermission() {
        #if DEBUG
        if isEnabled { permissionAsks += 1 }
        #endif
        guard isEnabled, let center else { return }
        #if DEBUG
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            let answer = error.map { "error: \($0.localizedDescription)" } ?? (granted ? "allowed" : "not allowed")
            Task { @MainActor in Notifier.shared.permissionAnswer = answer }
        }
        #else
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        #endif
    }

    /// One update the reader might want to hear about: a skill, its source and the revision there.
    struct Found: Hashable {
        let key: String
        let source: String
        let upstream: String
        var token: String { "\(key)@\(upstream)" }
    }

    /// Tells the reader about updates that were not there the last time they were told.
    /// Revisions told about are remembered, so a restart does not repeat them. Nothing counts as
    /// told while macOS does not show Skillori's notifications (its question unanswered, or
    /// answered no): once it does, the next check tells about everything that is waiting.
    func updatesFound(_ found: [Found]) {
        guard isEnabled, let center else {
            // The reader turned notifications off in Settings: what is there now is old news if
            // they turn them on again.
            _ = remember(found)
            return
        }
        Task { @MainActor in
            let status = await center.notificationSettings().authorizationStatus
            guard status == .authorized || status == .provisional else {
                UserDefaults.standard.removeObject(forKey: Self.toldKey)
                return
            }
            let new = remember(found)
            guard !new.isEmpty else { return }
            try? await center.add(UNNotificationRequest(identifier: Self.updatesID, content: Self.content(for: new), trigger: nil))
        }
    }

    /// Notes these updates as told and gives the ones that were not told before.
    private func remember(_ found: [Found]) -> [Found] {
        var told = Set(UserDefaults.standard.stringArray(forKey: Self.toldKey) ?? [])
        // Forget revisions that are no longer an update, so a later one at the same skill is new again.
        told.formIntersection(Set(found.map(\.token)))
        let new = found.filter { !told.contains($0.token) }
        told.formUnion(new.map(\.token))
        UserDefaults.standard.set(Array(told).sorted(), forKey: Self.toldKey)
        return new
    }

    private static func content(for new: [Found]) -> UNNotificationContent {
        let sources = Dictionary(grouping: new, by: \.source)
        let content = UNMutableNotificationContent()
        if sources.count == 1, let (source, skills) = sources.first {
            content.title = skills.count == 1 ? "An update for 1 skill" : "Updates for \(skills.count) skills"
            content.body = "\(source) has changed. Review it in Skillori."
        } else {
            content.title = "Updates for \(new.count) skills"
            let names = sources.keys.sorted().prefix(3).joined(separator: ", ")
            content.body = "From \(sources.count) sources: \(names)\(sources.count > 3 ? " and more" : ""). Review them in Skillori."
        }
        content.threadIdentifier = Self.updatesID
        return content
    }

    /// How an update run ended, when the reader was not looking at Skillori.
    func runEnded(names: [String], phase: UpdateRunner.Phase) {
        guard isEnabled, let center, NSApp.keyWindow == nil else { return }
        let content = UNMutableNotificationContent()
        let what = names.count == 1 ? names[0] : "\(names.count) skills"
        switch phase {
        case .succeeded:
            content.title = "Updated \(what)"
            content.body = "The installer finished. Agents may need a new session to load the new version."
        case .failed(let reason):
            content.title = "Could not update \(what)"
            content.body = reason
        default:
            return
        }
        center.add(UNNotificationRequest(identifier: Self.runID, content: content, trigger: nil))
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { Notifier.shared.openLibrary() }
    }
}
