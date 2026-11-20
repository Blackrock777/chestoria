import AVFoundation
import CoreLocation
import SwiftUI
import UIKit
@preconcurrency import UserNotifications

// MARK: - Place recognition

/// Knows where the person is. Recognition uses it to narrow candidates; the Snap chip shows the nearest place.
@Observable
final class PlaceRecognizer: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var lastLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func start() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
    }

    /// Nearest story place and its distance. Without a fix (or far from the site) it falls back to the site's featured place.
    func nearest(in site: SiteContent) -> (place: Place, meters: Int?) {
        let places = site.storyPlaces
        let fallback = (site.featured ?? places[0], Optional(12))
        guard let loc = lastLocation, let best = places.min(by: { distance($0, loc) < distance($1, loc) }) else { return fallback }
        let d = distance(best, loc)
        return d > RecognitionPolicy.onSiteMeters ? fallback : (best, Int(d))
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
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "app.chestoria.camera")
    private(set) var isConfigured = false
    private var pending: PhotoDelegate?

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

    /// Takes a photo. Returns nil in the simulator or if capture fails.
    func capture() async -> UIImage? {
        guard Self.isAvailable else { return nil }
        return await withCheckedContinuation { cont in
            queue.async { [self] in
                guard session.isRunning else { cont.resume(returning: nil); return }
                let delegate = PhotoDelegate { image in cont.resume(returning: image) }
                pending = delegate
                output.capturePhoto(with: AVCapturePhotoSettings(), delegate: delegate)
            }
        }
    }

    private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
        let done: (UIImage?) -> Void
        init(done: @escaping (UIImage?) -> Void) { self.done = done }
        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            done(photo.fileDataRepresentation().flatMap(UIImage.init(data:)))
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(output) { session.addOutput(output) }
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
    private static var on: Bool { UserDefaults.standard.bool(forKey: Settings.haptics) }
    static func tap() { guard on else { return }; UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func pulse(intensity: CGFloat) { guard on else { return }; UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: max(0.2, min(1, intensity))) }
    static func success() { guard on else { return }; UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func rigid() { guard on else { return }; UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
}

// MARK: - Read aloud

@MainActor @Observable
final class Narrator: NSObject, AVSpeechSynthesizerDelegate {
    @ObservationIgnored private let synth = AVSpeechSynthesizer()
    private(set) var isSpeaking = false

    override init() { super.init(); synth.delegate = self }

    func stop() { if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }; isSpeaking = false }

    /// Reads `text` in the story language (e.g. "it"), or stops if already reading.
    func toggle(_ text: String, language: String) {
        if synth.isSpeaking { stop(); return }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: language)
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
        guard UserDefaults.standard.bool(forKey: Settings.recall) else { return }
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
