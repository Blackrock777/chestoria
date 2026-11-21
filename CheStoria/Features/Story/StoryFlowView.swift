import SwiftUI

/// The full-screen loop: recognising → (choose) → question → reveal → look closer → sticker.
struct StoryFlowView: View {
    let request: FlowRequest
    @Environment(AppModel.self) private var model
    @State private var place: Place?
    @State private var choices: [Place] = []
    @State private var noMatch = false
    @State private var seenLabel: String?
    @State private var heritage = false
    @State private var step: Step = .recognizing
    @State private var chosen = 0
    @State private var confidence = 2
    /// True only when the person's photo really shows this place (recognised, or picked from "which one?").
    /// After "that's a bottle → stories nearby", the place's own photos are used instead of theirs.
    @State private var photoIsPlace = false

    private var placePhoto: UIImage? { photoIsPlace ? request.photo : nil }

    enum Step: Int { case recognizing, choose, notAPlace, question, reveal, lookCloser, sticker }

    /// Re-read the place from the current site, so a language change mid-flow shows translated text.
    private var current: Place? { place.flatMap { model.site.place(id: $0.id) } ?? place }

    var body: some View {
        ZStack {
            switch step {
            case .recognizing:
                RecognizingView(request: request) { result in handle(result) }
                    .transition(.opacity)
            case .choose:
                ChoosePlaceView(photo: request.photo, places: choices, label: seenLabel, noMatch: noMatch,
                                onPick: { picked in place = picked; photoIsPlace = true; go(.question) },
                                onNone: { noMatch = true; go(.notAPlace) })
                .transition(.opacity)
            case .notAPlace:
                NotAPlaceView(photo: request.photo, label: seenLabel, heritage: heritage, nearby: choices,
                              onPick: { picked in place = picked; photoIsPlace = false; go(.question) },
                              onRetake: { model.activeFlow = nil })
                .transition(.opacity)
            case .question:
                if let p = current, let story = p.story {
                    QuestionView(place: p, story: story, photo: placePhoto) { i, sure in chosen = i; confidence = sure; go(.reveal) }
                        .transition(.opacity)
                }
            case .reveal:
                if let p = current, let story = p.story {
                    RevealView(place: p, story: story, chosen: chosen, confidence: confidence) { go(story.lookCloser == nil ? .sticker : .lookCloser) }
                        .transition(.push(from: .trailing))
                }
            case .lookCloser:
                if let look = current?.story?.lookCloser {
                    LookCloserView(look: look) { go(.sticker) }
                        .transition(.push(from: .trailing))
                }
            case .sticker:
                if let sticker = current?.story?.sticker {
                    StickerEarnedView(sticker: sticker, photo: placePhoto, onKeepExploring: { finish(.trip) }, onSeeAll: { finish(.stickers) })
                        .transition(.move(edge: .bottom))
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if step != .recognizing && step != .sticker {
                CloseButton { model.activeFlow = nil }
                    .padding(.trailing, 16).padding(.top, 4)
                    .environment(\.colorScheme, .dark)
            }
        }
        #if DEBUG
        .onAppear(perform: jumpForScreenshots)
        #endif
    }

    private func handle(_ result: RecognitionResult) {
        switch result {
        case .confident(let p): place = p; photoIsPlace = request.photo != nil; go(.question, animated: false)
        case .unsure(let ps, let label): choices = ps; seenLabel = label; noMatch = false; go(.choose, animated: false)
        case .notAPlace(let label, let h, let nearby): choices = nearby; seenLabel = label; heritage = h; go(.notAPlace, animated: false)
        }
    }

    private func go(_ next: Step, animated: Bool = true) {
        withAnimation(animated ? Motion.glide : .easeInOut(duration: 0.25)) { step = next }
    }

    private func finish(_ tab: AppTab) {
        guard let p = current else { model.activeFlow = nil; return }
        if let story = p.story { RecallScheduler.schedule(for: p, story: story, strings: model.strings) }
        LiveActivityController.shared.end()
        model.finishStory(at: p, goTo: tab, photo: placePhoto)
    }

    #if DEBUG
    private func jumpForScreenshots() {
        let target: Step? = switch DebugLaunch.screen {
        case "question": .question
        case "reveal": .reveal
        case "closer": .lookCloser
        case "sticker": .sticker
        default: nil
        }
        if let target { place = request.suggested; step = target }
    }
    #endif
}

// MARK: - Recognising

/// While Vision compares the photo, the wait becomes part of the curiosity gap:
/// brackets lock on, a scan line sweeps, clues appear.
struct RecognizingView: View {
    let request: FlowRequest
    let onResult: (RecognitionResult) -> Void
    @Environment(AppModel.self) private var model
    @Environment(PlaceMatcher.self) private var matcher
    @Environment(PlaceRecognizer.self) private var location
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var locked = false
    @State private var scan = false
    @State private var clues: [String] = []
    @State private var visibleClues = 0
    @State private var thinking = ""
    @State private var flash = true

    var body: some View {
        let t = model.strings
        let place = request.suggested
        GeometryReader { geo in
            let start = CGRect(x: (geo.size.width - 270) / 2, y: geo.size.height * 0.3, width: 270, height: 320)
            let focus: CGRect = {
                if request.photo != nil {
                    return CGRect(x: geo.size.width * 0.12, y: geo.size.height * 0.28, width: geo.size.width * 0.76, height: geo.size.height * 0.4)
                }
                let img = ImageLoader.shared.cached(place.cameraImage)?.size ?? CGSize(width: 1, height: 1)
                return CoverLayout(imageSize: img, container: geo.size, anchor: CGPoint(x: place.cameraAnchor.x, y: place.cameraAnchor.y), zoom: 1.06).rect(place.focus)
            }()
            let box = locked ? focus : start

            ZStack(alignment: .topLeading) {
                if let photo = request.photo { CoverImage(image: photo) } else { CoverImage(place.cameraImage, anchor: place.cameraAnchor, zoom: 1.06) }
                Color.black.opacity(0.32)
                Reticle(color: Palette.tufo, line: 4, corner: 30)
                    .frame(width: box.width, height: box.height)
                    .overlay(alignment: .top) {
                        Rectangle().fill(LinearGradient(colors: [.clear, Palette.tufo, .clear], startPoint: .leading, endPoint: .trailing))
                            .frame(height: 2).shadow(color: Palette.tufo.opacity(0.7), radius: 9)
                            .padding(.horizontal, 8)
                            .offset(y: scan ? box.height * 0.92 : box.height * 0.06)
                            .opacity(locked ? 1 : 0)
                    }
                    .offset(x: box.minX, y: box.minY)
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 14) {
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(Array((clues + [t("scan.gotItChip")]).enumerated()), id: \.offset) { i, clue in
                            let got = i == clues.count
                            Text(clue).font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(got ? Palette.onTufo : .white)
                                .padding(.horizontal, 15).frame(height: 38)
                                .background { if got { Capsule().fill(Palette.tufo) } }
                                .glassEffect(got ? .identity : .regular, in: .capsule)
                                .opacity(i < visibleClues ? 1 : 0)
                                .scaleEffect(i < visibleClues ? 1 : 0.85)
                                .animation(Motion.pop, value: visibleClues)
                        }
                    }
                    .frame(maxWidth: 340)
                    Text(thinking.isEmpty ? t("scan.looking") : thinking).font(Typeface.hand(22)).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 8)
                        .contentTransition(.opacity)
                }
                .padding(.bottom, 54)
            }
        }
        .overlay { Color.white.opacity(flash ? 1 : 0).allowsHitTesting(false) }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .task { await run() }
    }

    private func run() async {
        // Every pause checks for cancellation, so leaving the screen stops the sequence.
        func pause(_ ms: Int) async -> Bool { (try? await Task.sleep(for: .milliseconds(reduce ? min(ms, 120) : ms))) != nil }
        let t = model.strings
        withAnimation(.easeOut(duration: 0.5)) { flash = false }
        // Recognition runs alongside the animation, so it never feels like waiting.
        let site = model.site
        let recognition = Task { () -> RecognitionResult in
            guard let photo = request.photo else { return .confident(request.suggested) }
            return await matcher.identify(photo, in: site, near: location.lastLocation, catalog: model.catalog)
        }
        guard await pause(250) else { recognition.cancel(); return }
        withAnimation(reduce ? .default : .spring(response: 0.7, dampingFraction: 0.72)) { locked = true }
        guard await pause(450) else { return }
        withAnimation(.easeInOut(duration: 0.9).repeatCount(3, autoreverses: true)) { scan = true }
        let result = await recognition.value
        // Show what the AI actually saw in the photo; for a known place, add its clues.
        let vocab = model.catalog.vocabulary
        let seen = (matcher.log.first?.topLabels ?? []).compactMap { id in
            vocab?.labels.first { $0.id == id }.map { vocab!.name($0, language: model.language) }
        }
        if case .confident(let p) = result {
            clues = request.photo == nil ? (model.site.place(id: p.id)?.clues ?? p.clues) : Array((seen.prefix(2) + [p.name]).prefix(3))
        } else {
            clues = Array(seen.prefix(3))
        }
        for i in 1...clues.count + 1 {
            guard await pause(420) else { return }
            visibleClues = i
            if i == 2 { withAnimation { thinking = clues.prefix(2).joined(separator: "… ").lowercased().capitalizedFirst + "…" } }
        }
        if case .confident = result { withAnimation { thinking = t("scan.gotIt") }; Haptics.success() }
        guard await pause(700) else { return }
        onResult(result)
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Shown when the photo could be one of several places: the person picks, or says none of these.
struct ChoosePlaceView: View {
    let photo: UIImage?
    let places: [Place]
    let label: String?
    let noMatch: Bool
    let onPick: (Place) -> Void
    let onNone: () -> Void
    @Environment(AppModel.self) private var model
    @State private var shown = false

    var body: some View {
        let t = model.strings
        ZStack {
            if let photo { CoverImage(image: photo).blur(radius: 18).overlay(Color.black.opacity(0.45)).ignoresSafeArea() }
            else { Palette.piperno.ignoresSafeArea() }
            VStack(alignment: .leading, spacing: 14) {
                Spacer()
                if let label { Text(t("ai.looksLike", label)).font(Typeface.hand(22)).foregroundStyle(Palette.tufo) }
                Text(t("scan.unsureTitle")).font(Typeface.display(30)).foregroundStyle(.white)
                Text(t("scan.unsureBody")).font(.system(size: 16)).foregroundStyle(.white.opacity(0.8))
                ForEach(Array(places.compactMap { model.site.place(id: $0.id) }.enumerated()), id: \.element.id) { i, p in
                    Button { Haptics.tap(); onPick(p) } label: {
                        HStack(spacing: 14) {
                            CoverImage(p.cameraImage, anchor: p.cameraAnchor).frame(width: 64, height: 64).clipShape(.rect(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(Typeface.display(19)).foregroundStyle(.white)
                                Text(p.street).font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(12)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                    }
                    .rise(shown, delay: 0.1 + Double(i) * 0.08)
                }
                Button(t("ai.noneOfThese"), action: onNone)
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity).padding(.top, 6)
                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 20)
        }
        .preferredColorScheme(.dark)
        .onAppear { shown = true }
    }
}

/// The photo isn't one of our places. Say what it looks like, kindly, and offer what is nearby.
struct NotAPlaceView: View {
    let photo: UIImage?
    let label: String?
    let heritage: Bool
    let nearby: [Place]
    let onPick: (Place) -> Void
    let onRetake: () -> Void
    @Environment(AppModel.self) private var model
    @State private var shown = false

    var body: some View {
        let t = model.strings
        ZStack {
            if let photo { CoverImage(image: photo).blur(radius: 14).overlay(Color.black.opacity(0.5)).ignoresSafeArea() }
            else { Palette.piperno.ignoresSafeArea() }
            VStack(alignment: .leading, spacing: 14) {
                Spacer()
                if let photo {
                    CoverImage(image: photo).frame(width: 110, height: 110).clipShape(.rect(cornerRadius: 24))
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white, lineWidth: 4)).rotationEffect(.degrees(-4))
                        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                        .scaleEffect(shown ? 1 : 0.6).animation(Motion.pop, value: shown)
                }
                Text(label.map { t(heritage ? "ai.heritageTitle" : "ai.notPlaceTitle", $0) } ?? t("scan.noneTitle"))
                    .font(Typeface.display(30)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                    .rise(shown, delay: 0.1)
                Text(t(heritage ? "ai.heritageBody" : "ai.notPlaceBody")).font(.system(size: 16)).foregroundStyle(.white.opacity(0.85))
                    .rise(shown, delay: 0.2)
                Button(t("scan.tryAgain"), action: onRetake).buttonStyle(CTAButtonStyle(kind: .tufo)).rise(shown, delay: 0.3)
                if !nearby.isEmpty {
                    Text(t("ai.nearby")).font(.system(size: 12, weight: .bold)).textCase(.uppercase).kerning(1).foregroundStyle(.white.opacity(0.7)).padding(.top, 8)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(nearby.compactMap { model.site.place(id: $0.id) }) { p in
                                Button { Haptics.tap(); onPick(p) } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        CoverImage(p.cameraImage, anchor: p.cameraAnchor).frame(width: 130, height: 90).clipShape(.rect(cornerRadius: 14))
                                        Text(p.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                                    }
                                    .frame(width: 130)
                                }
                            }
                        }
                    }
                    .rise(shown, delay: 0.4)
                }
                Spacer().frame(height: 20)
            }
            .padding(.horizontal, 20)
        }
        .preferredColorScheme(.dark)
        .onAppear { shown = true }
    }
}

