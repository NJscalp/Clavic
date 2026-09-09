//
//  PoseCameraView.swift
//  Clavic
//
//  Die Oberfläche zum Kamera-Modus (siehe PoseCamera.swift).
//
//  DIE KAMERA LÄUFT SOFORT. Beim Öffnen sieht man sich selbst — kein
//  vorgeschalteter Auswahl-Bildschirm. Die Vorlage wird in die laufende Kamera
//  HINEINGELEGT: durchsichtig, verschiebbar, zoombar, damit man die Pose
//  nachstellen kann, während man sich sieht.
//
//  Zwei Entscheidungen, die den Unterschied machen:
//
//  1. Der Kamerarahmen übernimmt das SEITENVERHÄLTNIS der Vorlage, sobald eine
//     da ist, und die Aufnahme wird genau auf diesen Ausschnitt beschnitten.
//     Dadurch stimmt hinterher nicht nur die Pose, sondern auch der Bildaufbau —
//     ohne das ist ein 9:16-Selfie unter einer 4:5-Vorlage immer verschoben.
//  2. Die Vorlage liegt IM Rahmen, nicht darüber, und lässt sich verschieben
//     und zoomen. Man richtet damit den eigenen Körper an der Vorlage aus, statt
//     zu raten.
//

import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct PoseCameraView: View {
    /// Wird mit dem fertigen Paket aufgerufen; der Chat sendet es dann.
    var onSend: (PoseCameraResult) -> Void
    var onCancel: () -> Void
    /// NUR „Swap me in" — kein Auswahlmenue.
    ///
    /// Der Weg vom Startbildschirm heisst „Put yourself in any photo", und das
    /// IST `swap`. Wer ihn antippt, hat sich schon entschieden; ihm danach vier
    /// Moeglichkeiten hinzustellen, von denen drei etwas anderes tun, macht aus
    /// einer klaren Ansage wieder eine Frage.
    ///
    /// Der Chat-Tab oeffnet denselben Bildschirm aus einem allgemeinen
    /// Kameraknopf heraus — dort ist die Auswahl richtig und bleibt deshalb
    /// voreingestellt an.
    var nurSwap: Bool = false

    // Zwei Wege zum selben Ergebnis: mit der Kamera ein Selfie machen (Vorlage
    // liegt dabei durchsichtig darüber) ODER beide Bilder aus der Mediathek
    // nehmen. Die Auswahl steht VOR der Kamera, damit sie sich nicht bei jedem
    // Öffnen einschaltet, wenn man sie gar nicht braucht.
    private enum Stage { case start, shoot, compose }

    // Der Zwischenschritt „Kamera oder Mediathek?" ist raus. Er hat eine
    // Frage gestellt, die man am Feld selbst beantwortet: Wer die Kamera will,
    // tippt auf das Selfie-Feld und waehlt dort Kamera. Ein eigener Screen
    // dafuer ist ein Umweg.
    @State private var stage: Stage = .compose
    /// Merkt den gewählten Weg — der Zurück-Knopf im letzten Schritt muss
    /// dorthin führen, wo man hergekommen ist.
    @State private var usedCamera = false
    @State private var camera = PoseCameraModel()

    // Vorlage
    @State private var referenceData: Data?
    @State private var referenceSelection: PhotosPickerItem?
    @State private var linkText = ""
    @State private var showLinkField = false
    @State private var showLinkAlert = false
    /// EIN Picker mit Ziel statt zweier.
    ///
    /// Vorher hingen zwei `.photosPicker`-Modifier an derselben View. SwiftUI
    /// bedient davon nur einen — beim Tippen auf „You" ging der Vorlagen-Picker
    /// auf, und das eigene Foto landete als `referenceData`. Sichtbar wurde das
    /// als durchsichtiges Bild von einem selbst ueber der Live-Kamera.
    private enum PickerTarget { case shot, reference }
    @State private var pickerTarget: PickerTarget?
    @State private var pickedItem: PhotosPickerItem?
    @State private var isLoadingReference = false
    @State private var errorText: String?

    // Ausrichtung der Vorlage im Rahmen

    // Aufnahme
    @State private var shotData: Data?
    @State private var shotSelection: PhotosPickerItem?
    @State private var isCapturing = false

    // Absicht
    @State private var intent: PoseIntent = .swap
    @State private var aspekt: PoseAspect = .auto
    @State private var aufloesung: PoseResolution = .high
    /// Alle Feineinstellungen liegen hinter einer Zeile. Beim Betreten stehen
    /// nur die beiden Felder da — vorher waren Seitenverhaeltnis, Aufloesung
    /// und Textfeld sofort sichtbar, mit gesetzter Vorauswahl.
    @State private var zeigeErweitert = false
    @State private var extraText = ""
    @FocusState private var textFocused: Bool

    /// Einmal dekodierte Vorschauen.
    ///
    /// `UIImage(data:)` im View-Body dekodiert das JPEG bei JEDEM Neuzeichnen —
    /// und waehrend die Tastatur auf- oder zufaehrt, sind das 60 Neuzeichnungen
    /// pro Sekunde bei mehreren MB je Bild. Genau daran hat das Auf- und
    /// Zuklappen des Textfelds geruckelt.
    @State private var shotPreview: UIImage?
    @State private var referencePreview: UIImage?
    @FocusState private var linkFocused: Bool

    // Halo AI hält den Kamera-Bildschirm HELL — die Vorschau ist eine Karte
    // auf ruhigem Grau, nicht ein schwarzer Vollbild-Sucher. Passt ohnehin
    // besser zu unserem Theme als das frühere Schwarz.
    private let bg = Theme.background

    /// Rahmenverhältnis = Verhältnis der Vorlage (begrenzt, damit extreme
    /// Panoramen den Bildschirm nicht sprengen).
    private var frameAspect: CGFloat {
        guard let ui = referencePreview, ui.size.height > 0 else { return 3.0 / 4.0 }
        return min(max(ui.size.width / ui.size.height, 0.5), 1.4)
    }

    private var hasReference: Bool { referenceData != nil }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            switch stage {
            case .start:   startStage
            case .shoot:   shootStage
            case .compose: composeStage
            }

            if let errorText {
                VStack {
                    Spacer()
                    Text(errorText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .background(Theme.danger.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 120)
                }
                .transition(.opacity)
            }
        }
        .onChange(of: referenceSelection) { _, item in
            guard let item else { return }
            Task { await loadReference(from: item) }
        }
        .onChange(of: shotSelection) { _, item in
            guard let item else { return }
            Task { await loadShot(from: item) }
        }
        // Auswahl über Modifier statt eingebettete Picker: im letzten Schritt
        // sitzen die Auswahlflächen in einer Zeile, dort ist kein Platz für
        // zwei ausgewachsene PhotosPicker-Knöpfe.
        .onChange(of: shotData) { _, data in
            shotPreview = data.flatMap { UIImage(data: $0) }
        }
        .onChange(of: referenceData) { _, data in
            referencePreview = data.flatMap { UIImage(data: $0) }
        }
        .photosPicker(
            isPresented: Binding(
                get: { pickerTarget != nil },
                set: { if !$0 { pickerTarget = nil } }
            ),
            selection: $pickedItem,
            matching: .images
        )
        .onChange(of: pickedItem) { _, item in
            guard let item, let target = pickerTarget else { return }
            pickerTarget = nil
            pickedItem = nil
            Task {
                switch target {
                case .shot: await loadShot(from: item)
                case .reference: await loadReference(from: item)
                }
            }
        }
        .alert("Paste a link", isPresented: $showLinkAlert) {
            TextField("https://pin.it/…", text: $linkText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Load") { Task { await loadReference(fromLink: linkText) } }
            Button("Cancel", role: .cancel) { linkText = "" }
        } message: {
            Text("A Pinterest pin or any direct image link.")
        }
        .onDisappear { camera.stop() }
    }

    // MARK: - Einstieg: welchen Weg?

    private var startStage: some View {
        VStack(spacing: 0) {
            header(title: "Clavic", trailing: nil)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Text("Put yourself in any photo")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Pick the shot you want to recreate, add yourself, and you take the other person's place — same pose, same lighting.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
            }
            .padding(.horizontal, 22)

            Spacer(minLength: 0)

            VStack(spacing: 11) {
                Button {
                    usedCamera = true
                    withAnimation(.spring(duration: 0.3)) { stage = .shoot }
                } label: {
                    startOption(icon: "camera.fill",
                                title: "Use camera to make selfie",
                                subtitle: "The reference sits next to your camera so you can copy the pose",
                                filled: true)
                }
                .buttonStyle(.plain)

                Button {
                    usedCamera = false
                    withAnimation(.spring(duration: 0.3)) { stage = .compose }
                } label: {
                    startOption(icon: "photo.stack",
                                title: "Use image from library",
                                subtitle: "Pick both photos from your library — no camera needed",
                                filled: false)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 34)
        }
    }

    private func startOption(icon: String, title: String, subtitle: String, filled: Bool) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(filled ? Color.white : Theme.textPrimary)
                .frame(width: 44, height: 44)
                .background(filled ? AnyShapeStyle(Color.white.opacity(0.22)) : AnyShapeStyle(Theme.surface), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .opacity(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(filled ? Color.white : Theme.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(filled ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surfaceHigh),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Kamera + Vorlage einlegen

    private var shootStage: some View {
        VStack(spacing: 0) {
            // Über der Kamera steht die Marke, kein wechselnder Zustandstext —
            // der Hinweis unter dem Rahmen sagt ohnehin, was gerade zu tun ist.
            header(title: "Clavic", trailing: nil)

            Spacer(minLength: 0)

            cameraFrame
                .padding(.horizontal, 18)

            Spacer(minLength: 0)

            VStack(spacing: 13) {
                // Die Vorlage wird HIER in die laufende Kamera eingelegt —
                // nicht in einem Schritt davor. Ohne Vorlage steht an dieser
                // Stelle die Aufforderung, mit Vorlage die Miniatur zum Tauschen.
                referenceBar
                    .padding(.horizontal, 22)

                Text(hintText)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                shutterRow
            }
            .padding(.bottom, 26)
        }
        // Die Kamera startet mit der Ansicht, nicht erst nach einer Auswahl.
        .task { await camera.start() }
    }

    private var hintText: String {
        if !camera.isAvailable && !camera.permissionDenied {
            return "No camera here — pick a selfie from your photos instead"
        }
        if camera.permissionDenied {
            return "Turn on camera access in Settings, or pick a selfie from your photos"
        }
        return hasReference
            ? "Copy the pose from the reference next to you, then shoot"
            : "Add the shot you want to recreate — it stays next to your camera"
    }

    /// Leiste unter der Kamera: Vorlage einlegen bzw. die eingelegte zeigen.
    @ViewBuilder private var referenceBar: some View {
        if referenceData != nil, let ui = referencePreview {
            HStack(spacing: 11) {
                Image(uiImage: ui)
                    .resizable().scaledToFill()
                    .frame(width: 62, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.stroke, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Reference")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Copy this pose")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 0)

                PhotosPicker(selection: $referenceSelection, matching: .images) {
                    Text("Change")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Theme.surface, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.spring(duration: 0.3)) { clearReference() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Theme.surface, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if showLinkField {
            HStack(spacing: 8) {
                TextField("https://pin.it/…", text: $linkText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($linkFocused)
                    .submitLabel(.go)
                    .onSubmit { Task { await loadReference(fromLink: linkText) } }
                    .padding(.horizontal, 13).padding(.vertical, 11)
                    .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                Button {
                    Task { await loadReference(fromLink: linkText) }
                } label: {
                    Group {
                        if isLoadingReference {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold))
                        }
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(linkText.trimmingCharacters(in: .whitespaces).isEmpty || isLoadingReference)

                Button {
                    withAnimation(.spring(duration: 0.25)) { showLinkField = false; linkFocused = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.plain)
            }
        } else {
            HStack(spacing: 9) {
                PhotosPicker(selection: $referenceSelection, matching: .images) {
                    addReferenceChip(icon: "photo.stack", title: "Add reference", filled: true)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.spring(duration: 0.25)) { showLinkField = true; linkFocused = true }
                } label: {
                    addReferenceChip(icon: "link", title: "Link", filled: false)
                }
                .buttonStyle(.plain)
            }
            .overlay(alignment: .center) {
                if isLoadingReference {
                    ProgressView().tint(Theme.textPrimary)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(.black.opacity(0.6), in: Capsule())
                }
            }
        }
    }

    private func addReferenceChip(icon: String, title: String, filled: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold))
            Text(title).font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .foregroundStyle(filled ? Color.white : Theme.textPrimary)
        .frame(maxWidth: filled ? .infinity : nil)
        .padding(.horizontal, filled ? 16 : 18).padding(.vertical, 12)
        .background(filled ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surfaceHigh), in: Capsule())
    }

    private var cameraFrame: some View {
        ZStack {
            // Eigener Rahmen der Kamera — das Live-Bild sitzt darin, die Vorlage
            // liegt IM selben Rahmen darüber.
            if camera.isAvailable {
                CameraPreviewLayer(camera: camera)
            } else {
                ZStack {
                    Theme.surfaceHigh
                    VStack(spacing: 8) {
                        Image(systemName: camera.permissionDenied ? "lock.fill" : "camera.fill")
                            .font(.system(size: 26, weight: .light))
                        Text(camera.permissionDenied ? "Camera access is off" : "No camera available")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
            }

            // Die Vorlage lag frueher halbtransparent IM Kamerabild. Genau das
            // hat gestoert — sie verdeckt einen selbst und tauchte als Geist in
            // Ergebnissen auf. Sie steht jetzt ausschliesslich als Kachel neben
            // der Kamera (siehe `referenceBar`).
        }
        .aspectRatio(frameAspect, contentMode: .fit)
        .frame(maxHeight: 520)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
    }

    /// Drei Knöpfe unter der Karte, wie bei Halo: Mediathek links, großer
    /// hohler Auslöser in der Mitte, Kamerawechsel rechts. Bewusst kein
    /// gefüllter Kreis — der Ring liest sich als Auslöser, nicht als Punkt.
    private var shutterRow: some View {
        HStack(spacing: 0) {
            PhotosPicker(selection: $shotSelection, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 50, height: 50)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!hasReference)
            .opacity(hasReference ? 1 : 0.3)
            .frame(maxWidth: .infinity)

            Button {
                Task { await shoot() }
            } label: {
                ZStack {
                    Circle().fill(Theme.surface).frame(width: 72, height: 72)
                    Circle().strokeBorder(Theme.textPrimary.opacity(0.18), lineWidth: 3)
                        .frame(width: 80, height: 80)
                    if isCapturing { ProgressView().tint(Theme.textPrimary) }
                }
            }
            .buttonStyle(.plain)
            .disabled(!camera.isAvailable || isCapturing || !hasReference)
            .opacity(camera.isAvailable && hasReference ? 1 : 0.3)
            .frame(maxWidth: .infinity)

            Button {
                Task { await camera.flip() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 50, height: 50)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!camera.isAvailable)
            .opacity(camera.isAvailable ? 1 : 0.35)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Was soll passieren

    private var composeStage: some View {
        VStack(spacing: 0) {
            header(title: nurSwap ? "Put yourself in it" : "What should I do?", trailing: AnyView(
                Button {
                    // Über die Kamera gekommen → zurück zum Auslösen.
                    // Über die Mediathek → zurück zur Wegwahl.
                    shotData = nil
                    withAnimation(.spring(duration: 0.3)) { stage = .shoot }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(Theme.surface, in: Circle())
                }
                .buttonStyle(.plain)
            ))

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // ZWEI FELDER, BEIDE BENANNT — das eigene Selfie zuerst.
                    //
                    // Vorher standen hier zwei 92 Punkt breite Kacheln mit
                    // „You" und „Reference". Beim Mediathek-Weg sind beide
                    // anfangs leer, und dann entscheidet allein die
                    // Beschriftung, welches Foto wohin gehoert — genau diese
                    // Zuordnung bestimmt spaeter, wer im Ergebnis wer ist.
                    // „Reference" sagt das niemandem.
                    //
                    // Das eigene Selfie steht links, weil der Screen jetzt
                    // direkt geoeffnet wird: die erste Frage ist „wer bist du",
                    // nicht „was willst du nachstellen".
                    HStack(alignment: .top, spacing: 12) {
                        // Links das eigene Selfie, rechts die Vorlage.
                        Button { pickerTarget = .shot } label: {
                            bildplatz(shotPreview,
                                      titel: "Your selfie",
                                      hinweis: "Tap to take one or pick a photo",
                                      laedt: false)
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button { linkText = ""; showLinkAlert = true } label: {
                                Label("Paste a Pinterest link", systemImage: "link")
                            }
                            Button { pickerTarget = .reference } label: {
                                Label("Choose from Photos", systemImage: "photo.stack")
                            }
                        } label: {
                            bildplatz(referencePreview,
                                      titel: "Pinterest image",
                                      hinweis: "Paste a link or pick a photo",
                                      laedt: isLoadingReference)
                        }
                    }

                    // Eine Zeile statt drei Abschnitte. Zugeklappt zeigt der
                    // Screen nur die zwei Felder und den Knopf.
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            zeigeErweitert.toggle()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                            Text("Advanced settings")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.textTertiary)
                                .rotationEffect(.degrees(zeigeErweitert ? 90 : 0))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 16)
                        .background(Theme.surfaceHigh,
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if zeigeErweitert {
                    wahlzeile("Aspect ratio") {
                        ForEach(PoseAspect.allCases) { option in
                            chip(option.label, unten: option.hint, aktiv: aspekt == option) {
                                withAnimation(.spring(duration: 0.22)) { aspekt = option }
                            }
                        }
                    }

                    // Die Dauer steht MIT an der Auswahl. GEMESSEN: 2K rund
                    // 59 s, 4K rund 282 s — das ist der Unterschied zwischen
                    // „gleich da" und „geh einen Kaffee holen", und niemand
                    // sollte ihn erst hinterher merken.
                    wahlzeile("Resolution") {
                        ForEach(PoseResolution.allCases) { option in
                            chip(option.label, unten: option.hint, aktiv: aufloesung == option) {
                                withAnimation(.spring(duration: 0.22)) { aufloesung = option }
                            }
                        }
                    }

                    if !nurSwap {
                        VStack(spacing: 8) {
                            ForEach(PoseIntent.allCases) { option in
                                Button {
                                    withAnimation(.spring(duration: 0.25)) { intent = option }
                                } label: {
                                    intentRow(option)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Anything else? (optional)")
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                        // Im Swap-Modus schlug das Beispiel genau das vor, was
                        // ohnehin passiert („swap me with the person…"). Hier
                        // gehoert etwas hin, das ZUSAETZLICH wirkt.
                        TextField(nurSwap
                                  ? "e.g. keep my glasses, make it golden hour"
                                  : "e.g. swap me with the person sitting on the Lamborghini",
                                  text: $extraText, axis: .vertical)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1...4)
                            .focused($textFocused)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    }   // Ende: erweiterte Einstellungen

                    Button {
                        send()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles").font(.system(size: 15, weight: .bold))
                            Text("Create").font(.system(size: 17, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Theme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCreate)
                    .opacity(canCreate ? 1 : 0.35)
                    .padding(.top, 2)

                    if !canCreate {
                        Text(shotData == nil ? "Add a photo of yourself to continue"
                                             : "Add the shot you want to recreate")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 34)
            }
        }
    }

    /// Ein benanntes Bildfeld. Gross genug, dass man sieht, was drin liegt.
    ///
    /// Der Titel steht OBEN und immer — auch wenn ein Bild drin ist. Vorher
    /// stand er unter der Kachel und verschwand gefuehlt, sobald ein Foto da
    /// war; wer dann zurueckkam, musste raten, welches Feld welches ist.
    private func bildplatz(_ bild: UIImage?, titel: String,
                           hinweis: String, laedt: Bool) -> some View {
        // Die Beschriftung sitzt IM Feld, nicht darueber. Gestrichelte Raender
        // sind Formular-Vokabular — hier traegt eine gefuellte Flaeche mit
        // rundem Symbolabzeichen und weichem Schatten.
        ZStack {
            if let ui = bild {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Theme.accent.opacity(0.12), Theme.accent.opacity(0.04)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 9) {
                    ZStack {
                        Circle().fill(Theme.accent.opacity(0.15))
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.accent)
                    }
                    .frame(width: 52, height: 52)
                    Text(titel)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text(hinweis)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
            }
            if laedt {
                Color.black.opacity(0.25)
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(0.78, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(bild == nil ? Theme.accent.opacity(0.22) : Theme.stroke, lineWidth: 1)
        )
        .shadow(color: Theme.accent.opacity(0.13), radius: 14, y: 6)
    }

    private func wahlzeile<Inhalt: View>(_ titel: String,
                                         @ViewBuilder inhalt: () -> Inhalt) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(titel)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 7) { inhalt() }
        }
    }

    private func chip(_ text: String, unten: String?, aktiv: Bool,
                      _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(spacing: 1) {
                Text(text)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                if let unten {
                    Text(unten)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .opacity(aktiv ? 0.85 : 0.6)
                }
            }
            .foregroundStyle(aktiv ? Color.white : Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(aktiv ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surfaceHigh),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func intentRow(_ option: PoseIntent) -> some View {
        let active = intent == option
        return HStack(spacing: 12) {
            Image(systemName: option.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? Color.white : Theme.textSecondary)
                .frame(width: 34, height: 34)
                .background(active ? AnyShapeStyle(Color.white.opacity(0.22)) : AnyShapeStyle(Theme.surface), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(option.title).font(.system(size: 15, weight: .bold, design: .rounded))
                Text(option.subtitle).font(.system(size: 11.5, weight: .medium, design: .rounded)).opacity(0.62)
            }
            Spacer(minLength: 0)
            if active {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 17, weight: .bold))
            }
        }
        .foregroundStyle(active ? Color.white : Theme.textPrimary)
        .padding(.horizontal, 13).padding(.vertical, 11)
        .background(active ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surfaceHigh),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    /// Ein Bildplatz. Leer zeigt er, WAS hier hingehört — sonst weiß beim
    /// Mediathek-Weg niemand, welcher Platz das eigene Foto ist und welcher
    /// die Vorlage. Genau diese Zuordnung entscheidet später den Prompt.
    private func slot(_ image: UIImage?, label: String, hint: String) -> some View {
        VStack(spacing: 5) {
            Group {
                if let ui = image {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else {
                    ZStack {
                        Theme.surfaceHigh
                        VStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Theme.textSecondary)
                            Text(hint)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.textTertiary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 6)
                        }
                    }
                }
            }
            .frame(width: 92, height: 118)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(image == nil ? Theme.accent.opacity(0.5) : Theme.stroke,
                                  style: StrokeStyle(lineWidth: 1, dash: image == nil ? [5, 4] : []))
            )
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var canCreate: Bool { shotData != nil && referenceData != nil }

    // MARK: - Kopfzeile

    private func header(title: String, trailing: AnyView?) -> some View {
        HStack {
            Button {
                camera.stop()
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(Theme.surface, in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Spacer()

            if let trailing { trailing } else { Color.clear.frame(width: 34, height: 34) }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: - Aktionen

    private func loadReference(from item: PhotosPickerItem) async {
        isLoadingReference = true
        defer { isLoadingReference = false; referenceSelection = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), UIImage(data: data) != nil else {
            flash("Couldn't read that photo.")
            return
        }
        applyReference(data)
    }

    private func loadReference(fromLink text: String) async {
        linkFocused = false
        isLoadingReference = true
        defer { isLoadingReference = false }
        do {
            let data = try await ReferenceLoader.load(from: text)
            applyReference(data)
            linkText = ""
            showLinkField = false
        } catch {
            flash(error.localizedDescription)
        }
    }

    /// Legt die Vorlage in die laufende Kamera. Kein Ansichtswechsel — die
    /// Die Vorlage erscheint als Kachel neben der Kamera, nicht mehr darin.
    private func applyReference(_ data: Data) {
        withAnimation(.spring(duration: 0.35)) { referenceData = data }
    }

    private func clearReference() {
        referenceData = nil
    }

    private func shoot() async {
        isCapturing = true
        defer { isCapturing = false }
        guard let raw = await camera.capture() else {
            flash("Couldn't take that shot.")
            return
        }
        // Auf genau den Ausschnitt beschneiden, der im Rahmen zu sehen war —
        // sonst passt die Aufnahme nicht mehr zur Vorlage, an der sich der
        // Nutzer gerade ausgerichtet hat.
        shotData = ImageCrop.centerCrop(raw, toAspect: frameAspect) ?? raw
        camera.stop()
        withAnimation(.spring(duration: 0.35)) { stage = .compose }
    }

    private func loadShot(from item: PhotosPickerItem) async {
        defer { shotSelection = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), UIImage(data: data) != nil else {
            flash("Couldn't read that photo.")
            return
        }
        shotData = data
        camera.stop()
        withAnimation(.spring(duration: 0.35)) { stage = .compose }
    }

    private func send() {
        guard let shotData, let referenceData else { return }
        textFocused = false
        let trimmed = extraText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Erst nachsehen, WAS auf den Bildern ist. Der Personen-Prompt spricht
        // durchgehend von „mir" und „meinem Gesicht" — bei zwei Autofotos hat
        // das Modell darum eine Person erfunden, weil der Prompt eine verlangte.
        Task {
            // `flatMap` nimmt keine async-Funktion — deshalb ausgeschrieben.
            var shotHasPerson = true
            if let ui = UIImage(data: shotData) {
                shotHasPerson = await SubjectDetector.hasPerson(in: ui) ?? true
            }
            var refHasPerson = true
            if let ui = UIImage(data: referenceData) {
                refHasPerson = await SubjectDetector.hasPerson(in: ui) ?? true
            }
            // Nur wenn auf BEIDEN niemand ist, ist es sicher ein Objekt-Tausch.
            let hasPerson = shotHasPerson || refHasPerson

            let gewaehlt: PoseIntent = nurSwap ? .swap : intent
            let result = PoseCameraResult(
                shot: shotData,
                reference: referenceData,
                instruction: trimmed.isEmpty ? gewaehlt.chatLine : trimmed,
                // Zielszene (reference) für den Licht-Hint: Weißabgleich/Helligkeit
                // der Vorlage, nicht des Selfies.
                prompt: PosePrompt.build(intent: gewaehlt, userText: trimmed,
                                         sceneImage: referenceData,
                                         hasPerson: hasPerson),
                aspectRatio: aspekt.rawValue,
                quality: aufloesung.rawValue
            )
            await MainActor.run {
                camera.stop()
                onSend(result)
            }
        }
    }

    private func flash(_ text: String) {
        withAnimation { errorText = text }
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            await MainActor.run { withAnimation { errorText = nil } }
        }
    }
}

// MARK: - Zuschnitt

enum ImageCrop {
    /// Mittiger Zuschnitt auf ein Zielverhältnis (Breite/Höhe). Bildet genau
    /// das ab, was `videoGravity = .resizeAspectFill` in der Vorschau gezeigt
    /// hat: die Mitte des Sensorbildes, auf das Rahmenformat gestutzt.
    static func centerCrop(_ data: Data, toAspect target: CGFloat) -> Data? {
        guard target > 0, let image = UIImage(data: data) else { return nil }
        let normalized = redrawUpright(image)
        guard let cg = normalized.cgImage else { return nil }

        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        guard w > 0, h > 0 else { return nil }
        let current = w / h

        var rect: CGRect
        if current > target {
            let newWidth = h * target
            rect = CGRect(x: (w - newWidth) / 2, y: 0, width: newWidth, height: h)
        } else {
            let newHeight = w / target
            rect = CGRect(x: 0, y: (h - newHeight) / 2, width: w, height: newHeight)
        }
        rect = rect.integral
        guard let cropped = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped).jpegData(compressionQuality: 0.95)
    }

    /// Rechnet eine normalisierte Box von einem Zuschnitt in einen anderen um.
    ///
    /// Gebraucht, sobald das Format NACH der Aufnahme noch gewechselt wird: die
    /// Box wurde gegen das damalige Rahmenformat gemessen, geschnitten wird
    /// aber neu. Ohne diese Umrechnung säße die Markierung im exportierten Bild
    /// an einer anderen Stelle als die, auf die die Nutzerin sie gezogen hat.
    ///
    /// Beide Zuschnitte sind mittige Ausschnitte derselben Aufnahme, deshalb
    /// führt der Weg über die absoluten Koordinaten der Aufnahme.
    static func remap(
        _ rect: CGRect,
        fromAspect source: CGFloat,
        toAspect target: CGFloat,
        sourceAspect raw: CGFloat
    ) -> CGRect {
        guard source > 0, target > 0, raw > 0, source != target else { return rect }

        /// Ausschnitt in einem gedachten Bild der Breite `raw` und Höhe 1.
        func crop(for aspect: CGFloat) -> CGRect {
            if raw > aspect {
                let width = aspect
                return CGRect(x: (raw - width) / 2, y: 0, width: width, height: 1)
            }
            let height = raw / aspect
            return CGRect(x: 0, y: (1 - height) / 2, width: raw, height: height)
        }

        let from = crop(for: source)
        let to = crop(for: target)
        guard to.width > 0, to.height > 0 else { return rect }

        let absolute = CGRect(
            x: from.minX + rect.minX * from.width,
            y: from.minY + rect.minY * from.height,
            width: rect.width * from.width,
            height: rect.height * from.height
        )

        var mapped = CGRect(
            x: (absolute.minX - to.minX) / to.width,
            y: (absolute.minY - to.minY) / to.height,
            width: absolute.width / to.width,
            height: absolute.height / to.height
        )

        // Der neue Ausschnitt kann schmaler sein als der alte — dann ragt die
        // Box heraus und wird auf das sichtbare Bild gestutzt.
        mapped.size.width = min(mapped.width, 1)
        mapped.size.height = min(mapped.height, 1)
        mapped.origin.x = min(max(mapped.minX, 0), 1 - mapped.width)
        mapped.origin.y = min(max(mapped.minY, 0), 1 - mapped.height)
        return mapped
    }

    /// Zeichnet das Bild ohne EXIF-Drehung neu — danach stimmen Pixel- und
    /// Anzeigekoordinaten überein, was `cropping(to:)` voraussetzt.
    static func redrawUpright(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
