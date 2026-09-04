//
//  PhotoDirectorPreview.swift
//  Clavic
//
//  Native design review harness for the future Photo Director tab.
//  It is only reachable through DEBUG launch environment variables and is not
//  connected to the production navigation, APIs, credits, or persistence.
//

#if DEBUG
import SwiftUI

enum PhotoDirectorPreviewStage: String {
    case start
    case analysis
    case ideas
    case results
}

struct PhotoDirectorPreviewRoot: View {
    private let variant: Int
    private let initialStage: PhotoDirectorPreviewStage

    @State private var stage: PhotoDirectorPreviewStage

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let parsedVariant = Int(environment["PHOTO_DIRECTOR_PREVIEW_VARIANT"] ?? "1") ?? 1
        let parsedStage = PhotoDirectorPreviewStage(
            rawValue: environment["PHOTO_DIRECTOR_PREVIEW_STAGE"] ?? "start"
        ) ?? .start
        variant = min(max(parsedVariant, 1), 4)
        initialStage = parsedStage
        _stage = State(initialValue: parsedStage)
    }

    var body: some View {
        PhotoDirectorPreviewShell(variant: variant, stage: $stage) {
            Group {
                switch variant {
                case 2:
                    PhotoDirectorConversationConcept(stage: stage, advance: advance)
                case 3:
                    PhotoDirectorLookLabConcept(stage: stage, advance: advance)
                case 4:
                    PhotoDirectorMoodboardConcept(stage: stage, advance: advance)
                default:
                    PhotoDirectorEditorialConcept(stage: stage, advance: advance)
                }
            }
            .id("\(variant)-\(stage.rawValue)-\(initialStage.rawValue)")
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
        .preferredColorScheme(.light)
    }

    private func advance() {
        withAnimation(.spring(response: 0.48, dampingFraction: 0.88)) {
            switch stage {
            case .start: stage = .analysis
            case .analysis: stage = .ideas
            case .ideas: stage = .results
            case .results: stage = .start
            }
        }
    }
}

private struct PhotoDirectorPreviewShell<Content: View>: View {
    let variant: Int
    @Binding var stage: PhotoDirectorPreviewStage
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                appTopBar
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            previewTabBar
        }
    }

    private var appTopBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image("credit_coin")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                Text(stage == .results ? "245" : "250")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(Theme.accent, in: Capsule())

            Spacer()

            VStack(spacing: 1) {
                Text("Clavic")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("PHOTO DIRECTOR · 0\(variant)")
                    .font(.system(size: 7.5, weight: .black, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer()

            Image(systemName: "gearshape.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 40, height: 40)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.vertical, 10)
        .background(Theme.background.opacity(0.98))
    }

    private var previewTabBar: some View {
        HStack(spacing: 2) {
            tabItem("sparkles.rectangle.stack.fill", "Director", selected: true)
            tabItem("wand.and.stars", "Chat")
            tabItem("slider.horizontal.3", "Studio")
            tabItem("photo.on.rectangle", "Library")
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.8), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 7)
        .padding(.horizontal, Theme.screenPadding)
        .padding(.bottom, 6)
    }

    private func tabItem(_ icon: String, _ label: String, selected: Bool = false) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(selected ? .white : Theme.textSecondary)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(selected ? Theme.accent : .clear, in: Capsule())
    }
}

// MARK: - 01 Editorial Stack

private struct PhotoDirectorEditorialConcept: View {
    let stage: PhotoDirectorPreviewStage
    let advance: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                title("Your photo, art-directed.", subtitle: "Clavic reads the light, pose and mood — then builds the edits this exact photo needs.")

                switch stage {
                case .start: start
                case .analysis: analysis
                case .ideas: ideas
                case .results: results
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
    }