// MARK: - Question

/// Ask first, tell after. The photo shrinks to the top while the sheet springs up.
struct QuestionView: View {
    let place: Place
    let story: Story
    let photo: UIImage?
    let onAnswer: (Int, Int) -> Void
    @Environment(AppModel.self) private var model
    @State private var shown = false
    @State private var selected: Int?
    @State private var confidence = 2

    var body: some View {
        let t = model.strings
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Palette.calce
                Group {
                    if let photo { CoverImage(image: photo) } else { PlaceGallery(place: place, topInset: geo.safeAreaInsets.top + 56) }
                }
                .frame(height: shown ? geo.size.height * 0.42 : geo.size.height)
                .animation(Motion.glide, value: shown)

                VStack(alignment: .leading, spacing: 12) {
                    Capsule().fill(Palette.hair).frame(width: 38, height: 5).frame(maxWidth: .infinity)
                    Text(story.eyebrow).font(.system(size: 12, weight: .bold)).textCase(.uppercase).kerning(1).foregroundStyle(Palette.stone)
                        .rise(shown, delay: 0.45)
                    Text(story.question).font(Typeface.display(31, relativeTo: .title)).foregroundStyle(Palette.piperno)
                        .fixedSize(horizontal: false, vertical: true).minimumScaleFactor(0.8)
                        .rise(shown, delay: 0.5)
                    Spacer(minLength: 8)
                    ForEach(Array(story.answers.enumerated()), id: \.offset) { i, a in
                        Button(a) {
                            selected = i; Haptics.tap()
                            Task { try? await Task.sleep(for: .milliseconds(480)); onAnswer(i, confidence) }
                        }
                        .buttonStyle(AnswerButtonStyle(selected: selected == i, key: ["A", "B", "C", "D"][min(i, 3)]))
                        .disabled(selected != nil)
                        .rise(shown, delay: 0.65 + Double(i) * 0.09, distance: 18)
                    }
                    HStack(spacing: 10) {
                        Text(t("question.howSure")).font(.system(size: 15)).foregroundStyle(Palette.stone)
                        ForEach(1...3, id: \.self) { n in
                            Button { confidence = n; Haptics.tap() } label: {
                                Circle().fill(n <= confidence ? Palette.piperno : .clear)
                                    .overlay(Circle().stroke(Palette.piperno, lineWidth: 2)).frame(width: 14, height: 14)
                                    .padding(6)
                            }
                            .accessibilityLabel(t("question.sure\(n)"))
                        }
                    }
                    .frame(maxWidth: .infinity).rise(shown, delay: 0.95)
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
                .frame(height: geo.size.height * 0.62, alignment: .top)
                .background(Palette.calce, in: UnevenRoundedRectangle(topLeadingRadius: 38, topTrailingRadius: 38))
                .shadow(color: .black.opacity(0.25), radius: 20, y: -6)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .offset(y: shown ? 0 : geo.size.height)
                .animation(.spring(response: 0.6, dampingFraction: 0.78).delay(0.12), value: shown)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .sensoryFeedback(.selection, trigger: selected)
        .onAppear { shown = true }
    }
}

// MARK: - Reveal

/// The answer, as a page you want to read: the place's photo, a result badge, the story in a card,
/// and quick actions (Tonight, Then & Now, Listen, About) in the style of an Apple Maps place card.
struct RevealView: View {
    let place: Place
    let story: Story
    let chosen: Int
    var confidence = 2
    let onNext: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduce
    @AppStorage(Settings.autoRead) private var autoRead = false
    @State private var narrator = Narrator()
    @State private var shown = false
    @State private var stamped = false
    @State private var showInfo = false
    @State private var showThenNow = false
    @State private var showTonight = false

