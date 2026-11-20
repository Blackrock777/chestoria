import AVFoundation
import CoreLocation
import SwiftUI
import UIKit
@preconcurrency import UserNotifications

// MARK: - Place recognition

/// Picks the place you are looking at. GPS does most of the work; the photo only has to break ties.
/// This first version uses location only and falls back to the first story place (useful in the simulator).
@Observable
final class PlaceRecognizer: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let places: [Place]
    private(set) var lastLocation: CLLocation?

    init(places: [Place]) {
        self.places = places.filter { $0.story != nil }
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func start() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
    }

    /// Nearest story place and the distance to it, if we have a fix.
    var nearest: (place: Place, meters: Int?) {
        guard let loc = lastLocation, let best = places.min(by: { distance($0, loc) < distance($1, loc) }) else {
            return (places.last ?? places[0], 12)   // demo default: the Thermopolium, 12 m away
        }
        return (best, Int(distance(best, loc)))
    }

    private func distance(_ p: Place, _ loc: CLLocation) -> CLLocationDistance {
        CLLocation(latitude: p.latitude, longitude: p.longitude).distance(from: loc)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in self.lastLocation = loc }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

// MARK: - Camera

/// Owns the capture session off the main thread.
nonisolated final class CameraSession: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.chestoria.camera")
    private(set) var isConfigured = false

    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
        #endif
    }

    func start() {
        queue.async { [self] in
            if !isConfigured { configure() }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() { queue.async { [self] in if session.isRunning { session.stopRunning() } } }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }
        session.commitConfiguration()
        isConfigured = true
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

// MARK: - Haptics

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func pulse(intensity: CGFloat) { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: max(0.2, min(1, intensity))) }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func rigid() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
}

// MARK: - Read aloud

@MainActor @Observable
final class Narrator: NSObject, AVSpeechSynthesizerDelegate {
    @ObservationIgnored private let synth = AVSpeechSynthesizer()
    private(set) var isSpeaking = false

    override init() { super.init(); synth.delegate = self }

    func toggle(_ text: String) {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate); isSpeaking = false; return }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first)
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        synth.speak(u); isSpeaking = true
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

// MARK: - Next-morning recall

/// Schedules one quiet recall question for the next morning. Uses provisional authorisation,
/// so nobody is interrupted by a permission prompt; it lands silently in Notification Center.
enum RecallScheduler {
    static let category = "RECALL"

    static func schedule(for place: Place, story: Story, at hour: Int = 8, minute: Int = 12) {
        let center = UNUserNotificationCenter.current()
        let actions = story.recallChoices.enumerated().map { i, title in
            UNNotificationAction(identifier: "answer.\(i)", title: title, options: [])
        }
        let categoryID = category, prompt = story.recallPrompt, placeID = place.id, correct = story.correctIndex
        center.setNotificationCategories([UNNotificationCategory(identifier: categoryID, actions: actions, intentIdentifiers: [])])
        center.requestAuthorization(options: [.alert, .sound, .provisional]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "CheStoria"
            content.body = prompt
            content.categoryIdentifier = categoryID
            content.userInfo = ["place": placeID, "correct": correct]
            var when = Calendar.current.dateComponents([.year, .month, .day], from: .now.addingTimeInterval(86_400))
            when.hour = hour; when.minute = minute
            let request = UNNotificationRequest(identifier: "recall.\(placeID)", content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
            center.add(request)
        }
    }
}
