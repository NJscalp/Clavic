//
//  RemoveObjectsView.swift
//  Clavic
//
//  Etwas aus einem Foto herausnehmen, indem man darübermalt.
//
//  DIE MASCHINE DAFUER STAND SCHON, nur im Studio-Tab eingebaut: `EraseCanvas`
//  malt die Maske, `EraseMask.prepare` macht daraus Basisbild, markiertes Bild
//  und Maske in identischer Pixelgroesse, und `EraseMask.composite` rechnet die
//  Antwort des Modells so zurueck, dass AUSSERHALB der bemalten Stelle kein
//  einziges Pixel anders ist.
//
//  Genau dieses Zurueckrechnen ist der Unterschied. Ohne es liefert jedes
//  Bildmodell ein neues Bild, das dem alten aehnelt — Gesicht minimal anders,
//  Farbe verschoben, Rand neu erfunden. Mit ihm aendert sich nur der Fleck,
//  ueber den man gemalt hat. Das ist auch der Grund, warum das Werkzeug bei
//  Apple so unauffaellig wirkt: es taeuscht keine Bearbeitung vor, es entfernt.
//
//  DREI EINSTELLUNGEN AUS DEM STUDIO WERDEN UEBERNOMMEN, weil sie dort schon
//  gemessen wurden: Qualitaet `low` und Seedream statt GPT Image 2 (die Flaeche
//  ist klein und lokal, ausserhalb bleibt ohnehin alles stehen), und ein
//  engerer Abfragetakt, damit das Ergebnis sofort erscheint.
//

import PhotosUI
import SwiftUI

struct RemoveObjectsView: View {
    /// Optional schon mitgebracht — sonst waehlt man hier eines.
    var startBild: Data? = nil
    var onFertig: (UIImage) -> Void = { _ in }
    var onClose: () -> Void = {}

    @Environment(Store.self) private var store
    @AppStorage("acceptedContentPolicy") private var acceptedContentPolicy = false

    @State private var bild: UIImage?
    @State private var striche: [EraseStroke] = []
    @State private var pinsel: Double = 0.055
    @State private var laeuft = false
    @State private var meldung: String?
    @State private var auswahl: PhotosPickerItem?
    @State private var zeigeEinwilligung = false
    @State private var showPaywall = false
    @State private var zeigePicker = false

