import ActivityKit
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
    private var activity: Activity<SecretActivityAttributes>?
    /// Only nudge when a story is genuinely close.
    static let triggerMeters = 150

    func update(status: LocationStatus, site: SiteContent, visited: Set<String>, strings: UIStrings) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard case .near(let place, let meters) = status, meters <= Self.triggerMeters, place.story != nil, !visited.contains(place.id) else {
            end(); return
        }
        let state = SecretActivityAttributes.ContentState(meters: meters, headline: strings("activity.secret", "\(meters)"),
                                                         detail: strings("activity.at", place.name))
        if let a = activity, a.attributes.placeName == place.name {
            let id = a.id
            Task {
                for act in Activity<SecretActivityAttributes>.activities where act.id == id {
                    await act.update(ActivityContent(state: state, staleDate: .now.addingTimeInterval(600)))
                }
            }
        } else {
            end()
            activity = try? Activity.request(attributes: SecretActivityAttributes(placeName: place.name, siteName: site.city),
                                             content: ActivityContent(state: state, staleDate: .now.addingTimeInterval(600)))
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