    private var right: Bool { chosen == story.correctIndex }

    var body: some View {
        let t = model.strings
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(story.eyebrow).font(.footnote.weight(.semibold)).textCase(.uppercase).kerning(0.6).foregroundStyle(Palette.stone)
                        Text(story.answerTitle).font(Typeface.display(36, relativeTo: .largeTitle)).foregroundStyle(Palette.piperno)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(story.subtitle).font(Typeface.displayBold(20, relativeTo: .title3)).foregroundStyle(Palette.azzurro)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .rise(shown, delay: 0.35)

                    actions.rise(shown, delay: 0.5)

                    Text(story.body)
                        .font(.system(size: 18)).lineSpacing(5).foregroundStyle(Palette.piperno)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.card, in: .rect(cornerRadius: 22))
                        .overlay(alignment: .topLeading) {
                            Image(systemName: "quote.opening").font(.system(size: 22, weight: .black)).foregroundStyle(Palette.tufo)
                                .offset(x: 16, y: -12)
                        }
                        .rise(shown, delay: 0.65)

                    if let theory = story.theory {
                        TheoryCard(theory: theory, stamped: stamped)
                            .opacity(shown ? 1 : 0).animation(.easeOut(duration: 0.4).delay(0.8), value: shown)
                    }

                    AnswerRecap(answers: story.answers, correct: story.correctIndex, chosen: chosen, title: t("reveal.yourAnswer"))
                        .rise(shown, delay: 0.9)
                }
                .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 24)
                .background(Palette.calce, in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32))
                .padding(.top, -32)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(Palette.calce)
        .safeAreaInset(edge: .bottom) {
            Button(story.lookCloser == nil ? t("reveal.collect") : t("reveal.lookCloser")) { Haptics.tap(); narrator.stop(); onNext() }
                .buttonStyle(CTAButtonStyle(kind: .tufo, shine: true))
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 6)
                .background(LinearGradient(colors: [Palette.calce.opacity(0), Palette.calce], startPoint: .top, endPoint: .center).padding(.top, -24))
                .rise(shown, delay: 1.0)
        }
        .preferredColorScheme(.light)
        .sensoryFeedback(right ? .success : .impact(weight: .light), trigger: shown)
        .onAppear {
            shown = true
            withAnimation(reduce ? nil : .spring(response: 0.38, dampingFraction: 0.55).delay(1.1)) { stamped = true }
            Task {
                try? await Task.sleep(for: .milliseconds(1300))
                if story.theory != nil { Haptics.rigid() }
                if autoRead && model.site.allowsReadAloud { narrator.toggle(spoken, language: model.language) }
            }
        }
        .onDisappear { narrator.stop() }
        .sheet(isPresented: $showInfo) { StoryInfoSheet(place: place) }
        .sheet(isPresented: $showThenNow) { if let tn = place.thenNow { ThenNowSheet(thenNow: tn, title: story.eyebrow) } }
    }

    /// The place's photo with the result on it, and a Then & Now button when there's an old picture.
    private var hero: some View {
        let t = model.strings
        let reaction = confidence == 3 ? (right ? t("reveal.rightSure") : t("reveal.wrongSure"))
            : right ? t("reveal.right") : t("reveal.wrong", story.answers[min(chosen, story.answers.count - 1)])
        return CoverImage(place.cameraImage, anchor: place.cameraAnchor)
            .frame(height: 340)
            .overlay {
                LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0), .init(color: .clear, location: 0.3),
                                       .init(color: .clear, location: 0.55), .init(color: .black.opacity(0.55), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 10) {
                    Label(reaction, systemImage: right ? "checkmark.circle.fill" : "lightbulb.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(right ? .white : Palette.onTufo)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(right ? Palette.maiolica : Palette.tufo, in: .capsule)
                        .fixedSize(horizontal: false, vertical: true)
                        .scaleEffect(shown ? 1 : 0.6, anchor: .bottomLeading).opacity(shown ? 1 : 0)
                        .animation(reduce ? nil : Motion.pop.delay(0.15), value: shown)
                    Spacer(minLength: 0)
                    if place.thenNow != nil {
                        Button { Haptics.tap(); showThenNow = true } label: {
                            Image(systemName: "clock.arrow.circlepath").font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white).frame(width: 46, height: 46)
                        }
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel(t("thenNow.title"))
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 46)
            }
    }

    /// Tinted quick actions, like the buttons under a place in Apple Maps.
    private var actions: some View {
        let t = model.strings
        return HStack(spacing: 10) {
            ActionTile(title: t("reveal.tonight"), icon: "fork.knife", tint: Palette.tufo, ink: Color(red: 0.55, green: 0.38, blue: 0.0)) { showTonight = true }
                .popover(isPresented: $showTonight, arrowEdge: .top) {
                    TonightCard(title: t("reveal.tellTonight"), line: story.dinnerLine)
                        .presentationCompactAdaptation(.popover)
                }
            if place.thenNow != nil {
                ActionTile(title: t("thenNow.title"), icon: "clock.arrow.circlepath", tint: Palette.mare) { showThenNow = true }
            }
            // Some sites only allow their authorised audio guides (Pompeii, visitor rules art. 6).
            if model.site.allowsReadAloud {
                ActionTile(title: narrator.isSpeaking ? t("reveal.stopReading") : t("reveal.listen"),
                           icon: narrator.isSpeaking ? "stop.fill" : "speaker.wave.2.fill", tint: Palette.azzurro) {
                    narrator.toggle(spoken, language: model.language)
                }
            }
            ActionTile(title: t("reveal.about"), icon: "info.circle", tint: Palette.maiolica) { showInfo = true }
        }
    }

    private var spoken: String { [story.answerTitle, story.subtitle, story.body].joined(separator: " ") }
}

