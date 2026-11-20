import Foundation
import CoreLocation

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

struct Sticker: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let collection: String
    let image: String
    let crop: NormalizedRect
    /// The line to retell at dinner, shown on the back of the sticker.
    let back: String
}

struct LookCloser: Codable, Hashable, Sendable {
    let prompt: String
    let hint: String
    let image: String
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
}

struct Place: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let site: String
    let street: String
    let latitude: Double
    let longitude: Double
    let cameraImage: String
    let cameraAnchor: NormalizedPoint
    /// The area the recogniser "locks onto", in camera-image coordinates.
    let focus: NormalizedRect
    let clues: [String]
    /// Position on the hand-drawn site map (0...1 of the map's width and height).
    let mapPoint: NormalizedPoint
    let story: Story?

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

struct Site: Codable, Hashable, Sendable {
    let name: String
    let tags: [String]
    let ticketPrice: String
    let ticketNote: String
    let dailyCap: String
    let dailyCapNote: String
    let thenImage: String
    let thenCaption: String
    let nowImage: String
    let bookingURL: URL
}

struct ContentBundle: Codable, Sendable {
    let site: Site
    let places: [Place]

    func place(id: String) -> Place? { places.first { $0.id == id } }
    var stickers: [Sticker] { places.compactMap { $0.story?.sticker } }
    func sticker(id: String) -> Sticker? { stickers.first { $0.id == id } }
}

enum ContentStore {
    enum LoadError: Error { case missingFile }

    static func load(from bundle: Bundle = .main) throws -> ContentBundle {
        guard let url = bundle.url(forResource: "pompeii", withExtension: "json") else { throw LoadError.missingFile }
        return try JSONDecoder().decode(ContentBundle.self, from: Data(contentsOf: url))
    }
}
