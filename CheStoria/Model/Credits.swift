import Foundation

/// Who made each photo, and the licence notices the app must show (built by tools/build_credits.py).
nonisolated struct Credits: Codable, Sendable {
    nonisolated struct Photo: Codable, Hashable, Sendable {
        let asset: String
        let title: String
        let author: String
        let licence: String
        let url: URL?
        let licenceURL: URL?
        var creator: String? {
            ["unknown author", "see file page"].contains(author.lowercased()) ? nil : author
        }

        var line: String {
            creator.map { "\($0) · \(licence)" } ?? licence
        }
    }
    nonisolated struct Notice: Codable, Hashable, Sendable { let title: String; let text: String; let url: URL? }

    let photos: [Photo]
    let notices: [Notice]

    func photo(for ref: ImageRef) -> Photo? {
        guard case .asset(let name) = ref else { return nil }
        return photos.first { $0.asset == name }
    }

    static let shared: Credits = {
        guard let url = Bundle.main.url(forResource: "credits", withExtension: "json", subdirectory: "Content"),
              let data = try? Data(contentsOf: url),
              let credits = try? JSONDecoder().decode(Credits.self, from: data) else { return Credits(photos: [], notices: []) }
        return credits
    }()
}

extension Place {
    /// Every photo this place shows, in the order it appears (for credits).
    var allImages: [ImageRef] {
        var out: [ImageRef] = []
        func add(_ r: ImageRef?) { if let r, !out.contains(r) { out.append(r) } }
        add(cameraImage)
        (photos ?? []).forEach(add)
        recognitionImages.forEach(add)
        add(thenNow?.now); add(thenNow?.then)
        add(story?.lookCloser?.image); add(story?.sticker.image)
        return out
    }

    /// Two or three of the place's own photos, for when the person's photo isn't of this place.
    var galleryImages: [ImageRef] {
        var out: [ImageRef] = []
        for r in [cameraImage] + (photos ?? []) + recognitionImages + [thenNow?.now].compactMap({ $0 }) where !out.contains(r) { out.append(r) }
        return Array(out.prefix(3))
    }
}