    private var start: some View {
        VStack(spacing: 14) {
            heroPhoto("preview_look_elevator_mirror", height: 430) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Label("1 PERSON", systemImage: "person.fill")
                        Spacer()
                        Label("PORTRAIT", systemImage: "viewfinder")
                    }
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(0.8)

                    Text("Ready for direction")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                }
            }

            identityLock
            blueButton("Analyze this photo", icon: "sparkles", action: advance)
        }
    }

    private var analysis: some View {
        VStack(spacing: 14) {
            ZStack {
                heroPhoto("preview_look_elevator_mirror", height: 420) { EmptyView() }
                LinearGradient(colors: [.clear, Theme.accent.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 78)
                    .offset(y: 28)
                RoundedRectangle(cornerRadius: Theme.cornerLarge)
                    .strokeBorder(Theme.accent.opacity(0.75), lineWidth: 2)
            }

            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    ProgressView().tint(Theme.accent)
                    Text("Reading your photo")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Spacer()
                    Text("72%")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                }
                analysisLine("Face & identity", "Locked", true)
                analysisLine("Light direction", "Front flash", true)
                analysisLine("Best opportunity", "Background + grade", false)
            }
            .padding(16)
            .cardStyle()

            blueButton("Preview recommendations", icon: "arrow.right", action: advance)
        }
    }

    private var ideas: some View {
        VStack(spacing: 12) {
            insightBanner("Your pose is strong. Keep your face, body and framing — use the edit to create a clearer story.")
            ideaCard(index: "01", title: "Sunset Flash", subtitle: "Warm sky replacement, crisp G7X flash and natural skin", image: "preview_look_photo_sunset", selected: true)
            ideaCard(index: "02", title: "Rooftop After Dark", subtitle: "Luxury dusk mood with believable ambient city light", image: "preview_look_rooftop_dusk")
            ideaCard(index: "03", title: "Editorial Elevator", subtitle: "Polished metal, direct flash and muted magazine color", image: "preview_look_elevator_mirror")
            moreDirectionsButton
            blueButton("Create all 3 · 5 credits", icon: "sparkles", action: advance)
        }
    }

    private var results: some View {
        VStack(spacing: 14) {
            resultHero("preview_look_rooftop_dusk", label: "CLAVIC PICK", score: "Best fit · 94%")

            HStack(spacing: 10) {
                smallResult("preview_look_photo_sunset", "Sunset")
                smallResult("preview_look_elevator_mirror", "Editorial")
            }

            directorNote
            improvementChips
            blueButton("Save Clavic Pick", icon: "square.and.arrow.down.fill", action: {})
            saveAllButton
        }
    }
}

// MARK: - 02 Director Conversation

private struct PhotoDirectorConversationConcept: View {
    let stage: PhotoDirectorPreviewStage
    let advance: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    title("Ask your photo director", subtitle: "A guided conversation that turns one upload into a complete set.")

                    switch stage {
                    case .start: start
                    case .analysis: analysis
                    case .ideas: ideas
                    case .results: results
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }

