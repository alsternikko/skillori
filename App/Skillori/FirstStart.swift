import AppKit
import SkilloriCore
import SkilloriUI
import SwiftUI

/// First start, in three steps: what Skillori does, where it looks, and the first reading.
/// A fourth step about checking and notifications waits for backlog etapp 2.
struct FirstStartView: View {
    @Environment(InventoryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var step = 1
    var onDone: () -> Void = {}
    var onLibrary: () -> Void = {}

    static let width: CGFloat = 320
    private static let steps = 3

    var body: some View {
        PanelSurface {
            ZStack {
                content
                    .id(step)
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
            }
            .animation(Motion.swap, value: step)
        }
        .frame(width: Self.width)
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch step {
            case 1: welcome
            case 2: whereToLook
            default: firstReading
            }
        }
        // Every step is the same height, so the window never has to change size.
        .frame(height: 446, alignment: .top)
    }

    // MARK: Step 1

    @ViewBuilder private var welcome: some View {
        hero(.rest, label: "Welcome") {
            SkilloriMark().fill(Tone.rest.foreground).frame(width: 72, height: 72).padding(.top, 22)
            Spacer(minLength: 0)
            lead("Your agent skills, in one place.")
        }
        PlainList {
            bullet("Reads skill folders on this Mac")
            bullet("Uploads nothing")
            bullet("Never runs a script from a skill", isLast: true)
        }
        footer {
            Button("Continue") { step = 2 }.buttonStyle(PillButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Step 2

    @ViewBuilder private var whereToLook: some View {
        let agents = AgentPresence.found(among: knownAgents)
        hero(.quiet, label: "Agents") {
            AgentConstellation(agents: agents).padding(.top, 8)
            Spacer(minLength: 0)
            lead(agents.count == 1 ? "1 agent found on this Mac" : "\(agents.count) agents found on this Mac")
            note("Full Disk Access is not needed.", tone: .quiet)
        }
        PlainList {
            ListRow {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Shared skills")
                    DataText("~/.agents/skills").foregroundStyle(Palette.ink2)
                }
            } trailing: { EmptyView() }
            ListRow {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Each agent's own folder")
                    DataText("~/.claude · ~/.cursor · and more").foregroundStyle(Palette.ink2)
                }
            } trailing: { EmptyView() }
            ListRow(isLast: true) {
                Text("Skills in a project folder?").foregroundStyle(Palette.ink2)
            } trailing: {
                Button("Add folder") { store.addProject() }.buttonStyle(HintButtonStyle(underlined: true))
            }
        }
        footer {
            Button("Continue") { step = 3 }.buttonStyle(PillButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
            Button("Back") { step = 1 }.buttonStyle(PillButtonStyle())
        }
    }

    private var knownAgents: [Agent] {
        [.claudeCode, .cursor, .codex, .geminiCLI, .antigravity, .openCode, .kiro, .copilot, .amp, .droid, .devin, .goose]
    }

    // MARK: Step 3

    @ViewBuilder private var firstReading: some View {
        let inventory = store.inventory
        let total = inventory?.installations.count ?? 0
        hero(inventory == nil ? .quiet : .new, label: inventory == nil ? "Reading" : "Found") {
            DotNumber(inventory == nil ? "--" : "\(total)", size: 72)
                .opacity(inventory == nil ? 0.36 : 1)
                .padding(.top, 22)
            Spacer(minLength: 0)
            lead(total == 1 ? "skill on this Mac" : "skills on this Mac")
            if let inventory {
                let folders = inventory.roots.filter { $0.state == .found }.count
                note("\(folders) folders read in \(Int(inventory.duration * 1000)) ms.", tone: .new)
            }
        }
        PlainList {
            count("Installed by you", store.trackedCount + store.unknownCount)
            count("Managed by apps", store.managedCount)
            count("With no known source", store.unknownCount, muted: true, isLast: true)
        }
        footer {
            Button("Done", action: onDone).buttonStyle(PillButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
            Button("Open Library", action: onLibrary).buttonStyle(PillButtonStyle())
            Spacer(minLength: 0)
            Button("Back") { step = 2 }.buttonStyle(HintButtonStyle())
        }
    }

    // MARK: Parts

    private func hero(_ tone: Tone, label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                LabelText(label)
                Spacer(minLength: 8)
                LabelText("\(step) of \(Self.steps)")
            }
            .foregroundStyle(tone.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
        .frame(height: 268)
        .foregroundStyle(tone.foreground)
        .background(tone.background, in: RoundedRectangle(cornerRadius: Radius.block, style: .continuous))
    }

    private func lead(_ text: String) -> some View {
        Text(text).font(TypeRole.sans(20, .medium)).tracking(-0.4).lineSpacing(2)
    }

    private func note(_ text: String, tone: Tone) -> some View {
        Text(text).font(TypeRole.sans(12)).foregroundStyle(tone.secondary).padding(.top, 6)
    }

    private func bullet(_ text: String, isLast: Bool = false) -> some View {
        ListRow(isLast: isLast) {
            HStack(spacing: 10) {
                Circle().fill(Palette.ink).frame(width: 6.5, height: 6.5)
                Text(text)
            }
        } trailing: { EmptyView() }
    }

    private func count(_ text: String, _ value: Int, muted: Bool = false, isLast: Bool = false) -> some View {
        ListRow(isLast: isLast) {
            Text(text).foregroundStyle(muted ? Palette.ink2 : Palette.ink)
        } trailing: {
            DataText("\(value)").foregroundStyle(Palette.ink2)
        }
    }

    @ViewBuilder private func footer(@ViewBuilder content: () -> some View) -> some View {
        Spacer(minLength: 0)
        HStack(spacing: 6) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 10, leading: 4, bottom: 4, trailing: 6))
    }
}

/// Skillori in the middle, the agents found on this Mac around it.
private struct AgentConstellation: View {
    let agents: [Agent]

