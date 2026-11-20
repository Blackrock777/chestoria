import SwiftUI

/// Today's walk on a hand-drawn site map. Only places you found are shown, never what you missed.
struct TripView: View {
    @Environment(AppModel.self) private var model
    @State private var showSite = false
    @State private var drawn = false

    var body: some View {
        let visited = model.visitedPlaces
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("My trip").font(Typeface.display(36, relativeTo: .largeTitle)).foregroundStyle(Palette.piperno)
                    Spacer()
                    Button { showSite = true } label: {
                        Label("Pompeii · \(visited.count) secrets", systemImage: "ticket").font(.system(size: 14, weight: .medium))
                    }
                    .tint(Palette.azzurro)
                }
                .padding(.horizontal, 8)

                SiteMap(places: visited, drawn: drawn)
                    .aspectRatio(361.0 / 520.0, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 30))
                    .overlay(RoundedRectangle(cornerRadius: 30).stroke(Palette.hair, lineWidth: 1.5))

                HStack(spacing: 10) {
                    ForEach(Array(model.collectedStickers.prefix(2).enumerated()), id: \.element.sticker.id) { i, item in
                        HStack(spacing: 10) {
                            StickerArt(sticker: item.sticker, border: 3).frame(width: 44, height: 40)
                            Text(item.sticker.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.piperno)
                                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 10).frame(height: 64)
                        .background(Palette.card, in: .rect(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.hair, lineWidth: 1.5))
                        .rise(drawn, delay: 1.6 + Double(i) * 0.12)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .background(Palette.calce)
        .onAppear { drawn = false; DispatchQueue.main.async { drawn = true } }
        .sheet(isPresented: $showSite) { SiteSheet(site: model.content.site).presentationDetents([.large]).presentationCornerRadius(38) }
    }
}

/// The hand-drawn map. Drawn in a 361 × 520 design space and scaled to fit.
struct SiteMap: View {
    let places: [Place]
    let drawn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce

    private static let base = CGSize(width: 361, height: 520)

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / Self.base.width
            let pts = places.map { CGPoint(x: $0.mapPoint.x * Self.base.width * k, y: $0.mapPoint.y * Self.base.height * k) }
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in drawBase(ctx, k: k) }
                SmoothPath(points: pts)
                    .trim(from: 0, to: drawn ? 1 : 0)
                    .stroke(Palette.piperno, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [0.1, 9]))
                    .animation(reduce ? nil : .easeInOut(duration: 1.6).delay(0.4), value: drawn)
                ForEach(Array(places.enumerated()), id: \.element.id) { i, place in
                    let big = i == places.count - 1
                    ZStack {
                        Circle().fill(Palette.tufo).overlay(Circle().stroke(.white, lineWidth: 4)).shadow(color: .black.opacity(0.2), radius: 3, y: 3)
                        Circle().fill(Color(red: 0.17, green: 0.19, blue: 0.18)).padding(big ? 12 : 11)
                    }
                    .frame(width: big ? 36 : 32, height: big ? 36 : 32)
                    .scaleEffect(drawn ? 1 : 0.4).opacity(drawn ? 1 : 0).offset(y: drawn ? 0 : -40)
                    .animation(reduce ? nil : Motion.pop.delay(0.35 + Double(i) * 0.6), value: drawn)
                    .position(pts[i])
                    .accessibilityLabel(place.name)
                    if place.id != "forum" {
                        Text(place.name).font(.system(size: 11.5, weight: .bold)).foregroundStyle(Color(red: 0.17, green: 0.19, blue: 0.18))
                            .fixedSize()
                            .position(x: pts[i].x + (big ? -10 : 70) * k, y: pts[i].y + (big ? 28 : -26) * k)
                            .opacity(drawn ? 1 : 0).animation(.easeOut.delay(0.6 + Double(i) * 0.6), value: drawn)
                    }
                }
                if let last = pts.last { YouAreHere().position(x: last.x + 34 * k, y: last.y + 66 * k) }
            }
        }
        .background(Color(red: 0.98, green: 0.98, blue: 0.96))
        .environment(\.colorScheme, .light)
    }

    private func drawBase(_ ctx: GraphicsContext, k: CGFloat) {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }
        let wall: [CGPoint] = [p(60, 46), p(132, 26), p(250, 34), p(318, 70), p(338, 160), p(330, 300), p(300, 420), p(210, 470), p(96, 462), p(40, 380), p(26, 230), p(34, 120)]
        var w = Path(); w.addLines(wall); w.closeSubpath()
        ctx.fill(w, with: .color(Color(red: 0.957, green: 0.945, blue: 0.91)))
        ctx.stroke(w, with: .color(Color(red: 0.81, green: 0.79, blue: 0.73)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [2, 5]))
        let streets = [(p(40, 300), p(336, 278)), (p(48, 168), p(334, 150)), (p(196, 34), p(206, 466)), (p(110, 40), p(104, 450))]
        for (a, b) in streets {
            var s = Path(); s.move(to: a); s.addLine(to: b)
            ctx.stroke(s, with: .color(Color(red: 0.89, green: 0.875, blue: 0.83)), style: StrokeStyle(lineWidth: 10 * k, lineCap: .round))
        }
        var sea = Path(); sea.addLines([p(0, 300), p(18, 300), p(26, 340), p(18, 380), p(18, 520), p(0, 520)]); sea.closeSubpath()
        ctx.fill(sea, with: .color(Color(red: 0.86, green: 0.92, blue: 0.96)))
        ctx.fill(Path(roundedRect: CGRect(origin: p(62, 232), size: CGSize(width: 34 * k, height: 58 * k)), cornerRadius: 4), with: .color(Color(red: 0.94, green: 0.91, blue: 0.85)))
        var v = Path(); v.addLines([p(250, 34), p(284, 0), p(296, 10), p(308, -2), p(342, 34)]); v.closeSubpath()
        ctx.fill(v, with: .color(Color(red: 0.91, green: 0.9, blue: 0.85)))
        ctx.stroke(v, with: .color(Color(red: 0.72, green: 0.69, blue: 0.64)), lineWidth: 1.5)
        let grey = Color(red: 0.6, green: 0.62, blue: 0.61)
        ctx.draw(Text("Forum").font(.system(size: 10 * k, weight: .semibold)).foregroundStyle(Color(red: 0.42, green: 0.44, blue: 0.43)), at: p(70, 222))
        ctx.draw(Text("Vesuvius ↗").font(.system(size: 9 * k, weight: .semibold)).foregroundStyle(Color(red: 0.42, green: 0.44, blue: 0.43)), at: p(296, 46))
        var t = ctx; t.translateBy(x: 190 * k, y: 310 * k); t.rotate(by: .degrees(-4))
        t.draw(Text("VIA DELL’ABBONDANZA").font(.system(size: 9 * k, weight: .bold)).kerning(1.2).foregroundStyle(grey), at: .zero)
        var u = ctx; u.translateBy(x: 216 * k, y: 410 * k); u.rotate(by: .degrees(88))
        u.draw(Text("VIA DI STABIA").font(.system(size: 9 * k, weight: .bold)).kerning(1.2).foregroundStyle(grey), at: .zero)
    }
}

