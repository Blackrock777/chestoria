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
    /// File name of the person's own photo the sticker was cut from (Application Support/Stickers).
    var photoFile: String? = nil
    var id: String { stickerID }
}

/// Progress for one site. Stored as JSON in UserDefaults, one entry per site.
struct TripState: Codable, Equatable, Sendable {
    var visited: [String] = []
    var collected: [CollectedSticker] = []
    /// When this trip's first story was finished; drives "Day 2 of your trip".
    var startedAt: Date?

    /// Starting point taken from the site's optional `demoTrip`, so demos never begin empty.
    static func demo(for site: SiteContent) -> TripState {
        guard let demo = site.demoTrip else { return TripState() }
        let collected = demo.collected.enumerated().compactMap { i, stickerID -> CollectedSticker? in
            guard let place = site.placeOwning(stickerID: stickerID) else { return nil }
            return CollectedSticker(stickerID: stickerID, placeID: place.id, date: .now.addingTimeInterval(-3600 * Double(i + 1)))
        }
        return TripState(visited: demo.visited, collected: collected, startedAt: .now.addingTimeInterval(-86_400))
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
        static let recallRight = "chestoria.recall.right"
        static let recallAnswered = "chestoria.recall.answered"
        static func trip(_ site: String) -> String { "chestoria.trip.v2.\(site)" }
    }

    init(catalog: Catalog, defaults: UserDefaults = .standard, loader: @escaping (String) -> Catalog? = { try? ContentStore.load(language: $0) }) {
        self.catalog = catalog
        self.defaults = defaults
        self.loader = loader
        let site = defaults.string(forKey: Settings.site).flatMap(catalog.site(id:)) ?? catalog.defaultSite
        self.site = site
        self.hasOnboarded = defaults.bool(forKey: Keys.onboarded)
        self.state = Self.loadState(for: site, defaults: defaults)
    }

    private static func loadState(for site: SiteContent, defaults: UserDefaults) -> TripState {
        if let data = defaults.data(forKey: Keys.trip(site.id)), let saved = try? JSONDecoder().decode(TripState.self, from: data) {
            // Drop anything the current content no longer contains.
            return TripState(visited: saved.visited.filter { site.place(id: $0) != nil },
                             collected: saved.collected.filter { site.sticker(id: $0.stickerID) != nil },
                             startedAt: saved.startedAt)
        }
        // A new trip starts empty: no invented progress. Profile → Demo can load the content's demo trip.
        return TripState()
    }

    var visitedPlaces: [Place] { state.visited.compactMap(site.place(id:)) }
    var visitedBySite: [String: Set<String>] {
        Dictionary(uniqueKeysWithValues: catalog.sites.map { entry in
            let trip = entry.id == site.id ? state : Self.loadState(for: entry, defaults: defaults)
            return (entry.id, Set(trip.visited))
        })
    }
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
        SharedStore.saveWidgetEmptyText(strings("widget.empty"))
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
        defaults.set(id, forKey: Settings.site)
    }

    /// Answers to next-morning questions, for the "Remembered" stat.
    var recallStats: (remembered: Int, answered: Int) {
        (defaults.integer(forKey: Keys.recallRight), defaults.integer(forKey: Keys.recallAnswered))
    }
    func recordRecall(correct: Bool) {
        defaults.set(defaults.integer(forKey: Keys.recallAnswered) + 1, forKey: Keys.recallAnswered)
        if correct { defaults.set(defaults.integer(forKey: Keys.recallRight) + 1, forKey: Keys.recallRight) }
    }

    func startStory(at place: Place, photo: UIImage? = nil) {
        guard place.story != nil else { return }
        activeFlow = FlowRequest(photo: photo, suggested: place)
    }

    func finishStory(at place: Place, goTo tab: AppTab, photo: UIImage? = nil) {
        if state.startedAt == nil { state.startedAt = .now }
        if !state.visited.contains(place.id) { state.visited.append(place.id) }
        if let sticker = place.story?.sticker {
            let file = photo.flatMap { StickerPhotos.save($0, id: "\(site.id)-\(sticker.id)") }
            if let i = state.collected.firstIndex(where: { $0.stickerID == sticker.id }) {
                if let file { state.collected[i].photoFile = file }
            } else {
                state.collected.append(CollectedSticker(stickerID: sticker.id, placeID: place.id, date: .now, photoFile: file))
            }
        }
        activeFlow = nil
        selectedTab = tab
    }

    /// For presentations: the content's demo trip (if it has one).
    func loadDemo() { state = .demo(for: site); selectedTab = .snap }
    func startFresh() { state = TripState(); selectedTab = .snap }
    /// Kept for launch arguments and tests.
    func resetDemo() { loadDemo() }

    /// "Welcome to Pompeii" before the first story; "Pompeii · Day 2 of your trip" after, counted from the real start date.
    var welcomeEyebrow: String {
        if let fixed = site.welcome.eyebrow { return fixed }
        guard let start = state.startedAt else { return strings("welcome.first", site.city) }
        let days = (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: start), to: Calendar.current.startOfDay(for: .now)).day ?? 0) + 1
        return strings("welcome.day", site.city, "\(days)")
    }

    /// The person's own photo for a sticker, if they took one.
    func stickerPhoto(_ sticker: Sticker) -> UIImage? {
        state.collected.first { $0.stickerID == sticker.id }?.photoFile.flatMap(StickerPhotos.load)
    }

    func resetOnboarding() { hasOnboarded = false }

    private func save() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Keys.trip(site.id)) }
    }
}

/// Sticker photos are the person's own shots, kept on the device.
enum StickerPhotos {
    static var folder: URL { URL.applicationSupportDirectory.appending(path: "Stickers", directoryHint: .isDirectory) }

    static func save(_ image: UIImage, id: String) -> String? {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let side: CGFloat = 900, s = min(1, side / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * s, height: image.size.height * s)
        let small = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = small.jpegData(compressionQuality: 0.85) else { return nil }
        let name = "\(id).jpg"
        return (try? data.write(to: folder.appending(path: name), options: .atomic)) != nil ? name : nil
    }

    static func load(_ name: String) -> UIImage? { UIImage(contentsOfFile: folder.appending(path: name).path) }
}
