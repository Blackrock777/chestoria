import MapKit
import SwiftUI

/// Old vs today for one place: drag the handle to compare.
struct ThenNowSheet: View {
    let thenNow: ThenNow
    let title: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var split: CGFloat = 0.5
    @State private var dragged = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let t = model.strings
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(.system(size: 12, weight: .bold)).textCase(.uppercase).kerning(1).foregroundStyle(Palette.stone)
                ThenNowSlider(then: thenNow.then, now: thenNow.now, caption: thenNow.thenCaption, todayLabel: thenNow.nowCaption, split: $split)
                    .frame(maxHeight: 420)
                    .simultaneousGesture(DragGesture().onChanged { _ in dragged = true })
                Spacer()
            }
            .padding(20)
            .background(Palette.calce)
            .navigationTitle(t("thenNow.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("common.done")) { dismiss() } } }
        }
        .presentationDetents([.large])
        .task {
            guard !reduce else { return }
            try? await Task.sleep(for: .milliseconds(500))
            for step in 0...60 where !dragged { split = 0.5 + sin(Double(step) / 60 * .pi * 2) * 0.3; try? await Task.sleep(for: .milliseconds(30)) }
        }
    }
}

/// Opened from a map pin: what you discovered here, your sticker, its sources and Then & Now.
struct PlaceSheet: View {
    let place: Place
    @Environment(AppModel.self) private var model
    @Environment(PlaceRecognizer.self) private var location
    @Environment(\.dismiss) private var dismiss
    @State private var showSources = false
    @State private var showThenNow = false

    var body: some View {
        let t = model.strings
        let p = model.site.place(id: place.id) ?? place
        let story = p.story
        let found = model.visitedPlaces.contains { $0.id == p.id }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                CoverImage(p.cameraImage, anchor: p.cameraAnchor).frame(height: 220).clipShape(.rect(cornerRadius: 24))
                Text(p.name).font(Typeface.display(30)).foregroundStyle(Palette.piperno)
                Text(p.street).font(.system(size: 14)).foregroundStyle(Palette.stone).padding(.top, -10)
                if let story, found {
                    HStack(alignment: .top, spacing: 14) {
                        StickerArt(sticker: story.sticker, border: 5, photo: model.stickerPhoto(story.sticker)).frame(width: 84, height: 72)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(story.answerTitle).font(Typeface.display(20)).foregroundStyle(Palette.piperno)
                            Text(story.body).font(.system(size: 15)).foregroundStyle(Palette.piperno)
                        }
                    }
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 1.5).fill(Palette.tufo).frame(width: 3)
                        Text(story.dinnerLine).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.piperno)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    if let fc = story.factCheck {
                        Button { showSources = true } label: { VerifiedPill(text: t("reveal.sourced", "\(fc.sources.count)")) }
                    }
                } else {
                    Label(t("place.notYet"), systemImage: "camera").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.stone)
                }
                if let tn = p.thenNow {
                    Button { showThenNow = true } label: {
                        Label(t("thenNow.open"), systemImage: "clock.arrow.circlepath").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CTAButtonStyle(kind: .light))
                    .overlay(Capsule().stroke(Palette.hair, lineWidth: 1.5))
                    .sheet(isPresented: $showThenNow) { ThenNowSheet(thenNow: tn, title: p.name) }
                }
                if story != nil {
                    if found {
                        Button(t("place.playAgain")) { dismiss(); model.startStory(at: p) }.buttonStyle(CTAButtonStyle(kind: .dark))
                    } else if isNear(p) {
                        // Indoors or where photos aren't allowed, being there is enough to start.
                        Button(t("place.startHere")) { dismiss(); model.startStory(at: p) }.buttonStyle(CTAButtonStyle(kind: .dark))
                    }
                }
                Button { directions(to: p) } label: {
                    Label(t("place.directions"), systemImage: "figure.walk").frame(maxWidth: .infinity)
                }
                .buttonStyle(CTAButtonStyle(kind: .light))
                .overlay(Capsule().stroke(Palette.hair, lineWidth: 1.5))
            }
            .padding(20)
        }
        .background(Palette.calce)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(32)
        .sheet(isPresented: $showSources) { if let fc = story?.factCheck { SourcesSheet(factCheck: fc) } }
    }

    /// Within 150 m by real GPS, never guessed.
    private func isNear(_ p: Place) -> Bool {
        guard let here = location.lastLocation else { return false }
        return here.distance(from: CLLocation(latitude: p.latitude, longitude: p.longitude)) <= 150
    }

    /// Opens Apple Maps with walking directions to the place.
    private func directions(to p: Place) {
        let item = MKMapItem(location: CLLocation(latitude: p.latitude, longitude: p.longitude), address: nil)
        item.name = p.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}
