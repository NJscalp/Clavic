//
//  DirectorCameraView.swift
//  Clavic
//
//  Zwei Situationen, die nichts miteinander zu tun haben:
//
//  „Ort" — niemand ist da, ich füge mich nachträglich ein. Das ist der Solo
//  Shot, dort entsteht ein erzeugtes Bild.
//
//  „Regie" — jemand ist dabei und fotografiert mich, kann es aber nicht. Hier
//  wird NICHTS erzeugt. Es entstehen echte Fotos; die App übernimmt nur den
//  Teil, den die andere Person nicht kann, und sagt in einem einzigen kurzen
//  Satz, was zu ändern ist.
//
//  Deshalb kostet dieser Modus keine Credits und macht keine Server-Runde. Wer
//  gerade jemanden vor sich stehen hat, wartet nicht auf ein Rechenzentrum.
//
//  Ausgelöst wird von selbst: sobald eine Sekunde lang alles stimmt, fällt ein
//  Burst. Ein Auslöseknopf würde genau die Hand bewegen, die gerade ruhig
//  geworden ist.
//

import AVFoundation
import SwiftData
import SwiftUI
import UIKit
import Vision

// MARK: - Die Regeln

/// Was der App an der aktuellen Einstellung nicht passt.
///
/// Eigener Typ und bewusst ohne UI: das sind Geometrie-Regeln, und Geometrie
/// prüft man in einem Test, nicht am Küchentisch mit dem Telefon in der Hand.
enum DirectorHint: String, Equatable, CaseIterable {
    case comeCloser
    case phoneLower
    case tiltDown
    case holdStraight

    var text: String {
        switch self {
        case .comeCloser:   return "Two steps closer"
        case .phoneLower:   return "Hold the phone lower"
        case .tiltDown:     return "Tilt further down"
        case .holdStraight: return "Hold it level"
        }
    }
}

/// Alle Maße normalisiert (0…1) mit Ursprung OBEN LINKS.
struct DirectorFrame: Equatable {
    /// Umriss der erkannten Person. `nil` = niemand im Bild.
    var person: CGRect?
    /// Höhe der Brustlinie. `nil`, wenn die Pose nicht sicher genug erkannt wurde.
    var chestY: CGFloat?
    /// Neigung des Horizonts in Grad. `nil`, wenn keiner gefunden wurde.
    var horizonDegrees: Double?
}

enum DirectorCoach {

    /// Ab hier gilt die Person als groß genug im Bild.
    static let minimumPersonHeight: CGFloat = 0.55
    /// Die Brust darf nicht deutlich unter der Bildmitte liegen — dann schaut
    /// die Kamera von oben herab, und das ist die Perspektive, die jeden
    /// kleiner und breiter macht.
    static let maximumChestY: CGFloat = 0.58
    static let maximumHorizonDegrees: Double = 4

    /// Genau EIN Hinweis. Zwei gleichzeitig liest niemand, und drei bewegen
    /// die Hand in drei Richtungen.
    ///
    /// Die Reihenfolge ist die, in der man es auch selbst korrigieren würde:
    /// erst überhaupt nah genug hin, dann die Höhe, dann der Anschnitt, und
    /// die schiefe Kante zuletzt — sie stört am wenigsten.
    static func hint(for frame: DirectorFrame) -> DirectorHint? {
        guard let person = frame.person else { return .comeCloser }

        if person.height < minimumPersonHeight { return .comeCloser }
        if let chestY = frame.chestY, chestY > maximumChestY { return .phoneLower }
        if person.maxY >= 0.99 { return .tiltDown }
        if let degrees = frame.horizonDegrees, abs(degrees) > maximumHorizonDegrees {
            return .holdStraight
        }
        return nil
    }
}

// MARK: - Ansicht

struct DirectorCameraView: View {

    let onCancel: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var camera = PoseCameraModel()
    @State private var frame = DirectorFrame()
    @State private var isAnalyzing = false

    /// Der angezeigte Hinweis wechselt frühestens alle 1,2 s. Ohne diese
    /// Sperre flackert der Text bei jeder kleinen Bewegung, und man liest
    /// keinen einzigen davon zu Ende.
    @State private var shownHint: DirectorHint?
    @State private var lastHintChange = Date.distantPast

    /// Seit wann stimmt alles? Erst nach 0,6 s durchgehend fällt der Burst.
    @State private var goodSince: Date?
    @State private var isBursting = false
    @State private var shots: [Data] = []
    @State private var chosen: Set<Int> = []
    @State private var toast: String?

    private let hintHold: TimeInterval = 1.2
    private let steadyDuration: TimeInterval = 0.6