            if stage != .start { composer }
        }
    }

    private var start: some View {
        VStack(spacing: 16) {
            directorBubble("Send me one photo. I’ll protect your identity and show you the three directions I’d actually create for it.")
            heroPhoto("preview_look_elevator_mirror", height: 350) {
                Label("YOUR PHOTO", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(0.8)
            }
            identityLock
            blueButton("Send to Director", icon: "arrow.up", action: advance)
        }
    }

    private var analysis: some View {
        VStack(spacing: 15) {
            userPhotoBubble
            directorBubble("I’m checking what makes this photo work before I suggest anything. I won’t change your face, hair color, body or framing.")
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 11) {
                    ZStack {
                        Circle().fill(Theme.accentSoft).frame(width: 42, height: 42)
                        Image(systemName: "viewfinder.circle.fill").foregroundStyle(Theme.accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Analyzing composition")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("Light · pose · depth · social fit")
                            .font(.system(size: 12.5, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    ProgressView().tint(Theme.accent)
                }
                ProgressView(value: 0.78).tint(Theme.accent)
            }
            .padding(16)
            .cardStyle()
            blueButton("Show what you found", icon: "arrow.right", action: advance)
        }
    }

    private var ideas: some View {
        VStack(spacing: 14) {
            userPhotoBubble
            directorBubble("The flash and centered pose are already good. I’d keep them and change the world around you. These are my three strongest directions:")
            chatIdea("A", "After-hours elevator", "Most natural", "preview_look_elevator_mirror", true)
            chatIdea("B", "Sunset on film", "Most shareable", "preview_look_photo_sunset", false)
            chatIdea("C", "Rooftop city glow", "Most elevated", "preview_look_rooftop_dusk", false)
            moreDirectionsButton
            blueButton("Generate the set · 5 credits", icon: "sparkles", action: advance)
        }
    }

    private var results: some View {
        VStack(spacing: 14) {
            directorBubble("I made all three. The rooftop version is the strongest because the light on your face already matches a dusk scene.")
            resultHero("preview_look_rooftop_dusk", label: "MY PICK", score: "Natural light match")
            HStack(spacing: 10) {
                smallResult("preview_look_elevator_mirror", "Original mood")
                smallResult("preview_look_photo_sunset", "Sunset film")
            }
            directorBubble("Want me to make the city softer, add a subtle G7X flash, or keep it exactly like this?")
            improvementChips
            blueButton("Save selected", icon: "square.and.arrow.down.fill", action: {})
        }
    }

    private var userPhotoBubble: some View {
        HStack {
            Spacer(minLength: 68)
            Image("preview_look_elevator_mirror")
                .resizable()
                .scaledToFill()
                .frame(width: 148, height: 188)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 25, height: 25)
                        .background(Theme.accent, in: Circle())
                        .padding(8)
                }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
            Text("Tell the Director what to change…")
                .font(.system(size: 13.5, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Image(systemName: "arrow.up")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Theme.accent, in: Circle())
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(Theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }
}

// MARK: - 03 Look Lab

private struct PhotoDirectorLookLabConcept: View {
    let stage: PhotoDirectorPreviewStage
    let advance: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom) {
                    title("Look Lab", subtitle: "Your photo becomes a set — with every choice still under your control.")
                    Spacer(minLength: 4)
                    Text("BETA")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Theme.accentSoft, in: Capsule())
                }

                stageRail

                switch stage {
                case .start: start
                case .analysis: analysis
                case .ideas: ideas
                case .results: results
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
    }

    private var stageRail: some View {
        HStack(spacing: 5) {
            railStep("1", "Photo", active: true)
            railLine(active: stage != .start)
            railStep("2", "Read", active: stage != .start)
            railLine(active: stage == .ideas || stage == .results)
            railStep("3", "Looks", active: stage == .ideas || stage == .results)
            railLine(active: stage == .results)
            railStep("4", "Pick", active: stage == .results)
        }
        .padding(.vertical, 8)
    }

    private var start: some View {
        VStack(spacing: 13) {
            ZStack(alignment: .bottom) {
                Image("preview_look_elevator_mirror")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 420)
                    .clipped()
                HStack(spacing: 8) {
                    labTag("Identity", "lock.fill")
                    labTag("Pose", "figure.stand")
                    labTag("Frame", "aspectratio")
                }
                .padding(13)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.6), lineWidth: 1))

            Text("AI can change the atmosphere — never the person unless you ask.")
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            blueButton("Build my look plan", icon: "arrow.right", action: advance)
        }
    }

    private var analysis: some View {
        VStack(spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                Image("preview_look_elevator_mirror")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 150, height: 235)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                VStack(spacing: 10) {
                    metricCard("LIGHT", "Direct flash", "sun.max.fill", Theme.warning)
                    metricCard("POSE", "Centered", "figure.stand", Theme.accent)
                    metricCard("MOOD", "Night out", "moon.stars.fill", Color.indigo)
                }
            }

            VStack(alignment: .leading, spacing: 11) {
                Text("THE DIRECTOR IS MAPPING YOUR OPTIONS")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(Theme.textSecondary)
                ProgressView(value: 0.82).tint(Theme.accent)
                Text("Matching your existing light to believable locations and camera treatments…")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(16)
            .cardStyle()
            blueButton("Open look plan", icon: "arrow.right", action: advance)
        }
    }

    private var ideas: some View {
        VStack(spacing: 13) {
            insightBanner("Best strategy: preserve the direct flash and replace only the environment and color treatment.")
            largeLookCard(number: "LOOK 01", name: "Rooftop Dusk", detail: "Best light match", image: "preview_look_rooftop_dusk", selected: true)
            HStack(spacing: 10) {
                compactLookCard("LOOK 02", "Sunset Film", "preview_look_photo_sunset")
                compactLookCard("LOOK 03", "Soft Editorial", "preview_look_afterglow")
            }
            moreDirectionsButton
            blueButton("Run all looks · 5 credits", icon: "play.fill", action: advance)
        }
    }

    private var results: some View {
        VStack(spacing: 13) {
            beforeAfter
            HStack(spacing: 10) {
                compactLookCard("02", "Sunset Film", "preview_look_photo_sunset")
                compactLookCard("03", "Soft Editorial", "preview_look_afterglow")
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Director score", systemImage: "sparkles")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Spacer()
                    Text("94")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.accent)
                }
                Text("The rooftop is most believable because it preserves the original flash direction and body contrast.")
                    .font(.system(size: 13.5, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                improvementChips
            }
            .padding(16)
            .cardStyle()
            blueButton("Save best version", icon: "square.and.arrow.down.fill", action: {})
        }
    }
}

