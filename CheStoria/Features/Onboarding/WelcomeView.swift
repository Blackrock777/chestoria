import SwiftUI

/// One screen, no account. The site's photo drifts in slowly while the headline rises word by word.
/// Every word on this screen comes from the content files.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var zoom: CGFloat = 1.16
    @State private var shown = false

    var body: some View {
        @Bindable var model = model
        let w = model.site.welcome, t = model.strings
        ZStack(alignment: .bottom) {
            CoverImage(w.image, anchor: w.imageAnchor)
                .scaleEffect(zoom, anchor: UnitPoint(x: w.imageAnchor.x, y: 0.4))
                .ignoresSafeArea()
            LinearGradient(stops: [.init(color: .black.opacity(0.45), location: 0), .init(color: .clear, location: 0.22),
                                   .init(color: .clear, location: 0.42), .init(color: Color(red: 0.04, green: 0.05, blue: 0.05).opacity(0.88), location: 0.72),
                                   .init(color: Color(red: 0.04, green: 0.05, blue: 0.05).opacity(0.97), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Circle().fill(Palette.tufo).frame(width: 8, height: 8)
                    Text(w.eyebrow).font(.system(size: 13, weight: .semibold)).textCase(.uppercase).kerning(0.5)
                }
                .foregroundStyle(.white.opacity(0.8))
                .rise(shown, delay: 0.1)

                WordFlow(words: w.headline.split(separator: " ").map(String.init), shown: shown, reduce: reduce)
                    .id(w.headline)

                Text(w.body).font(.system(size: 17)).foregroundStyle(.white.opacity(0.8))
                    .rise(shown, delay: 0.75)

                Button { model.showLanguagePicker = true } label: {
                    HStack {
                        Text(t("welcome.storiesIn", t("lang.name")))
                        Spacer()
                        Text(t("common.change")).foregroundStyle(Palette.tufo)
                    }
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 52)
                    .contentShape(Rectangle())
                }
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
                .rise(shown, delay: 0.85)

                Button(t("welcome.start")) { Haptics.tap(); model.completeOnboarding() }
                    .buttonStyle(CTAButtonStyle(kind: .light))
                    .rise(shown, delay: 0.95)

                Text(t("welcome.noAccount")).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity).rise(shown, delay: 1.05)
            }
            .padding(.horizontal, 24).padding(.bottom, 12)
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 8) {
                ZStack { RoundedRectangle(cornerRadius: 7).fill(Palette.tufo); Circle().fill(Color(red: 0.17, green: 0.19, blue: 0.18)).padding(6) }
                    .frame(width: 24, height: 24)
                Text("CheStoria").font(Typeface.display(18))
            }
            .foregroundStyle(.white).padding(.leading, 24).padding(.top, 8)
            .opacity(shown ? 1 : 0)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(reduce ? nil : .easeOut(duration: 9)) { zoom = 1 }
            withAnimation(.easeOut(duration: 0.6)) { shown = true }
        }
    }
}

/// Headline that rises in word by word with a spring.
private struct WordFlow: View {
    let words: [String]
    let shown: Bool
    let reduce: Bool
    @State private var appeared = false
    var body: some View {
        FlowLayout(spacing: 11, lineSpacing: 0) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                Text(w).font(Typeface.display(44, relativeTo: .largeTitle)).foregroundStyle(.white)
                    .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 26)
                    .animation(reduce ? nil : Motion.pop.delay(0.25 + Double(i) * 0.07), value: shown)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(words.joined(separator: " "))
        .accessibilityAddTraits(.isHeader)
    }
}

/// Simple wrapping layout for the word-by-word headline.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 4
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, p) in arrange(bounds.width, subviews).points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        var pts: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > width { x = 0; y += lineH + lineSpacing; lineH = 0 }
            pts.append(CGPoint(x: x, y: y)); x += sz.width + spacing; lineH = max(lineH, sz.height); maxX = max(maxX, x - spacing)
        }
        return (pts, CGSize(width: maxX, height: y + lineH))
    }
}

extension View {
    /// Fade-and-rise entrance used across the app.
    func rise(_ shown: Bool, delay: Double, distance: CGFloat = 16) -> some View {
        modifier(RiseModifier(shown: shown, delay: delay, distance: distance))
    }
}

private struct RiseModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduce
    let shown: Bool, delay: Double, distance: CGFloat
    func body(content: Content) -> some View {
        content.opacity(shown ? 1 : 0).offset(y: shown || reduce ? 0 : distance)
            .animation(reduce ? .easeOut(duration: 0.2) : .timingCurve(0.32, 0.72, 0, 1, duration: 0.6).delay(delay), value: shown)
    }
}
