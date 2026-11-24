import MapKit
import SwiftUI

/// The discovery map shows found places as gold pins and undiscovered stories as "?" pins.
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
/// Pins that would overlap at the current zoom are grouped into a numbered cluster; tap it to zoom in.
struct TripMapView: View {
    let site: SiteContent
    let visited: [Place]
    var onTap: (Place) -> Void
    @Environment(AppModel.self) private var model
    @State private var position: MapCameraPosition
    @State private var region: MKCoordinateRegion?
    @State private var size: CGSize = .zero

    init(site: SiteContent, visited: [Place], onTap: @escaping (Place) -> Void) {
        self.site = site; self.visited = visited; self.onTap = onTap
        // Start framed on the site; setting it later in onAppear can be lost inside a GeometryReader.
        _position = State(initialValue: .region(Self.region(for: site)))
    }

    var body: some View {
        let t = model.strings
        let visitedIDs = Set(visited.map(\.id))
        let shown = region ?? Self.region(for: site)
        let clusters = MapClusterer.clusters(site.places, visited: visitedIDs, span: shown.span, size: size)
        Map(position: $position) {
                UserAnnotation()
                ForEach(Array(clusters.enumerated()), id: \.element.id) { i, cluster in
                    Annotation("", coordinate: cluster.coordinate, anchor: .top) {
                        if cluster.members.count == 1, let place = cluster.members.first {
                            let found = visitedIDs.contains(place.id)
                            TripPin(found: found, latest: place.id == visited.last?.id, delay: min(Double(i) * 0.06, 0.8),
                                    label: found && (place.showsMapLabel ?? true) ? place.name : nil, hasStory: place.story != nil)
                                .onTapGesture { Haptics.tap(); onTap(place) }
                                .accessibilityLabel(found || place.story == nil ? place.name : t("trip.toFind"))
                                .accessibilityAddTraits(.isButton)
                        } else {
                            ClusterPin(count: cluster.members.count, found: cluster.foundCount, stories: cluster.storyCount)
                                .onTapGesture { Haptics.tap(); open(cluster) }
                                .accessibilityLabel(t("trip.cluster", "\(cluster.members.count)"))
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .onEnd) { region = $0.region }
            .animation(.snappy, value: clusters.map(\.id))
            // Measured beside the map, not around it: a GeometryReader parent made the map start at zero size and zoom far out.
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .onChange(of: site.id) { region = nil; position = .region(Self.region(for: site)) }
    }

    /// Zooms to the places in a cluster; if they sit on the same spot, opens the most interesting one.
    private func open(_ cluster: MapClusterer.Cluster) {
        let lats = cluster.members.map(\.latitude), lons = cluster.members.map(\.longitude)
        let spanLat = (lats.max()! - lats.min()!), spanLon = (lons.max()! - lons.min()!)
        if max(spanLat, spanLon) < 0.00015, let first = cluster.members.first { onTap(first); return }
        let target = MKCoordinateRegion(
            center: .init(latitude: (lats.max()! + lats.min()!) / 2, longitude: (lons.max()! + lons.min()!) / 2),
            span: .init(latitudeDelta: max(spanLat * 2.2, 0.0012), longitudeDelta: max(spanLon * 2.2, 0.0012)))
        withAnimation(.smooth(duration: 0.6)) { position = .region(target) }
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

/// Groups pins that would overlap on screen. Pure, so it can be tested.
nonisolated enum MapClusterer {
    struct Cluster: Identifiable, Equatable {
        let members: [Place]
        let foundCount: Int
        let storyCount: Int
        var id: String { members.map(\.id).joined(separator: "+") }
        var coordinate: CLLocationCoordinate2D {
            .init(latitude: members.map(\.latitude).reduce(0, +) / Double(members.count),
                  longitude: members.map(\.longitude).reduce(0, +) / Double(members.count))
        }
        static func == (a: Cluster, b: Cluster) -> Bool { a.id == b.id }
    }

    /// `radius` is in screen points: two pins closer than this become one cluster.
    /// Found places and stories lead their cluster, so they are never hidden behind "coming soon" dots.
    static func clusters(_ places: [Place], visited: Set<String>, span: MKCoordinateSpan, size: CGSize, radius: CGFloat = 34) -> [Cluster] {
        guard size.width > 0, size.height > 0, span.latitudeDelta > 0, span.longitudeDelta > 0 else {
            return places.map { Cluster(members: [$0], foundCount: visited.contains($0.id) ? 1 : 0, storyCount: $0.story == nil ? 0 : 1) }
        }
        let ptLat = span.latitudeDelta / size.height, ptLon = span.longitudeDelta / size.width
        func rank(_ p: Place) -> Int { visited.contains(p.id) ? 0 : p.story != nil ? 1 : 2 }
        let ordered = places.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
        var groups: [(seed: Place, members: [Place])] = []
        for p in ordered {
            if let i = groups.firstIndex(where: { g in
                hypot((g.seed.latitude - p.latitude) / ptLat, (g.seed.longitude - p.longitude) / ptLon) < radius
            }) {
                groups[i].members.append(p)
            } else {
                groups.append((p, [p]))
            }
        }
        return groups.map { g in
            Cluster(members: g.members, foundCount: g.members.filter { visited.contains($0.id) }.count,
                    storyCount: g.members.filter { $0.story != nil }.count)
        }
    }
}

/// A numbered bubble for several places; gold ring if you found any of them.
private struct ClusterPin: View {
    let count: Int
    let found: Int
    let stories: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let size: CGFloat = count > 20 ? 46 : count > 9 ? 40 : 34
        Text("\(count)")
            .font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
            .foregroundStyle(stories > 0 ? .white : Palette.piperno)
            .frame(width: size, height: size)
            .background(Circle().fill(stories > 0 ? Palette.azzurro : Color.white))
            .overlay(Circle().stroke(found > 0 ? Palette.tufo : .white, lineWidth: found > 0 ? 4 : 3))
            .shadow(color: .black.opacity(0.22), radius: 4, y: 3)
            .frame(width: max(size, 44), height: max(size, 44))
            .contentShape(Circle())
            .padding(.top, -max(size, 44) / 2)
            .scaleEffect(shown ? 1 : 0.4).opacity(shown ? 1 : 0)
            .onAppear { withAnimation(reduce ? nil : Motion.pop.delay(0.15)) { shown = true } }
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

// MARK: - Site tickets

struct SiteSheet: View {
    @Environment(AppModel.self) private var model

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
                Link(destination: site.tickets.bookingURL) { Text(t("site.book")).frame(maxWidth: .infinity) }
                    .buttonStyle(CTAButtonStyle(kind: .dark)).padding(.top, 8)
            }
            .padding(.horizontal, 20)
        }
        .background(Palette.calce)
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
