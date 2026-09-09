//
//  LarpFunnelView.swift
//  Clavic
//
//  Conversion-Onboarding VOR der Paywall (für kalten Ad-Traffic). Kein Chat —
//  ein schneller, geführter Ablauf:
//    Foto einfügen → ECHTE Analyse (Larp-Agent) → antippbare Ideen → eine wählen
//    → „Continue to see your result" → Paywall.
//  Strikt Pro: das echte Ergebnis wird ERST NACH dem Kauf generiert und dann
//  wirklich geliefert (kein Fake-Ladebalken, keine Täuschung). Die Analyse ist
//  billig (Claude Vision), nur die teure Bildgenerierung (GPT Image 2) ist gated.
//
//  Nutzt die bestehende Agent-API (`DirectorAPI.chat` → offer_options) und die
//  Bild-Pipeline (`ImageEditAPI`). Siehe [[clavic-larp-agent]].
//

import SwiftUI
import PhotosUI

struct LarpFunnelView: View {
    @Environment(Store.self) private var store
    /// Wird aufgerufen, wenn der Funnel fertig ist (gekauft+Ergebnis gesehen ODER
    /// weggetippt) → Aufrufer setzt `hasSeenLarpFunnel = true`.
    var onFinish: () -> Void

    private enum Stage: Equatable {
        case start        // Foto einfügen
        case analyzing    // echte Analyse läuft
        case options      // Ideen zur Auswahl
        case locked       // Idee gewählt → „Continue to see your result"
        case generating   // nach Kauf: echtes Ergebnis wird gerendert
        case result       // fertiges Ergebnis
    }

    @State private var stage: Stage = .start
    @State private var photoSelection: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var replyLine: String = ""
    @State private var options: [DirectorAPI.Option] = []
    @State private var chosen: DirectorAPI.Option?
    @State private var resultImage: Data?
    @State private var showPaywall = false
    @State private var errorText: String?

