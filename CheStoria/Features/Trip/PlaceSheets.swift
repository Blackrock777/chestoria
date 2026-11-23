import MapKit
import SwiftUI

/// Old vs today for one place: drag the handle to compare.
struct ThenNowSheet: View {
    let place: Place
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var split: CGFloat = 0.5
    @State private var dragged = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let t = model.strings
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(place.name).font(.system(size: 12, weight: .bold)).textCase(.uppercase).kerning(1).foregroundStyle(Palette.stone)
                    if let comparison = place.thenNow {
                        ThenNowSlider(then: comparison.then, now: comparison.now, caption: comparison.thenCaption,
                                      todayLabel: comparison.nowCaption == "Today" ? t("thenNow.today") : comparison.nowCaption, split: $split)
                            .frame(height: 380)
                            .simultaneousGesture(DragGesture().onChanged { _ in dragged = true })
                        Text(t("thenNow.framing")).font(.footnote).foregroundStyle(Palette.stone)
                        let images = [comparison.then, comparison.now].compactMap(Credits.shared.photo(for:))
                        if !images.isEmpty {
                            Text(t("about.photos")).font(.headline)
                            ForEach(images, id: \.asset) { PhotoCreditRow(photo: $0).padding(.vertical, 5) }
                        }
                    } else {
                        ContentUnavailableView(t("thenNow.unavailable"), systemImage: "photo.on.rectangle",
                                               description: Text(t("thenNow.unavailableDetail")))
                        if place.story != nil {
                            CoverImage(place.cameraImage, anchor: place.cameraAnchor)
                                .frame(height: 220).clipShape(.rect(cornerRadius: 22))
                            Text(t("thenNow.today")).font(.subheadline).foregroundStyle(Palette.stone)
                            if let credit = Credits.shared.photo(for: place.cameraImage) { PhotoCreditRow(photo: credit) }
                        }
                    }
                }
                .padding(20)
            }
            .background(Palette.calce)
            .navigationTitle(t("thenNow.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("common.done")) { dismiss() } } }
        }
        .tint(.primary)
        .presentationDetents([.large])
        .task {
            guard !reduce, place.thenNow != nil else { return }
            do {
                try await Task.sleep(for: .milliseconds(500))
                for step in 0...60 {
                    guard !dragged else { break }
                    split = 0.5 + sin(Double(step) / 60 * .pi * 2) * 0.3
                    try await Task.sleep(for: .milliseconds(30))
                }
            } catch is CancellationError {
                return
            } catch {
                return
            }
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
                if story != nil {
                    CoverImage(p.cameraImage, anchor: p.cameraAnchor).frame(height: 220).clipShape(.rect(cornerRadius: 24))
                }
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
                    Button { showSources = true } label: {
                        Label(t("reveal.about"), systemImage: "info.circle").font(.subheadline.weight(.semibold))
                    }
                    .tint(Palette.azzurro)
                } else if story == nil {
                    Label(t("place.comingSoon"), systemImage: "hourglass").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.stone)
                } else {
                    Label(t("place.notYet"), systemImage: "camera").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.stone)
                }
                Button { showThenNow = true } label: {
                    Label(t(p.thenNow == nil ? "thenNow.title" : "thenNow.open"), systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CTAButtonStyle(kind: .light))
                .overlay(Capsule().stroke(Palette.hair, lineWidth: 1.5))
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
        .sheet(isPresented: $showSources) { StoryInfoSheet(place: p) }
        .sheet(isPresented: $showThenNow) { ThenNowSheet(place: p) }
    }

    /// Within 150 m by real GPS, never guessed.
    private func isNear(_ p: Place) -> Bool {
        guard let here = location.lastLocation else { return false }
        return here.distance(from: CLLocation(latitude: p.latitude, longitude: p.longitude)) <= 150
    }

    /// Opens Apple Maps with walking directions to the place.
    private func directions(to p: Place) {
        let item = MKMapItem(location: p.directionsTarget, address: nil)
        item.name = p.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}
