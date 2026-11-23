import Foundation
import CoreLocation

// MARK: - Small value types

nonisolated struct NormalizedPoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
}

nonisolated struct NormalizedRect: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

/// A point in map units, written in JSON as `[x, y]`.
nonisolated struct MapPoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Double.self); y = try c.decode(Double.self)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer(); try c.encode(x); try c.encode(y)
    }
}

/// An image is either an asset compiled into the app (`"forum"`) or a URL (`"https://…/forum.jpg"`).
/// Remote images let new places ship without an app update.
nonisolated enum ImageRef: Codable, Hashable, Sendable {
    case asset(String)
    case remote(URL)

    init(_ string: String) {
        if let url = URL(string: string), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" {
            self = .remote(url)
        } else {
            self = .asset(string)
        }
    }
    init(from decoder: Decoder) throws { self.init(try decoder.singleValueContainer().decode(String.self)) }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .asset(let n): try c.encode(n); case .remote(let u): try c.encode(u.absoluteString) }
    }
}

// MARK: - Stories and places

nonisolated struct Sticker: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let collection: String
    let image: ImageRef
    let crop: NormalizedRect
    /// The line to retell at dinner, shown on the back of the sticker.
    let back: String
}

nonisolated struct LookCloser: Codable, Hashable, Sendable {
    let prompt: String
    let hint: String
    let image: ImageRef
    /// How the photo is framed on screen (0...1 per axis) and how far it is zoomed beyond "fill".
    let anchor: NormalizedPoint
    let zoom: Double
    /// Where the detail is, in image coordinates (0...1).
    let target: NormalizedPoint
}

nonisolated struct Theory: Codable, Hashable, Sendable {
    /// "THEORY" or "LEGEND". Shown on the red seal.
    let label: String
    let lead: String
    let text: String
}

/// Where a story's facts come from. `sourced` = checked against published sources;
/// `verified` = confirmed by the site's authority (shown as "Verified").
nonisolated struct FactCheck: Codable, Hashable, Sendable {
    nonisolated struct Source: Codable, Hashable, Sendable { let title: String; let url: URL }
    nonisolated enum Status: String, Codable, Sendable { case sourced, verified }
    let status: Status
    let checkedOn: String
    let sources: [Source]
}

nonisolated struct Story: Codable, Hashable, Sendable {
    let eyebrow: String
    let question: String
    let answers: [String]
    let correctIndex: Int
    let answerTitle: String
    let subtitle: String
    let body: String
    let source: String
    let theory: Theory?
    let dinnerLine: String
    let lookCloser: LookCloser?
    let sticker: Sticker
    /// Short words used in the next-morning recall question ("Bank", "Bar", "Bakery").
    let recallChoices: [String]
    let recallPrompt: String
    let factCheck: FactCheck?
}

nonisolated struct ThenNow: Codable, Hashable, Sendable {
    let then: ImageRef
    let thenCaption: String
    let now: ImageRef
    let nowCaption: String
    let watchHint: String?
}

nonisolated struct Place: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let site: String
    let street: String
    let latitude: Double
    let longitude: Double
    let cameraImage: ImageRef
    let cameraAnchor: NormalizedPoint
    /// The area the recogniser "locks onto", in camera-image coordinates.
    let focus: NormalizedRect
    let clues: [String]
    /// Legacy position on a hand-drawn site map, in map units. The Trip map uses Apple Maps and only needs latitude/longitude.
    let mapPoint: MapPoint?
    let showsMapLabel: Bool?
    /// Optional old-vs-today comparison for this place (shown after the story and on the map).
    let thenNow: ThenNow?
    /// Plain-English descriptions the AI matches photos against (embedded by tools/embed_content.py).
    let aiDescriptions: [String]?
    /// Photos used to recognise this place from the camera.
    let referenceImages: [ImageRef]?
    /// Extra photos of the place shown in its gallery (not used for recognition).
    let photos: [ImageRef]?
    /// false for places the camera shouldn't be used for (indoor art, ticketed or no-photo rooms).
    /// They open from the map, or from Snap when you are standing there.
    let cameraRecognition: Bool?
    /// Where visitors actually go in, when it differs from the site's point (catacombs, tunnels).
    let entrance: Entrance?
    nonisolated struct Entrance: Codable, Hashable, Sendable { let latitude: Double; let longitude: Double; let note: String? }
    let story: Story?

    var recognitionImages: [ImageRef] { referenceImages ?? [cameraImage] }

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var usesCamera: Bool { cameraRecognition ?? true }
    /// Where walking directions should lead.
    var directionsTarget: CLLocation { entrance.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) } ?? CLLocation(latitude: latitude, longitude: longitude) }
}

