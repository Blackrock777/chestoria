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
    /// One place, clearly.
    case confident(Place)
    /// Probably one of these (best first); `label` says what the AI sees, e.g. "a church façade".
    case unsure([Place], label: String?)
    /// Not one of our places. `label` is what it looks like ("a cup of coffee");
    /// `heritage` is true when it still looks historic (a place we have no story for yet).
    case notAPlace(label: String?, heritage: Bool, nearby: [Place])
}

/// What the camera sees right now, updated a few times a second.
struct LiveGuess: Equatable {
    let label: String?
    let heritage: Bool
    let place: Place?
}

/// SigLIP image encoder (google/siglip-base-patch16-224, Apache-2.0) running on device with Core ML.
/// Produces a 768-d, L2-normalised embedding for any image or camera frame.
nonisolated final class SigLIPEmbedder: @unchecked Sendable {
    static let shared = SigLIPEmbedder()
    private let request: VNCoreMLRequest?
    private let lock = NSLock()

    var isAvailable: Bool { request != nil }

    private init() {
        let config = MLModelConfiguration()
        #if targetEnvironment(simulator)
        config.computeUnits = .cpuOnly
        #endif
        if let url = Bundle.main.url(forResource: "SigLIPVision", withExtension: "mlmodelc"),
           let model = try? MLModel(contentsOf: url, configuration: config), let vn = try? VNCoreMLModel(for: model) {
            let r = VNCoreMLRequest(model: vn)
            r.imageCropAndScaleOption = .centerCrop
            request = r
        } else {
            request = nil
        }
    }

    func embed(_ image: CGImage) -> [Float]? { run(VNImageRequestHandler(cgImage: image, options: [:])) }
    func embed(_ buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .right) -> [Float]? {
        run(VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation, options: [:]))
    }

    private func run(_ handler: VNImageRequestHandler) -> [Float]? {
        guard let request else { return nil }
        lock.lock(); defer { lock.unlock() }
        guard (try? handler.perform([request])) != nil,
              let array = (request.results?.first as? VNCoreMLFeatureValueObservation)?.featureValue.multiArrayValue else { return nil }
        var v = (0..<array.count).map { Float(truncating: array[$0]) }
        let n = sqrt(v.reduce(0) { $0 + $1 * $1 })
        if n > 0 { v = v.map { $0 / n } }
        return v
    }

    static func dot(_ a: [Float], _ b: [Float]) -> Float {
        var s: Float = 0
        for i in 0..<min(a.count, b.count) { s += a[i] * b[i] }
        return s
    }
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

/// Scores for one photo against every candidate place and every label.
nonisolated struct PhotoScores: Sendable {
    /// (place id, best similarity to its reference photos, best similarity to its descriptions)
    var places: [(id: String, image: Float, text: Float)]
    /// Labels ranked by similarity.
    var labels: [(label: AIVocabulary.Label, score: Float)]
    var usedAI: Bool
}

/// Reference-photo index for one site. With the AI model it stores SigLIP embeddings;
/// without it (model missing), colour-and-layout descriptors.
nonisolated final class PlaceIndex: @unchecked Sendable {
    private var embeddings: [String: [[Float]]] = [:]
    private var descriptors: [String: [ColorLayoutDescriptor]] = [:]
    private let lock = NSLock()

    func add(placeID: String, images: [CGImage]) {
        let e = SigLIPEmbedder.shared.isAvailable ? images.compactMap { SigLIPEmbedder.shared.embed($0) } : []
        let d = images.compactMap(ColorLayoutDescriptor.init)
        lock.lock(); embeddings[placeID] = e; descriptors[placeID] = d; lock.unlock()
    }

    func scores(for image: CGImage? = nil, embedding: [Float]? = nil, among ids: Set<String>, vocabulary: AIVocabulary?) -> PhotoScores {
        lock.lock(); let emb = embeddings, ds = descriptors; lock.unlock()
        if let e = embedding ?? image.flatMap({ SigLIPEmbedder.shared.embed($0) }) {
            let places = ids.map { id -> (id: String, image: Float, text: Float) in
                let img = emb[id]?.map { SigLIPEmbedder.dot(e, $0) }.max() ?? 0
                let txt = vocabulary?.placeText[id]?.map { SigLIPEmbedder.dot(e, $0) }.max() ?? 0
                return (id, img, txt)
            }
            let labels = (vocabulary?.labels ?? []).map { ($0, SigLIPEmbedder.dot(e, $0.embedding)) }.sorted { $0.1 > $1.1 }
            return PhotoScores(places: places, labels: labels.map { (label: $0.0, score: $0.1) }, usedAI: true)
        }
        // Fallback: descriptor distance (0 best) turned into a similarity (1 best).
        guard let image, let q = ColorLayoutDescriptor(image) else { return PhotoScores(places: [], labels: [], usedAI: false) }
        let places = ids.map { id in (id: id, image: 1 - (ds[id]?.map { q.distance(to: $0) }.min() ?? 1), text: Float(0)) }
        return PhotoScores(places: places, labels: [], usedAI: false)
    }
}

