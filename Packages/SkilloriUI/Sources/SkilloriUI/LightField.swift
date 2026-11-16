import AppKit
import Foundation
import SwiftUI

/// The colours of the light inside an accent block: sixteen even steps, from the calm end of
/// the block, where its text sits, to the far end. Steps are kept in OKLab, which is the space
/// the shader mixes them in.
public struct LightRamp: Sendable, Equatable {
    /// Whether text on the block is light or dark. It follows the calm end of the ramp.
    public enum Ink: Sendable { case light, dark }

    let lut: [Float]
    let ink: Ink

    public init(lut: [UInt32], ink: Ink) {
        precondition(lut.count == 16, "A light ramp has sixteen steps")
        self.lut = lut.flatMap { hex -> [Float] in
            let lab = LightRamp.oklab(hex)
            return [lab.x, lab.y, lab.z]
        }
        self.ink = ink
    }

    static func oklab(_ hex: UInt32) -> SIMD3<Float> {
        func linear(_ byte: UInt32) -> Double {
            let c = Double(byte & 0xFF) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let r = linear(hex >> 16), g = linear(hex >> 8), b = linear(hex)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return SIMD3(Float(0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s),
                     Float(1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s),
                     Float(0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s))
    }
}

public extension LightRamp {
    // These are measured, not chosen: the mean colour of 3 by 3 pixels at up to forty points
    // along a line through each reference image, resampled to sixteen even steps in OKLab.
    // The study in docs/design/gradient-studie-2026-11-13/index.html has these and eight more,
    // and is where the three in use were picked.

    /// "Meadow": mauve grey, warm cream, khaki, then green into deep green. From the Nothing wallpaper.
    static let meadow = LightRamp(lut: [0x99909C, 0xB995C4, 0xA68CBB, 0x9E8CB4, 0xADA1B3, 0xC1BCC2, 0xD0CCCA, 0xD6D3CA,
                                        0xD9D4C1, 0xD0C49F, 0xA49E59, 0x3E8039, 0x27A64A, 0x24B955, 0x168D47, 0x122B22],
                                  ink: .light)
    /// "Rose": crimson, pink, orchid and violet, lavender at the far end. From the Sphole on dusty rose.
    static let rose = LightRamp(lut: [0xA41720, 0xA51821, 0xAC1A26, 0xB41C2C, 0xBC2337, 0xCA3052, 0xE16BAC, 0xEBACDA,
                                      0xE49DE0, 0xC555DD, 0x9F33D6, 0x8027D1, 0x8528CC, 0xA547D2, 0xC7A3DC, 0xB7A3CE],
                                ink: .light)
    /// "Orchid": pale pink-lilac, lilac, grey blue, then soft green. From the blurry squircle on mint.
    static let orchid = LightRamp(lut: [0xF2CBEF, 0xF1C8F0, 0xF1C8F0, 0xF1C7EF, 0xF0C4EC, 0xEBBEE9, 0xE6B8E7, 0xDCAFE1,
                                        0xC7A2D4, 0xA18EC0, 0x70879C, 0x6EA075, 0x93C36E, 0xB2D885, 0xC1E4A4, 0xCDE7BA],
                                  ink: .dark)
}

/// The living background of an accent block. The block itself is the body of light and stays
/// put: its bands run across the whole block, and what changes, slowly, is the gradient's own
/// range: where the bands crowd, how wide each is, and how far they wrap round the edge.
/// It holds still when Reduce Motion is on.
public struct LightField: View {
    let ramp: LightRamp
    let radius: CGFloat
    let corners: RoundedCornerStyle
    /// Seconds added to the clock, so two blocks on screen do not change in step.
    let phase: Double
    /// A still picture, for places that must not change, such as the app icon.
    let still: Bool
    /// Eases the whole block for what lies on it, not only the side where a block's text sits.
    let easedThroughout: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    /// The clock starts when the block appears. A long-lived clock would lose precision.
    @State private var start = Date()
    /// Whether any part of the block's window can be seen. A closed panel or a library behind
    /// other windows keeps its views, and without this the light would go on drawing there.
    @State private var onScreen = true