    private static let slots: [CGPoint] = [
        CGPoint(x: 236, y: 75), CGPoint(x: 206, y: 112), CGPoint(x: 132, y: 127), CGPoint(x: 58, y: 112),
        CGPoint(x: 28, y: 75), CGPoint(x: 58, y: 38), CGPoint(x: 132, y: 23), CGPoint(x: 206, y: 38),
    ]
    private static let centre = CGPoint(x: 132, y: 75)

    var body: some View {
        let shown = agents.count > Self.slots.count ? Array(agents.prefix(Self.slots.count - 1)) : agents
        let extra = agents.count - shown.count
        let used = shown.count + (extra > 0 ? 1 : 0)
        ZStack {
            Path { path in
                for slot in Self.slots.prefix(used) {
                    path.move(to: Self.centre)
                    path.addLine(to: slot)
                }
            }
            .stroke(Palette.ink3, lineWidth: 1)

            SkilloriMark().fill(.white).frame(width: 28, height: 28)
                .frame(width: 48, height: 48)
                .background(Palette.charcoal, in: RoundedRectangle(cornerRadius: Radius.block, style: .continuous))
                .position(Self.centre)

            ForEach(Array(shown.enumerated()), id: \.element.id) { index, agent in
                AgentMark(agent: agent).position(Self.slots[index])
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(TypeRole.mono(9.5))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 30, height: 30)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    .position(Self.slots[used - 1])
                    .accessibilityLabel("\(extra) more")
            }
        }
        .frame(width: 264, height: 150)
        .frame(maxWidth: .infinity)
    }
}

/// Shows first start once, in the same panel form as the menu bar panel, centred.
@MainActor
final class FirstStartController {
    static let doneKey = "didFinishFirstStart"
    private let store: InventoryStore
    private let windows: WindowRouter
    private var panel: PanelWindow?

    init(store: InventoryStore, windows: WindowRouter) {
        self.store = store
        self.windows = windows
    }

    func showIfNeeded() {
        if !UserDefaults.standard.bool(forKey: Self.doneKey) { show() }
    }

    func show() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let panel = PanelWindow()
        panel.level = .floating
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.fullScreenAuxiliary]
        let host = NSHostingView(rootView: FirstStartView(
            onDone: { [weak self] in self?.finish() },
            onLibrary: { [weak self] in
                self?.finish()
                self?.windows.showLibrary()
            }
        ).environment(store))
        panel.setContent(host)
        panel.onCancel = { [weak self] in self?.finish() }
        panel.setContentSize(host.fittingSize)
        panel.center()
        self.panel = panel
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        panel?.orderOut(nil)
        panel = nil
    }
}

extension Notification.Name {
    static let showFirstStart = Notification.Name("SkilloriShowFirstStart")
}
