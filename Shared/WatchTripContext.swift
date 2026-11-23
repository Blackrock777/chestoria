import CoreLocation
import Foundation

/// A paired watch receives trip settings and discovered place IDs. Location stays on the device that reads it.
nonisolated struct WatchTripContext: Codable, Equatable, Sendable {
    static let transferKey = "watchTripContext.v1"

    let language: String
    let visited: [String: Set<String>]
    let hapticsEnabled: Bool
}

/// Shared by the watch and the iPhone Live Activity so both present the same nearby choices.
nonisolated struct NearbySecret: Identifiable, Equatable, Sendable {
    let siteID: String
    let place: Place
    let meters: Int
    var id: String { "\(siteID)/\(place.id)" }

    static let radius: CLLocationDistance = 150
    static let fixLifetime: TimeInterval = 30
    static let maximumAccuracy: CLLocationAccuracy = 65

    static func usable(_ fix: CLLocation, now: Date = .now) -> Bool {
        let age = now.timeIntervalSince(fix.timestamp)
        return CLLocationCoordinate2DIsValid(fix.coordinate) && fix.horizontalAccuracy > 0
            && fix.horizontalAccuracy <= maximumAccuracy && age >= -5 && age <= fixLifetime
    }

    static func choices(in sites: [SiteContent], fix: CLLocation?, visited: [String: Set<String>],
                        now: Date = .now) -> [NearbySecret] {
        guard let fix, usable(fix, now: now) else { return [] }

        let ranked = sites.flatMap { site in
            site.storyPlaces.compactMap { place -> (secret: NearbySecret, distance: CLLocationDistance)? in
                guard visited[site.id]?.contains(place.id) != true else { return nil }
                let distance = fix.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
                guard distance <= radius else { return nil }
                // Display approximate distance in 10 m steps instead of implying GPS precision.
                let meters = max(10, Int((distance / 10).rounded()) * 10)
                return (NearbySecret(siteID: site.id, place: place, meters: meters), distance)
            }
        }.sorted {
            if $0.distance == $1.distance { return $0.secret.id < $1.secret.id }
            return $0.distance < $1.distance
        }
        guard let nearest = ranked.first else { return [] }
        let ambiguity = max(25, fix.horizontalAccuracy)
        return ranked.prefix(2).filter { $0.distance - nearest.distance <= ambiguity }.map(\.secret)
    }
}
