import SwiftUI
import UIKit

/// Colours come from the stones of Naples. Each has exactly one job (see design/README).
enum Palette {
    static let piperno = Color("Piperno")          // ink, primary buttons
    static let tufo = Color("Tufo")                // brand + reward moments only
    static let tufoSoft = Color("TufoSoft")
    static let azzurro = Color("Azzurro")          // interactive, links
    static let azzurroSoft = Color("AzzurroSoft")
    static let maiolica = Color("Maiolica")        // verified facts only
    static let maiolicaSoft = Color("MaiolicaSoft")
    static let pompei = Color("Pompei")            // legends and theories, never wrong answers
    static let pompeiSoft = Color("PompeiSoft")
    static let calce = Color("Calce")              // backgrounds
    static let card = Color("Card")
    static let stone = Color("Stone")
    static let hair = Color("Hair")
    static let sunk = Color("Sunk")
    static let mare = Color("Mare")
    /// Text placed on Tufo is always dark, in both appearances.
    static let onTufo = Color(red: 0.12, green: 0.14, blue: 0.13)
}

/// Apple's system typeface (SF Pro), so the app reads like it belongs on the phone.
/// Sizes scale with Dynamic Type through UIFontMetrics.
enum Typeface {
    /// Big headings, questions and answers.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        scaled(size, weight: .bold, design: .default, style: style)
    }
    static func displayBold(_ size: CGFloat, relativeTo style: Font.TextStyle = .headline) -> Font {
        scaled(size, weight: .semibold, design: .default, style: style)
    }
    /// Short friendly reactions ("Spot on!"): SF Pro Rounded.
    static func hand(_ size: CGFloat) -> Font {
        scaled(size, weight: .semibold, design: .rounded, style: .title3)
    }

    private static func scaled(_ size: CGFloat, weight: UIFont.Weight, design: UIFontDescriptor.SystemDesign, style: Font.TextStyle) -> Font {
        var font = UIFont.systemFont(ofSize: size, weight: weight)
        if let d = font.fontDescriptor.withDesign(design) { font = UIFont(descriptor: d, size: size) }
        return Font(UIFontMetrics(forTextStyle: style.uiKit).scaledFont(for: font))
    }
}

private extension Font.TextStyle {
    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}

enum Motion {
    /// Springy arrival used for answers, stickers and pins.
    static let pop = Animation.spring(response: 0.5, dampingFraction: 0.62)
    /// iOS-like ease for sheets and pushes.
    static let glide = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.55)
    static func stagger(_ index: Int, base: Double = 0, step: Double = 0.08) -> Double { base + Double(index) * step }
}

extension View {
    /// Applies an animation unless the person has asked for reduced motion.
    func motion(_ animation: Animation?, value: some Equatable, reduce: Bool) -> some View {
        self.animation(reduce ? .easeInOut(duration: 0.01) : animation, value: value)
    }
}
