//
//  OnboardingFlowView.swift
//  Clavic
//
//  Bildgefuehrtes Onboarding nach dem Muster der umsatzstaerksten Apps der
//  Kategorie (Retake 22 Screens, Glam 16, Photoleap 16, Facetune 9). Das alte
//  `OnboardingView` hatte 3 Schritte mit langen Absaetzen und eine Marquee mit
//  Dutzenden Miniaturen — beides genau das Gegenteil dessen, was dort
//  funktioniert.
//
//  Bildsprache: WayShots Aufbau (grosses Motiv, eine Aussage, ein Button),
//  aber HELL statt dunkel — weisser Grund mit blauem Verlauf, Milchglas-Flaechen
//  und Bewegung beim Seitenwechsel.
//  Uebernommen von Retake: Problem- und Loesungs-Screen zeigen dasselbe Motiv,
//  und die Fragen kommen mit Bildvorschau statt als Icon-Chips.
//
//  Regeln, die aus der Recherche kommen und hier durchgaengig gelten:
//   • EIN Gedanke pro Screen: eine Schlagzeile, eine Zeile darunter, ein Bild,
//     ein Button. Nichts sonst.
//   • Schlagzeilen sind kurz (3–5 Woerter). Der Beweis ist das Bild, nicht der
//     Text.
//   • Problem-Screen und Loesungs-Screen zeigen DASSELBE Motiv. Erst das
//     Problem, dann derselbe Moment repariert — das ist der staerkste Beleg.
//   • Fragen kommen mit Bildvorschau statt als Icon-Chips, und mit hoechstens
//     vier Optionen pro Screen statt zehn auf einmal.
//

import SwiftUI

// MARK: - Modell

/// Eine Auswahlmoeglichkeit auf einem Frage-Screen. `ziel` bleibt kompatibel
/// zur bestehenden Speicherung in `OnboardingGoals.swift`.
struct ObOption: Identifiable {
    let ziel: OnboardingZiel
    /// Kleine, gedaempfte Zeile oben: der Nutzen.
    let nutzen: String
    /// Grosse, fette Zeile darunter: der Name.
    let label: String
    let bild: String
    var id: String { ziel.rawValue }
}

/// Eine Karte im Startkarussell.
struct ObKarte: Identifiable {
    let bild: String
    let titel: String
    let zeile: String
    var id: String { bild }
}

/// Die Screen-Typen des Flows.
enum ObPage: Identifiable {
    /// Einstieg: ein grosser Vorher/Nachher-Beleg statt einer Miniaturwand.
    case hero(title: String, sub: String, example: OnboardingExample)
    /// Problem oder Beweis: eine Aussage, ein Motiv.
    case story(title: String, sub: String, example: OnboardingExample)
    /// Frage mit Bildvorschauen, hoechstens vier Optionen.
    case question(title: String, sub: String, options: [ObOption])
    /// Ergebnis-Raster als sozialer Beleg.
    case gallery(title: String, sub: String, bilder: [String])
    /// Bewertung und Zitat kurz vor der Paywall.
    case proof(title: String, sub: String)
    /// Das Maskottchen spricht. Muster aus 33 Maskottchen-Onboardings bei
    /// appllama — ELSA, Lingvano, Liftoff, ZOE und Yazio machen alle dasselbe:
    /// Sprechblase oben, Figur darunter, Fortschritt oben. Die Figur ist der
    /// Erzaehler, nicht Dekoration.
    case mascot(kopf: String, satz: String, video: String, bilder: [String])
    /// Kartenkarussell wie bei Glam AI: grosse Hochkantkarten, die Nachbarn
    /// ragen herein, Titel und Zeile unten auf der Karte.
    case karussell(kopf: String, satz: String, karten: [ObKarte])
    /// Vorschau der echten App: Chat-Blasen wie im Director, damit man sieht,
    /// wie man Clavic bedient — nicht nur, was rauskommt.
    case chat(title: String, sub: String, frage: String, antwort: String, bild: String)
    /// „Preparing…" mit abhakender Liste. Kein Spinner: Glam AI, Facetune und
    /// Retake haben alle diesen Screen, und alle zeigen benannte Schritte, die
    /// nacheinander abhaken. Ein Spinner sagt „warte", eine Liste sagt „hier
    /// passiert Arbeit fuer dich".
    case preparing(title: String, schritte: [String])
    /// Zeigt, wie der Director arbeitet: das Maskottchen praesentiert, daneben
    /// laufen die Ideen ein, die er vorschlaegt.
    case director(title: String, sub: String, video: String, bild: String, ideen: [String])

