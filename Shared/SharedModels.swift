import ActivityKit
import Foundation

/// Data shared between the app and the widget extension through the App Group.
nonisolated enum SharedStore {
    static let appGroup = "group.app.chestoria"
    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }
    private static let recallKey = "recall.latest"

    static func saveRecall(_ payload: RecallPayload) {
        if let data = try? JSONEncoder().encode(payload) { defaults.set(data, forKey: recallKey) }
    }
    static func loadRecall() -> RecallPayload? {
        defaults.data(forKey: recallKey).flatMap { try? JSONDecoder().decode(RecallPayload.self, from: $0) }
    }
}

/// The next-morning question, already in the person's language (the widget has no content files).
nonisolated struct RecallPayload: Codable, Hashable, Sendable {
    var title: String
    var prompt: String
    var choices: [String]
    var placeName: String
    var answeredCorrectly: Bool?
    var resultText: String?
}

/// Live Activity shown when a story is waiting nearby ("Secret 30 m ahead").
nonisolated struct SecretActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var meters: Int
        var headline: String   // "Secret 30 m ahead"
        var detail: String     // "A story is waiting at Thermopolium"
    }
    var placeName: String
    var siteName: String
}
