import AppKit
import CoreText
import SwiftUI

/// Registers the bundled font files and reports which faces are really available.
@MainActor
public enum SkilloriFonts {
    public private(set) static var hasDots = false
    public private(set) static var hasInter = false
    public private(set) static var hasGeistMono = false
    private static var registered = false

    public static func register() {
        guard !registered else { return }
        registered = true
        if let folder = Bundle.module.url(forResource: "Fonts", withExtension: nil),
           let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for file in files where ["ttf", "otf"].contains(file.pathExtension.lowercased()) {
                CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
            }
        }
        hasDots = NSFont(name: "icomoon", size: 12) != nil
        hasInter = NSFontManager.shared.availableFontFamilies.contains("Inter")
        hasGeistMono = NSFontManager.shared.availableFontFamilies.contains("Geist Mono")
    }
}

/// Type roles. Dots for big numbers, sans for names and text, mono for labels and data.
/// The heaviest weight anywhere is medium.
@MainActor
public enum TypeRole {
    public static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        face("Inter", size, weight, available: SkilloriFonts.hasInter) ?? .system(size: size, weight: weight)
    }

    public static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        face("Geist Mono", size, weight, available: SkilloriFonts.hasGeistMono)
            ?? .system(size: size, weight: weight, design: .monospaced)
    }

    /// Picks the family member for a weight. Both families are variable fonts, so the
    /// weight has to be resolved through the font manager rather than by a face name.
    private static func face(_ family: String, _ size: CGFloat, _ weight: Font.Weight, available: Bool) -> Font? {
        guard available else { return nil }
        // NSFontManager's scale: 3 light, 5 regular, 6 medium.
        let step = weight == .medium ? 6 : weight == .light ? 3 : 5
        guard let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: step, size: size) else {
            return nil
        }
        return Font(font)
    }

    public static func dots(_ size: CGFloat) -> Font {
        SkilloriFonts.hasDots ? .custom("icomoon", fixedSize: size) : mono(size * 0.8, .light)
    }
}

/// Mono caps, 10 pt, +6 %. For labels above things.
public struct LabelText: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text.uppercased()).font(TypeRole.mono(10)).tracking(0.6).lineLimit(1)
    }
}

/// A label whose words change now and then, such as when the sources were last asked: the
/// old words leave with a slight blur as the new ones arrive.
public struct SwappingLabel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let text: String
    let alignment: Alignment
    public init(_ text: String, alignment: Alignment = .leading) {
        self.text = text
        self.alignment = alignment
    }
    public var body: some View {
        ZStack(alignment: alignment) {
            LabelText(text).id(text).transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
        }
        .animation(Motion.swap, value: text)
    }
}

/// Mono 10.5 pt. For technical and numeric data.
public struct DataText: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text).font(TypeRole.mono(10.5)).lineLimit(1)
    }
}

/// A big number in the dot font. The font only has capitals, digits and a few signs.
/// Several characters get one empty dot column between them (21 %); the font's own
/// spacing lets digits touch.
public struct DotNumber: View {
    let text: String
    let size: CGFloat
    public init(_ text: String, size: CGFloat = 88) {
        self.text = text.uppercased()
        self.size = size
    }
    public var body: some View {
        Text(text)
            .font(TypeRole.dots(size))
            .tracking(text.count > 1 ? size * 0.21 : 0)
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel(text)
    }
}
