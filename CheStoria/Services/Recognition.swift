import CoreLocation
import CoreML
import UIKit
import Vision

// MARK: - Images (asset or remote)

/// Loads `ImageRef`s: assets synchronously, remote URLs asynchronously with an in-memory cache
/// (and URLCache on disk).
final class ImageLoader {
    static let shared = ImageLoader()
    private let cache = NSCache<NSString, UIImage>()

    func cached(_ ref: ImageRef) -> UIImage? {
        switch ref {
        case .asset(let name): return UIImage(named: name)
        case .remote(let url): return cache.object(forKey: url.absoluteString as NSString)
        }
    }

    func load(_ ref: ImageRef) async -> UIImage? {
        if let hit = cached(ref) { return hit }
        guard case .remote(let url) = ref, let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: url.absoluteString as NSString)
        return image
    }
}

// MARK: - Recognition

/// What the photo turned out to be.
enum RecognitionResult: Equatable {
    case confident(Place)
    /// Several places look alike; ask the person (best guess first).
    case unsure([Place])
    /// Nothing matched well; offer nearby places.
    case none([Place])
}

/// A small colour-and-layout fingerprint: an HSV histogram plus an 8×8 brightness layout.
/// It runs everywhere (including the simulator, where Vision's feature-print model is unavailable)
/// and is good enough to tell apart the handful of places GPS leaves as candidates.
nonisolated struct ColorLayoutDescriptor: Sendable {
    let histogram: [Float]
    let layout: [Float]

    init?(_ image: CGImage) {
        let side = 32
        var px = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &px, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        var hist = [Float](repeating: 0, count: 12 * 3 * 3)
        var gray = [Float](repeating: 0, count: 64)
        for y in 0..<side {
            for x in 0..<side {
                let i = (y * side + x) * 4
                let r = Float(px[i]) / 255, g = Float(px[i + 1]) / 255, b = Float(px[i + 2]) / 255
                let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
                var h: Float = 0
                if d > 0.0001 {
                    if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
                    else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
                    h = (h < 0 ? h + 6 : h) / 6
                }
                let sat = mx > 0 ? d / mx : 0
                let hb = min(11, Int(h * 12)), sb = min(2, Int(sat * 3)), vb = min(2, Int(mx * 3))
                hist[(hb * 3 + sb) * 3 + vb] += 1
                gray[(y / 4) * 8 + x / 4] += 0.299 * r + 0.587 * g + 0.114 * b
            }
        }
        let total = Float(side * side)
        histogram = hist.map { $0 / total }
        let mean = gray.reduce(0, +) / 64
        let centred = gray.map { $0 - mean }
        let norm = max(0.0001, sqrt(centred.reduce(0) { $0 + $1 * $1 }))
        layout = centred.map { $0 / norm }
    }

    /// 0 (identical) … 1 (completely different).
    func distance(to other: ColorLayoutDescriptor) -> Float {
        let h = zip(histogram, other.histogram).reduce(0) { $0 + abs($1.0 - $1.1) } / 2
        let cos = zip(layout, other.layout).reduce(0) { $0 + $1.0 * $1.1 }
        return 0.65 * h + 0.35 * (1 - cos) / 2
    }
}