    private var kosten: Int { CreditCosts.imageEditCredits(quality: "low") }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                kopf
                if let bild {
                    leinwand(bild)
                    werkzeuge
                } else {
                    auswahlLeer
                }
            }
        }
        // EIGENER ZUSTAND, kein gerechnetes Binding.
        //
        // Hier stand ein `Binding` mit leerem Setter — es konnte also nur
        // aufgehen, nie zugehen. Wer den Bildwaehler abbrach, bekam ihn sofort
        // wieder. Im Simulator so gesehen.
        .photosPicker(isPresented: $zeigePicker, selection: $auswahl, matching: .images)
        .onChange(of: auswahl) { _, neu in
            guard let neu else { return }
            Task { await lade(neu) }
        }
        .onAppear {
            if let startBild, let ui = UIImage(data: startBild) {
                bild = PhotoEditEngine.normalizedForEditing(ui)
            } else if bild == nil {
                // Ohne Bild gibt es hier nichts zu tun — also gleich fragen.
                zeigePicker = true
            }
        }
        .alert("Before you continue", isPresented: $zeigeEinwilligung) {
            Button("Continue") { acceptedContentPolicy = true; entferne() }
            Button("View policy") { UIApplication.shared.open(LegalLinks.terms) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This uploads the photo for processing. Only continue with photos of yourself or people who have given permission.")
        }
        // Vollbild wie an allen anderen Stellen. Diese hier hiess intern
        // `showPaywall` statt `showSubscriptionGate` und ist mir beim
        // Umstellen durchgerutscht — deshalb kam sie wieder als Karte.
        .fullScreenCover(isPresented: $showPaywall) { PaywallView() }
        .overlay(alignment: .top) { if let meldung { hinweis(meldung) } }
        .animation(.easeInOut(duration: 0.2), value: meldung)
    }

    // MARK: - Aufbau

    private var kopf: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 34, height: 34)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 1) {
                Text("Remove objects")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Paint over what should go")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            // Platzhalter, damit die Mitte wirklich in der Mitte liegt.
            Color.clear.frame(width: 34, height: 34)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.bottom, 10)
    }

    /// Eine grosse antippbare Flaeche statt Symbol, Satz und Knopf
    /// untereinander. Vorher standen drei Elemente lose im Raum — das las sich
    /// wie ein Formular. Jetzt ist die ganze Karte das Feld.
    private var auswahlLeer: some View {
        VStack {
            Spacer(minLength: 0)
            PhotosPicker(selection: $auswahl, matching: .images) {
                ZStack {
                    LinearGradient(colors: [Theme.accent.opacity(0.10),
                                            Theme.accent.opacity(0.03)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Theme.accent.opacity(0.14))
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        .frame(width: 74, height: 74)
                        Text("Add a photo")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Paint over what should disappear")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 340)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: Theme.accent.opacity(0.12), radius: 16, y: 8)
                .padding(.horizontal, Theme.screenPadding)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }

    /// Das Bild mit der Maske darueber.
    ///
    /// `fittedRect` ist Pflicht: `scaledToFit` laesst oben/unten oder
    /// links/rechts Luft, und dort darf nicht gemalt werden — sonst liegen
    /// Striche neben dem Bild und die Maske passt hinterher nicht.
    private func leinwand(_ ui: UIImage) -> some View {
        GeometryReader { geo in
            let rahmen = fittedRect(for: ui, in: geo.size)
            ZStack {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                EraseCanvas(strokes: $striche, brush: pinsel, imageRect: rahmen)
                    .allowsHitTesting(!laeuft)
                if laeuft { arbeitet }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(.horizontal, 12)
    }

    private var arbeitet: some View {
        VStack(spacing: 8) {
            ProgressView().tint(Theme.accent)
            Text("Removing — the rest of the photo stays untouched")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var werkzeuge: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "paintbrush.pointed")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                Slider(value: $pinsel, in: 0.02...0.14)
                    .tint(Theme.accent)
                    .disabled(laeuft)

                knopf("arrow.uturn.backward") { if !striche.isEmpty { striche.removeLast() } }
                    .disabled(striche.isEmpty || laeuft)
                knopf("trash") { striche = [] }
                    .disabled(striche.isEmpty || laeuft)
            }

            Button { starte() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "eraser.fill").font(.system(size: 15, weight: .bold))
                    Text("Remove · \(kosten) credit\(kosten == 1 ? "" : "s")")
                        .font(.system(size: 16.5, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(striche.isEmpty || laeuft ? Theme.textPrimary.opacity(0.18) : Theme.accent,
                            in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(striche.isEmpty || laeuft)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    private func knopf(_ symbol: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 36, height: 36)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func hinweis(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 8)
    }

    // MARK: - Rechnen

    private func fittedRect(for image: UIImage, in size: CGSize) -> CGRect {
        let ratio = image.size.width / max(image.size.height, 1)
        var w = size.width
        var h = w / ratio
        if h > size.height { h = size.height; w = h * ratio }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func lade(_ item: PhotosPickerItem) async {
        guard let daten = try? await item.loadTransferable(type: Data.self),
              let ui = UIImage(data: daten) else { return }
        await MainActor.run {
            bild = PhotoEditEngine.normalizedForEditing(ui)
            striche = []
        }
    }

    private func starte() {
        guard acceptedContentPolicy else { zeigeEinwilligung = true; return }
        entferne()
    }

    private func entferne() {
        guard let bild, !striche.isEmpty else { return }
        guard store.canCreate else { showPaywall = true; return }
        guard store.canAfford(kosten) else {
            blitz("Not enough credits — top up to keep editing.")
            return
        }
        guard let vorbereitet = EraseMask.prepare(base: bild, strokes: striche),
              let basis = vorbereitet.base.jpegData(compressionQuality: 0.82),
              let markiert = vorbereitet.marked.jpegData(compressionQuality: 0.82) else {
            blitz("The mask could not be prepared.")
            return
        }

        laeuft = true
        Task {
            defer { Task { @MainActor in laeuft = false } }
            do {
                // `low` und Seedream: die Flaeche ist klein und lokal, und
                // ausserhalb der Maske bleibt ohnehin jedes Originalpixel —
                // im Studio schon so gemessen.
                let anfrage = ImageEditRequest(
                    prompt: EraseMask.prompt,
                    referenceImages: [basis, markiert],
                    quality: "low",
                    aspectRatio: "auto",
                    model: ImageEditAPI.defaultModel
                )
                let id = try await ImageEditAPI.createTask(anfrage)
                for versuch in 0..<200 {
                    if versuch > 0 { try? await Task.sleep(nanoseconds: 1_250_000_000) }
                    let stand = try await ImageEditAPI.fetchTask(id: id)
                    if stand.status == .succeeded, let adresse = stand.imageURL,
                       let url = URL(string: adresse),
                       let (daten, _) = try? await URLSession.shared.data(from: url),
                       let roh = UIImage(data: daten) {
                        let erzeugt = PhotoEditEngine.normalizedForEditing(roh)
                        // DAS IST DER PUNKT: nur der bemalte Fleck wird
                        // uebernommen. Ohne das kommt ein neues Bild zurueck,
                        // das dem alten nur aehnelt.
                        guard let fertig = EraseMask.composite(erzeugt, using: vorbereitet) else {
                            throw URLError(.cannotDecodeContentData)
                        }
                        await MainActor.run {
                            store.consume(kosten)
                            self.bild = fertig
                            striche = []
                            onFertig(fertig)
                        }
                        return
                    }
                    if stand.status == .failed { throw URLError(.badServerResponse) }
                }
                throw URLError(.timedOut)
            } catch {
                await MainActor.run { blitz("That didn't work — try again.") }
            }
        }
    }

    private func blitz(_ text: String) {
        withAnimation { meldung = text }
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { withAnimation { meldung = nil } }
        }
    }
}
