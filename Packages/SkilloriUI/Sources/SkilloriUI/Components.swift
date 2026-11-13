import SwiftUI

/// The outer surface of the menu bar panel and of first start: solid ground. Its edge is the
/// window's own shadow, which already has a thin rim; in dark mode, where that rim cannot be
/// seen, a faint light hairline takes its place. Nothing in the app is translucent.
public struct PanelSurface<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(6)
            .background(Palette.panel, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(scheme == .dark ? 0.12 : 0), lineWidth: 1))
            .foregroundStyle(Palette.ink)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.panel, style: .circular) }
}

/// What a number is a share of: `part` out of `whole`, with a caption at each end.
public struct ScaleReading: Sendable {
    public let part: Int
    public let whole: Int
    public let partLabel: String
    public let wholeLabel: String

    public init(part: Int, whole: Int, partLabel: String, wholeLabel: String) {
        self.part = part
        self.whole = whole
        self.partLabel = partLabel
        self.wholeLabel = wholeLabel
    }
}

/// A ruler with ten divisions. The share is a heavier stroke from the left, ending in a marker.
public struct ScaleBar: View {
    let reading: ScaleReading
    public init(_ reading: ScaleReading) { self.reading = reading }

    public var body: some View {
        VStack(spacing: 4) {
            Canvas { context, size in
                let base = size.height - 0.5
                var ruler = Path()
                for step in 0...10 {
                    let x = (size.width - 1) * CGFloat(step) / 10 + 0.5
                    ruler.move(to: CGPoint(x: x, y: base - 8))
                    ruler.addLine(to: CGPoint(x: x, y: base))
                }
                ruler.move(to: CGPoint(x: 0, y: base))
                ruler.addLine(to: CGPoint(x: size.width, y: base))
                context.stroke(ruler, with: .foreground, lineWidth: 1)
                context.opacity = 1
            }
            .opacity(0.4)
            .overlay(alignment: .bottomLeading) {
                GeometryReader { proxy in
                    let x = max(1.5, proxy.size.width * share)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: proxy.size.height - 1.5))
                        path.addLine(to: CGPoint(x: x, y: proxy.size.height - 1.5))
                    }
                    .stroke(lineWidth: 3)
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                    }
                    .stroke(lineWidth: 1.5)
                }
            }
            .frame(height: 13)
            HStack {
                Text(reading.partLabel.uppercased())
                Spacer(minLength: 8)
                Text(reading.wholeLabel.uppercased()).opacity(0.6)
            }
            .font(TypeRole.mono(9))
            .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(reading.partLabel), \(reading.wholeLabel)")
    }

    private var share: CGFloat {
        reading.whole > 0 ? min(1, CGFloat(reading.part) / CGFloat(reading.whole)) : 0
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
    let scale: ScaleReading?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(tone: Tone, label: String, stamp: String, number: String, dimmed: Bool = false,
                lead: String, note: String, scale: ScaleReading? = nil) {
        self.scale = scale
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
            if let scale {
                ScaleBar(scale).opacity(dimmed ? 0.36 : 1).padding(.top, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 14, leading: 16, bottom: scale == nil ? 16 : 12, trailing: 16))
        .foregroundStyle(tone.foreground)
        .background(tone.background, in: RoundedRectangle(cornerRadius: Radius.block, style: .circular))
        .accessibilityElement(children: .combine)
    }
}

/// Rows that sit straight on the panel's ground, under the block they belong to.
public struct PlainList<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One row in a plain list, with a hairline under it. With `tree` it starts with a branch line,
/// a corner on the last row.
public struct ListRow<Leading: View, Trailing: View>: View {
    let isLast: Bool
    let tree: Bool
    let leading: Leading
    let trailing: Trailing

    public init(isLast: Bool = false, tree: Bool = false,
                @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.isLast = isLast
        self.tree = tree
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if tree {
                Path { path in
                    path.move(to: CGPoint(x: 0.5, y: 0))
                    path.addLine(to: CGPoint(x: 0.5, y: isLast ? 7.5 : 15))
                    path.move(to: CGPoint(x: 0.5, y: 7.5))
                    path.addLine(to: CGPoint(x: 10, y: 7.5))
                }
                .stroke(Palette.ink3, lineWidth: 1)
                .frame(width: 10, height: 15)
                .accessibilityHidden(true)
            }
            leading.frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .font(TypeRole.sans(13))
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .overlay(alignment: .bottom) { Palette.ink.opacity(0.1).frame(height: 1) }
    }
}

/// A key or shortcut in a small outlined box.
public struct KeyCap: View {
    let key: String
    public init(_ key: String) { self.key = key }

    public var body: some View {
        Text(key)
            .font(TypeRole.mono(10))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .circular).strokeBorder(.primary.opacity(0.4), lineWidth: 1))
    }
}

/// Mono caps in a small-radius outline; `prominent` fills it. On a toned block, pass the tone
/// so the button takes the block's own ink.
public struct PillButtonStyle: ButtonStyle {
    let prominent: Bool
    let tone: Tone?
    public init(prominent: Bool = false, on tone: Tone? = nil) {
        self.prominent = prominent
        self.tone = tone
    }