/// Compares a photo against each place's reference images. Uses Vision feature prints when they
/// work (real devices) and the colour-and-layout descriptor otherwise. New places only need
/// reference photos in the content; nothing is trained.
nonisolated final class FeaturePrintIndex: @unchecked Sendable {
    enum Backend: Sendable { case vision, descriptor }
    private var prints: [String: [VNFeaturePrintObservation]] = [:]
    private var descriptors: [String: [ColorLayoutDescriptor]] = [:]
    private(set) var backend: Backend = .vision
    /// The backend used for the most recent `rank` call (may fall back per photo).
    private(set) var lastBackend: Backend = .vision
    private let lock = NSLock()

    static func featurePrint(of image: CGImage) -> VNFeaturePrintObservation? {
        func run(cpuOnly: Bool) -> VNFeaturePrintObservation? {
            let request = VNGenerateImageFeaturePrintRequest()
            request.imageCropAndScaleOption = .scaleFill
            if cpuOnly, let cpu = MLComputeDevice.allComputeDevices.first(where: { if case .cpu = $0 { true } else { false } }) {
                request.setComputeDevice(cpu, for: .main)
            }
            guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil else { return nil }
            return request.results?.first as? VNFeaturePrintObservation
        }
        return run(cpuOnly: false) ?? run(cpuOnly: true)
    }

    func add(placeID: String, images: [CGImage]) {
        let fps = images.compactMap(Self.featurePrint(of:))
        let ds = images.compactMap(ColorLayoutDescriptor.init)
        lock.lock(); prints[placeID] = fps; descriptors[placeID] = ds; lock.unlock()
    }

    /// Picks Vision only if it clearly tells every pair of places apart. In the simulator (and if the
    /// model misbehaves) it returns identical vectors, so the descriptor is used instead.
    func chooseBackend() {
        lock.lock(); defer { lock.unlock() }
        let groups = prints.filter { !$0.value.isEmpty }
        guard groups.count >= 2, groups.count == descriptors.count else { backend = .descriptor; return }
        let ids = Array(groups.keys)
        for i in 0..<ids.count {
            for j in (i + 1)..<ids.count {
                for a in groups[ids[i]]! {
                    for b in groups[ids[j]]! {
                        var d: Float = 0
                        guard (try? a.computeDistance(&d, to: b)) != nil, d > 0.05 else { backend = .descriptor; return }
                    }
                }
            }
        }
        backend = .vision
    }

    var isEmpty: Bool { lock.lock(); defer { lock.unlock() }; return descriptors.isEmpty }

    /// Places sorted by their closest reference image (smaller distance = more alike).
    func rank(_ image: CGImage, among ids: Set<String>?) -> [(id: String, distance: Float)] {
        lock.lock(); let fps = prints, ds = descriptors, backend = self.backend; lock.unlock()
        var scores: [(String, Float)] = []
        switch backend {
        case .vision:
            if let query = Self.featurePrint(of: image) {
                for (id, refs) in fps where ids?.contains(id) ?? true {
                    let best = refs.compactMap { fp -> Float? in var d: Float = 0; return (try? query.computeDistance(&d, to: fp)) != nil ? d : nil }.min()
                    if let best { scores.append((id, best)) }
                }
            }
            // No real signal (missing or identical distances): judge this photo with the descriptor instead.
            let spread = (scores.map(\.1).max() ?? 0) - (scores.map(\.1).min() ?? 0)
            if scores.count < 2 || spread < 0.01 {
                scores = []
                if let query = ColorLayoutDescriptor(image) {
                    for (id, refs) in ds where ids?.contains(id) ?? true {
                        if let best = refs.map({ query.distance(to: $0) }).min() { scores.append((id, best)) }
                    }
                }
                lastBackend = .descriptor
                return scores.sorted { $0.1 < $1.1 }.map { (id: $0.0, distance: $0.1) }
            }
        case .descriptor:
            guard let query = ColorLayoutDescriptor(image) else { return [] }
            for (id, refs) in ds where ids?.contains(id) ?? true {
                if let best = refs.map({ query.distance(to: $0) }).min() { scores.append((id, best)) }
            }
        }
        lastBackend = backend
        return scores.sorted { $0.1 < $1.1 }.map { (id: $0.0, distance: $0.1) }
    }
}

/// Decides what a ranking means. Thresholds come from the site's `recognition` content block,
/// so they can be tuned on site (using the recognition log in Profile) without a code change.
enum RecognitionPolicy {
    /// If the person is further than this from every place, ignore location (e.g. testing at home).
    static let onSiteMeters: CLLocationDistance = 3_000

    static func decide(_ ranked: [(id: String, distance: Float)], places: [Place], backend: FeaturePrintIndex.Backend = .descriptor,
                       settings: SiteContent.Recognition = .init()) -> RecognitionResult {
        let lookup = { (id: String) in places.first { $0.id == id } }
        let cap = backend == .vision ? settings.visionMaxDistance : settings.descriptorMaxDistance
        let separation = settings.separation
        guard let best = ranked.first, let bestPlace = lookup(best.id), best.distance <= cap else {
            return .none(places)
        }
        if ranked.count > 1, best.distance > ranked[1].distance * separation {
            return .unsure(ranked.prefix(3).filter { $0.distance <= cap }.compactMap { lookup($0.id) })
        }
        return .confident(bestPlace)
    }

