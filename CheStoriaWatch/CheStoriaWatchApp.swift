import CoreLocation
import SwiftUI
import UIKit

@main
struct CheStoriaWatchApp: App {
    @Environment(\.scenePhase) private var phase
    @State private var walk = WatchWalk()
    @State private var sync = WatchTripSync()
    @State private var catalog: Catalog?
    @State private var path: [Route] = []

    private enum Route: Hashable {
        case nearby, comparisons
        case clue(String, String)
        case comparison(String, String)
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                if let catalog {
                    home(catalog)
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .nearby: nearby(catalog)
                            case .comparisons: comparisons(catalog)
                            case let .clue(site, id):
                                if let place = catalog.site(id: site)?.place(id: id) {
                                    clue(place, site: site, strings: catalog.strings)
                                }
                            case let .comparison(site, id):
                                if let place = catalog.site(id: site)?.place(id: id), let pair = place.thenNow {
                                    CrownComparison(place: place, pair: pair, strings: catalog.strings)
                                }
                            }
                        }
                } else {
                    ContentUnavailableView("CheStoria", systemImage: "exclamationmark.triangle")
                }
            }
            .onChange(of: sync.context?.language, initial: true) { _, language in load(language) }
            .onChange(of: phase, initial: true) { _, phase in walk.setActive(phase == .active) }
            .task {
                sync.onReceive = { [walk] context in walk.applyTrip(context) }
            }
            .onChange(of: walk.nearbyNotificationTap) { path = [.nearby] }
            .onOpenURL { url in
                guard url.scheme == "chestoria", ["snap", "nearby"].contains(url.host ?? "") else { return }
                path = [.nearby]
            }
        }
    }

    private func load(_ language: String?) {
        let preferred = language ?? Locale.current.language.languageCode?.identifier ?? "en"
        catalog = (try? ContentStore.loadBundled(language: preferred)) ?? (try? ContentStore.loadBundled())
        if let catalog { walk.configure(catalog: catalog, context: sync.context) }
    }

    private func home(_ catalog: Catalog) -> some View {
        let t = catalog.strings
        return List {
            NavigationLink(value: Route.nearby) {
                Label(t("watch.nearby"), systemImage: "location.circle")
            }
            NavigationLink(value: Route.comparisons) {
                Label(t("thenNow.title"), systemImage: "clock.arrow.circlepath")
            }
        }
        .navigationTitle("CheStoria")
    }

    private func choices(_ catalog: Catalog, fix: CLLocation?, now: Date = .now) -> [NearbySecret] {
        NearbySecret.choices(in: catalog.sites, fix: fix, visited: sync.context?.visited ?? [:], now: now)
    }

    private func nearby(_ catalog: Catalog) -> some View {
        let t = catalog.strings
        return TimelineView(.periodic(from: .now, by: 5)) { timeline in
            let results = choices(catalog, fix: walk.fix, now: timeline.date)
            List {
                if !walk.walking {
                    Text(t("watch.walkIntro")).font(.footnote).foregroundStyle(.secondary)
                    Button(t("watch.startWalk")) { walk.start() }.buttonStyle(.borderedProminent)
                } else {
                    if walk.authorization == .denied || walk.authorization == .restricted {
                        Label(t("watch.locationOff"), systemImage: "location.slash")
                            .font(.footnote)
                    } else if !(walk.fix.map { NearbySecret.usable($0, now: timeline.date) } ?? false) {
                        HStack { ProgressView(); Text(t("watch.locating")).font(.footnote) }
                    } else if results.isEmpty {
                        Text(t("watch.noSecrets")).font(.footnote).foregroundStyle(.secondary)
                    } else {
                        if results.count > 1 {
                            Text(t("watch.choose")).font(.caption2).foregroundStyle(.secondary)
                                .listRowBackground(Color.clear)
                        }
                        ForEach(results) { secret in
                            let meters = secret.meters.formatted(.number.locale(Locale(identifier: catalog.language)))
                            NavigationLink(value: Route.clue(secret.siteID, secret.place.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(secret.place.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                            .minimumScaleFactor(0.75)
                                        Spacer(minLength: 0)
                                        Text("≈\(meters) m").font(.caption2).foregroundStyle(.secondary).fixedSize()
                                            .accessibilityLabel(Text(t("watch.distance", meters)))
                                    }
                                    if let clue = secret.place.clues.first {
                                        Text(clue).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                            .listRowInsets(.init(top: 4, leading: 10, bottom: 4, trailing: 10))
                        }
                    }
                }
            }
            .environment(\.defaultMinListRowHeight, 30)
        }
        .navigationTitle(t("watch.nearby"))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if walk.walking {
                Button { walk.stop() } label: {
                    Label(t("watch.endWalk"), systemImage: "stop.fill")
                        .font(.footnote.weight(.semibold))
                        .frame(minHeight: 32).padding(.horizontal, 13)
                        .background(.quaternary, in: .capsule)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .background(.background)
            }
        }
    }

    private func clue(_ place: Place, site: String, strings t: UIStrings) -> some View {
        List {
            Text(place.name).font(.headline)
            Text(place.street).font(.footnote).foregroundStyle(.secondary)
            if let clue = place.clues.first {
                Label(clue, systemImage: "eye").font(.body)
            }
            if place.thenNow?.supportsOfflineWatch == true {
                NavigationLink(t("thenNow.title"), value: Route.comparison(site, place.id))
            }
        }
        .navigationTitle(t("watch.clue"))
    }

    private func comparisons(_ catalog: Catalog) -> some View {
        List {
            ForEach(catalog.sites) { site in
                Section(site.city) {
                    ForEach(site.places.filter { $0.thenNow?.supportsOfflineWatch == true }) { place in
                        NavigationLink(place.name, value: Route.comparison(site.id, place.id))
                    }
                }
            }
        }
        .navigationTitle(catalog.strings("thenNow.title"))
    }
}

private extension ThenNow {
    var supportsOfflineWatch: Bool {
        if case .asset = then, case .asset = now { return true }
        return false
    }
}

private struct CrownComparison: View {
    let place: Place
    let pair: ThenNow
    let strings: UIStrings
    @State private var period = 1.0
    @FocusState private var crownFocused: Bool

    private var now: Bool { period >= 0.5 }
    private var label: String { strings(now ? "watch.now" : "watch.then") }
    private var caption: String { now ? (pair.nowCaption == "Today" ? strings("thenNow.today") : pair.nowCaption) : pair.thenCaption }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(label).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Text(caption).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                photo(height: max(48, min(116, geometry.size.height - 60)))
                HStack(spacing: 4) {
                    Text(strings("watch.crownHint")).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    NavigationLink { photoCredits } label: {
                        Image(systemName: "info.circle").font(.body).frame(minWidth: 30, minHeight: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(strings("about.photos")))
                }
                if let clue = pair.watchHint ?? place.clues.first {
                    Label(clue, systemImage: "eye").font(.caption2).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 4)
        }
        // The comparison owns the Crown. Photo credits scroll on their own screen.
        .focusable()
        .focused($crownFocused)
        .digitalCrownRotation($period, from: 0, through: 1, by: 1, sensitivity: .high, isContinuous: false, isHapticFeedbackEnabled: true)
        .defaultFocus($crownFocused, true)
        .navigationTitle(place.name)
    }

    private func photo(height: CGFloat) -> some View {
        Button { period = now ? 0 : 1 } label: {
            Group {
                if let photo = image(now ? pair.now : pair.then) {
                    Image(uiImage: photo).resizable().scaledToFit()
                        .accessibilityHidden(true)
                } else {
                    Label(strings("watch.imageUnavailable"), systemImage: "photo")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background(.quaternary, in: .rect(cornerRadius: 12))
            .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(caption))
        .accessibilityHint(Text(strings("watch.switchView")))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: period = 1
            case .decrement: period = 0
            @unknown default: break
            }
        }
    }

    private var photoCredits: some View {
        List([pair.then, pair.now].compactMap(Credits.shared.photo(for:)), id: \.asset) { credit in
            VStack(alignment: .leading, spacing: 4) {
                Text(credit.title).font(.headline)
                Text(credit.line).font(.footnote).foregroundStyle(.secondary)
                if let url = credit.url ?? credit.licenceURL {
                    Link(strings("watch.photoSource"), destination: url).font(.footnote)
                }
            }
        }
        .navigationTitle(strings("about.photos"))
    }

    private func image(_ ref: ImageRef) -> UIImage? {
        guard case .asset(let name) = ref,
              let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "ComparisonImages") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}
