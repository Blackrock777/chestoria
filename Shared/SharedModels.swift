import ActivityKit
import Foundation

/// Live Activity shown when a story is waiting nearby ("Secret 30 m ahead").
nonisolated struct SecretActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var meters: Int
        var headline: String   // "Secret 30 m ahead"
        var detail: String     // "A story is waiting at Thermopolium"
        var watchTitle: String?
        var watchDetail: String?
        var watchExpired: String?
    }
    var placeName: String
    var siteName: String
}
