import SwiftUI

/// Hot/cold feedback for the detail hunt. Pure so it can be unit tested.
struct HuntFeedback: Equatable {
    static let foundRadius: CGFloat = 46

    let distance: CGFloat

    var isFound: Bool { distance < Self.foundRadius }
    /// Seconds per pulse: slow when far, fast when close.
    var pulseInterval: Double { Double(max(0.28, min(1.6, distance / 150))) }
    /// 0 (far) ... 1 (on target), used for haptic intensity.
    var closeness: CGFloat { max(0, min(1, 1 - distance / 320)) }
    /// Key into the interface strings ("closer.hot" → "hot!").
    var labelKey: String {
        switch distance {
        case ..<Self.foundRadius: "closer.found"
        case ..<90: "closer.hot"
        case ..<160: "closer.warmer"
        case ..<260: "closer.warm"
        default: "closer.colder"
        }
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}

/// Photographing a detail protects the memory of it (Henkel 2014). Haptic pulses speed up as you
/// get close, so the hunt works without reading anything.
struct LookCloserView: View {
    let look: LookCloser
    let onSnap: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var photo: UIImage?
    @State private var ring: CGPoint?
    @State private var aim: CGPoint?
    @State private var found = false
    @State private var showTip = false
    @State private var flash = 0
    @State private var shown = false

    var body: some View {
        let t = model.strings
        let imageSize = (photo ?? ImageLoader.shared.cached(look.image))?.size ?? CGSize(width: 3, height: 2)
        GeometryReader { geo in
            let layout = CoverLayout(imageSize: imageSize, container: geo.size,
                                     anchor: CGPoint(x: look.anchor.x, y: look.anchor.y), zoom: look.zoom)
            let target = layout.point(look.target)
            let pos = ring ?? CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.47)
            let fb = HuntFeedback(distance: HuntFeedback.distance(pos, target))

            ZStack(alignment: .topLeading) {
                CoverImage(look.image, anchor: look.anchor, zoom: look.zoom)
                RadialGradient(colors: [.clear, .black.opacity(0.55)], center: .init(x: 0.5, y: 0.55), startRadius: geo.size.width * 0.45, endRadius: geo.size.height * 0.75)
                LinearGradient(stops: [.init(color: .black.opacity(0.5), location: 0), .init(color: .clear, location: 0.25),
                                       .init(color: .clear, location: 0.7), .init(color: .black.opacity(0.55), location: 1)], startPoint: .top, endPoint: .bottom)

                PulsingRing(interval: found ? 0.9 : fb.pulseInterval, found: found, reduce: reduce)
                    .position(pos)
                    .opacity(shown ? 1 : 0).scaleEffect(shown ? 1 : 0.4)
                    .animation(Motion.pop.delay(0.3), value: shown)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in if !found { aim = v.location } })
            .overlay(alignment: .top) {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t("closer.eyebrow")).font(.system(size: 11, weight: .bold)).textCase(.uppercase).kerning(1.2).foregroundStyle(Palette.tufo)
                        Text(look.prompt).font(Typeface.display(20)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: 26))
                    .rise(shown, delay: 0.1)