    private var isReviewing: Bool { !shots.isEmpty }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if isReviewing {
                    reviewGrid
                } else {
                    liveCamera
                }
            }
        }
        .onAppear { Task { await start() } }
        .onDisappear {
            camera.stopFrameStream()
            camera.stop()
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Theme.surface, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
                    .padding(.top, 58)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toast)
    }

    private var header: some View {
        HStack {
            Button { onCancel() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 38, height: 38)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 1) {
                Text("DIRECTOR")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .kerning(1.1)
                Text(isReviewing ? "Pick your shots" : "Real photos, no AI")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Color.clear.frame(width: 38, height: 38)
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, Theme.screenPadding)
        .padding(.vertical, 10)
    }

    // MARK: - Live

    private var liveCamera: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                ZStack {
                    Color.black
                        .frame(width: geo.size.width, height: geo.size.height)

                    if camera.isAvailable {
                        CameraPreviewLayer(camera: camera, cornerRadius: 12)
                            .frame(width: geo.size.width, height: geo.size.height)
                    } else {
                        Theme.surfaceHigh
                        VStack(spacing: 8) {
                            Image(systemName: camera.permissionDenied ? "lock.fill" : "camera.fill")
                                .font(.system(size: 25, weight: .light))
                            Text(camera.permissionDenied ? "Camera access is off" : "No camera available")
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(Theme.textSecondary)
                    }

                    if isBursting {
                        Color.white.opacity(0.18)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .compositingGroup()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .bottom) { hintPlate }
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .padding(.horizontal, Theme.screenPadding)

            Text("Hand the phone to someone. It shoots by itself once everything lines up.")
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Spacer(minLength: 8)
        }
    }

    /// Ein Satz, groß, mittig unten. Stimmt alles, steht dort das grüne Häkchen
    /// — sonst wüsste niemand, ob die App gerade nur nichts zu meckern hat oder
    /// gar nicht mehr hinschaut.
    @ViewBuilder
    private var hintPlate: some View {
        Group {
            if let shownHint {
                Text(shownHint.text)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Label("Hold it there", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.go)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.black.opacity(0.45), in: Capsule())
        .padding(.bottom, 22)
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: shownHint)
    }

    // MARK: - Auswahl

    private var reviewGrid: some View {
        VStack(spacing: 12) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Array(shots.enumerated()), id: \.offset) { index, data in
                        if let image = UIImage(data: data) {
                            Button {
                                if chosen.contains(index) { chosen.remove(index) } else { chosen.insert(index) }
                            } label: {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 190)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                                            .strokeBorder(chosen.contains(index) ? Theme.accent : Theme.stroke,
                                                          lineWidth: chosen.contains(index) ? 3 : 1)
                                    )
                                    .overlay(alignment: .topTrailing) {
                                        if chosen.contains(index) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 21))
                                                .foregroundStyle(.white, Theme.accent)
                                                .padding(8)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
            }

            HStack(spacing: 10) {
                Button {
                    shots = []
                    chosen = []
                    goodSince = nil
                    Task { await start() }
                } label: {
                    Text("Again")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .glassEffect(.regular.interactive(), in: Capsule())
                }
                .buttonStyle(.plain)

                Button { saveChosen() } label: {
                    Text("Save")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .glassEffect(.regular.tint(Theme.accent).interactive(), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(chosen.isEmpty)
                .opacity(chosen.isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Kamera und Analyse

    private func start() async {
        await camera.start()
        // Die Nutzerin steht VOR der Linse, jemand anderes hält das Telefon.
        if camera.isFront { await camera.flip() }
        camera.startFrameStream(minimumInterval: 0.125) { buffer, orientation in
            Task { @MainActor in analyse(buffer, orientation: orientation) }
        }
    }

    private func analyse(_ buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        guard !isAnalyzing, !isBursting, shots.isEmpty else { return }
        isAnalyzing = true
        Task {
            let measured = await DirectorVision.measure(pixelBuffer: buffer, orientation: orientation)
            await MainActor.run {
                isAnalyzing = false
                guard !isBursting, shots.isEmpty else { return }
                frame = measured
                updateHint()
            }
        }
    }

    private func updateHint() {
        let current = DirectorCoach.hint(for: frame)

        if current != shownHint, Date().timeIntervalSince(lastHintChange) >= hintHold {
            shownHint = current
            lastHintChange = Date()
        }

        // Für den Auslöser zählt die MESSUNG, nicht der angezeigte Text: der
        // hängt absichtlich bis zu 1,2 s hinterher.
        guard current == nil else {
            goodSince = nil
            return
        }
        let since = goodSince ?? Date()
        if goodSince == nil { goodSince = since }
        if Date().timeIntervalSince(since) >= steadyDuration {
            Task { await burst() }
        }
    }

    /// Sechs Aufnahmen über 1,5 s. Nicht schneller: sonst zeigen alle sechs
    /// denselben Moment und die Auswahl danach wäre sinnlos.
    private func burst() async {
        guard !isBursting else { return }
        isBursting = true
        camera.stopFrameStream()
        defer { isBursting = false }

        var captured: [Data] = []
        for index in 0..<6 {
            if index > 0 { try? await Task.sleep(nanoseconds: 250_000_000) }
            if let data = await camera.capture() { captured.append(data) }
        }

        guard !captured.isEmpty else {
            flash("That didn't work — give it another go.")
            goodSince = nil
            camera.startFrameStream(minimumInterval: 0.125) { buffer, orientation in
                Task { @MainActor in analyse(buffer, orientation: orientation) }
            }
            return
        }
        shots = captured
        chosen = []
        camera.stop()
    }

    /// Gleiche Ablage wie überall sonst: Datei in Documents, Thumbnail fürs
    /// Raster, SwiftData-Eintrag. Kein Credit, keine Server-Runde.
    private func saveChosen() {
        let selected = chosen.sorted().compactMap { shots.indices.contains($0) ? shots[$0] : nil }
        guard !selected.isEmpty else { return }

        for data in selected {
            let project = VideoProject(
                prompt: "Director", templateTitle: "Director",
                ratio: .portrait, resolution: .p720, duration: 0,
                generateAudio: false, useFastModel: true,
                referenceImagesData: [],
                isImageOutput: true, useKie: false,
                creditCost: 0, imageQuality: "original"
            )
            let filename = "\(project.id.uuidString).jpg"
            let destination = URL.documentsDirectory.appending(path: filename)
            guard (try? data.write(to: destination)) != nil else { continue }
            project.localVideoFilename = filename
            if let image = UIImage(data: data),
               let thumbnail = image.preparingThumbnail(
                of: CGSize(width: 600, height: 600 * image.size.height / max(image.size.width, 1))
               ) {
                project.thumbnailData = thumbnail.jpegData(compressionQuality: 0.8)
            } else {
                project.thumbnailData = data
            }
            project.status = .succeeded
            modelContext.insert(project)
        }
        try? modelContext.save()
        onCancel()
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { withAnimation { if toast == text { toast = nil } } }
        }
    }
}

// MARK: - Messung

/// Liest aus einem Kamerabild die drei Zahlen, die `DirectorCoach` braucht.
enum DirectorVision {

    static func measure(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) async -> DirectorFrame {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: analyse(pixelBuffer, orientation: orientation))
            }
        }
    }

    private static func analyse(
        _ pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> DirectorFrame {
        let humans = VNDetectHumanRectanglesRequest()
        let pose = VNDetectHumanBodyPoseRequest()
        let horizon = VNDetectHorizonRequest()

        // Einzeln, aus demselben Grund wie im PlacementSuggester: ein
        // fehlgeschlagenes Modell darf nicht die übrigen Messungen kosten.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        for request in [humans, pose, horizon] as [VNRequest] {
            try? handler.perform([request])
        }

        var result = DirectorFrame()

        if let observation = (humans.results ?? []).max(by: {
            $0.boundingBox.height < $1.boundingBox.height
        }) {
            result.person = flip(observation.boundingBox)
        }

        if let body = pose.results?.first {
            result.chestY = chestHeight(body)
        }

        if let line = horizon.results?.first {
            result.horizonDegrees = Double(line.angle) * 180 / .pi
        }

        return result
    }

    /// Mitte zwischen Schulter- und Hüftlinie. Beide Seiten müssen sicher
    /// erkannt sein — eine halb geratene Brusthöhe ist schlechter als keine,
    /// weil sie einen falschen Hinweis auslöst.
    private static func chestHeight(_ body: VNHumanBodyPoseObservation) -> CGFloat? {
        let joints: [VNHumanBodyPoseObservation.JointName] = [
            .leftShoulder, .rightShoulder, .leftHip, .rightHip,
        ]
        var values: [CGFloat] = []
        for joint in joints {
            guard let point = try? body.recognizedPoint(joint), point.confidence > 0.3 else {
                return nil
            }
            values.append(1 - point.location.y)   // Vision zählt von unten
        }
        let shoulders = (values[0] + values[1]) / 2
        let hips = (values[2] + values[3]) / 2
        return (shoulders + hips) / 2
    }

    private static func flip(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
    }
}
