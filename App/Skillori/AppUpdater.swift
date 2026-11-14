import AppKit
import Foundation
import Observation
import Sparkle

/// Keeps Skillori itself up to date, with Sparkle (docs/beslut/0002).
///
/// Sparkle does the checking, the download, the signature check and the install. Its own
/// windows are not used: this class is Sparkle's "user driver", so every step lands here as
/// a `phase` that the settings and the panel draw in the app's own design.
///
/// The feed is skillori.app/appcast.xml, written by scripts/release.sh. Each update is signed
/// with an EdDSA key whose public half is `SUPublicEDKey` in Info.plist; Sparkle refuses
/// anything else.
@MainActor
@Observable
final class AppUpdater: NSObject {
    static let shared = AppUpdater()

    enum Phase: Equatable {
        /// Nothing to say yet: no check has run since launch.
        case idle
        /// A check the reader asked for is on its way.
        case checking
        /// The feed has nothing newer.
        case upToDate
        /// A newer version. `downloaded` when an earlier session already fetched it.
        case available(version: String, downloaded: Bool)
        /// Fetching it. `fraction` is nil until the size is known.
        case downloading(version: String, fraction: Double?)
        /// Unpacking and checking the signature.
        case preparing(version: String)
        /// Sparkle is replacing the app; it relaunches on its own.
        case installing(version: String)
        /// The last step failed. The reader can try again.
        case failed(String)
        /// This build cannot update itself (no feed or key, as in a clone built without them).
        case unavailable
    }

    private(set) var phase: Phase = .idle
    /// What is new in the version on offer, as plain text from the feed.
    private(set) var notes: String?
    /// When the feed last answered, from Sparkle's own record.
    private(set) var lastCheck: Date?

    /// Checking once a day is on unless the reader turns it off. Sparkle stores the choice.
    var checksAutomatically: Bool {
        get { access(keyPath: \.checksAutomatically); return updater?.automaticallyChecksForUpdates ?? sampleChecks }
        set {
            withMutation(keyPath: \.checksAutomatically) {
                updater?.automaticallyChecksForUpdates = newValue
                sampleChecks = newValue
            }
        }
    }

    /// The version on offer or on its way in, for the panel's line.
    var offeredVersion: String? {
        switch phase {
        case let .available(v, _), let .downloading(v, _), let .preparing(v), let .installing(v): v
        default: nil
        }
    }

    var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .preparing, .installing: true
        default: false
        }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static let changelogURL = URL(string: "https://skillori.app/changelog/")!

    private var updater: SPUUpdater?
    /// Stands in for Sparkle's setting in debug pictures, where Sparkle isn't started.
    @ObservationIgnored private var sampleChecks = true
    /// Sparkle waits on these until the reader answers.
    private var foundReply: ((SPUUserUpdateChoice) -> Void)?
    /// Install was pressed after Sparkle let go of its offer: install as soon as it is found again.
    private var installWhenFound = false
    private var cancelDownload: (() -> Void)?
    private var expectedBytes: UInt64 = 0
    private var receivedBytes: UInt64 = 0

    /// Starts Sparkle. Its scheduler then checks once a day while the app runs.
    func start() {
        #if DEBUG
        if let sample = ProcessInfo.processInfo.environment["SKILLORI_SAMPLE_APP_UPDATE"] {
            useSample(sample)
            return
        }
        #endif
        let info = Bundle.main.infoDictionary ?? [:]
        guard (info["SUFeedURL"] as? String)?.isEmpty == false,
              (info["SUPublicEDKey"] as? String)?.isEmpty == false else {
            phase = .unavailable
            return
        }
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: nil)
        do {
            try updater.start()
            self.updater = updater
            lastCheck = updater.lastUpdateCheckDate
        } catch {
            phase = .unavailable
            print("[Skillori] app updates could not start: \(error.localizedDescription)")
        }
    }

    /// The reader's "Check now".
    func checkNow() {
        guard let updater, updater.canCheckForUpdates else { return }
        if foundReply != nil { return }  // An offer is already on the table.
        phase = .checking
        updater.checkForUpdates()
    }

    /// The reader's "Install". Sparkle downloads, checks and installs, then relaunches the app.
    func install() {
        guard let reply = foundReply else {
            installWhenFound = true
            checkNow()
            return
        }
        foundReply = nil
        reply(.install)
    }

    func cancel() {
        cancelDownload?()
        cancelDownload = nil
    }

    func openChangelog() {
        let anchor = offeredVersion.map { "#v\($0)" } ?? ""
        NSWorkspace.shared.open(URL(string: Self.changelogURL.absoluteString + anchor) ?? Self.changelogURL)
    }

    private func refreshLastCheck() {
        if let date = updater?.lastUpdateCheckDate { lastCheck = date }
    }

    /// The feed's description is HTML; the panel and settings want one plain paragraph.
    private static func plainText(_ html: String?) -> String? {
        guard let html, !html.isEmpty else { return nil }
        let text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func message(for error: Error) -> String {
        let error = error as NSError
        if error.domain == NSURLErrorDomain { return "No answer from skillori.app" }
        return error.localizedDescription
    }

    #if DEBUG
    /// `SKILLORI_SAMPLE_APP_UPDATE=available|downloading|preparing|failed|current` shows a fixed state.
    private func useSample(_ sample: String) {
        lastCheck = Date().addingTimeInterval(-40 * 60)
        notes = "Skills from a plugin marketplace now show where they came from, and the panel opens faster."
        switch sample {
        case "available": phase = .available(version: "0.2.0", downloaded: false)
        case "downloading": phase = .downloading(version: "0.2.0", fraction: 0.42)
        case "preparing": phase = .preparing(version: "0.2.0")
        case "failed": phase = .failed("No answer from skillori.app")
        default: phase = .upToDate
        }
    }
    #endif
}