                    Text(aim == nil && !found ? t("closer.drag") : t(fb.labelKey))
                        .font(Typeface.hand(24)).foregroundStyle(.white)
                        .padding(.horizontal, 18).frame(height: 44)
                        .glassEffect(.regular, in: .capsule)
                        .contentTransition(.opacity)
                        .animation(.easeOut(duration: 0.2), value: fb.labelKey)
                    if showTip && !found {
                        Text(look.hint).font(.system(size: 13)).foregroundStyle(.white.opacity(0.85)).transition(.opacity)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 112)
            }
            .overlay(alignment: .bottom) {
                ShutterButton(enabled: found, glowing: found) {
                    flash += 1; Haptics.rigid()
                    Task { try? await Task.sleep(for: .milliseconds(160)); onSnap() }
                }
                .padding(.bottom, 72)
            }
            .task(id: geo.size.width + imageSize.width) { await follow(target: target, start: pos) }
            .task(id: found) { await hapticPulses(target: target) }
        }
        .overlay { FlashOverlay(trigger: flash) }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear { shown = true }
        .task { if photo == nil { photo = await ImageLoader.shared.load(look.image) } }
        .task { try? await Task.sleep(for: .seconds(6)); withAnimation { showTip = true } }
    }

    /// Ring eases towards the finger every frame; locks onto the target once found.
    private func follow(target: CGPoint, start: CGPoint) async {
        var p = start
        #if DEBUG
        if DebugLaunch.autoSolve { aim = target }
        #endif
        while !Task.isCancelled {
            let goal = found ? target : (aim ?? p)
            p.x += (goal.x - p.x) * 0.22; p.y += (goal.y - p.y) * 0.22
            ring = p
            if !found, HuntFeedback(distance: HuntFeedback.distance(p, target)).isFound {
                withAnimation(Motion.pop) { found = true }
                Haptics.success()
            }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    private func hapticPulses(target: CGPoint) async {
        guard !found else { return }
        while !Task.isCancelled && !found {
            guard let r = ring, aim != nil else { try? await Task.sleep(for: .milliseconds(300)); continue }
            let fb = HuntFeedback(distance: HuntFeedback.distance(r, target))
            Haptics.pulse(intensity: 0.3 + fb.closeness * 0.7)
            try? await Task.sleep(for: .seconds(fb.pulseInterval))
        }
    }
}

private struct PulsingRing: View {
    let interval: Double
    let found: Bool
    let reduce: Bool

    var body: some View {
        TimelineView(.animation(paused: reduce)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let colour: Color = found ? .white : Palette.tufo
            ZStack {
                ForEach(0..<2, id: \.self) { k in
                    let phase = ((t / interval) + Double(k) * 0.5).truncatingRemainder(dividingBy: 1)
                    Circle().stroke(colour, lineWidth: 4).frame(width: 120, height: 120)
                        .scaleEffect(1 + phase * 0.9).opacity(0.7 * (1 - phase))
                }
                Circle().fill(found ? Palette.tufo.opacity(0.18) : .clear)
                    .overlay(Circle().stroke(colour, lineWidth: 4))
                    .frame(width: 120, height: 120)
                    .scaleEffect(found ? 1 : 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Sticker earned

/// The detail photo peels into a die-cut sticker (CapWords) that tilts towards your finger (Any Distance).
struct StickerEarnedView: View {
    let sticker: Sticker
    var photo: UIImage? = nil
    let onKeepExploring: () -> Void
    let onSeeAll: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var arrived = false
    @State private var shown = false
    @State private var tilt: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            Text(model.strings("sticker.new")).font(.system(size: 11, weight: .bold)).textCase(.uppercase).kerning(0.6)
                .foregroundStyle(Palette.onTufo).padding(.horizontal, 12).frame(height: 28)
                .background(Palette.tufo, in: .capsule)
                .scaleEffect(shown ? 1 : 0).animation(Motion.pop.delay(0.8), value: shown)
                .padding(.top, 40)

            StickerArt(sticker: sticker, sheen: tilt.width / 120, photo: photo)
                .frame(width: 270, height: 190)
                .rotation3DEffect(.degrees(Double(-tilt.height / 6)), axis: (1, 0, 0))
                .rotation3DEffect(.degrees(Double(tilt.width / 6)), axis: (0, 1, 0))
                .rotationEffect(.degrees(arrived ? -5 : -40))
                .scaleEffect(arrived ? 1 : 0.25)
                .offset(y: arrived ? 0 : 240)
                .opacity(arrived ? 1 : 0)
                .padding(.top, 56)
                .gesture(DragGesture().onChanged { v in tilt = CGSize(width: max(-120, min(120, v.translation.width)), height: max(-120, min(120, v.translation.height))) }
                    .onEnded { _ in withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) { tilt = .zero } })

            Text(sticker.title).font(Typeface.display(38, relativeTo: .largeTitle)).foregroundStyle(Palette.piperno)
                .multilineTextAlignment(.center).padding(.top, 52).rise(shown, delay: 0.9)
            Text(model.strings("sticker.addedTo", sticker.collection))
                .font(.system(size: 16)).foregroundStyle(Palette.stone).padding(.top, 10).rise(shown, delay: 1.0)
            Spacer()
            VStack(spacing: 14) {
                Button(model.strings("sticker.keepExploring"), action: onKeepExploring).buttonStyle(CTAButtonStyle(kind: .dark))
                Button(model.strings("sticker.seeAll"), action: onSeeAll).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.azzurro)
            }
            .rise(shown, delay: 1.1)
        }
        .padding(.horizontal, 24).padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RadialGradient(colors: [Color(red: 1, green: 0.96, blue: 0.85), Palette.calce], center: .init(x: 0.5, y: 0.3), startRadius: 0, endRadius: 420).ignoresSafeArea())
        .preferredColorScheme(.light)
        .onAppear {
            shown = true
            withAnimation(reduce ? nil : .spring(response: 0.75, dampingFraction: 0.6).delay(0.1)) { arrived = true }
            Task { try? await Task.sleep(for: .milliseconds(450)); Haptics.rigid() }
        }
    }
}