// MARK: - Site

nonisolated struct SiteMap: Codable, Hashable, Sendable {
    nonisolated struct Street: Codable, Hashable, Sendable { let from: MapPoint; let to: MapPoint }
    nonisolated struct Block: Codable, Hashable, Sendable { let x: Double; let y: Double; let w: Double; let h: Double }
    nonisolated struct Label: Codable, Hashable, Sendable {
        nonisolated enum Style: String, Codable, Sendable { case place, street, water }
        let text: String
        let x: Double
        let y: Double
        let rotation: Double?
        let style: Style
    }
    let width: Double
    let height: Double
    let outline: [MapPoint]
    let water: [MapPoint]?
    let streets: [Street]
    let blocks: [Block]?
    let mountains: [[MapPoint]]?
    let labels: [Label]
}

nonisolated struct SiteContent: Codable, Identifiable, Hashable, Sendable {
    nonisolated struct Welcome: Codable, Hashable, Sendable {
        /// Optional fixed line above the headline; normally the app writes "Welcome to Pompeii" / "Pompeii · Day 2 of your trip".
        let eyebrow: String?
        let headline: String
        let body: String
        let image: ImageRef
        let imageAnchor: NormalizedPoint
    }
    nonisolated struct Tickets: Codable, Hashable, Sendable {
        nonisolated struct Tile: Codable, Hashable, Sendable { let label: String; let value: String; let note: String }
        let tags: [String]
        let tiles: [Tile]
        let bookingURL: URL
        let sources: [FactCheck.Source]?
    }
    /// Recognition thresholds, tunable per site from content (see the recognition log in Profile).
    /// Every field is optional; missing ones fall back to the defaults below.
    nonisolated struct Recognition: Codable, Hashable, Sendable {
        var descriptorMaxDistance: Float?
        var separation: Float?
        var nearbyMeters: Double?
        /// SigLIP: image similarity needed to open a story straight away, and its lead over the runner-up.
        var aiConfident: Float?
        var aiMargin: Float?
        /// SigLIP: similarity above which we ask "Which one is it?" instead of saying it's not a place.
        var aiPossible: Float?
        /// How much the text descriptions count next to the reference photos when ranking places.
        var aiTextWeight: Float?

        var descriptorCap: Float { descriptorMaxDistance ?? 0.56 }
        var separationRatio: Float { separation ?? 0.86 }
        var nearby: Double { nearbyMeters ?? 500 }
        var confident: Float { aiConfident ?? 0.72 }
        var margin: Float { aiMargin ?? 0.05 }
        var possible: Float { aiPossible ?? 0.62 }
        var textWeight: Float { aiTextWeight ?? 2 }
    }
    nonisolated struct DemoTrip: Codable, Hashable, Sendable {
        let visited: [String]
        let collected: [String]
    }

    let id: String
    let name: String
    let city: String
    let featuredPlace: String
    let welcome: Welcome
    let tickets: Tickets
    let postcardImage: ImageRef
    /// Real-world corners of the optional hand-drawn map (legacy; the Trip map uses Apple Maps).
    let geoBounds: GeoBounds?
    nonisolated struct GeoBounds: Codable, Hashable, Sendable { let north: Double; let south: Double; let west: Double; let east: Double }
    let map: SiteMap?
    let places: [Place]
    let demoTrip: DemoTrip?
    let recognition: Recognition?
    /// false where the site allows only its own authorised audio guides; hides "read aloud".
    let readAloud: Bool?

    var recognitionSettings: Recognition { recognition ?? Recognition() }
    var allowsReadAloud: Bool { readAloud ?? true }
    /// Centre of all places, used for "Pompeii is 1,240 km away".
    var centre: CLLocation {
        let lat = places.map(\.latitude).reduce(0, +) / Double(max(places.count, 1))
        let lon = places.map(\.longitude).reduce(0, +) / Double(max(places.count, 1))
        return CLLocation(latitude: lat, longitude: lon)
    }

    func place(id: String) -> Place? { places.first { $0.id == id } }
    var storyPlaces: [Place] { places.filter { $0.story != nil } }
    /// Story places the camera can recognise.
    var cameraPlaces: [Place] { storyPlaces.filter(\.usesCamera) }
    var stickers: [Sticker] { places.compactMap { $0.story?.sticker } }
    func sticker(id: String) -> Sticker? { stickers.first { $0.id == id } }
    func placeOwning(stickerID: String) -> Place? { places.first { $0.story?.sticker.id == stickerID } }
    var featured: Place? { place(id: featuredPlace) ?? storyPlaces.first }
}

