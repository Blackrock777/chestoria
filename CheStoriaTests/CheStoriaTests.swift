import Testing
import Foundation
import CoreGraphics
@testable import CheStoria

@MainActor
struct ContentTests {
    @Test func bundledContentDecodes() throws {
        let content = try ContentStore.load()
        #expect(content.places.count >= 2)
        #expect(content.site.bookingURL.host() == "www.pompeiisites.org")
    }

    @Test func everyStoryIsWellFormed() throws {
        for place in try ContentStore.load().places {
            guard let story = place.story else { continue }
            #expect(story.answers.indices.contains(story.correctIndex), "\(place.id): correct answer out of range")
            #expect(story.recallChoices.count == story.answers.count, "\(place.id): recall choices must match answers")
            // Short beats long: about 30 words, never a wall of text.
            #expect(story.body.split(separator: " ").count <= 40, "\(place.id): story body is too long")
            if let look = story.lookCloser {
                #expect((0...1).contains(look.target.x) && (0...1).contains(look.target.y))
            }
        }
    }
}

struct CoverLayoutTests {
    @Test func fillsAndCentresByDefault() {
        let l = CoverLayout(imageSize: CGSize(width: 1800, height: 1200), container: CGSize(width: 393, height: 852))
        #expect(abs(l.displaySize.height - 852) < 0.001)
        #expect(abs(l.point(.init(x: 0.5, y: 0.5)).x - 196.5) < 0.001)
    }

    @Test func anchorAndZoomMoveTheTarget() {
        // Same framing as the Look closer screen: snakes must sit above the shutter.
        let l = CoverLayout(imageSize: CGSize(width: 1800, height: 1198), container: CGSize(width: 393, height: 852),
                            anchor: CGPoint(x: 0.55, y: 1), zoom: 1.15)
        let snakes = l.point(.init(x: 0.555, y: 0.72))
        #expect(snakes.y > 450 && snakes.y < 640)
        #expect(snakes.x > 150 && snakes.x < 300)
    }
}

struct HuntFeedbackTests {
    @Test func getsHotterAndFasterAsYouApproach() {
        let far = HuntFeedback(distance: 400), near = HuntFeedback(distance: 60)
        #expect(far.label == "colder…")
        #expect(near.label == "hot!")
        #expect(near.pulseInterval < far.pulseInterval)
        #expect(near.closeness > far.closeness)
    }

    @Test func foundInsideRadius() {
        #expect(HuntFeedback(distance: 20).isFound)
        #expect(!HuntFeedback(distance: 80).isFound)
    }
}

@MainActor
struct AppModelTests {
    private func freshModel() throws -> AppModel {
        let defaults = UserDefaults(suiteName: "chestoria.tests.\(UUID().uuidString)")!
        return AppModel(content: try ContentStore.load(), defaults: defaults)
    }

    @Test func demoTripStartsWithTwoPlacesAndOneSticker() throws {
        let m = try freshModel()
        #expect(m.visitedPlaces.map(\.id) == ["forum", "tragic-poet"])
        #expect(m.collectedStickers.count == 1)
    }

    @Test func finishingAStoryCollectsItsStickerOnce() throws {
        let m = try freshModel()
        let thermo = try #require(m.content.place(id: "thermopolium"))
        m.startStory(at: thermo)
        #expect(m.activePlace == thermo)
        m.finishStory(at: thermo, goTo: .trip)
        m.finishStory(at: thermo, goTo: .trip)
        #expect(m.collectedStickers.filter { $0.sticker.id == "guardian-snakes" }.count == 1)
        #expect(m.visitedPlaces.last?.id == "thermopolium")
        #expect(m.activePlace == nil && m.selectedTab == .trip)
        #expect(m.isNew(thermo.story!.sticker))
    }
}
