import ActivityKit
import CoreLocation
import Foundation
import UserNotifications
import WidgetKit

/// Handles answers tapped on the next-morning notification: confirms right or wrong straight away,
/// records it for the "Remembered" stat and updates the widget.
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()
    var onAnswer: ((Bool) -> Void)?

    func activate() { UNUserNotificationCenter.current().delegate = self }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        guard action.hasPrefix("answer."), let chosen = Int(action.dropFirst("answer.".count)),
              let correct = info["correct"] as? Int, let right = info["rightText"] as? String, let wrong = info["wrongText"] as? String else {
            completionHandler(); return
        }
        let ok = chosen == correct
        let content = UNMutableNotificationContent()
        content.title = "CheStoria"
        content.body = ok ? right : wrong
        center.add(UNNotificationRequest(identifier: "recall.result.\(UUID().uuidString)", content: content,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
        Task { @MainActor in
            self.onAnswer?(ok)
            if var payload = SharedStore.loadRecall() {
                payload.answeredCorrectly = ok; payload.resultText = ok ? right : wrong
                SharedStore.saveRecall(payload)
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
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
