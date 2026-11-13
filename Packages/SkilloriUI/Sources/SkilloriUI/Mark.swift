import AppKit
import SwiftUI

/// The Skillori mark, version 2.
///
/// Drawn on a 7 × 7 grid of 100-unit circles with a 20-unit gap (820 × 820 in all).
/// The outermost ring of cells is the safe zone and stays empty, so the symbol itself
/// uses the inner 5 × 5 cells (580 × 580): twelve dots and a © in the upper right cell.
public struct SkilloriMark: Shape {
    /// Dot positions on the inner 5 × 5 grid, column and row 0–4.
    public static let dots: [(col: Int, row: Int)] = [
        (1, 0), (2, 0), (3, 0),
        (0, 1),
        (1, 2), (2, 2), (3, 2),
        (0, 3), (4, 3),
        (1, 4), (2, 4), (3, 4),
    ]
    /// The cell that holds the © instead of a dot.
    public static let signCell: (col: Int, row: Int) = (4, 1)

    static let dot: CGFloat = 100
    static let pitch: CGFloat = 120
    static let symbolSide: CGFloat = 580
    static let fullSide: CGFloat = 820

    /// With the safe zone the shape fills its rect as the 820 grid; without it, as the 580 symbol.
    public var safeZone: Bool

    public init(safeZone: Bool = false) {
        self.safeZone = safeZone
    }

    public func path(in rect: CGRect) -> Path {
        let side = safeZone ? Self.fullSide : Self.symbolSide
        let scale = min(rect.width, rect.height) / side
        let inset: CGFloat = safeZone ? Self.pitch : 0
        var path = Path()
        for dot in Self.dots {
            path.addEllipse(in: Self.cell(dot.col, dot.row, inset: inset))
        }
        let sign = Self.cell(Self.signCell.col, Self.signCell.row, inset: inset)
        path.addPath(Self.copyrightSign, transform: CGAffineTransform(translationX: sign.minX, y: sign.minY))
        let transform = CGAffineTransform(translationX: rect.midX - side * scale / 2, y: rect.midY - side * scale / 2)
            .scaledBy(x: scale, y: scale)
        return path.applying(transform)
    }

    private static func cell(_ col: Int, _ row: Int, inset: CGFloat) -> CGRect {
        CGRect(x: inset + CGFloat(col) * pitch, y: inset + CGFloat(row) * pitch, width: dot, height: dot)
    }

