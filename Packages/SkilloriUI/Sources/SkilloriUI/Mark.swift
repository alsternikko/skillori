import AppKit
import SwiftUI

/// The Skillori mark: an S of 15 equal dots on a 5 × 7 grid (rows 3, 2, 1, 3, 1, 2, 3).
/// Dot diameter is 92 % of the grid pitch.
public struct SkilloriMark: Shape {
    /// Grid positions, column 0–4 and row 0–6.
    public static let dots: [(col: Int, row: Int)] = [
        (1, 0), (2, 0), (3, 0),
        (0, 1), (4, 1),
        (0, 2),
        (1, 3), (2, 3), (3, 3),
        (4, 4),
        (0, 5), (4, 5),
        (1, 6), (2, 6), (3, 6),
    ]

    public init() {}

    public func path(in rect: CGRect) -> Path {
        let pitch = min(rect.width / 5, rect.height / 7)
        let origin = CGPoint(x: rect.midX - pitch * 2.5, y: rect.midY - pitch * 3.5)
        let d = pitch * 0.92
        var path = Path()
        for dot in Self.dots {
            let cx = origin.x + (CGFloat(dot.col) + 0.5) * pitch
            let cy = origin.y + (CGFloat(dot.row) + 0.5) * pitch
            path.addEllipse(in: CGRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d))
        }
        return path
    }
}

public extension SkilloriMark {
    enum MenuBarState: Sendable { case rest, attention, stale }

    /// Template image for the menu bar. `attention` swaps the upper right dot for a larger one.
    @MainActor
    static func menuBarImage(_ state: MenuBarState = .rest) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            let pitch: CGFloat = 2.2
            let origin = CGPoint(x: rect.midX - pitch * 2.5, y: rect.midY - pitch * 3.5)
            let d = pitch * 0.92
            NSColor.black.withAlphaComponent(state == .stale ? 0.4 : 1).setFill()
            for dot in dots {
                if state == .attention, dot.col == 4, dot.row == 1 { continue }
                let cx = origin.x + (CGFloat(dot.col) + 0.5) * pitch
                let cy = origin.y + (CGFloat(dot.row) + 0.5) * pitch
                NSBezierPath(ovalIn: CGRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d)).fill()
            }
            if state == .attention {
                let r: CGFloat = 2.4
                let cx = origin.x + 4.8 * pitch
                let cy = origin.y + 1.2 * pitch
                NSBezierPath(ovalIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Skillori"
        return image
    }
}
