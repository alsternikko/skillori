import AppKit
import SwiftUI

/// Colour, corner and spacing tokens for the "Readout" direction
/// (docs/design/visuell-riktning-readout-2026-11-12.md).
public enum Palette {
    public static let ground = Color(light: 0xE6E6E8, dark: 0x0E0E0F)
    public static let panel = Color(light: 0xF1F1F3, dark: 0x19191B)
    public static let card = Color(light: 0xFAFAFB, dark: 0x242427)
    public static let softBlock = Color(light: 0xDCDCE0, dark: 0x2E2E32)
    public static let line = Color(light: 0xEBEBEE, dark: 0x303034)
    public static let ink = Color(light: 0x151516, dark: 0xF1F1F3)
    public static let ink2 = Color(light: 0x6B6B70, dark: 0xA3A3A8)
    public static let ink3 = Color(light: 0xA3A3A8, dark: 0x6B6B70)
    /// Text and marks on a filled control; flips with `ink`.
    public static let onInk = Color(light: 0xFFFFFF, dark: 0x151516)

    public static let charcoal = Color(hex: 0x1E1E1F)
    public static let lime = Color(hex: 0xBDF24B)
    public static let lilac = Color(hex: 0xB592FF)
    /// Fixed near-black for text on lime and lilac, in both appearances.
    public static let inkFixed = Color(hex: 0x151516)
}

/// Corner radii. Every corner the app draws itself is a plain circular arc, as in the design
/// sketches; only the app icon uses the softer macOS shape.
public enum Radius {
    public static let panel: CGFloat = 16
    public static let block: CGFloat = 10
    public static let row: CGFloat = 8
    /// Buttons, fields and segmented controls.
    public static let control: CGFloat = 6
    /// Status chips and key caps.
    public static let chip: CGFloat = 4
}

/// What a block says. Colour carries the state, so text on it stays black or white.
public enum Tone: Sendable {
    /// At rest. Charcoal in light mode, light in dark mode.
    case rest
    /// Something new.
    case new
    /// Needs you.
    case attention
    /// No reading or nothing to say yet.
    case quiet

    public var background: Color {
        switch self {
        case .rest: Color(light: 0x1E1E1F, dark: 0xF1F1F3)
        case .new: Palette.lime
        case .attention: Palette.lilac
        case .quiet: Palette.softBlock
        }
    }

    public var foreground: Color {
        switch self {
        case .rest: Color(light: 0xFFFFFF, dark: 0x151516)
        case .new, .attention: Palette.inkFixed
        case .quiet: Palette.ink
        }
    }

    public var secondary: Color {
        switch self {
        case .rest: Color(light: 0xFFFFFF, dark: 0x151516).opacity(0.6)
        case .new, .attention: Palette.inkFixed.opacity(0.62)
        case .quiet: Palette.ink2
        }
    }
}

public extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}
