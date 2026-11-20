import Foundation
import CoreLocation

// MARK: - Small value types

struct NormalizedPoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
}

struct NormalizedRect: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

/// A point in map units, written in JSON as `[x, y]`.
struct MapPoint: Codable, Hashable, Sendable {
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
enum ImageRef: Codable, Hashable, Sendable {
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

struct Sticker: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let collection: String
    let image: ImageRef
    let crop: NormalizedRect
    /// The line to retell at dinner, shown on the back of the sticker.
    let back: String
}

struct LookCloser: Codable, Hashable, Sendable {
    let prompt: String
    let hint: String
    let image: ImageRef
    /// How the photo is framed on screen (0...1 per axis) and how far it is zoomed beyond "fill".
    let anchor: NormalizedPoint
    let zoom: Double
    /// Where the detail is, in image coordinates (0...1).
    let target: NormalizedPoint
}

struct Theory: Codable, Hashable, Sendable {
    /// "THEORY" or "LEGEND". Shown on the red seal.
    let label: String
    let lead: String
    let text: String
}

/// Where a story's facts come from. `sourced` = checked against published sources;
/// `verified` = confirmed by the site's authority (shown as "Verified").
struct FactCheck: Codable, Hashable, Sendable {
    struct Source: Codable, Hashable, Sendable { let title: String; let url: URL }
    enum Status: String, Codable, Sendable { case sourced, verified }
    let status: Status
    let checkedOn: String
    let sources: [Source]
}

struct Story: Codable, Hashable, Sendable {
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

struct Place: Codable, Identifiable, Hashable, Sendable {
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
    /// Position on the site map, in map units.
    let mapPoint: MapPoint
    let showsMapLabel: Bool?
    /// Photos used to recognise this place from the camera (Vision feature prints).
    let referenceImages: [ImageRef]?
    let story: Story?

    var recognitionImages: [ImageRef] { referenceImages ?? [cameraImage] }

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

// MARK: - Site

struct SiteMap: Codable, Hashable, Sendable {
    struct Street: Codable, Hashable, Sendable { let from: MapPoint; let to: MapPoint }
    struct Block: Codable, Hashable, Sendable { let x: Double; let y: Double; let w: Double; let h: Double }
    struct Label: Codable, Hashable, Sendable {
        enum Style: String, Codable, Sendable { case place, street, water }
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

struct SiteContent: Codable, Identifiable, Hashable, Sendable {
    struct Welcome: Codable, Hashable, Sendable {
        let eyebrow: String
        let headline: String
        let body: String
        let image: ImageRef
        let imageAnchor: NormalizedPoint
    }
    struct Tickets: Codable, Hashable, Sendable {
        struct Tile: Codable, Hashable, Sendable { let label: String; let value: String; let note: String }
        let tags: [String]
        let tiles: [Tile]
        let bookingURL: URL
        let sources: [FactCheck.Source]?
    }
    /// Recognition thresholds, tunable per site from content (see the recognition log in Profile).
    struct Recognition: Codable, Hashable, Sendable {
        var visionMaxDistance: Float = 1.1
        var descriptorMaxDistance: Float = 0.56
        var separation: Float = 0.86
        var nearbyMeters: Double = 500
    }
    struct ThenNow: Codable, Hashable, Sendable {
        let title: String
        let then: ImageRef
        let thenCaption: String
        let now: ImageRef
    }
    struct DemoTrip: Codable, Hashable, Sendable {
        let visited: [String]
        let collected: [String]
    }

    let id: String
    let name: String
    let city: String
    let featuredPlace: String
    let welcome: Welcome
    let tickets: Tickets
    let thenNow: ThenNow?
    let postcardImage: ImageRef
    let map: SiteMap
    let places: [Place]
    let demoTrip: DemoTrip?
    let recognition: Recognition?

    var recognitionSettings: Recognition { recognition ?? Recognition() }
    /// Centre of all places, used for "Pompeii is 1,240 km away".
    var centre: CLLocation {
        let lat = places.map(\.latitude).reduce(0, +) / Double(max(places.count, 1))
        let lon = places.map(\.longitude).reduce(0, +) / Double(max(places.count, 1))
        return CLLocation(latitude: lat, longitude: lon)
    }

    func place(id: String) -> Place? { places.first { $0.id == id } }
    var storyPlaces: [Place] { places.filter { $0.story != nil } }
    var stickers: [Sticker] { places.compactMap { $0.story?.sticker } }
    func sticker(id: String) -> Sticker? { stickers.first { $0.id == id } }
    func placeOwning(stickerID: String) -> Place? { places.first { $0.story?.sticker.id == stickerID } }
    var featured: Place? { place(id: featuredPlace) ?? storyPlaces.first }
}

// MARK: - Catalog

struct CatalogIndex: Codable, Sendable {
    struct Entry: Codable, Sendable {
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

    var allFiles: [String] {
        ["catalog.json"] + sites.flatMap { [$0.file] + ($0.translations.map { Array($0.values) } ?? []) } + (strings.map { Array($0.values) } ?? [])
    }
}

struct Catalog: Sendable {
    static let supportedSchema = 2
    let index: CatalogIndex
    let sites: [SiteContent]
    let language: String
    let strings: UIStrings

    func site(id: String) -> SiteContent? { sites.first { $0.id == id } }
    var defaultSite: SiteContent { site(id: index.defaultSite) ?? sites[0] }
    func languages(forSite id: String) -> [String] { index.sites.first { $0.id == id }?.languages ?? ["en"] }
}

/// Interface text loaded from content, so wording and translations can change without code changes.
struct UIStrings: Sendable {
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
enum JSONMerge {
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
    enum LoadError: LocalizedError {
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
    static func load(language: String, bundle: Bundle = .main) throws -> Catalog {
        if let cached = try? loadCatalog(language: language, read: { try Data(contentsOf: cacheDirectory.appending(path: $0)) }),
           ContentValidator.problems(in: cached).isEmpty {
            return cached
        }
        return try loadBundled(language: language, bundle: bundle)
    }

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
        return Catalog(index: index, sites: sites, language: language, strings: UIStrings(table: table(language), fallback: table("en")))
    }

    /// Downloads every file the catalog mentions from `baseURL`, validates them in every language,
    /// and only then replaces the cache. The new content is used on the next launch.
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
}
