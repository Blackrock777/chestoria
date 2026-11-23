import SwiftUI

/// Introduces the selected site before opening the guide.
/// Every word on this screen comes from the content files.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var zoom: CGFloat = 1.16
    @State private var shown = false
    @State private var showPrivacy = false

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
                    Text(model.welcomeEyebrow).font(.system(size: 13, weight: .semibold)).textCase(.uppercase).kerning(0.5)
                }
                .foregroundStyle(.white.opacity(0.8))
                .rise(shown, delay: 0.1)

                WordFlow(words: w.headline.split(separator: " ").map(String.init), shown: shown, reduce: reduce)
                    .id(w.headline)

                Text(w.body).font(.system(size: 17)).foregroundStyle(.white.opacity(0.8))
                    .rise(shown, delay: 0.75)

                if model.catalog.sites.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(t("welcome.where")).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                        HStack(spacing: 8) {
                            ForEach(model.catalog.sites) { s in
                                Button { Haptics.tap(); withAnimation(.easeInOut) { model.switchSite(to: s.id) } } label: {
                                    Text(s.city).font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(s.id == model.site.id ? Palette.onTufo : .white)
                                        .padding(.horizontal, 16).frame(height: 38)
                                        .background { if s.id == model.site.id { Capsule().fill(Palette.tufo) } }
                                }
                                .glassEffect(s.id == model.site.id ? .identity : .regular.interactive(), in: .capsule)
                            }
                        }
                    }
                    .rise(shown, delay: 0.8)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(t("welcome.selectLanguage")).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                    Menu {
                        Picker(t("lang.title"), selection: Binding(get: { model.language },
                                                                   set: { code in Haptics.tap(); withAnimation { model.setLanguage(code) } })) {
                            ForEach(model.languages, id: \.self) { Text(model.languageName($0)).tag($0) }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "globe").font(.title3)
                            Text(model.languageName(model.language)).font(.title3.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").font(.body.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).frame(height: 60)
                        .contentShape(Rectangle())
                    }
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                }
                .rise(shown, delay: 0.85)

                Button(t("welcome.start")) {
                    Haptics.tap()
                    model.completeOnboarding()
                }
                .buttonStyle(CTAButtonStyle(kind: .light))
                .rise(shown, delay: 0.95)

                Button(t("privacy.title")) { showPrivacy = true }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .rise(shown, delay: 0.95)
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
        .sheet(isPresented: $showPrivacy) { PrivacyPolicySheet() }
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