/// Catmull-Rom curve through the visited pins.
nonisolated struct SmoothPath: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard points.count > 1 else { return p }
        p.move(to: points[0])
        for i in 0..<points.count - 1 {
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            p.addCurve(to: p2, control1: c1, control2: c2)
        }
        return p
    }
}

private struct YouAreHere: View {
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().fill(Palette.azzurro.opacity(0.18)).frame(width: pulse ? 48 : 24, height: pulse ? 48 : 24)
            Circle().fill(Palette.azzurro).frame(width: 16, height: 16).overlay(Circle().stroke(.white, lineWidth: 3))
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.2).repeatForever()) { pulse = true } }
        .accessibilityLabel("You are here")
    }
}

// MARK: - Site sheet: tickets and Then & Now

struct SiteSheet: View {
    let site: Site
    @State private var split: CGFloat = 0.55
    @State private var dragged = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(site.name).font(Typeface.display(29, relativeTo: .title)).foregroundStyle(Palette.piperno).padding(.top, 24)
                HStack(spacing: 8) {
                    ForEach(Array(site.tags.enumerated()), id: \.offset) { i, tag in
                        TagPill(text: tag, fill: i == 0 ? Palette.tufoSoft : Palette.sunk, ink: i == 0 ? Palette.piperno : Palette.stone)
                    }
                }
                HStack(spacing: 10) {
                    tile("Full ticket", site.ticketPrice, site.ticketNote)
                    tile("Daily cap", site.dailyCap, site.dailyCapNote)
                }
                Text("Then & Now · the Forum").font(.system(size: 12, weight: .bold)).textCase(.uppercase).kerning(1).foregroundStyle(Palette.stone).padding(.top, 4)
                ThenNowSlider(then: site.thenImage, now: site.nowImage, caption: site.thenCaption, split: $split)
                    .frame(height: 220)
                    .simultaneousGesture(DragGesture().onChanged { _ in dragged = true })
                Link(destination: site.bookingURL) {
                    Text("Book on official site  ↗").frame(maxWidth: .infinity)
                }
                .buttonStyle(CTAButtonStyle(kind: .dark)).padding(.top, 8)
            }
            .padding(.horizontal, 20)
        }
        .background(Palette.calce)
        .task {
            guard !reduce else { return }
            try? await Task.sleep(for: .milliseconds(700))
            // Sweep once so people see the slider can move.
            for step in 0...60 where !dragged {
                split = 0.55 + sin(Double(step) / 60 * .pi * 2) * 0.3
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }

    private func tile(_ label: String, _ value: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 13)).foregroundStyle(Palette.stone)
            Text(value).font(Typeface.display(22)).foregroundStyle(Palette.piperno)
            Text(note).font(.system(size: 11)).foregroundStyle(Palette.stone)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.hair, lineWidth: 1.5))
    }
}

struct ThenNowSlider: View {
    let then: String
    let now: String
    let caption: String
    @Binding var split: CGFloat

    var body: some View {
        GeometryReader { geo in
            let x = geo.size.width * split
            ZStack(alignment: .topLeading) {
                CoverImage(name: now, anchor: .init(x: 0.55, y: 0.45))
                CoverImage(name: then, anchor: .init(x: 0.5, y: 0.4))
                    .mask(alignment: .leading) { Rectangle().frame(width: x) }
                Rectangle().fill(.white).frame(width: 3).shadow(color: .black.opacity(0.4), radius: 8).offset(x: x - 1.5)
                Image(systemName: "chevron.left.chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.onTufo)
                    .frame(width: 42, height: 42).background(Circle().fill(Palette.tufo)).overlay(Circle().stroke(.white, lineWidth: 3))
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                    .position(x: x, y: geo.size.height / 2)
            }
            .overlay(alignment: .bottom) {
                HStack {
                    Text(caption); Spacer(); Text("Today")
                }
                .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .padding(10)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in split = max(0.04, min(0.96, v.location.x / geo.size.width)) })
        }
        .clipShape(.rect(cornerRadius: 22))
        .accessibilityElement()
        .accessibilityLabel("Then and now: the Forum in 1841 and today")
        .accessibilityAdjustableAction { dir in split = max(0.04, min(0.96, split + (dir == .increment ? 0.1 : -0.1))) }
    }
}