    static func candidates(_ places: [Place], near location: CLLocation?, nearbyMeters: CLLocationDistance = 500) -> [Place] {
        guard let loc = location else { return places }
        let withDistance = places.map { ($0, CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: loc)) }
        guard withDistance.contains(where: { $0.1 <= onSiteMeters }) else { return places }
        let near = withDistance.filter { $0.1 <= nearbyMeters }.map(\.0)
        return near.isEmpty ? places : near
    }
}

/// One recognition attempt, kept for the on-site tuning log in Profile.
struct RecognitionLogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let backend: FeaturePrintIndex.Backend
    let ranked: [(id: String, distance: Float)]
    let outcome: String
}

@Observable
final class PlaceMatcher {
    private var index = FeaturePrintIndex()
    private(set) var isReady = false
    private(set) var log: [RecognitionLogEntry] = []
    private var preparation: (site: String, task: Task<Void, Never>)?

    /// Computes fingerprints for every story place's reference images (off the main thread).
    /// Calling it again for the same site waits for the same work instead of starting over.
    func prepare(site: SiteContent) async {
        if let p = preparation, p.site == site.id { await p.task.value; return }
        isReady = false
        if preparation != nil { index = FeaturePrintIndex() }   // new site: start a fresh index
        let places = site.storyPlaces, index = self.index
        let task = Task { @MainActor in
            var jobs: [(String, [CGImage])] = []
            for place in places {
                var images: [CGImage] = []
                for ref in place.recognitionImages {
                    if let cg = await ImageLoader.shared.load(ref)?.normalizedCGImage { images.append(cg) }
                }
                jobs.append((place.id, images))
            }
            await Task.detached(priority: .utility) {
                for (id, imgs) in jobs { index.add(placeID: id, images: imgs) }
                index.chooseBackend()
            }.value
            self.isReady = true
        }
        preparation = (site.id, task)
        await task.value
    }

    /// Nearby places first; if none of them match (e.g. a gallery photo taken elsewhere), every place.
    func identify(_ photo: UIImage, in site: SiteContent, near location: CLLocation?) async -> RecognitionResult {
        await prepare(site: site)
        guard let cg = photo.normalizedCGImage else { return .none(site.storyPlaces) }
        let settings = site.recognitionSettings
        let nearby = RecognitionPolicy.candidates(site.storyPlaces, near: location, nearbyMeters: settings.nearbyMeters)
        let first = await rank(cg, among: nearby, settings: settings)
        if case .none = first, nearby.count < site.storyPlaces.count {
            let all = await rank(cg, among: site.storyPlaces, settings: settings)
            if case .none = all { return .none(nearby) }
            return all
        }
        return first
    }

    private func rank(_ cg: CGImage, among places: [Place], settings: SiteContent.Recognition) async -> RecognitionResult {
        let ids = Set(places.map(\.id)), index = self.index
        let ranked = await Task.detached(priority: .userInitiated) { index.rank(cg, among: ids) }.value
        let result = RecognitionPolicy.decide(ranked, places: places, backend: index.lastBackend, settings: settings)
        let outcome: String = switch result {
        case .confident(let p): "✓ \(p.name)"
        case .unsure(let ps): "? " + ps.map(\.name).joined(separator: " / ")
        case .none: "✗"
        }
        log.insert(RecognitionLogEntry(backend: index.lastBackend, ranked: ranked, outcome: outcome), at: 0)
        log = Array(log.prefix(20))
        #if DEBUG
        print("[Recognition] backend=\(index.lastBackend) ranked=\(ranked.map { "\($0.id)=\(String(format: "%.3f", $0.distance))" }) → \(result)")
        #endif
        return result
    }
}

extension UIImage {
    /// CGImage with orientation applied, so camera photos are compared upright.
    var normalizedCGImage: CGImage? {
        if imageOrientation == .up, let cg = cgImage { return cg }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let maxSide: CGFloat = 1024, s = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * s, height: size.height * s)
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }.cgImage
    }
}
