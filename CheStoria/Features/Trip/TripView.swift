import MapKit
import SwiftUI

/// Today's walk on Apple Maps: places you found are gold pins joined by your route;
/// stories you haven't found yet are quiet "?" pins, so the map invites you without spoiling anything.
struct TripView: View {
    @Environment(AppModel.self) private var model
    @State private var showSite = false
    @State private var openPlace: Place?
    @State private var appeared = false

    var body: some View {
        let t = model.strings
        let visited = model.visitedPlaces
        NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button { showSite = true } label: {
                    Label(t("trip.secrets", model.site.city, "\(visited.count)"), systemImage: "ticket")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.azzurro)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(Palette.azzurroSoft, in: .capsule)
                }
                .padding(.horizontal, 4)

                TripMapView(site: model.site, visited: visited) { openPlace = $0 }
                    .frame(height: 460)
                    .overlay(alignment: .bottom) {
                        if visited.isEmpty {
                            Text(t("trip.empty")).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.stone)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 14).padding(.vertical, 10).background(.regularMaterial, in: .capsule).padding(16)
                                .allowsHitTesting(false)
                        }
                    }
                    .clipShape(.rect(cornerRadius: 30))
                    .overlay(RoundedRectangle(cornerRadius: 30).stroke(Palette.hair, lineWidth: 1.5))

                HStack(spacing: 10) {
                    ForEach(Array(model.collectedStickers.prefix(2).enumerated()), id: \.element.sticker.id) { i, item in
                        HStack(spacing: 10) {
                            StickerArt(sticker: item.sticker, border: 3, photo: model.stickerPhoto(item.sticker)).frame(width: 44, height: 40)
                            Text(item.sticker.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.piperno)
                                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 10).frame(height: 64)
                        .background(Palette.card, in: .rect(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.hair, lineWidth: 1.5))
                        .rise(appeared, delay: 0.4 + Double(i) * 0.12)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .background(Palette.calce)
        .navigationTitle(t("trip.title"))
        .toolbar { ToolbarItem(placement: .topBarTrailing) { ProfileButton(style: .toolbar) } }
        }
        .onAppear { appeared = false; DispatchQueue.main.async { appeared = true } }
        .sheet(isPresented: $showSite) { SiteSheet().presentationDetents([.large]).presentationCornerRadius(38) }
        .sheet(item: $openPlace) { PlaceSheet(place: $0) }
    }
}

/// Apple Maps view of a site, built only from each place's latitude/longitude in the content.
struct TripMapView: View {
    let site: SiteContent
    let visited: [Place]
    var onTap: (Place) -> Void
    @Environment(AppModel.self) private var model
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        let t = model.strings
        let visitedIDs = Set(visited.map(\.id))
        // Found places, stories still to find, and small dots for places whose story is coming.
        let pins = site.places.sorted { ($0.story == nil ? 0 : 1) < ($1.story == nil ? 0 : 1) }
        Map(position: $position) {
            UserAnnotation()
            if visited.count > 1 {
                MapPolyline(coordinates: visited.map(\.coordinate))
                    .stroke(Palette.piperno, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [1, 8]))
            }
            ForEach(Array(pins.enumerated()), id: \.element.id) { i, place in
                let found = visitedIDs.contains(place.id)
                Annotation("", coordinate: place.coordinate, anchor: .top) {
                    TripPin(found: found, latest: place.id == visited.last?.id, delay: min(Double(i) * 0.12, 1.5),
                            label: found && (place.showsMapLabel ?? true) ? place.name : nil, hasStory: place.story != nil)
                        .onTapGesture { Haptics.tap(); onTap(place) }
                        .accessibilityLabel(found || place.story == nil ? place.name : t("trip.toFind"))
                        .accessibilityAddTraits(.isButton)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .onAppear { position = .region(Self.region(for: site)) }
        .onChange(of: site.id) { position = .region(Self.region(for: site)) }
    }

    /// Frames every place of the site with a little margin.
    static func region(for site: SiteContent) -> MKCoordinateRegion {
        let pts = site.places
        guard let minLat = pts.map(\.latitude).min(), let maxLat = pts.map(\.latitude).max(),
              let minLon = pts.map(\.longitude).min(), let maxLon = pts.map(\.longitude).max() else {
            return MKCoordinateRegion(center: site.centre.coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500)
        }
        return MKCoordinateRegion(
            center: .init(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: .init(latitudeDelta: max((maxLat - minLat) * 1.25, 0.004), longitudeDelta: max((maxLon - minLon) * 1.25, 0.004)))
    }
}

/// Gold pin for a place you found, a small "?" for a story still to find.
private struct TripPin: View {
    let found: Bool
    let latest: Bool
    let delay: Double
    var label: String? = nil
    var hasStory = true
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    private let ink = Color(red: 0.17, green: 0.19, blue: 0.18)

    var body: some View {
        Group {
            if !hasStory && !found {
                Circle().fill(Palette.stone.opacity(0.55)).overlay(Circle().stroke(.white, lineWidth: 2)).frame(width: 11, height: 11)
            } else if found {
                ZStack {
                    Circle().fill(Palette.tufo).overlay(Circle().stroke(.white, lineWidth: 4))
                    Circle().fill(ink).padding(latest ? 12 : 11)
                }
                .frame(width: latest ? 36 : 32, height: latest ? 36 : 32)
            } else {
                Image(systemName: "questionmark")
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(Palette.stone)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white))
                    .overlay(Circle().stroke(Palette.hair, lineWidth: 1.5))
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 3, y: 3)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .overlay(alignment: .top) {
            if let label {
                Text(label).font(.system(size: 12, weight: .bold)).foregroundStyle(ink)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.white.opacity(0.9), in: .capsule)
                    .fixedSize().offset(y: 44)
            }
        }
        .padding(.top, -22) // keeps the circle's centre on the coordinate
        .scaleEffect(shown ? 1 : 0.4).opacity(shown ? 1 : 0)
        .onAppear { withAnimation(reduce ? nil : Motion.pop.delay(0.2 + delay)) { shown = true } }
    }
}

// MARK: - Site sheet: tickets and Then & Now

struct SiteSheet: View {
    @Environment(AppModel.self) private var model
    @State private var thenNowPlace: Place?

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
                let withThenNow = site.places.filter { $0.thenNow != nil }
                if !withThenNow.isEmpty {
                    Text(t("thenNow.title")).font(.system(size: 12, weight: .bold)).textCase(.uppercase).kerning(1).foregroundStyle(Palette.stone).padding(.top, 4)
                    ForEach(withThenNow) { p in
                        Button { thenNowPlace = p } label: {
                            HStack(spacing: 12) {
                                HStack(spacing: 0) { CoverImage(p.thenNow!.then).frame(width: 40, height: 52); CoverImage(p.thenNow!.now).frame(width: 40, height: 52) }
                                    .clipShape(.rect(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.piperno)
                                    Text(p.thenNow!.thenCaption).font(.system(size: 13)).foregroundStyle(Palette.stone)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Palette.stone)
                            }
                            .padding(10).background(Palette.card, in: .rect(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.hair, lineWidth: 1.5))
                        }
                    }
                }
                Link(destination: site.tickets.bookingURL) { Text(t("site.book")).frame(maxWidth: .infinity) }
                    .buttonStyle(CTAButtonStyle(kind: .dark)).padding(.top, 8)
            }
            .padding(.horizontal, 20)
        }
        .background(Palette.calce)
        .sheet(item: $thenNowPlace) { p in if let tn = p.thenNow { ThenNowSheet(thenNow: tn, title: p.name) } }
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
