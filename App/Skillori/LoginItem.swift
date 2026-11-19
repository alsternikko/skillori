import Foundation
import Observation
import ServiceManagement

/// Whether Skillori opens when the reader logs in. The system keeps the answer (it shows in
/// System Settings › General › Login Items), so it is read back from there rather than stored here.
@MainActor @Observable
final class LoginItem {
    static let shared = LoginItem()

    enum State: Equatable { case off, on, needsApproval }

    private(set) var state: State = .off
    /// The last error from the system, shown until the next change.
    private(set) var problem: String?

    private init() { refresh() }

    /// Reads the state again; the reader can change it in System Settings while Skillori runs.
    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled: state = .on
        case .requiresApproval: state = .needsApproval
        default: state = .off
        }
    }

    var isOn: Bool { state != .off }

    func set(_ on: Bool) {
        problem = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            problem = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
