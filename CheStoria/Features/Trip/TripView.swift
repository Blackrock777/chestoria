import SwiftUI

/// Today's walk on a hand-drawn site map. Only places you found are shown, never what you missed.
struct TripView: View {
    @Environment(AppModel.self) private var model
    @State private var showSite = false
    @State private var drawn = false

    var body: some View {
        let t = model.strings
        let visited = model.visitedPlaces
        let map = model.site.map
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    Text(t("trip.title")).font(Typeface.display(36, relativeTo: .largeTitle)).foregroundStyle(Palette.piperno)
                    Spacer()
                    ProfileButton()
                }
                .padding(.horizontal, 8)
                Button { showSite = true } label: {
                    Label(t("trip.secrets", model.site.city, "\(visited.count)"), systemImage: "ticket")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.azzurro)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(Palette.azzurroSoft, in: .capsule)
                }
                .padding(.horizontal, 4)

                SiteMapView(map: map, places: visited, drawn: drawn)
                    .aspectRatio(map.width / map.height, contentMode: .fit)
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
        .sheet(isPresented: $showSite) { SiteSheet().presentationDetents([.large]).presentationCornerRadius(38) }
    }
}

/// A hand-drawn map rendered from the site's `map` description (walls, streets, water, labels).
struct SiteMapView: View {
    let map: SiteMap
    let places: [Place]
    let drawn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce

    private let ink = Color(red: 0.17, green: 0.19, blue: 0.18)

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / map.width
            let pts = places.map { CGPoint(x: $0.mapPoint.x * k, y: $0.mapPoint.y * k) }
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in drawBase(ctx, k: k) }
                SmoothPath(points: pts)
                    .trim(from: 0, to: drawn ? 1 : 0)
                    .stroke(ink, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [0.1, 9]))
                    .animation(reduce ? nil : .easeInOut(duration: 1.6).delay(0.4), value: drawn)
                ForEach(Array(places.enumerated()), id: \.element.id) { i, place in
                    let last = i == places.count - 1
                    ZStack {
                        Circle().fill(Palette.tufo).overlay(Circle().stroke(.white, lineWidth: 4)).shadow(color: .black.opacity(0.2), radius: 3, y: 3)
                        Circle().fill(ink).padding(last ? 12 : 11)
                    }
                    .frame(width: last ? 36 : 32, height: last ? 36 : 32)
                    .scaleEffect(drawn ? 1 : 0.4).opacity(drawn ? 1 : 0).offset(y: drawn ? 0 : -40)
                    .animation(reduce ? nil : Motion.pop.delay(0.35 + Double(i) * 0.6), value: drawn)
                    .position(pts[i])
                    .accessibilityLabel(place.name)
                    if place.showsMapLabel ?? true {
                        Text(place.name).font(.system(size: 11.5, weight: .bold)).foregroundStyle(ink)
                            .fixedSize()
                            .position(x: pts[i].x, y: pts[i].y + 28 * max(k, 0.8))
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
        func p(_ m: MapPoint) -> CGPoint { CGPoint(x: m.x * k, y: m.y * k) }
        func poly(_ ps: [MapPoint]) -> Path { var path = Path(); path.addLines(ps.map(p)); path.closeSubpath(); return path }

        let wall = poly(map.outline)
        ctx.fill(wall, with: .color(Color(red: 0.957, green: 0.945, blue: 0.91)))
        ctx.stroke(wall, with: .color(Color(red: 0.81, green: 0.79, blue: 0.73)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [2, 5]))
        for s in map.streets {
            var path = Path(); path.move(to: p(s.from)); path.addLine(to: p(s.to))
            ctx.stroke(path, with: .color(Color(red: 0.89, green: 0.875, blue: 0.83)), style: StrokeStyle(lineWidth: 10 * k, lineCap: .round))
        }
        if let water = map.water { ctx.fill(poly(water), with: .color(Color(red: 0.86, green: 0.92, blue: 0.96))) }
        for b in map.blocks ?? [] {
            ctx.fill(Path(roundedRect: CGRect(x: b.x * k, y: b.y * k, width: b.w * k, height: b.h * k), cornerRadius: 4),
                     with: .color(Color(red: 0.94, green: 0.91, blue: 0.85)))
        }
        for m in map.mountains ?? [] {
            let path = poly(m)
            ctx.fill(path, with: .color(Color(red: 0.91, green: 0.9, blue: 0.85)))
            ctx.stroke(path, with: .color(Color(red: 0.72, green: 0.69, blue: 0.64)), lineWidth: 1.5)
        }
        for l in map.labels {
            var c = ctx
            c.translateBy(x: l.x * k, y: l.y * k)
            if let r = l.rotation { c.rotate(by: .degrees(r)) }
            let text: Text = switch l.style {
            case .street: Text(l.text).font(.system(size: 9 * k, weight: .bold)).kerning(1.2).foregroundStyle(Color(red: 0.6, green: 0.62, blue: 0.61))
            case .water: Text(l.text).font(.system(size: 9 * k).italic()).foregroundStyle(Palette.azzurro)
            case .place: Text(l.text).font(.system(size: 10 * k, weight: .semibold)).foregroundStyle(Color(red: 0.42, green: 0.44, blue: 0.43))
            }
            c.draw(text, at: .zero)
        }
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
    @Environment(AppModel.self) private var model
    @State private var split: CGFloat = 0.55
    @State private var dragged = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let site = model.site, t = model.strings
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(site.name).font(Typeface.display(29, relativeTo: .title)).foregroundStyle(Palette.piperno).padding(.top, 24)
                HStack(spacing: 8) {
                    ForEach(Array(site.tickets.tags.enumerated()), id: \.offset) { i, tag in
                        TagPill(text: tag, fill: i == 0 ? Palette.tufoSoft : Palette.sunk, ink: i == 0 ? Palette.piperno : Palette.stone)
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(site.tickets.tiles, id: \.label) { tile($0.label, $0.value, $0.note) }
                }
                if let tn = site.thenNow {
                    Text(tn.title).font(.system(size: 12, weight: .bold)).textCase(.uppercase).kerning(1).foregroundStyle(Palette.stone).padding(.top, 4)
                    ThenNowSlider(then: tn.then, now: tn.now, caption: tn.thenCaption, todayLabel: t("site.today"), split: $split)
                        .frame(height: 220)
                        .simultaneousGesture(DragGesture().onChanged { _ in dragged = true })
                }
                Link(destination: site.tickets.bookingURL) { Text(t("site.book")).frame(maxWidth: .infinity) }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.card, in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.hair, lineWidth: 1.5))
    }
}