/// Turns scores into a decision. Thresholds come from the site's `recognition` block in content,
/// so they can be tuned on site (Profile → Recognition log) without a code change.
nonisolated enum RecognitionPolicy {
    /// If the person is further than this from every place, ignore location (e.g. testing at home).
    static let onSiteMeters: CLLocationDistance = 3_000

    static func decide(_ s: PhotoScores, places: [Place], settings: SiteContent.Recognition, language: String, vocabulary: AIVocabulary?) -> RecognitionResult {
        let lookup = { (id: String) in places.first { $0.id == id } }
        let label = s.labels.first
        let labelName = label.map { vocabulary?.name($0.label, language: language) ?? $0.label.id }
        let heritageLooking = s.labels.prefix(3).first.map(\.label.heritage) ?? true
        guard !s.places.isEmpty else { return .notAPlace(label: labelName, heritage: heritageLooking, nearby: places) }

        if s.usedAI {
            let byImage = s.places.sorted { $0.image > $1.image }
            let best = byImage[0], second = byImage.count > 1 ? byImage[1].image : 0
            let minimum = heritageLooking ? settings.possible - 0.08 : settings.possible
            let ranked = byImage.filter { $0.image >= minimum }
                .sorted { $0.image + settings.textWeight * $0.text > $1.image + settings.textWeight * $1.text }
            // Image similarity can confuse ordinary windows/balconies with a landmark.
            // Compare text scores with text scores: an everyday-object description that
            // beats the candidate's own descriptions is evidence against that identity.
            if let label, !label.label.heritage,
               vocabulary?.placeText[best.id]?.isEmpty == false,
               label.score > best.text {
                if best.image < settings.possible {
                    return .notAPlace(label: labelName, heritage: false, nearby: places)
                }
                // Preserve plausible landmarks for explicit confirmation, but never
                // auto-open one when its semantics conflict with the photograph.
                return .unsure(byImage.prefix(3).filter { $0.image >= settings.possible }.compactMap { lookup($0.id) }, label: labelName)
            }
            let competingDescription = ranked.contains {
                $0.id != best.id && $0.image >= settings.possible
                    && best.image - $0.image <= 2 * settings.margin && $0.text > best.text + 0.04
            }
            if best.image >= settings.confident, best.image - second >= settings.margin,
               !competingDescription, let p = lookup(best.id) { return .confident(p) }
            if !ranked.isEmpty {
                return .unsure(ranked.prefix(3).compactMap { lookup($0.id) }, label: labelName)
            }
            return .notAPlace(label: labelName, heritage: heritageLooking, nearby: places)
        }
        // Descriptor fallback (no AI model): similarity = 1 - distance.
        let ranked = s.places.sorted { $0.image > $1.image }
        let cap = 1 - settings.descriptorCap
        guard ranked[0].image >= cap, let p = lookup(ranked[0].id) else { return .notAPlace(label: nil, heritage: true, nearby: places) }
        if ranked.count > 1, (1 - ranked[0].image) > (1 - ranked[1].image) * settings.separationRatio {
            return .unsure(ranked.prefix(3).filter { $0.image >= cap }.compactMap { lookup($0.id) }, label: nil)
        }
        // Colour/layout alone is not reliable enough to identify a monument.
        return .unsure([p], label: nil)
    }

    /// Places the camera doesn't recognise (indoor art, no-photo rooms) are offered when you are
    /// standing at one, by real GPS, unless the photo clearly matched another place.
    static let hereMeters: CLLocationDistance = 150
    static func offeringPlacesHere(_ result: RecognitionResult, site: SiteContent, location: CLLocation?) -> RecognitionResult {
        guard let loc = location else { return result }
        let here = site.storyPlaces.filter { !$0.usesCamera && CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: loc) <= hereMeters }
            .sorted { CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: loc) < CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: loc) }
        guard !here.isEmpty else { return result }
        switch result {
        case .confident: return result
        case .unsure(let ps, let label): return .unsure(Array((here + ps).prefix(3)), label: label)
        case .notAPlace(let label, _, _): return .unsure(Array(here.prefix(3)), label: label)
        }
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
    let usedAI: Bool
    let places: [(id: String, image: Float, text: Float)]
    let topLabels: [String]
    let outcome: String
}

@Observable
final class PlaceMatcher {
    private var indexes: [String: PlaceIndex] = [:]
    private(set) var log: [RecognitionLogEntry] = []
    private(set) var live: LiveGuess?
    private var preparations: [String: Task<PlaceIndex, Never>] = [:]
    private var liveBusy = false
    private var liveGeneration = 0
    private var lastLiveCandidate: String?

    var usesAI: Bool { SigLIPEmbedder.shared.isAvailable }

    /// Embeds every story place's reference photos (off the main thread). Calling it again for the
    /// same site waits for the same work instead of starting over.
    func prepare(site: SiteContent) async {
        _ = await preparedIndex(for: site)
    }

