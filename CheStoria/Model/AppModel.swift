import Foundation
import Observation

enum AppTab: Hashable { case snap, trip, stickers }

struct CollectedSticker: Codable, Hashable, Identifiable, Sendable {
    let stickerID: String
    let placeID: String
    let date: Date
    var id: String { stickerID }
}

/// Persisted progress for one trip. Stored as JSON in UserDefaults.
struct TripState: Codable, Equatable, Sendable {
    var hasOnboarded = false
    var visited: [String] = []
    var collected: [CollectedSticker] = []

    /// A believable starting point for the demo: the Forum and the House of the Tragic Poet are already done.
    static var demo: TripState {
        TripState(hasOnboarded: false, visited: ["forum", "tragic-poet"],
                  collected: [CollectedSticker(stickerID: "cave-canem", placeID: "tragic-poet", date: .now.addingTimeInterval(-3600))])
    }
}

@Observable
final class AppModel {
    let content: ContentBundle
    var selectedTab: AppTab = .snap
    /// The place whose story is currently being played full-screen.
    var activePlace: Place?
    private(set) var state: TripState { didSet { save() } }

    private let defaults: UserDefaults
    private static let key = "chestoria.trip.v1"

    init(content: ContentBundle, defaults: UserDefaults = .standard) {
        self.content = content
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode(TripState.self, from: data) {
            state = saved
        } else {
            state = .demo
        }
    }

    var hasOnboarded: Bool { state.hasOnboarded }
    var visitedPlaces: [Place] { state.visited.compactMap(content.place(id:)) }
    var collectedStickers: [(sticker: Sticker, record: CollectedSticker)] {
        state.collected.sorted { $0.date > $1.date }.compactMap { rec in content.sticker(id: rec.stickerID).map { ($0, rec) } }
    }
    func isNew(_ sticker: Sticker) -> Bool { state.collected.max { $0.date < $1.date }?.stickerID == sticker.id }

    func completeOnboarding() { state.hasOnboarded = true }

    func startStory(at place: Place) {
        guard place.story != nil else { return }
        activePlace = place
    }

    func finishStory(at place: Place, goTo tab: AppTab) {
        if !state.visited.contains(place.id) { state.visited.append(place.id) }
        if let sticker = place.story?.sticker, !state.collected.contains(where: { $0.stickerID == sticker.id }) {
            state.collected.append(CollectedSticker(stickerID: sticker.id, placeID: place.id, date: .now))
        }
        activePlace = nil
        selectedTab = tab
    }

    func resetDemo() { state = .demo; selectedTab = .snap }

    private func save() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Self.key) }
    }
}