    public func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, prominent: prominent, tone: tone)
    }

    private struct PillBody: View {
        let configuration: Configuration
        let prominent: Bool
        let tone: Tone?
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            let ink = tone?.foreground ?? Palette.ink
            let onInk = tone?.background ?? Palette.onInk
            let shape = RoundedRectangle(cornerRadius: Radius.control, style: .circular)
            configuration.label
                .font(TypeRole.mono(10.5, .medium))
                .tracking(0.42)
                .textCase(.uppercase)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(prominent ? onInk : ink)
                .background(prominent ? ink : ink.opacity(hovering ? 0.08 : 0), in: shape)
                .overlay(shape.strokeBorder(ink.opacity(prominent ? 0 : 0.32), lineWidth: 1))
                .opacity(isEnabled ? (prominent && hovering ? 0.86 : 1) : 0.4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(Motion.press, value: configuration.isPressed)
                .contentShape(shape)
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

/// A tile with a label, one dot number and a caption. Used as a filter: the chosen tile is
/// the resting block, the others are cards unless they carry a tone of their own.
public struct StatTile: View {
    let label: String
    let number: String
    let caption: String
    let tone: Tone?
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    public init(label: String, number: String, caption: String, tone: Tone? = nil, isSelected: Bool,
                action: @escaping () -> Void) {
        self.label = label
        self.number = number
        self.caption = caption
        self.tone = tone
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        let shown: Tone? = isSelected ? .rest : tone
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    LabelText(label)
                    Spacer(minLength: 4)
                    if isSelected { LabelText("Shown") }
                }
                .foregroundStyle(shown?.secondary ?? Palette.ink2)
                DotNumber(number, size: 44)
                Text(caption)
                    .font(TypeRole.sans(12))
                    .foregroundStyle(shown?.secondary ?? Palette.ink2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .foregroundStyle(shown?.foreground ?? Palette.ink)
            .background(shown?.background ?? Palette.card, in: shape)
            .overlay(shape.strokeBorder(Palette.ink.opacity(hovering && !isSelected ? 0.14 : 0), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(TilePressStyle())
        .animation(Motion.hover, value: hovering)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(number) \(caption)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.block, style: .circular) }

    private struct TilePressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
                .animation(Motion.press, value: configuration.isPressed)
        }
    }
}

/// A status in mono capitals on a small-radius chip. The word carries the meaning; colour only
/// marks the two states that ask for attention.
public struct StatusChip: View {
    public enum Kind: Sendable { case neutral, new, attention, outline }
    let text: String
    let kind: Kind
    let mark: String?

    /// `mark` is a small shape shown before the word, so the status does not rest on colour.
    public init(_ text: String, kind: Kind = .neutral, mark: String? = nil) {
        self.text = text
        self.kind = kind
        self.mark = mark
    }

    public var body: some View {
        Text((mark.map { $0 + " " } ?? "") + text.uppercased())
            .font(TypeRole.mono(9.5))
            .tracking(0.57)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(kind == .outline ? AnyShapeStyle(.primary) : AnyShapeStyle(Palette.inkFixed))
            .background(fill, in: RoundedRectangle(cornerRadius: Radius.chip, style: .circular))
            .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .circular)
                .strokeBorder(Color(hex: 0xA3A3A8).opacity(kind == .outline ? 0.7 : 0), lineWidth: 1))
            .fixedSize()
    }

    private var fill: Color {
        switch kind {
        case .neutral: Color(hex: 0xE9E9EC)
        case .new: Palette.lime
        case .attention: Palette.lilac
        case .outline: .clear
        }
    }
}

/// A row of thin ticks, one per thing, followed by the count. For "how many agents".
public struct TickCount: View {
    let count: Int
    public init(_ count: Int) { self.count = count }

    public var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(0..<min(count, 10), id: \.self) { _ in
                    Rectangle().frame(width: 1, height: 8)
                }
            }
            .frame(width: 38, alignment: .leading)
            DataText("\(count)")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count)")
    }
}

/// A fixed row at the bottom of a window for the selected item: the resting block, full width.
public struct StatusLine<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        HStack(spacing: 6) { content }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 8))
            .frame(maxWidth: .infinity)
            .foregroundStyle(Tone.rest.foreground)
            .background(Tone.rest.background, in: RoundedRectangle(cornerRadius: Radius.block, style: .circular))
    }
}

/// A segmented choice in mono capitals. The chosen segment is a raised card.
public struct SegmentedChoice<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    public init(_ options: [(value: Value, label: String)], selection: Binding<Value>) {
        self.options = options
        _selection = selection
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let chosen = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.label.uppercased())
                        .font(TypeRole.mono(10.5, .medium))
                        .tracking(0.42)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .foregroundStyle(chosen ? Palette.ink : Palette.ink2)
                        .background(chosen ? Palette.card : .clear, in: RoundedRectangle(cornerRadius: Radius.chip, style: .circular))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(3)
        .fixedSize()
        .background(Palette.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: Radius.control, style: .circular))
        .animation(Motion.hover, value: selection)
    }
}

/// A card with a mono label row on top, for grouped settings and facts.
public struct LabeledCard<Content: View>: View {
    let label: String
    let note: String?
    let content: Content

    public init(_ label: String, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.note = note
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                LabelText(label)
                Spacer(minLength: 8)
                if let note { LabelText(note) }
            }
            .foregroundStyle(Palette.ink2)
            .padding(.bottom, 4)
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 8, trailing: 20))
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.block, style: .circular))
    }
}

/// A settings row: content on the left, a control or fact on the right, hairline under it.
public struct SettingRow<Leading: View, Trailing: View>: View {
    let isLast: Bool
    let leading: Leading
    let trailing: Trailing

    public init(isLast: Bool = false, @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.isLast = isLast
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 12) {
            leading.frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .font(TypeRole.sans(13))
        .padding(.vertical, 10)
        .frame(minHeight: 40)
        // A row is as tall as its content needs. Without this a tight parent can squeeze
        // the row below its content, which then overflows or truncates.
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .bottom) { if !isLast { Palette.line.frame(height: 1) } }
    }
}
