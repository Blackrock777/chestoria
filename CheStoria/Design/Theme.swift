import SwiftUI

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

enum Typeface {
    /// Bricolage Grotesque ExtraBold: questions, answers, big headings.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("BricolageGrotesque-ExtraBold", size: size, relativeTo: style)
    }
    static func displayBold(_ size: CGFloat, relativeTo style: Font.TextStyle = .headline) -> Font {
        .custom("BricolageGrotesque-Bold", size: size, relativeTo: style)
    }
    /// Kalam: one-line handwritten reactions only.
    static func hand(_ size: CGFloat) -> Font {
        .custom("Kalam-Bold", size: size, relativeTo: .title3)
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