// MARK: - 04 Moodboard

private struct PhotoDirectorMoodboardConcept: View {
    let stage: PhotoDirectorPreviewStage
    let advance: () -> Void

    @State private var selectedChoices: Set<String> = ["Keep identity", "Direct flash"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                title("Make this photo yours", subtitle: "Explore what could work, mix ideas or describe something completely different.")

                switch stage {
                case .start: start
                case .analysis: analysis
                case .ideas: ideas
                case .results: results
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
    }

    private var start: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                DirectorStockPhoto(.carPortrait)
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 390)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 5) {
                    Text("YOUR PHOTO")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.72))
                    Text("Nothing changes until you choose.")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

            identityLock
            openDirectionComposer
            blueButton("Show me what could work", icon: "sparkles", action: advance)
        }
    }

    private var analysis: some View {
        VStack(spacing: 14) {
            ZStack {
                DirectorStockPhoto(.carPortrait)
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 330)
                    .clipped()
                LinearGradient(colors: [.clear, Theme.accent.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 72)
                    .offset(y: 35)
                RoundedRectangle(cornerRadius: 27, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.65), lineWidth: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("WHAT I NOTICE")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1)
                    Spacer()
                    Text("Tap anything to change it")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                }
                observationRow("Light", "Warm and directional", "sun.max.fill")
                observationRow("Frame", "Close portrait", "viewfinder")
                observationRow("Mood", "Quiet, cinematic", "moon.stars.fill")
                observationRow("Identity", "Keep exactly as uploaded", "faceid")
            }
            .padding(16)
            .cardStyle()
            insightBanner("These are observations, not instructions. Keep them, change them, or ignore all of them.")
            blueButton("Explore open ideas", icon: "arrow.right", action: advance)
        }
    }

    private var ideas: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("STARTING POINTS")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(Theme.accent)
                    Text("Use one, mix them, or skip them")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                }
                Spacer()
                Text("5 ideas")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Theme.surface, in: Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    openIdeaTile(.carPortrait, "Keep it real", "Only clean the light")
                    openIdeaTile(.beachFlash, "Sunset flash", "Warm, sharp, candid")
                    openIdeaTile(.partyFlash, "Night out", "Color and energy")
                    openIdeaTile(.mirrorMoment, "Personal", "Soft and unexpected")
                    openIdeaTile(.cafeFilm, "Candid film", "Natural and easy")
                }
                .padding(.horizontal, 1)
            }

            buildYourOwnCard
            freePromptBar("Or type your own idea…")
            blueButton("Create 3 versions from my mix · 5 credits", icon: "sparkles", action: advance)
        }
    }

    private var results: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("YOUR VERSIONS")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(Theme.accent)
                    Text("Same photo. Your choices.")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                }
                Spacer()
                Text("Choose any")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Theme.surface, in: Capsule())
            }
            openResultGrid
            insightBanner("No automatic winner. Pick the one that feels like you — or change the mix and generate again.")
            freePromptBar("Tell me what you want different…")
            improvementChips
            blueButton("Save selected", icon: "square.and.arrow.down.fill", action: {})
            Text("Save all 3")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 51)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(Theme.stroke, lineWidth: 1))
        }
    }

    private var openDirectionComposer: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("What do you want from this photo?")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            freePromptBar("Describe a feeling, place, camera or nothing at all…")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    choiceChip("Surprise me", selected: true)
                    choiceChip("Still natural")
                    choiceChip("Post-ready")
                    choiceChip("Keep background")
                }
            }
        }
        .padding(15)
        .cardStyle()
    }

    private var buildYourOwnCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Build your own")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Nothing below is locked")
                        .font(.system(size: 11.5, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(Theme.accent)
            }
            openChoiceRow("LIGHT", ["Keep", "Direct flash", "Soft glow"])
            openChoiceRow("COLOR", ["Natural", "Warm", "Film"])
            openChoiceRow("SETTING", ["Keep", "Suggest", "I’ll write it"])
        }
        .padding(16)
        .cardStyle(corner: 21)
    }

    private var openResultGrid: some View {
        VStack(spacing: 10) {
            openResultCard("A", "Natural clean", .natural, selected: true, height: 360)
            HStack(spacing: 10) {
                openResultCard("B", "Warm flash", .warmFlash, height: 230)
                openResultCard("C", "Night film", .nightFilm, height: 230)
            }
        }
    }

    private func openChoiceRow(_ label: String, _ values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: 7) {
                ForEach(values, id: \.self) { value in
                    Button {
                        if selectedChoices.contains(value) {
                            selectedChoices.remove(value)
                        } else {
                            selectedChoices.insert(value)
                        }
                    } label: {
                        choiceChip(value, selected: selectedChoices.contains(value))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func openResultCard(_ letter: String, _ name: String, _ treatment: DirectorPhotoTreatment, selected: Bool = false, height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            DirectorStockPhoto(.carPortrait, treatment: treatment)
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.58)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text("VERSION \(letter)")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(0.9)
                    .foregroundStyle(.white.opacity(0.72))
                Text(name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(13)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Theme.accent, in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - Shared native preview components

private func title(_ headline: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
        Text(headline)
            .font(.system(size: 29, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.textPrimary)
        Text(subtitle)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private func heroPhoto<Overlay: View>(_ image: String, height: CGFloat, @ViewBuilder overlay: () -> Overlay) -> some View {
    ZStack(alignment: .bottomLeading) {
        Image(image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
        LinearGradient(colors: [.clear, .black.opacity(0.58)], startPoint: .center, endPoint: .bottom)
        overlay()
            .foregroundStyle(.white)
            .padding(17)
    }
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    .shadow(color: .black.opacity(0.13), radius: 16, y: 7)
}

private var identityLock: some View {
    HStack(spacing: 11) {
        Image(systemName: "faceid")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: 42, height: 42)
            .background(Theme.accentSoft, in: Circle())
        VStack(alignment: .leading, spacing: 2) {
            Text("Identity stays locked")
                .font(.system(size: 14.5, weight: .bold, design: .rounded))
            Text("Face, hair, body and framing only change when you ask.")
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        Spacer(minLength: 0)
        Image(systemName: "checkmark.seal.fill")
            .foregroundStyle(Theme.success)
    }
    .padding(13)
    .cardStyle()
}

private func blueButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack {
            Text(label)
            Spacer()
            Image(systemName: icon)
        }
        .font(.system(size: 16.5, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Theme.accent.opacity(0.23), radius: 12, y: 6)
    }
    .buttonStyle(.plain)
}

private func analysisLine(_ title: String, _ value: String, _ done: Bool) -> some View {
    HStack {
        Image(systemName: done ? "checkmark.circle.fill" : "circle.dotted")
            .foregroundStyle(done ? Theme.success : Theme.accent)
        Text(title)
            .font(.system(size: 13.5, weight: .medium, design: .rounded))
        Spacer()
        Text(value)
            .font(.system(size: 12.5, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.textSecondary)
    }
}

private func insightBanner(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 11) {
        Image(systemName: "sparkles")
            .foregroundStyle(Theme.accent)
            .font(.system(size: 17, weight: .semibold))
        Text(text)
            .font(.system(size: 13.5, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
    }
    .padding(15)
    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
}

private func ideaCard(index: String, title: String, subtitle: String, image: String, selected: Bool = false) -> some View {
    HStack(spacing: 13) {
        Image(image)
            .resizable()
            .scaledToFill()
            .frame(width: 104, height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        VStack(alignment: .leading, spacing: 7) {
            Text(index)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1)
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 12.5, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if selected {
                Label("Director pick", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
            }
        }
        Spacer(minLength: 0)
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(selected ? Theme.accent : Theme.textTertiary)
    }
    .padding(10)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(selected ? Theme.accent : Theme.stroke, lineWidth: selected ? 2 : 1))
}

private var moreDirectionsButton: some View {
    HStack {
        Image(systemName: "plus.circle.fill")
            .foregroundStyle(Theme.accent)
        VStack(alignment: .leading, spacing: 1) {
            Text("Give me more directions")
                .font(.system(size: 14, weight: .bold, design: .rounded))
            Text("Unlock 3 extra ideas · 2 credits")
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        Spacer()
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Theme.textTertiary)
    }
    .padding(14)
    .cardStyle()
}

private func resultHero(_ image: String, label: String, score: String) -> some View {
    ZStack(alignment: .bottomLeading) {
        Image(image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 430)
            .clipped()
        LinearGradient(colors: [.clear, .black.opacity(0.68)], startPoint: .center, endPoint: .bottom)
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.75))
            Text(score)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(17)
        VStack {
            HStack {
                Spacer()
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Theme.accent, in: Circle())
            }
            Spacer()
        }
        .padding(13)
    }
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
}

private func smallResult(_ image: String, _ name: String) -> some View {
    ZStack(alignment: .bottomLeading) {
        Image(image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 210)
            .clipped()
        LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
        Text(name)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(12)
    }
    .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
}

private var directorNote: some View {
    HStack(alignment: .top, spacing: 11) {
        Image(systemName: "sparkles")
            .foregroundStyle(.white)
            .frame(width: 35, height: 35)
            .background(Theme.accent, in: Circle())
        VStack(alignment: .leading, spacing: 4) {
            Text("Director’s note")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text("This version feels the most expensive and still looks like a photo you could have taken there.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
    }
    .padding(15)
    .cardStyle()
}

private var improvementChips: some View {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
            refinementChip("Softer flash", "sun.min.fill")
            refinementChip("More film", "camera.filters")
            refinementChip("Cleaner background", "eraser.fill")
        }
    }
}

private func refinementChip(_ text: String, _ icon: String) -> some View {
    Label(text, systemImage: icon)
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
}

private var saveAllButton: some View {
    Text("Save all versions")
        .font(.system(size: 15, weight: .bold, design: .rounded))
        .foregroundStyle(Theme.textPrimary)
        .frame(maxWidth: .infinity)
        .frame(height: 51)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(Theme.stroke, lineWidth: 1))
}

private func directorBubble(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
        Image(systemName: "sparkles")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(Theme.accent, in: Circle())
        Text(text)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(Theme.stroke, lineWidth: 1))
        Spacer(minLength: 18)
    }
}

private func chatIdea(_ letter: String, _ name: String, _ badge: String, _ image: String, _ selected: Bool) -> some View {
    HStack(spacing: 12) {
        Image(image)
            .resizable()
            .scaledToFill()
            .frame(width: 76, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        VStack(alignment: .leading, spacing: 5) {
            Text("OPTION \(letter)")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(1)
                .foregroundStyle(Theme.accent)
            Text(name)
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text(badge)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        Spacer()
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(selected ? Theme.accent : Theme.textTertiary)
    }
    .padding(9)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(selected ? Theme.accent : Theme.stroke, lineWidth: selected ? 2 : 1))
}

private func railStep(_ number: String, _ label: String, active: Bool) -> some View {
    VStack(spacing: 4) {
        Text(number)
            .font(.system(size: 11, weight: .black, design: .rounded))
            .foregroundStyle(active ? .white : Theme.textTertiary)
            .frame(width: 27, height: 27)
            .background(active ? Theme.accent : Theme.surfaceHigh, in: Circle())
        Text(label)
            .font(.system(size: 9.5, weight: .bold, design: .rounded))
            .foregroundStyle(active ? Theme.textPrimary : Theme.textTertiary)
    }
}

private func railLine(active: Bool) -> some View {
    Capsule()
        .fill(active ? Theme.accent : Theme.stroke)
        .frame(maxWidth: .infinity)
        .frame(height: 3)
        .offset(y: -8)
}

private func labTag(_ text: String, _ icon: String) -> some View {
    Label(text, systemImage: icon)
        .font(.system(size: 10.5, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.black.opacity(0.46), in: Capsule())
}

private func metricCard(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
    VStack(alignment: .leading, spacing: 7) {
        HStack {
            Image(systemName: icon).foregroundStyle(color)
            Spacer()
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
        }
        Text(title)
            .font(.system(size: 8.5, weight: .black, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(Theme.textTertiary)
        Text(value)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
    .padding(12)
    .frame(maxWidth: .infinity, minHeight: 71, alignment: .leading)
    .cardStyle(corner: 18)
}

private func largeLookCard(number: String, name: String, detail: String, image: String, selected: Bool) -> some View {
    ZStack(alignment: .bottomLeading) {
        Image(image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 350)
            .clipped()
        LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
        VStack(alignment: .leading, spacing: 4) {
            Text(number)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.7))
            Text(name)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Label(detail, systemImage: "sparkles")
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.84))
        }
        .padding(16)
        if selected {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Theme.accent, in: Circle())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(13)
        }
    }
    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
}

private func compactLookCard(_ number: String, _ name: String, _ image: String) -> some View {
    ZStack(alignment: .bottomLeading) {
        Image(image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 205)
            .clipped()
        LinearGradient(colors: [.clear, .black.opacity(0.62)], startPoint: .center, endPoint: .bottom)
        VStack(alignment: .leading, spacing: 3) {
            Text(number)
                .font(.system(size: 8.5, weight: .black, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.7))
            Text(name)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(12)
    }
    .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
}

private var beforeAfter: some View {
    GeometryReader { proxy in
        ZStack {
            HStack(spacing: 2) {
                Image("preview_look_elevator_mirror")
                    .resizable().scaledToFill()
                    .frame(width: (proxy.size.width - 2) / 2, height: 420).clipped()
                Image("preview_look_rooftop_dusk")
                    .resizable().scaledToFill()
                    .frame(width: (proxy.size.width - 2) / 2, height: 420).clipped()
            }
            Rectangle().fill(.white).frame(width: 3)
            Circle()
                .fill(.white)
                .frame(width: 40, height: 40)
                .shadow(color: .black.opacity(0.2), radius: 8)
                .overlay(Image(systemName: "arrow.left.and.right").font(.system(size: 13, weight: .bold)))
            HStack {
                Text("BEFORE")
                Spacer()
                Text("DIRECTOR PICK")
            }
            .font(.system(size: 9, weight: .black, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(.white)
            .padding(13)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
    .frame(height: 420)
    .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
}

private enum DirectorStockImage {
    case carPortrait
    case beachFlash
    case partyFlash
    case mirrorMoment
    case cafeFilm

    var url: URL? {
        let id: String
        switch self {
        case .carPortrait: id = "35419686"
        case .beachFlash: id = "34243396"
        case .partyFlash: id = "29913885"
        case .mirrorMoment: id = "8154669"
        case .cafeFilm: id = "32403506"
        }
        return URL(string: "https://images.pexels.com/photos/\(id)/pexels-photo-\(id).jpeg?auto=compress&cs=tinysrgb&w=1200")
    }
}

private enum DirectorPhotoTreatment {
    case natural
    case warmFlash
    case nightFilm
}

private struct DirectorStockPhoto: View {
    let photo: DirectorStockImage
    let treatment: DirectorPhotoTreatment

    init(_ photo: DirectorStockImage, treatment: DirectorPhotoTreatment = .natural) {
        self.photo = photo
        self.treatment = treatment
    }

    var body: some View {
        AsyncImage(url: photo.url, transaction: Transaction(animation: .easeInOut(duration: 0.25))) { phase in
            switch phase {
            case .success(let image): treated(image)
            case .failure:
                ZStack {
                    Theme.surfaceHigh
                    Image(systemName: "photo")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            default:
                ZStack {
                    Theme.surfaceHigh
                    ProgressView().tint(Theme.accent)
                }
            }
        }
    }

    @ViewBuilder
    private func treated(_ image: Image) -> some View {
        switch treatment {
        case .natural:
            image.resizable().saturation(0.97).contrast(1.03)
        case .warmFlash:
            image.resizable()
                .saturation(1.12)
                .contrast(1.08)
                .brightness(0.025)
                .colorMultiply(Color(red: 1.0, green: 0.95, blue: 0.88))
        case .nightFilm:
            image.resizable()
                .saturation(0.78)
                .contrast(1.16)
                .brightness(-0.035)
                .colorMultiply(Color(red: 0.86, green: 0.92, blue: 1.0))
        }
    }
}

private func observationRow(_ label: String, _ value: String, _ icon: String) -> some View {
    HStack(spacing: 10) {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: 30, height: 30)
            .background(Theme.accentSoft, in: Circle())
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 8.5, weight: .black, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.system(size: 13.5, weight: .bold, design: .rounded))
        }
        Spacer()
        Image(systemName: "pencil")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.textTertiary)
    }
}

private func openIdeaTile(_ photo: DirectorStockImage, _ title: String, _ subtitle: String) -> some View {
    ZStack(alignment: .bottomLeading) {
        DirectorStockPhoto(photo)
            .scaledToFill()
            .frame(width: 174, height: 246)
            .clipped()
        LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.76))
        }
        .foregroundStyle(.white)
        .padding(12)
        Image(systemName: "plus")
            .font(.system(size: 11, weight: .black))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: 30, height: 30)
            .background(.white, in: Circle())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(10)
    }
    .frame(width: 174, height: 246)
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
}

private func freePromptBar(_ placeholder: String) -> some View {
    HStack(spacing: 9) {
        Image(systemName: "text.cursor")
            .foregroundStyle(Theme.accent)
        Text(placeholder)
            .font(.system(size: 12.5, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
        Spacer()
        Image(systemName: "mic.fill")
            .font(.system(size: 12))
            .foregroundStyle(Theme.textTertiary)
    }
    .padding(.horizontal, 13)
    .frame(height: 48)
    .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
}

private func choiceChip(_ text: String, selected: Bool = false) -> some View {
    HStack(spacing: 5) {
        if selected {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .black))
        }
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
    }
    .foregroundStyle(selected ? .white : Theme.textSecondary)
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(selected ? Theme.accent : Theme.surface, in: Capsule())
    .overlay {
        if !selected { Capsule().strokeBorder(Theme.stroke, lineWidth: 1) }
    }
}

#Preview("Photo Director 01") {
    PhotoDirectorPreviewRoot(environment: [
        "PHOTO_DIRECTOR_PREVIEW_VARIANT": "1",
        "PHOTO_DIRECTOR_PREVIEW_STAGE": "ideas"
    ])
}
#endif