    var id: String {
        switch self {
        case let .hero(t, _, _):     return "hero-\(t)"
        case let .story(t, _, _):    return "story-\(t)"
        case let .question(t, _, _): return "q-\(t)"
        case let .gallery(t, _, _):  return "g-\(t)"
        case let .proof(t, _):       return "p-\(t)"
        case let .mascot(t, _, _, _): return "m-\(t)"
        case let .karussell(t, _, _): return "kar-\(t)"
        case let .chat(t, _, _, _, _): return "c-\(t)"
        case let .preparing(t, _):   return "prep-\(t)"
        case let .director(t, _, _, _, _): return "dir-\(t)"
        }
    }

    /// Frage-Screens brauchen eine Auswahl, bevor es weitergeht.
    var istFrage: Bool { if case .question = self { return true }; return false }
}

enum ObFlow {
    /// Sechs Screens. Vorher waren es vier vom selben Bautyp (Text + Bild),
    /// was sich beim Durchklicken wie dieselbe Seite zweimal anfuehlte. Jetzt
    /// wechseln sich vier Bauarten ab: Maskottchen spricht, Beweis, Bedienung,
    /// Frage.
    static let pages: [ObPage] = [
        .karussell(
            kopf: "Hi, I'm Clavic 👋",
            satz: "Send a photo, say what to change.",
            karten: [
                ObKarte(bild: "trend_goldenhour_after", titel: "Golden hour",
                        zeile: "Warm light, any time of day"),
                ObKarte(bild: "trend_y2kdigicam_after", titel: "Y2K digicam",
                        zeile: "That grainy 2000s feel"),
                ObKarte(bild: "trend_bluehour_after",  titel: "Blue hour",
                        zeile: "Deep evening tones")
            ]),
        .director(
            title: "Meet the Director",
            sub: "It reads your photo and suggests what would work.",
            video: "mascot_director",
            bild: "trend_bluehour_before",
            ideen: ["Warmer golden light", "Y2K digicam grain", "Cleaner background"]
        ),
        .chat(
            title: "Or just say it",
            sub: "No sliders, no filters, no menus.",
            frage: "make it golden hour",
            antwort: "On it — warmer light, same you.",
            bild: "trend_goldenhour_after"
        ),
        .story(
            title: "Club light, fixed",
            sub: "Red and grainy in, mood out.",
            example: .slider(before: "trend_redlight_before", after: "trend_redlight_after")
        ),
        .question(
            title: "Which look is yours?",
            sub: "Pick what you'd post. More than one is fine.",
            options: [
                ObOption(ziel: .licht, nutzen: "Warm light, any time of day",
                         label: "Golden hour",   bild: "trend_goldenhour_after"),
                ObOption(ziel: .trend, nutzen: "That grainy 2000s camera feel",
                         label: "Y2K digicam",   bild: "trend_y2kdigicam_after"),
                ObOption(ziel: .hintergrund, nutzen: "Deep blue evening tones",
                         label: "Blue hour",     bild: "trend_bluehour_after"),
                ObOption(ziel: .paar, nutzen: "Hard flash, night-out look",
                         label: "Flash & night", bild: "trend_g7xflash_after")
            ]
        ),
        .preparing(
            title: "Setting up Clavic…",
            schritte: ["Reading your picks",
                       "Matching this week's trends",
                       "Tuning colour for your skin tone",
                       "Getting your looks ready"]
        ),
        .mascot(kopf: "Ready when you are",
                satz: "Pick one photo — I'll take it from there.",
                video: "mascot_photo",
                bilder: ["trend_redsunset_after", "trend_y2kdigicam_after", "trend_redlight_after"])
    ]

}

// MARK: - Sprechblase

/// Abgerundete Blase mit Zipfel nach unten links — die Form, die in allen
/// untersuchten Maskottchen-Onboardings vorkommt.
private struct BlasenForm: Shape {
    var radius: CGFloat = 26
    var zipfel: CGSize = CGSize(width: 26, height: 18)

    func path(in rect: CGRect) -> Path {
        let koerper = CGRect(x: rect.minX, y: rect.minY,
                             width: rect.width, height: rect.height - zipfel.height)
        var p = Path(roundedRect: koerper, cornerRadius: radius, style: .continuous)
        let x = rect.minX + rect.width * 0.22
        p.move(to: CGPoint(x: x, y: koerper.maxY - 2))
        p.addLine(to: CGPoint(x: x - zipfel.width * 0.25, y: rect.maxY))
        p.addLine(to: CGPoint(x: x + zipfel.width, y: koerper.maxY - 2))
        p.closeSubpath()
        return p
    }
}

// MARK: - Wellen-Wechsel

