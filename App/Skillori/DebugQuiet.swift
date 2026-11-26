#if DEBUG
import Foundation

/// Debug builds only. While a test run drives the app (a probe, the self-test, the pictures),
/// its windows open far to the left of every screen and the app never makes itself active, so
/// whoever works at the Mac meanwhile keeps their screen and their keyboard. Pictures still come
/// out, since they are drawn from the windows' own content. `SKILLORI_ON_SCREEN=1` shows the
/// windows where they normally go, for watching a run.
enum DebugQuiet {
    /// Every test run here is started with at least one `SKILLORI_…` variable (a probe, the
    /// self-test, the pictures, an installer trial, sample data), so any of them makes the run
    /// quiet. A new test key needs no list to join; only `SKILLORI_ON_SCREEN` opts out.
    static let isOn: Bool = {
        let env = ProcessInfo.processInfo.environment
        return env["SKILLORI_ON_SCREEN"] == nil && env.keys.contains { $0.hasPrefix("SKILLORI_") }
    }()

    /// How far to the left the windows go: past any arrangement of screens.
    static let shift: CGFloat = -30_000

    /// Whether the menu bar panel may take the keyboard. A panel that doesn't activate the app
    /// takes keys from whatever app is in front, so in a quiet run it never does, except in the
    /// self-test, which checks the panel's keys (a short run).
    static let panelTakesKeys: Bool = !isOn || ProcessInfo.processInfo.environment["SKILLORI_SELFTEST"] != nil
}
#endif
