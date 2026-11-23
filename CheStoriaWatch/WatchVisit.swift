import CoreLocation
import Observation
import UserNotifications
import WatchConnectivity
import WatchKit

@Observable
final class WatchTripSync: NSObject, WCSessionDelegate {
    private(set) var context: WatchTripContext?
    var onReceive: ((WatchTripContext) -> Void)?
    private let defaults = UserDefaults.standard

    override init() {
        super.init()
        if let data = defaults.data(forKey: WatchTripContext.transferKey) { receive(data) }
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    private func receive(_ data: Data) {
        guard let update = try? JSONDecoder().decode(WatchTripContext.self, from: data) else { return }
        context = update
        defaults.set(data, forKey: WatchTripContext.transferKey)
        onReceive?(update)
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated, let data = session.receivedApplicationContext[WatchTripContext.transferKey] as? Data else { return }
        Task { @MainActor in receive(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[WatchTripContext.transferKey] as? Data else { return }
        Task { @MainActor in receive(data) }
    }
}

@Observable
final class WatchWalk: NSObject, CLLocationManagerDelegate, UNUserNotificationCenterDelegate {
    private let walkDuration: TimeInterval = 2 * 60 * 60
    private let manager = CLLocationManager()
    private let notifications = UNUserNotificationCenter.current()
    private let notificationID = "chestoria.watch.nearby"
    private(set) var walking = false
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var fix: CLLocation?
    private(set) var nearbyNotificationTap: UUID?
    private var active = false
    private var announced = Set<String>()
    private var lastCue: Date?
    private var backgroundSession: CLBackgroundActivitySession?
    private var endTask: Task<Void, Never>?
    private var walkEndsAt: Date?
    private var allowNotifications = false
    private var askedForNotifications = false
    private var sites: [SiteContent] = []
    private var visited: [String: Set<String>] = [:]
    private var strings = UIStrings.empty
    private var alertsEnabled = true

    override init() {
        super.init()
        authorization = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        notifications.delegate = self
    }

    func configure(catalog: Catalog, context: WatchTripContext?) {
        sites = catalog.sites
        strings = catalog.strings
        applyTrip(context)
    }

    func applyTrip(_ context: WatchTripContext?) {
        visited = context?.visited ?? [:]
        alertsEnabled = context?.hapticsEnabled ?? true
        if walking && active { requestNotificationsIfNeeded() }
    }

    func start() {
        guard !walking else { return }
        walking = true
        walkEndsAt = .now.addingTimeInterval(walkDuration)
        updateLocation()
        let duration = walkDuration
        endTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(duration)) } catch { return }
            self?.stop()
        }
    }

    func stop() {
        walking = false
        walkEndsAt = nil
        endTask?.cancel()
        endTask = nil
        announced.removeAll()
        lastCue = nil
        updateLocation()
        notifications.removePendingNotificationRequests(withIdentifiers: [notificationID])
        notifications.removeDeliveredNotifications(withIdentifiers: [notificationID])
    }

    func setActive(_ active: Bool) {
        self.active = active
        if let walkEndsAt, walkEndsAt <= .now { stop() } else { updateLocation() }
    }

    private func updateLocation() {
        guard walking, authorization != .denied, authorization != .restricted else {
            manager.stopUpdatingLocation()
            manager.allowsBackgroundLocationUpdates = false
            backgroundSession?.invalidate()
            backgroundSession = nil
            fix = nil
            return
        }
        guard active else { return }
        switch authorization {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            if backgroundSession == nil {
                backgroundSession = CLBackgroundActivitySession()
                manager.allowsBackgroundLocationUpdates = true
                manager.startUpdatingLocation()
            }
            requestNotificationsIfNeeded()
        default: break
        }
    }

    private func requestNotificationsIfNeeded() {
        guard alertsEnabled, backgroundSession != nil, !askedForNotifications else { return }
        askedForNotifications = true
        Task {
            allowNotifications = (try? await notifications.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    private func cue(for secrets: [NearbySecret], now: Date = .now) {
        let ids = Set(secrets.map(\.id))
        guard walking, alertsEnabled, active || allowNotifications, let first = secrets.first, announced.isDisjoint(with: ids),
              lastCue.map({ now.timeIntervalSince($0) >= 60 }) ?? true else { return }
        announced.formUnion(ids)
        lastCue = now
        if active {
            WKInterfaceDevice.current().play(.directionUp)
        } else {
            let content = UNMutableNotificationContent()
            content.title = strings(secrets.count == 1 ? "watch.nearby" : "watch.twoNearby")
            content.body = secrets.count == 1 ? "\(first.place.name) · \(strings("watch.distance", "\(first.meters)"))" :
                secrets.map(\.place.name).joined(separator: " · ")
            content.sound = .default
            notifications.add(UNNotificationRequest(identifier: notificationID, content: content, trigger: nil))
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorization = status
            updateLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            guard walking, authorization == .authorizedAlways || authorization == .authorizedWhenInUse else { return }
            if let walkEndsAt, walkEndsAt <= .now { stop(); return }
            fix = location
            cue(for: NearbySecret.choices(in: sites, fix: location, visited: visited))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Task { @MainActor in fix = nil }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in nearbyNotificationTap = UUID() }
        completionHandler()
    }
}