    private func preparedIndex(for site: SiteContent) async -> PlaceIndex {
        if let index = indexes[site.id] { return index }
        if let task = preparations[site.id] { return await task.value }
        let places = site.cameraPlaces, index = PlaceIndex()
        let task = Task { @MainActor in
            var jobs: [(String, [CGImage])] = []
            for place in places {
                var images: [CGImage] = []
                for ref in place.recognitionImages {
                    if let cg = await ImageLoader.shared.load(ref)?.normalizedCGImage { images.append(cg) }
                }
                jobs.append((place.id, images))
            }
            await Task.detached(priority: .utility) { for (id, imgs) in jobs { index.add(placeID: id, images: imgs) } }.value
            self.indexes[site.id] = index
            self.preparations[site.id] = nil
            return index
        }
        preparations[site.id] = task
        return await task.value
    }

    /// Compare all camera places visually; use location for nearby suggestions after an unknown photo.
    func identify(_ photo: UIImage, in site: SiteContent, near location: CLLocation?, catalog: Catalog) async -> RecognitionResult {
        let index = await preparedIndex(for: site)
        guard let cg = photo.normalizedCGImage else { return .notAPlace(label: nil, heritage: false, nearby: site.storyPlaces) }
        let settings = site.recognitionSettings
        let camera = site.cameraPlaces
        let nearby = RecognitionPolicy.candidates(camera, near: location, nearbyMeters: settings.nearby)
        let ids = Set(camera.map(\.id)), vocabulary = catalog.vocabulary
        let scores = await Task.detached(priority: .userInitiated) {
            index.scores(for: cg, among: ids, vocabulary: vocabulary)
        }.value
        // Confidence must include every visual competitor. GPS may narrow suggestions,
        // but must never manufacture a winning margin by removing the runner-up.
        var result = RecognitionPolicy.decide(scores, places: camera, settings: settings, language: catalog.language, vocabulary: catalog.vocabulary)
        if case .notAPlace(let label, let heritage, _) = result {
            result = .notAPlace(label: label, heritage: heritage, nearby: nearby)
        }
        result = RecognitionPolicy.offeringPlacesHere(result, site: site, location: location)
        record(scores, result: result)
        return result
    }

    /// Real-time guess for a camera frame (or the simulator's stand-in photo). Drops frames while busy.
    func liveGuess(buffer: CVPixelBuffer? = nil, image: CGImage? = nil, site: SiteContent, catalog: Catalog) {
        guard usesAI, let index = indexes[site.id], !liveBusy else { return }
        liveBusy = true
        let ids = Set(site.cameraPlaces.map(\.id)), vocab = catalog.vocabulary
        let generation = liveGeneration
        let settings = site.recognitionSettings, language = catalog.language, places = site.cameraPlaces
        nonisolated(unsafe) let frame = buffer
        Task.detached(priority: .userInitiated) {
            let e = frame.flatMap { SigLIPEmbedder.shared.embed($0) } ?? image.flatMap { SigLIPEmbedder.shared.embed($0) }
            let s = index.scores(embedding: e, among: ids, vocabulary: vocab)
            let decision = RecognitionPolicy.decide(s, places: places, settings: settings, language: language, vocabulary: vocab)
            let label = s.labels.first
            await MainActor.run {
                self.liveBusy = false
                guard generation == self.liveGeneration, e != nil else { return }
                let candidate: Place? = if case .confident(let p) = decision { p } else { nil }
                let place = candidate?.id == self.lastLiveCandidate ? candidate : nil
                self.lastLiveCandidate = candidate?.id
                self.live = LiveGuess(label: label.map { vocab?.name($0.label, language: language) ?? $0.label.id }, heritage: label?.label.heritage ?? false, place: place)
            }
        }
    }

    func clearLive() {
        liveGeneration += 1
        lastLiveCandidate = nil
        live = nil
    }

    private func record(_ s: PhotoScores, result: RecognitionResult) {
        let outcome: String = switch result {
        case .confident(let p): "✓ \(p.name)"
        case .unsure(let ps, let l): "? " + ps.map(\.name).joined(separator: " / ") + (l.map { " (\($0))" } ?? "")
        case .notAPlace(let l, let h, _): "✗ " + (l ?? "unknown") + (h ? " · heritage" : "")
        }
        #if DEBUG
        print("[Recognition] ai=\(s.usedAI) places=\(s.places.sorted { $0.image > $1.image }.map { "\($0.id)=\(String(format: "%.3f/%.3f", $0.image, $0.text))" }) labels=\(s.labels.prefix(3).map { "\($0.label.id)=\(String(format: "%.3f", $0.score))" }) → \(outcome)")
        #endif
        log.insert(RecognitionLogEntry(usedAI: s.usedAI, places: s.places.sorted { $0.image > $1.image }, topLabels: s.labels.prefix(3).map(\.label.id), outcome: outcome), at: 0)
        log = Array(log.prefix(20))
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
