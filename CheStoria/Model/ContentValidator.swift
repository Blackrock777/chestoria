import Foundation
import UIKit

/// Checks content before it is shown. Used by the unit tests (bundled content) and before
/// remote content replaces the cache, so a typo in JSON can never break the app.
enum ContentValidator {
    static func problems(in catalog: Catalog, checkAssets: Bool = true) -> [String] {
        var out: [String] = []
        if catalog.sites.isEmpty { out.append("catalog has no sites") }
        if catalog.site(id: catalog.index.defaultSite) == nil { out.append("defaultSite '\(catalog.index.defaultSite)' is not in the catalog") }
        let siteIDs = catalog.sites.map(\.id)
        if Set(siteIDs).count != siteIDs.count { out.append("duplicate site ids") }
        for site in catalog.sites { out += problems(in: site, checkAssets: checkAssets).map { "\(site.id): \($0)" } }
        return out
    }

    static func problems(in site: SiteContent, checkAssets: Bool = true) -> [String] {
        var out: [String] = []
        func image(_ ref: ImageRef, _ what: String) {
            if checkAssets, case .asset(let name) = ref, UIImage(named: name) == nil { out.append("\(what): no asset named '\(name)'") }
        }
        func unit(_ v: Double) -> Bool { (0...1).contains(v) }

        let placeIDs = site.places.map(\.id)
        if Set(placeIDs).count != placeIDs.count { out.append("duplicate place ids") }
        let stickerIDs = site.stickers.map(\.id)
        if Set(stickerIDs).count != stickerIDs.count { out.append("duplicate sticker ids") }
        if site.storyPlaces.isEmpty { out.append("no place has a story") }
        if site.place(id: site.featuredPlace)?.story == nil { out.append("featuredPlace '\(site.featuredPlace)' missing or has no story") }
        if site.map.outline.count < 3 { out.append("map outline needs at least 3 points") }

        image(site.welcome.image, "welcome.image")
        image(site.postcardImage, "postcardImage")
        if let tn = site.thenNow { image(tn.then, "thenNow.then"); image(tn.now, "thenNow.now") }

        for p in site.places {
            image(p.cameraImage, "\(p.id).cameraImage")
            if !(0...site.map.width).contains(p.mapPoint.x) || !(0...site.map.height).contains(p.mapPoint.y) {
                out.append("\(p.id): mapPoint is outside the map")
            }
            if !(-90...90).contains(p.latitude) || !(-180...180).contains(p.longitude) { out.append("\(p.id): bad coordinates") }
            guard let s = p.story else { continue }
            if !s.answers.indices.contains(s.correctIndex) { out.append("\(p.id): correctIndex out of range") }
            if s.answers.count < 2 { out.append("\(p.id): needs at least 2 answers") }
            if s.recallChoices.count != s.answers.count { out.append("\(p.id): recallChoices must match answers") }
            if s.body.split(separator: " ").count > 40 { out.append("\(p.id): story body is over 40 words (short beats long)") }
            image(s.sticker.image, "\(p.id).sticker.image")
            let c = s.sticker.crop
            if !(unit(c.x) && unit(c.y) && c.w > 0 && c.h > 0 && c.x + c.w <= 1.0001 && c.y + c.h <= 1.0001) { out.append("\(p.id): sticker crop outside the image") }
            if let look = s.lookCloser {
                image(look.image, "\(p.id).lookCloser.image")
                if !(unit(look.target.x) && unit(look.target.y)) { out.append("\(p.id): lookCloser.target outside the image") }
                if look.zoom < 1 { out.append("\(p.id): lookCloser.zoom must be ≥ 1") }
            }
        }
        if let demo = site.demoTrip {
            for id in demo.visited where site.place(id: id) == nil { out.append("demoTrip.visited: unknown place '\(id)'") }
            for id in demo.collected where site.sticker(id: id) == nil { out.append("demoTrip.collected: unknown sticker '\(id)'") }
        }
        return out
    }
}
