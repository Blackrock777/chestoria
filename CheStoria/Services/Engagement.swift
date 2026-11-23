import ActivityKit
import CoreLocation
import Foundation
import UserNotifications

/// Removes previously scheduled recall prompts after upgrading.
enum RetiredRecall {
    static func clearNotifications() {
        let center = UNUserNotificationCenter.current()
        Task {
            let pending = await center.pendingNotificationRequests().map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.hasPrefix("recall.") })
            let delivered = await center.deliveredNotifications().map(\.request.identifier)
            center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.hasPrefix("recall.") })
        }
    }
}

/// Starts, updates and ends the "Secret nearby" Live Activity from the Snap screen's location status.
final class LiveActivityController {
    static let shared = LiveActivityController()
    private var activity = Activity<SecretActivityAttributes>.activities.first

    func update(fix: CLLocation?, authorization: CLAuthorizationStatus, site: SiteContent, visited: Set<String>, strings: UIStrings) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              authorization == .authorizedWhenInUse || authorization == .authorizedAlways else { end(); return }
        let choices = NearbySecret.choices(in: [site], fix: fix, visited: [site.id: visited])
        guard let first = choices.first, let fix else {
            end(); return
        }
        let multiple = choices.count > 1
        let names = choices.map(\.place.name).joined(separator: " · ")
        let watchDetail = multiple ? names : [first.place.name, first.place.clues.first].compactMap { $0 }.joined(separator: " · ")
        let state = SecretActivityAttributes.ContentState(
            meters: first.meters,
            headline: multiple ? strings("watch.twoNearby") : strings("activity.secret", "\(first.meters)"),
            detail: multiple ? names : strings("activity.at", first.place.name),
            watchTitle: multiple ? strings("watch.twoNearby") : strings("watch.nearby"),
            watchDetail: watchDetail, watchExpired: strings("watch.locationStale")
        )
        let staleDate = fix.timestamp.addingTimeInterval(NearbySecret.fixLifetime)
        if let a = activity, a.attributes.siteName == site.city {
            guard a.content.state != state || (a.content.staleDate?.timeIntervalSinceNow ?? 0) < 15 else { return }
            let id = a.id
            Task { await Self.updateActivity(id: id, state: state, staleDate: staleDate) }
        } else {
            end()
            activity = try? Activity.request(attributes: SecretActivityAttributes(placeName: first.place.name, siteName: site.city),
                                             content: ActivityContent(state: state, staleDate: staleDate))
        }
    }

    @concurrent private static func updateActivity(id: String, state: SecretActivityAttributes.ContentState, staleDate: Date) async {
        for activity in Activity<SecretActivityAttributes>.activities where activity.id == id {
            await activity.update(ActivityContent(state: state, staleDate: staleDate))
        }
    }

    func end() {
        guard let id = activity?.id else { return }
        activity = nil
        Task {
            for act in Activity<SecretActivityAttributes>.activities where act.id == id { await act.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
