//
//  DirectorWorkspace.swift
//  Clavic
//
//  Was nach dem Absenden zu sehen ist — und was ausdrücklich NICHT zu sehen ist.
//
//  KEIN VERLAUF, KEINE BLASEN.
//  Hier stand ein Chat: Nachrichtenblasen, „Thinking…", ein Scrollback aus
//  vorherigen Zügen. Das ist das Gegenteil dessen, was der Director sein soll.
//  Ein Creative Director schickt dir keine Nachrichten — er sieht sich dein
//  Bild an und legt dir etwas hin.
//
//  Deshalb ist das hier eine WERKBANK, kein Gespräch: EIN Bild, EIN Befund,
//  die Auswahl darunter. Immer derselbe Aufbau, egal in welchem Zug. Nichts
//  scrollt weg, nichts staut sich an.
//
//  BEIM LESEN: DAS FOTO SELBST IST DIE LADEANZEIGE.
//  `BlurLoadingCard` — geblurtes Ausgangsbild, darüber die Clavic-Animation,
//  dieselbe wie im Chat-Tab seit jeher. Kein scharfes Bild mit einem Schleier
//  darüber: es ist gerade nicht deins, es ist bei ihm. Und die Figur steht
//  DARUNTER und schaut es sich an, statt oben unbeteiligt herumzustehen.
//
//  DIE WARTEZEIT ERZÄHLT.
//  Statt eines Kreisels und des Wortes „Thinking…" nennt er der Reihe nach,
//  was er gerade tut — Licht, Aufbau, Störstellen. Diese Stufen sind nicht
//  erfunden: es sind genau die Felder, die Stufe 1 tatsächlich ausliest.
//  Gemessen dauert eine Bildlesung rund 15 Sekunden; Ladebildschirme in
//  erfolgreichen Apps halten Leute fast neun, wenn sie erzählen, was passiert.
//

import SwiftUI

/// Was er der Reihe nach tut. Entspricht den Feldern der Bildlesung.
///
/// Steht ausserhalb der Struktur: `DirectorWorkspace` ist generisch (es nimmt
/// die Maskottchen-Ansicht entgegen), und generische Typen dürfen in Swift
/// keine statischen gespeicherten Eigenschaften haben.
private let arbeitsStufen = [
    "Where the light falls…",
    "What the frame cuts…",
    "What doesn't belong…",
    "Ideas coming together…",
]

struct DirectorWorkspace<Mascot: View>: View {
    /// Die Figur. Sie steht beim Lesen UNTER der Karte und schaut sie an,
    /// sonst darüber — deshalb reicht der Aufrufer sie herein, statt sie
    /// selbst zu platzieren.
    @ViewBuilder let mascot: () -> Mascot
    /// Das Bild, um das es geht — Ergebnis, sonst das Original.
    let photo: Data?
    /// Ein zweites Bild zum Vergleichen (Vorher), falls es ein Ergebnis gibt.
    let before: Data?
    let isWorking: Bool
    /// Zwischenstand aus dem Renderpfad, etwa „Fixing: plastic skin".
    let note: String?
    /// Seine eine Zeile.
    let verdict: String?
    let picks: [DirectorAPI.Option]
    let trends: [DirectorAPI.Option]
    let landed: Bool
    let throwToken: Int
    var onPick: (DirectorAPI.Option) -> Void = { _ in }
    var onOwnIdea: () -> Void = {}
    var onCompare: () -> Void = {}

    @State private var stufe = 0
    /// Laeuft, solange gelesen wird — treibt den Schimmer in der Zeile.
    @State private var schimmer = false
    @State private var zeigeVorher = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion


    var body: some View {
        VStack(spacing: 14) {
            if isWorking {
                ladeKarte
                mascot()
                arbeitsZeile
                // Darunter blieb der halbe Bildschirm leer. Zwei Platzhalter in
                // GENAU der Form der spaeteren Vorschlaege sagen ohne ein Wort,
                // was gleich passiert — und der Sprung vom Lesen zum Ergebnis
                // ist kleiner, weil die Form schon dasteht.
                platzhalterVorschlaege
            } else {
                mascot()
                bildZentriert
                if let verdict, !verdict.isEmpty { befund(verdict) }
            }

            if !picks.isEmpty {
                DirectorPicks(
                    picks: picks, trends: trends,
                    landed: landed, throwToken: throwToken,
                    sourcePhoto: before ?? photo,
                    onPick: onPick, onOwnIdea: onOwnIdea
                )
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                schimmer = true
            }
        }
        .task(id: isWorking) {
            guard isWorking, !reduceMotion else { return }
            stufe = 0
            // Vier Stufen à 4 s decken die gemessenen ~15 s ab. Läuft es
            // länger, bleibt die letzte stehen — sie verspricht nichts, was
            // sie nicht halten kann.
            while !Task.isCancelled && stufe < arbeitsStufen.count - 1 {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.4)) { stufe += 1 }
            }
        }
    }

    // MARK: - Beim Lesen

    /// Die Clavic-Ladeanimation im geblurten Foto — dieselbe Karte wie im
    /// Chat-Tab. Sie sagt ohne Worte: das Bild ist gerade in Arbeit.
    @ViewBuilder
    private var ladeKarte: some View {
        if let daten = photo, let ui = UIImage(data: daten) {
            BlurLoadingCard(ui: ui)
                .frame(maxHeight: 250)
        }
    }

    // MARK: - Was gleich kommt

    /// Zwei leere Vorschlaege in genau der Form der spaeteren echten.
    ///
    /// Vorher endete der Bildschirm nach der Textzeile und darunter lag die
    /// halbe Hoehe leer — das liest sich wie ein Fehler, nicht wie Arbeit.
    /// Die Platzhalter fuellen die Flaeche, sagen ohne ein Wort was folgt, und
    /// der Wechsel zum Ergebnis wird kleiner, weil die Form schon steht.
    private var platzhalterVorschlaege: some View {
        VStack(spacing: 10) {
            ForEach(0..<2, id: \.self) { i in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.textPrimary.opacity(0.07))
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 7) {
                        Capsule().fill(Theme.textPrimary.opacity(0.07))
                            .frame(width: i == 0 ? 150 : 118, height: 11)
                        Capsule().fill(Theme.textPrimary.opacity(0.05))
                            .frame(width: i == 0 ? 96 : 132, height: 9)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Theme.surface.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    if !reduceMotion {
                        // Dasselbe wandernde Licht wie in der Textzeile — ein
                        // Motiv, nicht zwei verschiedene Ladeanzeigen.
                        LinearGradient(colors: [.clear, Theme.textPrimary.opacity(0.06), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: 140)
                            .offset(x: schimmer ? 260 : -220)
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.top, 2)
        .transition(.opacity)
    }

    // MARK: - Das Bild

    private var bildKarte: some View {
        // Mittig. Ohne das saß die Karte am linken Rand, weil ein `scaledToFit`
        // im ZStack nur so breit wird wie es muss.
        ZStack(alignment: .center) {
            if let daten = anzuzeigen, let ui = UIImage(data: daten) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 186)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Theme.textPrimary.opacity(0.09), lineWidth: 1)
                    )
                    .padding(9)
                    .padding(.bottom, 6)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.clear)
                            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .shadow(color: Theme.textPrimary.opacity(0.14), radius: 14, x: 0, y: 8)
                    // Während er arbeitet, liegt das Bild ruhig unter einem
                    // Schleier — es ist gerade nicht deins, es ist bei ihm.
                    .overlay {
                        if isWorking {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Theme.background.opacity(0.32))
                                .padding(9)
                                .padding(.bottom, 6)
                        }
                    }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if before != nil && !isWorking {
                vergleichKnopf
            }
        }
    }

    /// `.frame(maxWidth: .infinity)` allein hat die Karte nicht zentriert —
    /// sie blieb an der linken Kante. Zwei Spacer sind eindeutig.
    private var bildZentriert: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            bildKarte
            Spacer(minLength: 0)
        }
    }

    private var anzuzeigen: Data? {
        if let before, zeigeVorher { return before }
        return photo
    }

    /// Vorher/Nachher am Bild selbst, kein eigener Reiter.
    private var vergleichKnopf: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { zeigeVorher.toggle() }
            onCompare()
        } label: {
            Text(zeigeVorher ? "Before" : "After")
                .font(.system(size: 11.5, weight: .black, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Theme.textPrimary.opacity(0.62), in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(18)
    }

    // MARK: - Arbeit und Befund

    private var arbeitsZeile: some View {
        HStack(spacing: 9) {
            // Kein Kreisel mehr. Ein Kreisel sagt „das System arbeitet"; hier
            // soll aber jemand mitdenken. Stattdessen wandert ein Licht durch
            // die Zeile selbst — dieselbe Bildsprache wie die Lupe darueber,
            // und es nimmt keinen eigenen Platz weg.
            let zeile = note ?? arbeitsStufen[min(stufe, arbeitsStufen.count - 1)]
            Text(zeile)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .overlay {
                    if !reduceMotion {
                        LinearGradient(
                            colors: [.clear, Theme.textPrimary.opacity(0.7), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: 80)
                        .offset(x: schimmer ? 210 : -150)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                        .mask { Text(zeile).font(.system(size: 17, weight: .semibold, design: .rounded)) }
                    }
                }
                .contentTransition(.opacity)
                .id(zeile)
                .transition(.opacity)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    /// Sein Urteil. Kein Sprechblasen-Schwanz, kein Avatar — eine Zeile, die
    /// dasteht wie eine Notiz am Rand eines Abzugs.
    private func befund(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Rectangle()
                .fill(Theme.accent)
                .frame(width: 3)
                .clipShape(Capsule())
            Text(text)
                // Größer und ruhiger. Mit 15 pt las es sich wie eine Fußnote;
                // es ist aber das Einzige, was er sagt.
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .lineSpacing(2)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }
}