// MARK: - Catalog

nonisolated struct CatalogIndex: Codable, Sendable {
    nonisolated struct Entry: Codable, Sendable {
        let id: String
        /// Base file, written in `baseLanguage`.
        let file: String
        let baseLanguage: String?
        /// Optional overlays with only the translated text, e.g. `{"it": "pompeii.it.json"}`.
        let translations: [String: String]?
        var languages: [String] { [baseLanguage ?? "en"] + (translations?.keys.sorted() ?? []) }
    }
    let schemaVersion: Int
    let defaultSite: String
    let sites: [Entry]
    /// Interface text per language, e.g. `{"en": "strings/en.json"}`. English is the fallback.
    let strings: [String: String]?
    let ai: AIFiles?

    nonisolated struct AIFiles: Codable, Sendable { let model: String; let labels: String; let textEmbeddings: String }

    var allFiles: [String] {
        ["catalog.json"] + sites.flatMap { [$0.file] + ($0.translations.map { Array($0.values) } ?? []) } + (strings.map { Array($0.values) } ?? [])
            + (ai.map { [$0.labels, $0.textEmbeddings] } ?? [])
    }
}

nonisolated struct Catalog: Sendable {
    static let supportedSchema = 2
    let index: CatalogIndex
    let sites: [SiteContent]
    let language: String
    let strings: UIStrings
    /// Labels and pre-computed text embeddings for the on-device AI (nil if the content has none).
    let vocabulary: AIVocabulary?

    func site(id: String) -> SiteContent? { sites.first { $0.id == id } }
    var defaultSite: SiteContent { site(id: index.defaultSite) ?? sites[0] }
    func languages(forSite id: String) -> [String] { index.sites.first { $0.id == id }?.languages ?? ["en"] }
}

/// Interface text loaded from content, so wording and translations can change without code changes.
nonisolated struct UIStrings: Sendable {
    let table: [String: String]
    let fallback: [String: String]

    static let empty = UIStrings(table: [:], fallback: [:])

    /// `t("reveal.youSaid", answer)` replaces `%@` placeholders in order.
    func callAsFunction(_ key: String, _ args: String...) -> String {
        var s = table[key] ?? fallback[key] ?? key
        for a in args { if let r = s.range(of: "%@") { s.replaceSubrange(r, with: a) } }
        return s
    }
}

/// Merges a translation overlay into a base JSON document. Objects merge key by key;
/// arrays of objects with an `id` merge item by item; anything else is replaced.
nonisolated enum JSONMerge {
    static func merge(_ base: Any, _ overlay: Any) -> Any {
        if let b = base as? [String: Any], let o = overlay as? [String: Any] {
            var r = b
            for (k, v) in o { r[k] = b[k].map { merge($0, v) } ?? v }
            return r
        }
        if let b = base as? [[String: Any]], let o = overlay as? [[String: Any]], b.allSatisfy({ $0["id"] is String }) {
            return b.map { item -> Any in
                guard let id = item["id"] as? String, let ov = o.first(where: { ($0["id"] as? String) == id }) else { return item }
                return merge(item, ov)
            }
        }
        return overlay
    }
}

// MARK: - Loading

/// Where content comes from. Bundled content always works offline; a remote base URL
/// (Info.plist key `ContentBaseURL`) can replace it without an app update.
enum ContentStore {
    nonisolated enum LoadError: LocalizedError {
        case missingFile(String)
        case unsupportedSchema(Int)
        case invalid([String])
        var errorDescription: String? {
            switch self {
            case .missingFile(let f): "Missing content file \(f)"
            case .unsupportedSchema(let v): "Content schema \(v) is newer than this app supports"
            case .invalid(let problems): "Content is invalid: " + problems.joined(separator: "; ")
            }
        }
    }

    /// Cached remote content if present and valid, otherwise the bundled content.
    #if os(iOS)
    static func load(language: String, bundle: Bundle = .main) throws -> Catalog {
        if let cached = try? loadCatalog(language: language, read: { try Data(contentsOf: cacheDirectory.appending(path: $0)) }),
           ContentValidator.problems(in: cached).isEmpty {
            return cached
        }
        return try loadBundled(language: language, bundle: bundle)
    }
    #endif

    static func loadBundled(language: String = "en", bundle: Bundle = .main) throws -> Catalog {
        try loadCatalog(language: language) { name in
            guard let base = bundle.resourceURL?.appending(path: "Content").appending(path: name),
                  FileManager.default.fileExists(atPath: base.path) else { throw LoadError.missingFile(name) }
            return try Data(contentsOf: base)
        }
    }