/// Wellenfoermige Kante, die von links nach rechts wandert. `fortschritt`
/// ist animierbar, damit SwiftUI die Zwischenschritte selbst rechnet.
private struct WelleShape: Shape {
    var fortschritt: CGFloat
    /// Ausschlag der Welle in Punkten. Bewusst klein — die Kante soll man
    /// kaum als Form wahrnehmen, nur als weiches Wandern.
    var ausschlag: CGFloat = 9
    /// Wie viele Wellenbaeuche ueber die Bildhoehe laufen.
    var baeuche: CGFloat = 1.5

    var animatableData: CGFloat {
        get { fortschritt }
        set { fortschritt = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        // Etwas ueber die Kanten hinaus, damit am Anfang und Ende nichts
        // stehen bleibt.
        let basis = -ausschlag + (rect.width + ausschlag * 2) * fortschritt
        let schritte = 80

        p.move(to: CGPoint(x: 0, y: rect.minY))
        for i in 0...schritte {
            let t = CGFloat(i) / CGFloat(schritte)
            let y = rect.height * t
            let x = basis + sin(t * .pi * 2 * baeuche + fortschritt * .pi * 2) * ausschlag
            if i == 0 { p.addLine(to: CGPoint(x: x, y: y)) }
            else       { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        p.addLine(to: CGPoint(x: 0, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Vorher/Nachher ohne Trennstrich und ohne Griff: das Nachher-Bild wird von
/// einer wandernden Welle freigelegt. Laeuft von allein und deutlich schneller
/// als der alte Slider.
struct WelleWechselView: View {
    let vorher: String
    let nachher: String
    @State private var fortschritt: CGFloat = 0

    var body: some View {
        ZStack {
            Image(vorher)
                .resizable()
                .scaledToFill()
            Image(nachher)
                .resizable()
                .scaledToFill()
                .mask(WelleShape(fortschritt: fortschritt))
        }
        .task {
            // Ungleiche Zeiten statt Hin und Her im Gleichtakt: das fertige
            // Bild steht lange, das Original nur kurz. Ein symmetrisches
            // autoreverse haette beide gleich lang gezeigt — und das Vorher
            // ist nicht das, was verkauft.
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.65)) { fortschritt = 1 }
                try? await Task.sleep(nanoseconds: 3_100_000_000)   // 0,65 s Lauf + 2,45 s Standzeit
                withAnimation(.easeInOut(duration: 0.5)) { fortschritt = 0 }
                try? await Task.sleep(nanoseconds: 900_000_000)     // 0,5 s Lauf + 0,4 s Standzeit
            }
        }
    }
}

// MARK: - Hauptansicht

struct OnboardingFlowView: View {
    @Binding var isPresented: Bool

    @State private var index = 0
    @State private var auswahl: Set<OnboardingZiel> = []
    /// Steuert die Einblend-Animation bei jedem Seitenwechsel.
    @State private var eingeblendet = false
    /// Langsame Drift der Farbflecken — der Hintergrund steht nie still.
    @State private var drift = false
    /// Langsamer Zoom auf dem Motiv (Ken Burns).
    @State private var kenBurns = false
    /// Wie viele Zeilen der Vorbereitungsliste schon abgehakt sind.
    @State private var erledigt = 0
    /// Wie weit der Chat-Ablauf fortgeschritten ist (0 = leer).
    @State private var chatPhase = 0
    /// Wie viele Karten schon aufgepoppt sind (Director und Auswahl).
    @State private var popp = 0
    /// Aktuelle Karte im Startkarussell.
    @State private var kartenIndex = 0

    private var pages: [ObPage] { ObFlow.pages }
    private var page: ObPage { pages[min(index, pages.count - 1)] }

    private var istMaskottchen: Bool {
        if case .mascot = page { return true }
        if case .karussell = page { return true }
        return false
    }

    private var istVorbereitung: Bool {
        if case .preparing = page { return true }
        return false
    }

    private var weiterMoeglich: Bool {
        guard case let .question(_, _, options) = page else { return true }
        return options.contains { auswahl.contains($0.ziel) }
    }

    private let blau = Color(red: 0.157, green: 0.502, blue: 0.941)
    private let blauHell = Color(red: 0.616, green: 0.808, blue: 1.0)

    var body: some View {
        ZStack {
            hintergrund

            VStack(spacing: 0) {
                fortschritt
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                // Auf Maskottchen-Screens traegt die Sprechblase den Text,
                // ein zweiter Titel darueber waere doppelt.
                if !istMaskottchen {
                    kopf
                        .padding(.horizontal, 28)
                        .padding(.top, 26)
                }

                inhalt
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    // Zentriert statt oben verankert: sonst sammelt sich die
                    // ganze Restflaeche als tote Luecke ueber dem Button.
                    .frame(maxHeight: .infinity)

                if !istVorbereitung {
                    cta
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                }
            }
        }
        .onAppear {
            einblenden()
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true }
            withAnimation(.easeInOut(duration: 11).repeatForever(autoreverses: true)) { kenBurns = true }
        }
        .onChange(of: index) { _, _ in einblenden() }
    }

    /// Weiss mit blauem Verlauf plus zwei weich gezeichnete Farbflecken. Die
    /// Flecken sind der Grund, warum die Milchglas-Flaechen ueberhaupt etwas
    /// zeigen — ohne Farbe dahinter ist Blur nur graues Rauschen.
    private var hintergrund: some View {
        ZStack {
            Color.white
            LinearGradient(colors: [blauHell.opacity(0.55), .white, blauHell.opacity(0.35)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(blau.opacity(0.30))
                .frame(width: 340, height: 340)
                .blur(radius: 90)
                .offset(x: drift ? -80 : -150, y: drift ? -270 : -200)
            Circle()
                .fill(blauHell.opacity(0.45))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: drift ? 175 : 110, y: drift ? 260 : 330)
        }
        .ignoresSafeArea()
    }

    private var fortschritt: some View {
        HStack(spacing: 4) {
            ForEach(0..<pages.count, id: \.self) { i in
                Capsule()
                    .fill(i <= index ? blau : blau.opacity(0.18))
                    .frame(height: 4)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: index)
    }

    /// Ueberschrift immer OBEN. Beim ersten Versuch lag sie unten im Bild —
    /// auf den Frage-Screens stand die Frage dadurch unter den Antworten.
    private var kopf: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Gestaffelt: erst die Schlagzeile, dann die Zeile darunter, dann
            // das Bild. Alles gleichzeitig einzublenden wirkt wie ein Ruck.
            Text(titel)
                // Groesser und enger gesetzt. 32 pt wirkte wie eine
                // Abschnitts-Ueberschrift, nicht wie der Screen-Titel.
                .font(.system(size: 40, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(eingeblendet ? 1 : 0)
                .offset(y: eingeblendet ? 0 : 18)
                .animation(.spring(response: 0.55, dampingFraction: 0.82), value: eingeblendet)
            Text(unterzeile)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(eingeblendet ? 1 : 0)
                .offset(y: eingeblendet ? 0 : 14)
                .animation(.spring(response: 0.55, dampingFraction: 0.82).delay(0.07),
                           value: eingeblendet)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titel: String {
        switch page {
        case let .hero(t, _, _), let .story(t, _, _), let .question(t, _, _),
             let .gallery(t, _, _): return t
        case let .proof(t, _): return t
        case .mascot: return ""
        case .karussell: return ""
        case let .chat(t, _, _, _, _): return t
        case .preparing: return ""
        case let .director(t, _, _, _, _): return t
        }
    }

    private var unterzeile: String {
        switch page {
        case let .hero(_, s, _), let .story(_, s, _), let .question(_, s, _),
             let .gallery(_, s, _): return s
        case let .proof(_, s): return s
        case .mascot: return ""
        case .karussell: return ""
        case let .chat(_, s, _, _, _): return s
        case .preparing: return ""
        case let .director(_, sb, _, _, _): return sb
        }
    }

    @ViewBuilder
    private var inhalt: some View {
        Group {
            switch page {
            case let .hero(_, _, example), let .story(_, _, example):
                Group {
                    // Vorher/Nachher laeuft ueber die Welle, alles andere
                    // weiter ueber die bestehende Karte (Video, Einzelbild).
                    if case let .slider(vorher, nachher) = example {
                        WelleWechselView(vorher: vorher, nachher: nachher)
                    } else {
                        ExampleCardView(example: example, corner: 30, animated: true)
                    }
                }
                .scaleEffect(kenBurns ? 1.06 : 1.0)     // langsamer Zoom
                .frame(maxWidth: .infinity)
                .frame(height: UIScreen.main.bounds.height * 0.55)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: blau.opacity(0.22), radius: 26, y: 14)

            case let .question(_, _, options):
                optionenRaster(options)

            case let .gallery(_, _, bilder):
                raster(bilder)

            case .proof:
                beleg

            case let .mascot(kopf, satz, video, bilder):
                maskottchen(kopf, satz, video: video, bilder: bilder)

            case let .karussell(kopf, satz, karten):
                startKarussell(kopf, satz, karten)

            case let .chat(_, _, frage, antwort, bild):
                chatVorschau(frage: frage, antwort: antwort, bild: bild)

            case let .preparing(titel, schritte):
                vorbereiten(titel, schritte)

            case let .director(_, _, video, bild, ideen):
                directorDemo(video: video, bild: bild, ideen: ideen)
            }
        }
        .id(index)                                   // erzwingt den Uebergang
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal:   .move(edge: .leading).combined(with: .opacity)))
        .opacity(eingeblendet ? 1 : 0)
        .scaleEffect(eingeblendet ? 1 : 0.94)
        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.14), value: eingeblendet)
    }

    /// Kachel mit fester Seitenlaenge. `scaledToFill` allein liess die Bilder
    /// vorher ueber den rechten Rand hinauslaufen — die Breite muss vom Raster
    /// kommen, nicht vom Bild.
    /// Zeilen-Karte: Vorschaubild links, rechts Nutzen und Name. Das
    /// 2x2-Kachelraster davor war das billige Muster — Text auf das Bild
    /// gestempelt, keine Hierarchie. Glam AI und ZOE nutzen diese Zeile.
    private func zeilenKarte(_ o: ObOption, aktiv: Bool) -> some View {
        HStack(spacing: 14) {
            Image(o.bild)
                .resizable()
                .scaledToFill()
                .frame(width: 76, height: 76)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(o.nutzen)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(o.label)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .strokeBorder(aktiv ? .clear : Color.secondary.opacity(0.35), lineWidth: 2)
                if aktiv {
                    Circle().fill(blau)
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 26, height: 26)
        }
        .padding(10)
        .padding(.trailing, 6)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.ultraThinMaterial))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(aktiv ? blau : .white.opacity(0.55), lineWidth: aktiv ? 2 : 1)
        )
        .shadow(color: blau.opacity(aktiv ? 0.22 : 0.08), radius: aktiv ? 14 : 8, y: 5)
    }

    private func optionenRaster(_ options: [ObOption]) -> some View {
        VStack(spacing: 12) {
            ForEach(Array(options.enumerated()), id: \.element.id) { i, option in
                let aktiv = auswahl.contains(option.ziel)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                        if aktiv { auswahl.remove(option.ziel) } else { auswahl.insert(option.ziel) }
                    }
                } label: { zeilenKarte(option, aktiv: aktiv) }
                .buttonStyle(.plain)
                // Eine Zeile pro Sekunde, mit demselben Pop wie beim Director.
                .opacity(i < popp ? 1 : 0)
                .scaleEffect(i < popp ? 1 : 0.9, anchor: .top)
            }
        }
        .task {
            popp = 0
            for _ in options {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { popp += 1 }
            }
        }
    }

    private func raster(_ bilder: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(bilder.prefix(4), id: \.self) { name in
                Color.clear
                    .aspectRatio(0.82, contentMode: .fit)
                    .overlay(Image(name).resizable().scaledToFill())
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: blau.opacity(0.14), radius: 12, y: 6)
            }
        }
    }

    private var beleg: some View {
        VStack(spacing: 16) {
            HStack(spacing: 5) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                }
            }
            .font(.system(size: 20))
            .padding(.vertical, 12)
            .padding(.horizontal, 22)
            .background(.ultraThinMaterial, in: Capsule())

            Image("trend_redsunset_after")
                .resizable()
                .scaledToFill()
                .frame(height: UIScreen.main.bounds.height * 0.38)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: blau.opacity(0.22), radius: 24, y: 12)
        }
    }

    /// Milchglas-Leiste mit blauem Verlaufs-Button darin.
    private var cta: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.easeInOut(duration: 0.3)) { weiter() }
        } label: {
            // Letzter Screen fuehrt in den Foto-Funnel, nicht in die App.
                Text(index == pages.count - 1 ? "Add your photo" : "Continue")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    Capsule().fill(
                        LinearGradient(colors: [blau, blau.opacity(0.82)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .shadow(color: blau.opacity(weiterMoeglich ? 0.42 : 0), radius: 18, y: 8)
                .opacity(weiterMoeglich ? 1 : 0.4)
        }
        .disabled(!weiterMoeglich)
        .buttonStyle(.plain)
        .scaleEffect(eingeblendet ? 1 : 0.96)
        .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.2), value: eingeblendet)
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    /// Sprechblase oben, Figur darunter, weicher Bodenschatten. Die Figur
    /// wippt langsam, damit der Screen nicht wie ein Standbild wirkt.
    /// Startscreen wie bei Glam AI: grosse Hochkantkarte in der Mitte, die
    /// Nachbarn ragen von den Seiten herein, Titel und Zeile unten AUF der
    /// Karte. Die Sprechblase ist raus — sie hat den Screen wie eine
    /// Kinderbuchseite wirken lassen; hier traegt das Bild.
    private func startKarussell(_ kopf: String, _ satz: String, _ karten: [ObKarte]) -> some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let breite = geo.size.width * 0.66
                ZStack {
                    ForEach(Array(karten.enumerated()), id: \.element.id) { i, karte in
                        let versatz = i - kartenIndex
                        let mitte = versatz == 0
                        ZStack(alignment: .bottomLeading) {
                            Image(karte.bild)
                                .resizable().scaledToFill()
                                .frame(width: breite, height: breite * 1.42)
                                .clipped()
                            LinearGradient(colors: [.clear, .black.opacity(0.72)],
                                           startPoint: .center, endPoint: .bottom)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(karte.titel)
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                Text(karte.zeile)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .opacity(0.85)
                            }
                            .foregroundStyle(.white)
                            .padding(16)
                        }
                        .frame(width: breite, height: breite * 1.42)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .shadow(color: blau.opacity(mitte ? 0.30 : 0.12),
                                radius: mitte ? 26 : 12, y: mitte ? 14 : 6)
                        .scaleEffect(mitte ? 1 : 0.84)
                        .opacity(abs(versatz) > 1 ? 0 : (mitte ? 1 : 0.55))
                        .offset(x: CGFloat(versatz) * breite * 0.86)
                        .zIndex(mitte ? 1 : 0)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(height: UIScreen.main.bounds.height * 0.46)
            .task {
                // Karten wechseln von allein, damit man sieht, dass es mehrere
                // Looks gibt, ohne wischen zu muessen.
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_400_000_000)
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                        kartenIndex = (kartenIndex + 1) % max(karten.count, 1)
                    }
                }
            }

            HStack(spacing: 6) {
                ForEach(0..<karten.count, id: \.self) { i in
                    Capsule()
                        .fill(i == kartenIndex ? blau : blau.opacity(0.22))
                        .frame(width: i == kartenIndex ? 18 : 6, height: 6)
                }
            }
            .padding(.top, 16)

            // Belegzeile ueber dem Text. Ohne sie stand der Block zwischen
            // Punkten und Button, linksbuendig unter einem mittigen Karussell —
            // ohne Achse und ohne Grund, dort zu sein. Glam AI setzt an
            // derselben Stelle einen Avatar-Stapel.
            HStack(spacing: 10) {
                HStack(spacing: -11) {
                    ForEach(Array(karten.prefix(3).enumerated()), id: \.offset) { _, k in
                        Image(k.bild)
                            .resizable().scaledToFill()
                            .frame(width: 30, height: 30)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow)
                        }
                    }
                    Text("Loved by creators")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 20)

            VStack(spacing: 6) {
                Text(kopf)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .tracking(-0.5)
                Text(satz)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            // Mittig wie das Karussell darueber — linksbuendig brach die Achse.
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.horizontal, 6)
        }
    }

    /// Abschluss-Screen. Die Sprechblase ist auch hier raus — sie hatte
    /// dasselbe Problem wie auf Screen 1: Figur unten, Text in einer Wolke
    /// darueber, das liest sich wie eine Kinderbuchseite. Jetzt derselbe
    /// Aufbau wie das Startkarussell: Bild oben, Text als Ueberschrift unten.
    private func maskottchen(_ kopf: String, _ satz: String, video: String, bilder: [String]) -> some View {
        VStack(spacing: 0) {
            ZStack {
                ForEach(Array(bilder.prefix(3).enumerated()), id: \.offset) { i, name in
                    let versatz: [CGFloat] = [-108, 0, 108]
                    let winkel: [Double]   = [-10, 0, 10]
                    Image(name)
                        .resizable().scaledToFill()
                        .frame(width: 124, height: 166)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(.white, lineWidth: 4))
                        .shadow(color: blau.opacity(0.22), radius: 16, y: 10)
                        .rotationEffect(.degrees(winkel[i]))
                        .offset(x: versatz[i], y: (i == 1 ? -12 : 6) - 74)
                        .zIndex(i == 1 ? 0 : -1)
                        .opacity(eingeblendet ? 1 : 0)
                        .scaleEffect(eingeblendet ? 1 : 0.86)
                        .animation(.spring(response: 0.55, dampingFraction: 0.75)
                            .delay(0.1 + Double(i) * 0.08), value: eingeblendet)
                }

                Ellipse()
                    .fill(RadialGradient(colors: [.white, .white.opacity(0)],
                                         center: .center, startRadius: 10, endRadius: 150))
                    .frame(width: 320, height: 250)
                    .offset(y: 104)

                SchleifenVideo(name: video)
                    .frame(width: 208, height: 208)
                    .blendMode(.multiply)
                    .offset(y: 96)
                    .opacity(eingeblendet ? 1 : 0)
                    .animation(.easeOut(duration: 0.5).delay(0.2), value: eingeblendet)
            }
            .frame(height: 366)

            VStack(spacing: 6) {
                Text(kopf)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .tracking(-0.5)
                Text(satz)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .opacity(eingeblendet ? 1 : 0)
            .offset(y: eingeblendet ? 0 : 14)
            .animation(.spring(response: 0.55, dampingFraction: 0.82).delay(0.3),
                       value: eingeblendet)
        }
    }

    /// Echter Chat statt schwebender Blasen: Kopfzeile mit Avatar und
    /// Online-Punkt, kurze Blasen nacheinander, dazwischen eine Tipp-Anzeige.
    /// Genau dieses Muster nutzen die Chat-Onboardings bei appllama — die
    /// Tipp-Blase ist der Grund, warum es lebendig statt gestellt wirkt.
    private func chatVorschau(frage: String, antwort: String, bild: String) -> some View {
        VStack(spacing: 0) {
            // Kopfzeile
            HStack(spacing: 11) {
                Image("clavic_mascot")
                    .resizable().scaledToFit()
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.white))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("Clavic").font(.system(size: 17, weight: .bold))
                    HStack(spacing: 5) {
                        Circle().fill(.green).frame(width: 7, height: 7)
                        Text("Online").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            VStack(alignment: .leading, spacing: 9) {
                if chatPhase >= 1 {
                    blase(frage, eigen: true)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                if chatPhase == 2 { tippBlase.transition(.opacity) }
                if chatPhase >= 3 {
                    blase(antwort, eigen: false)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                if chatPhase == 4 { tippBlase.transition(.opacity) }
                if chatPhase >= 5 {
                    Image(bild)
                        .resizable().scaledToFill()
                        .frame(height: UIScreen.main.bounds.height * 0.30)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.white.opacity(0.55)))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: blau.opacity(0.16), radius: 20, y: 10)
        .task {
            chatPhase = 0
            // Zeiten wie in einem echten Verlauf: kurz tippen, dann Antwort.
            let takt: [UInt64] = [400, 500, 900, 400, 1100]
            for _ in 0..<5 {
                try? await Task.sleep(nanoseconds: takt[min(chatPhase, 4)] * 1_000_000)
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { chatPhase += 1 }
            }
        }
    }

    private func blase(_ text: String, eigen: Bool) -> some View {
        HStack {
            if eigen { Spacer(minLength: 50) }
            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(eigen ? .white : .primary)
                .padding(.horizontal, 15).padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .fill(eigen ? AnyShapeStyle(blau) : AnyShapeStyle(Color.primary.opacity(0.07)))
                )
            if !eigen { Spacer(minLength: 50) }
        }
    }

    /// Drei Punkte, die nacheinander aufleuchten.
    private var tippBlase: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary.opacity(0.55))
                    .frame(width: 7, height: 7)
                    .scaleEffect(kenBurns ? 1.0 : 0.55)
                    .animation(.easeInOut(duration: 0.5).repeatForever()
                        .delay(Double(i) * 0.16), value: kenBurns)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.primary.opacity(0.07)))
    }

    /// Der Director in einem Telefon-Rahmen. Das Muster kommt von ReShoot:
    /// statt die Funktion zu illustrieren, zeigen sie die echte Oberflaeche im
    /// Geraet. Man sieht das Produkt, nicht eine Zeichnung davon — deshalb
    /// wirkt es fertig statt gebastelt.
    private func directorDemo(video: String, bild: String, ideen: [String]) -> some View {
        let breite = UIScreen.main.bounds.width * 0.62
        return VStack(spacing: 0) {
            ZStack {
                // Gehaeuse
                RoundedRectangle(cornerRadius: 42, style: .continuous)
                    .fill(Color(white: 0.10))
                    .frame(width: breite + 12, height: breite * 1.92 + 12)
                    .shadow(color: .black.opacity(0.28), radius: 26, y: 16)

                // Bildschirm
                VStack(spacing: 0) {
                    // Statuszeile
                    HStack {
                        Text("9:41").font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Image(systemName: "wifi").font(.system(size: 9))
                        Image(systemName: "battery.75").font(.system(size: 9))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)

                    HStack {
                        Text("Director")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                        Spacer()
                        Image(systemName: "sparkles").foregroundStyle(blau)
                    }
                    .padding(.horizontal, 14).padding(.bottom, 8)

                    ZStack(alignment: .bottomLeading) {
                        Image(bild).resizable().scaledToFill()
                            .frame(height: breite * 0.86)
                            .clipped()
                        LinearGradient(colors: [.clear, .black.opacity(0.55)],
                                       startPoint: .center, endPoint: .bottom)
                        Text("Reading your photo…")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(9)
                    }
                    .frame(height: breite * 0.86)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 12)

                    VStack(spacing: 7) {
                        ForEach(Array(ideen.enumerated()), id: \.offset) { i, idee in
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(blau)
                                Text(idee)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                                Spacer(minLength: 2)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(blau.opacity(0.6))
                            }
                            .padding(.horizontal, 11).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(blau.opacity(0.07)))
                            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(blau.opacity(0.25), lineWidth: 1))
                            .opacity(i < popp ? 1 : 0)
                            .scaleEffect(i < popp ? 1 : 0.85, anchor: .leading)
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 10)

                    Spacer(minLength: 0)

                    Text("Use this look")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Capsule().fill(blau))
                        .padding(.horizontal, 14).padding(.bottom, 12)
                }
                .frame(width: breite, height: breite * 1.92)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))

                // Dynamic Island
                Capsule().fill(.black)
                    .frame(width: breite * 0.30, height: 17)
                    .offset(y: -(breite * 1.92) / 2 + 16)
            }

            // Das Maskottchen steht neben dem Geraet und praesentiert.
            SchleifenVideo(name: video)
                .frame(width: 120, height: 120)
                .blendMode(.multiply)
                .offset(x: breite * 0.62, y: -70)
                .frame(height: 40)
        }
        .task {
            popp = 0
            for _ in ideen {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { popp += 1 }
            }
        }
    }

    /// Ladescreen als BILD, nicht als Liste. Vorher war es eine Textaufzaehlung
    /// mit Haken — das liest sich wie ein Formular, nicht wie eine Foto-App.
    /// Jetzt arbeitet sichtbar etwas am Bild: ein Scanstreifen laeuft darueber,
    /// das Motiv geht von unscharf und blass in scharf und farbig ueber, und der
    /// Fortschritt steht als Ring darauf. Die Bewertungskarte bleibt.
    private func vorbereiten(_ titel: String, _ schritte: [String]) -> some View {
        let anteil = Double(erledigt) / Double(max(schritte.count, 1))
        return VStack(spacing: 16) {
            ZStack {
                // Motiv: waehrend der Verarbeitung matt und weich, danach klar.
                Image("trend_goldenhour_after")
                    .resizable().scaledToFill()
                    .frame(height: UIScreen.main.bounds.height * 0.34)
                    .clipped()
                    .saturation(0.35 + 0.65 * anteil)
                    .blur(radius: (1 - anteil) * 7)
                    .overlay(Color.white.opacity((1 - anteil) * 0.18))

                // Scanstreifen, der von oben nach unten laeuft.
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.75), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 90)
                        .offset(y: kenBurns ? geo.size.height : -90)
                        .animation(.linear(duration: 1.6).repeatForever(autoreverses: false),
                                   value: kenBurns)
                        .blendMode(.plusLighter)
                }

                // Fortschrittsring mit Prozent.
                ZStack {
                    Circle().strokeBorder(.white.opacity(0.28), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: anteil)
                        .stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: anteil)
                    Text("\(Int(anteil * 100))%")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                .frame(width: 92, height: 92)
                .shadow(color: .black.opacity(0.3), radius: 10)
            }
            .frame(height: UIScreen.main.bounds.height * 0.34)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: blau.opacity(0.24), radius: 24, y: 12)

            Text(titel)
                .font(.system(size: 28, weight: .bold, design: .rounded))

            // Nur die LAUFENDE Zeile, nicht alle vier. Eine Liste mit Haken
            // wirkt wie eine Checkliste; eine wechselnde Zeile wie Arbeit.
            Text(schritte[min(erledigt, schritte.count - 1)])
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .id(erledigt)
                .transition(.opacity.combined(with: .move(edge: .bottom)))

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 3) {
                        ForEach(0..<5, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 13)).foregroundStyle(.yellow)
                        }
                    }
                    Spacer()
                    Text("Mia")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Text("\"I stopped downloading filter apps. I just tell it what I want now.\"")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white))
            .shadow(color: blau.opacity(0.14), radius: 18, y: 8)
        }
        .task {
            erledigt = 0
            for _ in schritte {
                try? await Task.sleep(nanoseconds: 900_000_000)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { erledigt += 1 }
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            withAnimation(.easeInOut(duration: 0.3)) { weiter() }
        }
    }

    private func einblenden() {
        eingeblendet = false
        withAnimation(.easeOut(duration: 0.42).delay(0.04)) { eingeblendet = true }
    }

    private func weiter() {
        if index < pages.count - 1 {
            index += 1
        } else {
            speichereZiele()
            isPresented = false
        }
    }

    private func speichereZiele() {
        let roh = auswahl.map(\.rawValue).joined(separator: ",")
        UserDefaults.standard.set(roh, forKey: OnboardingZiel.speicherSchluessel)
    }
}