    public init(_ ramp: LightRamp, radius: CGFloat = Radius.block, corners: RoundedCornerStyle = .circular,
                phase: Double = 0, still: Bool = false, easedThroughout: Bool = false) {
        self.ramp = ramp
        self.radius = radius
        self.corners = corners
        self.phase = phase
        self.still = still
        self.easedThroughout = easedThroughout
    }

    public var body: some View {
        let holds = reduceMotion || still
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: holds || !onScreen)) { timeline in
            GeometryReader { proxy in
                let elapsed = holds ? 0 : timeline.date.timeIntervalSince(start)
                Rectangle()
                    .fill(shader(size: proxy.size, time: Self.opening + phase + elapsed * Self.speed))
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: corners))
            }
        }
        .background(WindowVisibility(isVisible: $onScreen))
        .accessibilityHidden(true)
    }

    /// Where on the clock a block starts, and how fast the clock runs.
    private static let opening = 30.0
    private static let speed = 2.0

    private func shader(size: CGSize, time: Double) -> Shader {
        ShaderLibrary.bundle(.module).lightField(
            .float2(size),
            .float(time),
            .float(displayScale),
            .float(radius),
            .floatArray(ramp.lut),
            // which way the bands run (radians from top-to-bottom), how far they wrap round the
            // edge, how much the text's side is eased, and whether the text is dark
            .float4(0.6, 1, 0.8, ramp.ink == .dark ? 1 : 0),
            // edge light, grain, seed, eased throughout
            .float4(0.8, 0.012, 0, easedThroughout ? 1 : 0)
        )
    }
}

public extension Tone {
    /// The light this tone has as a block. A quiet block has none and stays a flat grey.
    var ramp: LightRamp? {
        switch self {
        case .rest: .meadow
        case .new: .rose
        case .attention: .orchid
        case .quiet: nil
        }
    }

    /// Text on the block. On a block of light it follows the ramp's calm end, in both appearances.
    var blockForeground: Color {
        guard let ramp else { return foreground }
        return ramp.ink == .dark ? Palette.inkFixed : .white
    }

    var blockSecondary: Color {
        guard let ramp else { return secondary }
        return ramp.ink == .dark ? Palette.inkFixed.opacity(0.66) : Color.white.opacity(0.72)
    }

    /// The block's background: light where the tone has a ramp, the flat tone otherwise.
    @MainActor @ViewBuilder func blockBackground(radius: CGFloat = Radius.block, phase: Double = 0) -> some View {
        if let ramp {
            LightField(ramp, radius: radius, phase: phase)
        } else {
            RoundedRectangle(cornerRadius: radius, style: .circular).fill(background)
        }
    }
}

/// Reports whether the window a view sits in can be seen: on screen, ordered in, and not
/// fully covered. Follows the window's occlusion state, which macOS updates as windows move.
struct WindowVisibility: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.onChange = { visible in
            // Reported from AppKit; the binding is changed after the current update.
            DispatchQueue.main.async { if isVisible != visible { isVisible = visible } }
        }
        return probe
    }

    func updateNSView(_ nsView: Probe, context: Context) {}

    final class Probe: NSView {
        var onChange: (Bool) -> Void = { _ in }
        private weak var watched: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let center = NotificationCenter.default
            if let watched {
                center.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: watched)
                center.removeObserver(self, name: NSWindow.willCloseNotification, object: watched)
            }
            watched = window
            guard let window else { onChange(false); return }
            center.addObserver(self, selector: #selector(occlusionChanged), name: NSWindow.didChangeOcclusionStateNotification, object: window)
            center.addObserver(self, selector: #selector(windowWillClose), name: NSWindow.willCloseNotification, object: window)
            onChange(window.occlusionState.contains(.visible))
        }

        @objc private func occlusionChanged() {
            onChange(window?.occlusionState.contains(.visible) ?? false)
        }

        @objc private func windowWillClose() {
            onChange(false)
        }
    }
}
