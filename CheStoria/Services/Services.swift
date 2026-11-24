import AVFoundation
import CoreLocation
import SwiftUI
import UIKit

// MARK: - Place recognition

/// What the Snap chip should honestly say about where you are.
enum LocationStatus: Equatable {
    case off                       // location permission is unavailable
    case locating                  // permission granted, no fix yet
    case near(Place, meters: Int)  // at the site
    case far(siteName: String, distance: String)
}

extension LocationStatus {
    /// Pure so it can be tested: never invents a distance.
    static func compute(site: SiteContent, location: CLLocation?, authorization: CLAuthorizationStatus, locale: Locale = .current) -> LocationStatus {
        guard authorization == .authorizedWhenInUse || authorization == .authorizedAlways else { return .off }
        func d(_ p: Place, _ l: CLLocation) -> CLLocationDistance { CLLocation(latitude: p.latitude, longitude: p.longitude).distance(from: l) }
        guard let loc = location, let best = site.storyPlaces.min(by: { d($0, loc) < d($1, loc) }) else { return .locating }
        let meters = d(best, loc)
        if meters <= RecognitionPolicy.onSiteMeters { return .near(best, meters: Int(meters)) }
        let km = Measurement(value: site.centre.distance(from: loc) / 1000, unit: UnitLength.kilometers)
        return .far(siteName: site.city, distance: km.formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale)))
    }
}

/// Knows where the person is. Recognition uses it to narrow candidates; the Snap chip shows the truth.
@Observable
final class PlaceRecognizer: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var lastLocation: CLLocation?
    private(set) var authorization: CLAuthorizationStatus

    override init() {
        authorization = CLLocationManager().authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func start() {
        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else { return }
        manager.startUpdatingLocation()
    }

    func requestPermission() { manager.requestWhenInUseAuthorization() }

    func status(in site: SiteContent, locale: Locale = .current) -> LocationStatus {
        LocationStatus.compute(site: site, location: lastLocation, authorization: authorization, locale: locale)
    }

    /// Another site in the catalog that you are standing in (within 3 km), if any.
    func siteNearby(in catalog: Catalog, current: SiteContent) -> SiteContent? {
        guard let loc = lastLocation else { return nil }
        return catalog.sites.first { $0.id != current.id && $0.places.contains { distance($0, loc) <= RecognitionPolicy.onSiteMeters } }
    }

    /// The place to fall back on when there is no photo: the nearest one at the site, else the featured place.
    func fallbackPlace(in site: SiteContent) -> Place {
        if case .near(let p, _) = status(in: site) { return p }
        return site.featured ?? site.storyPlaces[0]
    }

    private func distance(_ p: Place, _ loc: CLLocation) -> CLLocationDistance {
        CLLocation(latitude: p.latitude, longitude: p.longitude).distance(from: loc)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in self.lastLocation = loc }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.start()
            } else {
                self.manager.stopUpdatingLocation()
                self.lastLocation = nil
            }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

// MARK: - Camera

/// Owns the capture session off the main thread.
nonisolated final class CameraSession: @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let video = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "app.chestoria.camera")
    private let frameQueue = DispatchQueue(label: "app.chestoria.frames")
    private(set) var isConfigured = false
    private var pending: PhotoDelegate?
    private let frames = FrameDelegate()
    private var device: AVCaptureDevice?
    /// Called with a camera frame about twice a second, for live AI recognition.
    func setFrameHandler(_ handler: (@Sendable (CVPixelBuffer) -> Void)?) {
        frameQueue.async { [frames] in frames.onFrame = handler }
    }

    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
        #endif
    }

    func start() {
        queue.async { [self] in
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
            if !isConfigured { configure() }
            if device != nil && !session.isRunning { session.startRunning() }
        }
    }

    func stop() { queue.async { [self] in if session.isRunning { session.stopRunning() } } }

    func zoom(to factor: CGFloat) {
        queue.async { [self] in
            guard let device, (try? device.lockForConfiguration()) != nil else { return }
            defer { device.unlockForConfiguration() }
            device.videoZoomFactor = min(device.maxAvailableVideoZoomFactor, max(device.minAvailableVideoZoomFactor, factor))
        }
    }

    /// Takes a photo. Returns nil in the simulator or if capture fails.
    func capture() async -> UIImage? {
        guard Self.isAvailable else { return nil }
        return await withCheckedContinuation { cont in
            queue.async { [self] in
                guard pending == nil, session.isRunning,
                      let connection = output.connection(with: .video), connection.isActive, connection.isEnabled else {
                    cont.resume(returning: nil)
                    return
                }
                let delegate = PhotoDelegate { [self] image in
                    queue.async { [self] in
                        pending = nil
                        cont.resume(returning: image)
                    }
                }
                pending = delegate
                output.capturePhoto(with: AVCapturePhotoSettings(), delegate: delegate)
            }
        }
    }

    private final class FrameDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
        var onFrame: (@Sendable (CVPixelBuffer) -> Void)?
        private var last = Date.distantPast
        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            guard Date().timeIntervalSince(last) > 0.5, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            last = Date()
            onFrame?(buffer)
        }
    }

    private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
        let done: (UIImage?) -> Void
        private var image: UIImage?
        init(done: @escaping (UIImage?) -> Void) { self.done = done }
        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            if error == nil { image = photo.fileDataRepresentation().flatMap(UIImage.init(data:)) }
        }
        func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor settings: AVCaptureResolvedPhotoSettings, error: Error?) {
            done(error == nil ? image : nil)
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
            self.device = device
        }
        if session.canAddOutput(output) { session.addOutput(output) }
        video.alwaysDiscardsLateVideoFrames = true
        video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        video.setSampleBufferDelegate(frames, queue: frameQueue)
        if session.canAddOutput(video) { session.addOutput(video) }
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
    @ObservationIgnored private let audioSession = AVAudioSession.sharedInstance()
    @ObservationIgnored private var utteranceID: ObjectIdentifier?
    private(set) var isSpeaking = false

    override init() {
        super.init()
        synth.usesApplicationAudioSession = true
        synth.delegate = self
    }

    func stop() {
        guard let utteranceID else { return }
        synth.stopSpeaking(at: .immediate)
        finish(utteranceID)
    }

    /// Reads `text` in the story language (e.g. "it"), or stops if already reading.
    func toggle(_ text: String, language: String) throws {
        if isSpeaking {
            stop()
            return
        }
        // Playback honors the media volume and lets an explicit Listen tap play in Silent Mode.
        try audioSession.setCategory(.playback, mode: .default, options: .duckOthers)
        try audioSession.setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utteranceID = ObjectIdentifier(utterance)
        isSpeaking = true
        synth.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in finish(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in finish(id) }
    }

    private func finish(_ id: ObjectIdentifier) {
        guard utteranceID == id else { return }
        utteranceID = nil
        isSpeaking = false
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