struct ThenNowSlider: View {
    let then: ImageRef
    let now: ImageRef
    let caption: String
    let todayLabel: String
    @Binding var split: CGFloat

    var body: some View {
        GeometryReader { geo in
            let x = geo.size.width * split
            ZStack(alignment: .topLeading) {
                CoverImage(now, anchor: .init(x: 0.55, y: 0.45))
                CoverImage(then, anchor: .init(x: 0.5, y: 0.4))
                    .mask(alignment: .leading) { Rectangle().frame(width: x) }
                Rectangle().fill(.white).frame(width: 3).shadow(color: .black.opacity(0.4), radius: 8).offset(x: x - 1.5)
                Image(systemName: "chevron.left.chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.onTufo)
                    .frame(width: 42, height: 42).background(Circle().fill(Palette.tufo)).overlay(Circle().stroke(.white, lineWidth: 3))
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                    .position(x: x, y: geo.size.height / 2)
            }
            .overlay(alignment: .bottom) {
                HStack { Text(caption); Spacer(); Text(todayLabel) }
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.white).shadow(color: .black.opacity(0.6), radius: 4)
                    .padding(10)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in split = max(0.04, min(0.96, v.location.x / geo.size.width)) })
        }
        .clipShape(.rect(cornerRadius: 22))
        .accessibilityElement()
        .accessibilityLabel(caption)
        .accessibilityAdjustableAction { dir in split = max(0.04, min(0.96, split + (dir == .increment ? 0.1 : -0.1))) }
    }
}