    /// The © outline from the Figma sketch, in a 100 × 100 cell.
    static let copyrightSign: Path = {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        var path = Path()
        path.move(to: p(22.775, 49.999))
        path.addCurve(to: p(26.515, 36.079), control1: p(22.775, 44.917), control2: p(24.022, 40.277))
        path.addCurve(to: p(36.506, 26.089), control1: p(29.009, 31.881), control2: p(32.339, 28.551))
        path.addCurve(to: p(50.426, 22.348), control1: p(40.704, 23.595), control2: p(45.344, 22.348))
        path.addCurve(to: p(62.689, 25.236), control1: p(54.845, 22.348), control2: p(58.933, 23.311))
        path.addCurve(to: p(72.017, 33.049), control1: p(66.446, 27.13), control2: p(69.555, 29.735))
        path.addCurve(to: p(76.515, 44.223), control1: p(74.479, 36.363), control2: p(75.978, 40.088))
        path.addLine(to: p(64.204, 44.223))
        path.addCurve(to: p(59.375, 37.026), control1: p(63.636, 41.287), control2: p(62.026, 38.888))
        path.addCurve(to: p(50.426, 34.185), control1: p(56.755, 35.132), control2: p(53.772, 34.185))
        path.addCurve(to: p(42.472, 36.316), control1: p(47.522, 34.185), control2: p(44.871, 34.895))
        path.addCurve(to: p(36.743, 42.045), control1: p(40.073, 37.736), control2: p(38.163, 39.646))
        path.addCurve(to: p(34.612, 49.999), control1: p(35.322, 44.412), control2: p(34.612, 47.064))
        path.addCurve(to: p(36.743, 57.954), control1: p(34.612, 52.903), control2: p(35.322, 55.555))
        path.addCurve(to: p(42.472, 63.683), control1: p(38.163, 60.353), control2: p(40.073, 62.263))
        path.addCurve(to: p(50.426, 65.814), control1: p(44.871, 65.103), control2: p(47.522, 65.814))
        path.addCurve(to: p(58.996, 63.02), control1: p(53.772, 65.814), control2: p(56.629, 64.882))
        path.addCurve(to: p(63.447, 55.776), control1: p(61.364, 61.126), control2: p(62.847, 58.711))
        path.addLine(to: p(75.757, 55.776))
        path.addCurve(to: p(71.449, 66.95), control1: p(75.221, 59.911), control2: p(73.784, 63.636))
        path.addCurve(to: p(62.5, 74.81), control1: p(69.113, 70.264), control2: p(66.13, 72.884))
        path.addCurve(to: p(50.426, 77.651), control1: p(58.87, 76.704), control2: p(54.845, 77.651))
        path.addCurve(to: p(36.506, 73.957), control1: p(45.344, 77.651), control2: p(40.704, 76.42))
        path.addCurve(to: p(26.515, 63.92), control1: p(32.339, 71.464), control2: p(29.009, 68.118))
        path.addCurve(to: p(22.775, 49.999), control1: p(24.022, 59.722), control2: p(22.775, 55.081))
        path.closeSubpath()
        path.move(to: p(50, 99.999))
        path.addCurve(to: p(30.587, 96.116), control1: p(43.119, 99.999), control2: p(36.648, 98.705))
        path.addCurve(to: p(14.631, 85.368), control1: p(24.558, 93.528), control2: p(19.24, 89.945))
        path.addCurve(to: p(3.836, 69.412), control1: p(10.054, 80.76), control2: p(6.456, 75.441))
        path.addCurve(to: p(0.001, 49.999), control1: p(1.247, 63.383), control2: p(-0.031, 56.912))
        path.addCurve(to: p(3.93, 30.587), control1: p(0.032, 43.087), control2: p(1.342, 36.616))
        path.addCurve(to: p(14.726, 14.678), control1: p(6.55, 24.558), control2: p(10.149, 19.255))
        path.addCurve(to: p(30.635, 3.883), control1: p(19.303, 10.069), control2: p(24.606, 6.471))
        path.addCurve(to: p(50, 0), control1: p(36.664, 1.294), control2: p(43.119, 0))
        path.addCurve(to: p(69.413, 3.883), control1: p(56.913, 0), control2: p(63.384, 1.294))
        path.addCurve(to: p(85.322, 14.678), control1: p(75.473, 6.471), control2: p(80.776, 10.069))
        path.addCurve(to: p(96.07, 30.587), control1: p(89.899, 19.255), control2: p(93.481, 24.558))
        path.addCurve(to: p(99.999, 49.999), control1: p(98.658, 36.616), control2: p(99.968, 43.087))
        path.addCurve(to: p(96.164, 69.412), control1: p(100.031, 56.912), control2: p(98.753, 63.383))
        path.addCurve(to: p(85.416, 85.368), control1: p(93.576, 75.441), control2: p(89.993, 80.76))
        path.addCurve(to: p(69.46, 96.116), control1: p(80.839, 89.945), control2: p(75.521, 93.528))
        path.addCurve(to: p(50, 99.999), control1: p(63.399, 98.705), control2: p(56.913, 99.999))
        path.closeSubpath()
        path.move(to: p(50, 87.404))
        path.addCurve(to: p(64.583, 84.516), control1: p(55.177, 87.404), control2: p(60.038, 86.442))
        path.addCurve(to: p(76.515, 76.514), control1: p(69.129, 82.591), control2: p(73.106, 79.923))
        path.addCurve(to: p(84.564, 64.583), control1: p(79.955, 73.074), control2: p(82.639, 69.096))
        path.addCurve(to: p(87.405, 50.047), control1: p(86.489, 60.037), control2: p(87.436, 55.192))
        path.addCurve(to: p(84.469, 35.464), control1: p(87.405, 44.87), control2: p(86.426, 40.009))
        path.addCurve(to: p(76.42, 23.532), control1: p(82.544, 30.918), control2: p(79.861, 26.941))
        path.addCurve(to: p(64.536, 15.483), control1: p(73.011, 20.091), control2: p(69.05, 17.408))
        path.addCurve(to: p(50, 12.595), control1: p(60.022, 13.557), control2: p(55.177, 12.595))
        path.addCurve(to: p(35.512, 15.483), control1: p(44.855, 12.595), control2: p(40.025, 13.557))
        path.addCurve(to: p(23.58, 23.532), control1: p(30.998, 17.408), control2: p(27.02, 20.091))
        path.addCurve(to: p(15.531, 35.511), control1: p(20.171, 26.973), control2: p(17.488, 30.966))
        path.addCurve(to: p(12.595, 50.047), control1: p(13.574, 40.025), control2: p(12.595, 44.87))
        path.addCurve(to: p(15.436, 64.535), control1: p(12.564, 55.16), control2: p(13.511, 59.99))
        path.addCurve(to: p(23.485, 76.467), control1: p(17.393, 69.049), control2: p(20.076, 73.026))
        path.addCurve(to: p(35.417, 84.516), control1: p(26.926, 79.876), control2: p(30.903, 82.559))
        path.addCurve(to: p(50, 87.404), control1: p(39.962, 86.442), control2: p(44.823, 87.404))
        path.closeSubpath()
        return path
    }()
}

public extension SkilloriMark {
    enum MenuBarState: Sendable { case rest, attention, stale }

    /// Image for the menu bar: the full grid with its safe zone.
    ///
    /// At rest and when stale it is a template image, so the system colours it for the bar
    /// it sits on. `attention` is the one state with a colour of its own: the mark in ink
    /// on a lilac plate, the same block the app uses for "needs you".
    @MainActor
    static func menuBarImage(_ state: MenuBarState = .rest, side: CGFloat = 22) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            var ink = NSColor.black.withAlphaComponent(state == .stale ? 0.4 : 1)
            if state == .attention {
                let radius = side * 5 / 22
                context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
                context.setFillColor(NSColor(srgbRed: 0xB5 / 255, green: 0x92 / 255, blue: 0xFF / 255, alpha: 1).cgColor)
                context.fillPath()
                ink = NSColor(srgbRed: 0x15 / 255, green: 0x15 / 255, blue: 0x16 / 255, alpha: 1)
            }
            context.addPath(SkilloriMark(safeZone: true).path(in: rect).cgPath)
            context.setFillColor(ink.cgColor)
            context.fillPath()
            return true
        }
        image.isTemplate = state != .attention
        image.accessibilityDescription = "Skillori"
        return image
    }
}
