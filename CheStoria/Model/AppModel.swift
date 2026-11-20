import Foundation
import Observation
import UIKit

enum AppTab: Hashable { case snap, trip, stickers }

/// One run of the story loop. With a photo, recognition decides the place; without one, `suggested` is used.
struct FlowRequest: Identifiable {
    let id = UUID()
    let photo: UIImage?
    let suggested: Place
}

struct CollectedSticker: Codable, Hashable, Identifiable, Sendable {
    let stickerID: String
    let placeID: String
    let date: Date
    var id: String { stickerID }
}

/// Progress for one site. Stored as JSON in UserDefaults, one entry per site.
struct TripState: Codable, Equatable, Sendable {
    var visited: [String] = []
    var collected: [CollectedSticker] = []

    /// Starting point taken from the site's optional `demoTrip`, so demos never begin empty.
    static func demo(for site: SiteContent) -> TripState {
        guard let demo = site.demoTrip else { return TripState() }
        let collected = demo.collected.enumerated().compactMap { i, stickerID -> CollectedSticker? in
            guard let place = site.placeOwning(stickerID: stickerID) else { return nil }
            return CollectedSticker(stickerID: stickerID, placeID: place.id, date: .now.addingTimeInterval(-3600 * Double(i + 1)))
        }
        return TripState(visited: demo.visited, collected: collected)
    }
}

@Observable
final class AppModel {
    private(set) var catalog: Catalog
    private(set) var site: SiteContent
    var selectedTab: AppTab = .snap
    /// The story loop currently playing full-screen.
    var activeFlow: FlowRequest?
    var showProfile = false
    var showLanguagePicker = false
    private(set) var hasOnboarded: Bool { didSet { defaults.set(hasOnboarded, forKey: Keys.onboarded) } }
    private(set) var state: TripState { didSet { save() } }

    private let defaults: UserDefaults
    private let loader: (String) -> Catalog?
    private enum Keys {
        static let onboarded = "chestoria.onboarded"
        static func trip(_ site: String) -> String { "chestoria.trip.v2.\(site)" }
    }

    init(catalog: Catalog, defaults: UserDefaults = .standard, loader: @escaping (String) -> Catalog? = { try? ContentStore.load(language: $0) }) {
        self.catalog = catalog
        self.defaults = defaults
        self.loader = loader
        let site = catalog.defaultSite
        self.site = site
        self.hasOnboarded = defaults.bool(forKey: Keys.onboarded)
        self.state = Self.loadState(for: site, defaults: defaults)
    }

    private static func loadState(for site: SiteContent, defaults: UserDefaults) -> TripState {
        if let data = defaults.data(forKey: Keys.trip(site.id)), let saved = try? JSONDecoder().decode(TripState.self, from: data) {
            // Drop anything the current content no longer contains.
            return TripState(visited: saved.visited.filter { site.place(id: $0) != nil },
                             collected: saved.collected.filter { site.sticker(id: $0.stickerID) != nil })
        }
        return .demo(for: site)
    }

    var visitedPlaces: [Place] { state.visited.compactMap(site.place(id:)) }
    var collectedStickers: [(sticker: Sticker, record: CollectedSticker)] {
        state.collected.sorted { $0.date > $1.date }.compactMap { rec in site.sticker(id: rec.stickerID).map { ($0, rec) } }
    }
    func isNew(_ sticker: Sticker) -> Bool { state.collected.max { $0.date < $1.date }?.stickerID == sticker.id }

    func completeOnboarding() { hasOnboarded = true }

    // MARK: Language

    var language: String { catalog.language }
    var strings: UIStrings { catalog.strings }
    var languages: [String] { catalog.languages(forSite: site.id) }
    /// Display name of a language, written in that language ("Italiano").
    func languageName(_ code: String) -> String {
        Locale(identifier: code).localizedString(forLanguageCode: code)?.capitalized(with: Locale(identifier: code)) ?? code
    }

    /// Reloads content in another language. Trip progress is kept because ids do not change.
    func setLanguage(_ code: String) {
        guard code != language, let c = loader(code) else { return }
        catalog = c
        site = c.site(id: site.id) ?? c.defaultSite
        defaults.set(code, forKey: Settings.storyLanguage)
    }

    /// The best language to start with: the saved choice, else the device language if the content has it.
    static func preferredLanguage(available: [String], defaults: UserDefaults = .standard) -> String {
        if let saved = defaults.string(forKey: Settings.storyLanguage), available.contains(saved) { return saved }
        for id in Locale.preferredLanguages {
            if let code = Locale(identifier: id).language.languageCode?.identifier, available.contains(code) { return code }
        }
        return available.first ?? "en"
    }

    func switchSite(to id: String) {
        guard let s = catalog.site(id: id), s.id != site.id else { return }
        site = s
        state = Self.loadState(for: s, defaults: defaults)
    }

    func startStory(at place: Place, photo: UIImage? = nil) {
        guard place.story != nil else { return }
        activeFlow = FlowRequest(photo: photo, suggested: place)
    }

    func finishStory(at place: Place, goTo tab: AppTab) {
        if !state.visited.contains(place.id) { state.visited.append(place.id) }
        if let sticker = place.story?.sticker, !state.collected.contains(where: { $0.stickerID == sticker.id }) {
            state.collected.append(CollectedSticker(stickerID: sticker.id, placeID: place.id, date: .now))
        }
        activeFlow = nil
        selectedTab = tab
    }

    func resetDemo() { state = .demo(for: site); selectedTab = .snap }

    func resetOnboarding() { hasOnboarded = false }

    private func save() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Keys.trip(site.id)) }
    }
}
