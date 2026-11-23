import Foundation
import WatchConnectivity

/// The phone owns trip progress. The latest snapshot replaces any older queued snapshot.
final class PhoneWatchSync: NSObject, WCSessionDelegate {
    private var pending: WatchTripContext?
    private let session = WCSession.isSupported() ? WCSession.default : nil

    override init() {
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func publish(_ context: WatchTripContext) {
        pending = context
        send()
    }

    private func send() {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let pending, let data = try? JSONEncoder().encode(pending) else { return }
        try? session.updateApplicationContext([WatchTripContext.transferKey: data])
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in send() }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in send() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