// Sparkle calls these on the main thread.
extension AppUpdater: @preconcurrency SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // Info.plist turns the checks on (SUEnableAutomaticChecks), so Sparkle should not ask.
        // If it does, the answer is the same, with no system profile.
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        phase = .checking
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        refreshLastCheck()
        // An item that only points at a web page cannot be installed from here.
        if appcastItem.isInformationOnlyUpdate {
            reply(.dismiss)
            phase = .upToDate
            return
        }
        notes = Self.plainText(appcastItem.itemDescription)
        let version = appcastItem.displayVersionString
        if state.stage == .installing {
            // Fetched and unpacked in an earlier session: installing it is only a relaunch.
            phase = .installing(version: version)
            reply(.install)
            return
        }
        if installWhenFound {
            installWhenFound = false
            phase = .downloading(version: version, fraction: nil)
            reply(.install)
            return
        }
        foundReply = reply
        phase = .available(version: version, downloaded: state.stage == .downloaded)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        refreshLastCheck()
        phase = .upToDate
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        refreshLastCheck()
        foundReply = nil
        cancelDownload = nil
        installWhenFound = false
        phase = .failed(Self.message(for: error))
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        cancelDownload = cancellation
        expectedBytes = 0
        receivedBytes = 0
        phase = .downloading(version: offeredVersion ?? "", fraction: nil)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedBytes = expectedContentLength
        receivedBytes = 0
        phase = .downloading(version: offeredVersion ?? "", fraction: expectedBytes > 0 ? 0 : nil)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedBytes += length
        guard expectedBytes > 0 else { return }
        let fraction = min(1, Double(receivedBytes) / Double(expectedBytes))
        // A redraw per whole percent is plenty.
        if case let .downloading(_, old) = phase, Int((old ?? -1) * 100) == Int(fraction * 100) { return }
        phase = .downloading(version: offeredVersion ?? "", fraction: fraction)
    }

    func showDownloadDidStartExtractingUpdate() {
        cancelDownload = nil
        phase = .preparing(version: offeredVersion ?? "")
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        // The reader already pressed Install, so the app goes straight on to relaunch.
        phase = .installing(version: offeredVersion ?? "")
        reply(.install)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        phase = .installing(version: offeredVersion ?? "")
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdateInFocus() {}

    func dismissUpdateInstallation() {
        // The session is over. A failure, an answer or an offer stays on screen (Install then
        // asks again); a download that was cancelled returns to rest.
        foundReply = nil
        cancelDownload = nil
        refreshLastCheck()
        switch phase {
        case .failed, .upToDate, .available: break
        default: phase = .idle
        }
    }
}
