import CoreLocation
import SwiftUI

@main
struct CheStoriaWatchApp: App {
    @Environment(\.scenePhase) private var phase
    @State private var walk = WatchWalk()
    @State private var sync = WatchTripSync()
    @State private var catalog: Catalog?
    @State private var path: [Route] = []

    private enum Route: Hashable {
        case nearby
        case clue(String, String)
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                if let catalog {
                    home(catalog)
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .nearby: nearby(catalog)
                            case let .clue(site, id):
                                if let place = catalog.site(id: site)?.place(id: id) {
                                    clue(place, strings: catalog.strings)
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
            NavigationLink {
                PrivacyPolicyContent(unavailableMessage: t("privacy.unavailable"))
                    .navigationTitle(t("privacy.title"))
            } label: {
                Label(t("privacy.title"), systemImage: "hand.raised")
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

    private func clue(_ place: Place, strings t: UIStrings) -> some View {
        List {
            Text(place.name).font(.headline)
            Text(place.street).font(.footnote).foregroundStyle(.secondary)
            if let clue = place.clues.first {
                Label(clue, systemImage: "eye").font(.body)
            }
        }
        .navigationTitle(t("watch.clue"))
    }
}
