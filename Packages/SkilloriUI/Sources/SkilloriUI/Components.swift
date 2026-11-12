import SwiftUI

/// The panel's outer surface: a tint over whatever is behind it, with a hairline highlight.
/// The blur itself comes from the window (see the app's `GlassPanelWindow`).
public struct GlassPanel<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(6)
            .background(tint, in: shape)
            .overlay(shape.strokeBorder(.white.opacity(scheme == .dark ? 0.12 : 0.5), lineWidth: 1))
            .foregroundStyle(Palette.ink)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.panel, style: .continuous) }
    private var tint: Color {
        scheme == .dark ? Color(hex: 0x19191B, opacity: 0.8) : Color(hex: 0xF4F4F6, opacity: 0.8)
    }
}

/// A solid block with a label row, one big number, a lead line and a note.
public struct HeroBlock: View {
    let tone: Tone
    let label: String
    let stamp: String
    let number: String
    let dimmed: Bool
    let lead: String
    let note: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(tone: Tone, label: String, stamp: String, number: String, dimmed: Bool = false,
                lead: String, note: String) {
        self.tone = tone
        self.label = label
        self.stamp = stamp
        self.number = number
        self.dimmed = dimmed
        self.lead = lead
        self.note = note
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                LabelText(label)
                Spacer(minLength: 8)
                LabelText(stamp)
            }
            .foregroundStyle(tone.secondary)
            ZStack(alignment: .leading) {
                DotNumber(number)
                    .opacity(dimmed ? 0.36 : 1)
                    .id(number)
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
            }
            .animation(Motion.swap, value: number)
            .padding(.top, 20)
            Text(lead)
                .font(TypeRole.sans(15, .medium))
                .tracking(-0.15)
                .padding(.top, 12)
            Text(note)
                .font(TypeRole.sans(12))
                .foregroundStyle(tone.secondary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 40, trailing: 16))
        .foregroundStyle(tone.foreground)
        .background(tone.background, in: RoundedRectangle(cornerRadius: Radius.block, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The list that slides 24 pt up over the hero block.
///
/// What lies behind it is one flat colour, so the frosted edge is drawn as a soft fade from that
/// colour, seen through the sheet, into the sheet itself. It looks the same as a live backdrop blur and
/// costs nothing per frame.
public struct GlassList<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    public static var overlap: CGFloat { 24 }
    let behind: Color
    let content: Content

    public init(behind: Color, @ViewBuilder content: () -> Content) {
        self.behind = behind
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack(alignment: .top) {
                    sheet
                    LinearGradient(stops: [.init(color: frosted, location: 0),
                                           .init(color: frosted, location: 0.1),
                                           .init(color: sheetBase, location: 0.6),
                                           .init(color: sheetBase.opacity(0), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.overlap * 3)
                }
                .clipShape(shape)
            }
            .overlay(shape.strokeBorder(.white.opacity(scheme == .dark ? 0.1 : 0.6), lineWidth: 1))
            .padding(.top, -Self.overlap)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.block, style: .continuous) }
    private var sheetBase: Color { scheme == .dark ? Color(hex: 0x2A2A2D) : Color(hex: 0xFCFCFD) }
    private var sheetCover: Double { scheme == .dark ? 0.72 : 0.66 }
    private var sheet: Color { sheetBase.opacity(sheetCover) }
    /// The block's colour as seen through the sheet. Opaque, so the block's real edge
    /// behind the list does not show as a line.
    private var frosted: Color { behind.mix(with: sheetBase, by: sheetCover) }
}

/// One row in a glass list, with a hairline under it unless it is the last.
public struct ListRow<Leading: View, Trailing: View>: View {
    let isLast: Bool
    let leading: Leading
    let trailing: Trailing

    public init(isLast: Bool = false, @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.isLast = isLast
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 10) {
            leading.frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .font(TypeRole.sans(13))
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !isLast { Palette.ink.opacity(0.08).frame(height: 1) }
        }
    }
}

/// Mono caps in a full-round outline; `prominent` fills it.
public struct PillButtonStyle: ButtonStyle {
    let prominent: Bool
    public init(prominent: Bool = false) { self.prominent = prominent }

    public func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, prominent: prominent)
    }

    private struct PillBody: View {
        let configuration: Configuration
        let prominent: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(TypeRole.mono(10.5, .medium))
                .tracking(0.42)
                .textCase(.uppercase)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(prominent ? Palette.onInk : Palette.ink)
                .background(prominent ? Palette.ink : Palette.ink.opacity(hovering ? 0.06 : 0), in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.ink.opacity(prominent ? 0 : 0.28), lineWidth: 1))
                .opacity(isEnabled ? (prominent && hovering ? 0.86 : 1) : 0.4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(Motion.press, value: configuration.isPressed)
                .contentShape(Capsule())
                .animation(Motion.hover, value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

/// A quiet mono text button, for hints such as "CHECK NOW ⌘R" and inline links.
public struct HintButtonStyle: ButtonStyle {
    let underlined: Bool
    public init(underlined: Bool = false) { self.underlined = underlined }

    public func makeBody(configuration: Configuration) -> some View {
        HintBody(configuration: configuration, underlined: underlined)
    }

    private struct HintBody: View {
        let configuration: Configuration
        let underlined: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(TypeRole.mono(underlined ? 10.5 : 10))
                .tracking(0.42)
                .textCase(.uppercase)
                .underline(underlined)
                .foregroundStyle(underlined || hovering ? Palette.ink : Palette.ink2)
                .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
                .contentShape(Rectangle())
                .animation(Motion.hover, value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

/// Shared timing. Short, ease-out, no bounce.
public enum Motion {
    /// A value is replaced by another (a number, a label).
    public static let swap = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.18)
    public static let hover = Animation.easeOut(duration: 0.12)
    public static let press = Animation.easeOut(duration: 0.12)
}

/// Text that cross-fades with a slight blur when it changes.
public struct SwappingText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        ZStack(alignment: .trailing) {
            Text(text).id(text).transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
        }
        .animation(Motion.swap, value: text)
    }
}