/// One square-ish tinted button with an SF Symbol over a short label.
private struct ActionTile: View {
    let title: String
    let icon: String
    let tint: Color
    /// Text and icon colour, when the tint itself is too light to read (yellow).
    var ink: Color? = nil
    let action: () -> Void
    var body: some View {
        Button { Haptics.tap(); action() } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 19, weight: .semibold)).contentTransition(.symbolEffect(.replace))
                Text(title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
            }
            .foregroundStyle(ink ?? tint)
            .frame(maxWidth: .infinity).frame(height: 64)
            .background(tint.opacity(ink == nil ? 0.13 : 0.2), in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

/// The line to retell at dinner, in a small popover.
private struct TonightCard: View {
    let title: String
    let line: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "fork.knife").font(.footnote.weight(.bold)).textCase(.uppercase).foregroundStyle(Palette.tufo)
            Text(line).font(.title3.weight(.semibold)).foregroundStyle(Palette.piperno).fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 300, alignment: .leading)
    }
}

/// The three answers again, with the right one ticked and yours marked: a quick visual "aha".
private struct AnswerRecap: View {
    let answers: [String]
    let correct: Int
    let chosen: Int
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote.weight(.semibold)).textCase(.uppercase).kerning(0.6).foregroundStyle(Palette.stone)
            ForEach(Array(answers.enumerated()), id: \.offset) { i, a in
                let isRight = i == correct, isMine = i == chosen
                HStack(spacing: 10) {
                    Image(systemName: isRight ? "checkmark.circle.fill" : isMine ? "xmark.circle.fill" : "circle")
                        .foregroundStyle(isRight ? Palette.maiolica : isMine ? Palette.stone : Palette.hair)
                    Text(a).font(.subheadline.weight(isRight ? .semibold : .regular))
                        .foregroundStyle(isRight ? Palette.piperno : Palette.stone)
                        .strikethrough(isMine && !isRight, color: Palette.stone)
                    Spacer()
                }
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(isRight ? Palette.maiolicaSoft : Palette.card, in: .rect(cornerRadius: 14))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Two or three of the place's own photos, swipeable, used when the person's photo isn't of this place.
struct PlaceGallery: View {
    let place: Place
    var topInset: CGFloat = 60
    @State private var page = 0

    var body: some View {
        let images = place.galleryImages
        TabView(selection: $page) {
            ForEach(Array(images.enumerated()), id: \.offset) { i, ref in
                CoverImage(ref, anchor: i == 0 ? place.cameraAnchor : .init(x: 0.5, y: 0.5)).tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .overlay(alignment: .top) {
            if images.count > 1 {
                HStack(spacing: 6) {
                    ForEach(images.indices, id: \.self) { i in
                        Capsule().fill(.white.opacity(i == page ? 1 : 0.5)).frame(width: i == page ? 18 : 7, height: 7)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .animation(.snappy, value: page)
                .padding(.top, topInset)
            }
        }
    }
}