    static func loadCatalog(language: String, read: (String) throws -> Data) throws -> Catalog {
        let decoder = JSONDecoder()
        let index = try decoder.decode(CatalogIndex.self, from: read("catalog.json"))
        guard index.schemaVersion <= Catalog.supportedSchema else { throw LoadError.unsupportedSchema(index.schemaVersion) }
        let sites = try index.sites.map { entry -> SiteContent in
            var json = try JSONSerialization.jsonObject(with: read(entry.file))
            if language != (entry.baseLanguage ?? "en"), let file = entry.translations?[language] {
                json = JSONMerge.merge(json, try JSONSerialization.jsonObject(with: read(file)))
            }
            return try decoder.decode(SiteContent.self, from: JSONSerialization.data(withJSONObject: json))
        }
        func table(_ lang: String) -> [String: String] {
            guard let file = index.strings?[lang], let data = try? read(file) else { return [:] }
            return (try? decoder.decode([String: String].self, from: data)) ?? [:]
        }
        var vocabulary: AIVocabulary?
        if let ai = index.ai, let labels = try? read(ai.labels), let emb = try? read(ai.textEmbeddings) {
            vocabulary = try? AIVocabulary(labelsJSON: labels, embeddingsJSON: emb)
        }
        return Catalog(index: index, sites: sites, language: language, strings: UIStrings(table: table(language), fallback: table("en")), vocabulary: vocabulary)
    }

    /// Downloads every file the catalog mentions from `baseURL`, validates them in every language,
    /// and only then replaces the cache. The new content is used on the next launch.
    #if os(iOS)
    static func refresh(from baseURL: URL, session: URLSession = .shared) async throws {
        let (indexData, _) = try await session.data(from: baseURL.appending(path: "catalog.json"))
        let index = try JSONDecoder().decode(CatalogIndex.self, from: indexData)
        var files: [String: Data] = ["catalog.json": indexData]
        for name in index.allFiles where name != "catalog.json" {
            files[name] = try await session.data(from: baseURL.appending(path: name)).0
        }
        let read: (String) throws -> Data = { name in
            guard let d = files[name] else { throw LoadError.missingFile(name) }
            return d
        }
        for lang in Set(index.sites.flatMap(\.languages)) {
            let problems = ContentValidator.problems(in: try loadCatalog(language: lang, read: read), checkAssets: false)
            guard problems.isEmpty else { throw LoadError.invalid(problems) }
        }
        let fm = FileManager.default
        try? fm.removeItem(at: cacheDirectory)
        for (name, data) in files {
            let url = cacheDirectory.appending(path: name)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
    }

    static var remoteBaseURL: URL? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "ContentBaseURL") as? String, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    static var cacheDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Content", directoryHint: .isDirectory)
    }

    static func clearCache() { try? FileManager.default.removeItem(at: cacheDirectory) }
    #endif
}

// MARK: - AI vocabulary

/// Everyday and heritage labels plus SigLIP text embeddings, loaded from content (ai/*.json).
nonisolated struct AIVocabulary: Sendable {
    nonisolated struct Label: Sendable { let id: String; let heritage: Bool; let names: [String: String]; let embedding: [Float] }
    let model: String
    let labels: [Label]
    let placeText: [String: [[Float]]]

    private struct LabelsFile: Decodable {
        nonisolated struct L: Decodable { let id: String; let heritage: Bool; let names: [String: String] }
        let labels: [L]
    }
    private struct EmbeddingsFile: Decodable {
        let model: String
        let labels: [String: String]
        let places: [String: [String]]
    }

    init(labelsJSON: Data, embeddingsJSON: Data) throws {
        let lf = try JSONDecoder().decode(LabelsFile.self, from: labelsJSON)
        let ef = try JSONDecoder().decode(EmbeddingsFile.self, from: embeddingsJSON)
        model = ef.model
        labels = lf.labels.compactMap { l in ef.labels[l.id].flatMap(Self.decode).map { Label(id: l.id, heritage: l.heritage, names: l.names, embedding: $0) } }
        placeText = ef.places.mapValues { $0.compactMap(Self.decode) }
    }

    /// Base64 little-endian float16 → [Float].
    static func decode(_ b64: String) -> [Float]? {
        guard let data = Data(base64Encoded: b64), data.count % 2 == 0 else { return nil }
        return data.withUnsafeBytes { raw in raw.bindMemory(to: UInt16.self).map { Float(Float16(bitPattern: UInt16(littleEndian: $0))) } }
    }

    func name(_ label: Label, language: String) -> String { label.names[language] ?? label.names["en"] ?? label.id }
}