    // Dunkler, cineastischer Look (unabhängig vom Light-Theme der App).
    private let bg = Color(red: 0.05, green: 0.05, blue: 0.07)
    private let gold = Color(red: 0.91, green: 0.77, blue: 0.33)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.08, blue: 0.11), bg, .black],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            content
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Dezentes Schließen (App-Store-konform: Nutzer kommt ohne Kauf rein).
            if stage != .analyzing && stage != .generating {
                VStack {
                    HStack {
                        Spacer()
                        Button { onFinish() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white.opacity(0.55))
                                .frame(width: 34, height: 34)
                                .background(.white.opacity(0.08), in: Circle())
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
            }
        }
        .onChange(of: photoSelection) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .onChange(of: store.isPro) { _, isPro in
            // Kauf in der Paywall erfolgreich → jetzt das echte Ergebnis rendern.
            if isPro, stage == .locked {
                showPaywall = false
                Task { await generate() }
            }
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView().environment(store)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Inhalt je Stufe

    @ViewBuilder private var content: some View {
        switch stage {
        case .start:      startStage
        case .analyzing:  analyzingStage
        case .options:    optionsStage
        case .locked:     lockedStage
        case .generating: generatingStage
        case .result:     resultStage
        }
    }

    // 1) Foto einfügen
    private var startStage: some View {
        VStack(spacing: 22) {
            Spacer()
            LarpScene(height: 240)
                .frame(maxWidth: 320)

            VStack(spacing: 10) {
                Text("See YOURSELF in the flex")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Drop one photo. The Trend Agent reads it and turns it into whatever is going off right now — supercars, iced chains, the whole vibe.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()

            PhotosPicker(selection: $photoSelection, matching: .images) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 17, weight: .bold))
                    Text("Add your photo")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(gold, in: Capsule())
            }
            Text("Takes a few seconds · your photo stays private")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.bottom, 28)
        }
    }

    // 2) Analyse läuft (echt)
    private var analyzingStage: some View {
        VStack(spacing: 24) {
            Spacer()
            photoThumb(size: 150)
                .overlay(alignment: .bottomLeading) {
                    PixelLarper(inspecting: true, size: 80).offset(x: -14, y: 10)
                }
            VStack(spacing: 6) {
                dotsText("Reading your photo")
                Text("Finding the best flex for this shot")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
        }
    }

    // 3) Ideen zur Auswahl
    private var optionsStage: some View {
        VStack(spacing: 18) {
            Spacer()
            photoThumb(size: 120)
            Text(replyLine.isEmpty ? "Here's how I'd flex this:" : replyLine)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                    Button {
                        chosen = opt
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { stage = .locked }
                    } label: {
                        HStack {
                            Text(opt.label)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(gold)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 17)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(gold.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
    }

    // 4) Gewählt → Paywall-Gate (Ergebnis „ready", aber locked)
    private var lockedStage: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                photoThumb(size: 230)
                    .blur(radius: 14)
                    .overlay(Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                VStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(gold)
                    Text("Your result is ready")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 230, height: 230)

            VStack(spacing: 6) {
                Text(chosen?.label ?? "Your flex")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Unlock Clavic Pro to generate it and keep creating unlimited looks.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()

            Button { showPaywall = true } label: {
                HStack(spacing: 8) {
                    Text("Continue to see your result")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(gold, in: Capsule())
            }
            .padding(.bottom, 28)
        }
    }

    // 5) Nach Kauf: echtes Rendern
    private var generatingStage: some View {
        VStack(spacing: 20) {
            Spacer()
            LarpMoneyLoader(note: "Creating your result")
            Text("Rendering your \(chosen?.label ?? "flex")…")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
        }
    }

    // 6) Ergebnis
    private var resultStage: some View {
        VStack(spacing: 20) {
            Spacer()
            if let data = resultImage, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable().scaledToFit()
                    .frame(maxWidth: 320, maxHeight: 380)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(gold.opacity(0.4), lineWidth: 1))
            }
            Text(errorText == nil ? "Your flex is ready 🔥" : errorText!)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Spacer()
            Button { onFinish() } label: {
                Text("Start creating")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(gold, in: Capsule())
            }
            .padding(.bottom, 28)
        }
    }

    // MARK: - Bausteine

    private func photoThumb(size: CGFloat) -> some View {
        Group {
            if let data = photoData, let ui = UIImage(data: data) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                Color.white.opacity(0.08)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 1))
    }

    private func dotsText(_ text: String) -> some View {
        TimelineView(.periodic(from: .now, by: 0.45)) { ctx in
            let n = Int(ctx.date.timeIntervalSinceReferenceDate / 0.45) % 3 + 1
            HStack(spacing: 3) {
                Text(text).foregroundStyle(.white)
                Text(String(repeating: ".", count: n)).foregroundStyle(gold)
            }
            .font(.system(size: 17, weight: .bold, design: .rounded))
        }
    }

    // MARK: - Ablauf

    private func loadPhoto(_ item: PhotosPickerItem) async {
        guard let raw = try? await item.loadTransferable(type: Data.self) else { return }
        let data = UIImage(data: raw)?.jpegForAPIUpload(maxDimension: 1280, quality: 0.85) ?? raw
        await MainActor.run {
            photoData = data
            withAnimation(.easeInOut(duration: 0.3)) { stage = .analyzing }
        }
        await analyze(data)
    }

    private func analyze(_ data: Data) async {
        let reply = try? await DirectorAPI.chat(history: [], message: "", images: [data])
        await MainActor.run {
            replyLine = reply?.message ?? ""
            let opts = (reply?.picks ?? []) + (reply?.trends ?? [])
            options = opts.count >= 2 ? opts : Self.fallbackOptions
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { stage = .options }
        }
    }

    private func generate() async {
        await MainActor.run { withAnimation(.easeInOut(duration: 0.3)) { stage = .generating } }
        guard let photo = photoData, let opt = chosen else {
            await finishWithError("Something went wrong — start creating in the app.")
            return
        }
        let request = ImageEditRequest(
            prompt: opt.prompt,
            referenceImages: [photo],
            quality: "medium",
            aspectRatio: "auto",
            model: ImageEditAPI.chatModel
        )
        // Erstes Ergebnis nach dem Abo = Willkommens-Reward → verbraucht KEINEN Credit.
        do {
            let taskID = try await ImageEditAPI.createTask(request)
            if let data = await poll(taskID) {
                await MainActor.run {
                    resultImage = data
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { stage = .result }
                }
            } else {
                await finishWithError("Couldn't render right now — you're all set, create it in the app.")
            }
        } catch {
            await finishWithError("Couldn't render right now — you're all set, create it in the app.")
        }
    }

    /// Nutzer ist bereits Pro — bei einem Render-Problem nicht blockieren, sondern
    /// mit freundlichem Hinweis in die App lassen.
    private func finishWithError(_ msg: String) async {
        await MainActor.run {
            errorText = msg
            withAnimation(.easeInOut(duration: 0.3)) { stage = .result }
        }
    }

    private func poll(_ taskID: String) async -> Data? {
        // 200 × 3 s = 10 Minuten. Vorher waren es 80 (= 4 Minuten) — GEMESSEN
        // braucht GPT Image 2 bei 4K/high rund 282 s, also MEHR als das alte
        // Limit. Die App gab auf, während WaveSpeed weiterrechnete: Bild fertig,
        // abgerechnet, aber nie angezeigt ("Timeout"-Fehler trotz Kosten).
        for _ in 0..<200 {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let state = try? await ImageEditAPI.fetchTask(id: taskID) else { continue }
            switch state.status {
            case .succeeded:
                guard let s = state.imageURL, let url = URL(string: s),
                      let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
                return data
            case .failed:
                return nil
            default:
                continue
            }
        }
        return nil
    }

    /// Sichere Standard-Ideen, falls die Analyse mal nichts liefert (Funnel darf
    /// nie in einer Sackgasse enden). Identity-locked.
    private static let fallbackOptions: [DirectorAPI.Option] = [
        .init(id: "fallback_supercar", label: "Supercar flex", caption: "Night street, hard flash",
              mode: .restage, prompt: "Keep the exact same person from the photo — identical face, features, bone structure, skin tone, eye colour and hair, do not change or beautify their face. Place them leaning on a glossy black Lamborghini in a night city street, harsh direct flash like a paparazzi shot, real reflections on the paint, believable shadows, shot-on-phone realism with subtle grain. Change only the world around them.", preview: nil),
        .init(id: "fallback_icedout", label: "Iced-out night look", caption: "Rooftop, city bokeh",
              mode: .restage, prompt: "Keep the exact same person from the photo — identical face, features, bone structure, skin tone, eye colour and hair, do not change or beautify their face. Add a diamond Cuban chain and a two-tone luxury watch, dark designer outfit, upscale rooftop lounge at night with city lights bokeh behind them, warm flash lighting, natural imperfect skin, shot-on-phone realism. Change only the outfit and background.", preview: nil),
        .init(id: "fallback_oldmoney", label: "Old-money golden hour", caption: "Yacht deck, golden hour",
              mode: .restage, prompt: "Keep the exact same person from the photo — identical face, features, bone structure, skin tone, eye colour and hair, do not change or beautify their face. Dress them in a quiet-luxury cream outfit on a Mediterranean yacht deck at warm golden hour, soft natural light from the side, believable reflections and shadows, subtle phone-photo grain. Change only the outfit and scene.", preview: nil)
    ]
}
