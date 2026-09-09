//
//  OnboardingGoals.swift
//  Clavic
//
//  Die eine Frage im Einstieg: was willst du eigentlich machen?
//
//  WOHER DER AUFBAU KOMMT.
//  Nachgebaut nach Facetunes Schritt „Editing Goals" (12 Mio $ Monatsumsatz,
//  Schritt 5 von 9). Dort: Zurueckpfeil, Schrittzaehler und „Skip" in einer
//  Zeile, eine Ueberschrift die abbricht („I want to use Facetune to…"), in
//  Klammern der Hinweis auf Mehrfachauswahl, darunter ein fliessendes Raster
//  aus umrandeten Pillen mit Linien-Icon, und ganz unten ein GRAUER Knopf,
//  der erst mit der ersten Auswahl angeht.
//
//  Perfect365 (200 Tsd. $) baut denselben Schritt als „Editing Style Quiz".
//
//  WARUM WIR DAS BRAUCHEN.
//  Der Director faengt heute bei null an und raet, was jemand vorhat. Diese
//  Antwort steht ihm ab dem ersten Foto zur Verfuegung. Deshalb sind die
//  Chips auch keine erfundenen Kategorien, sondern genau das, was die App
//  wirklich kann — jede Zeile hier hat eine Entsprechung im Produkt.
//
//  NICHT UEBERNOMMEN: Facetune fragt davor Geschlecht und Geburtsjahr ab. Das
//  brauchen wir fuer nichts, also fragen wir es nicht.
//

import SwiftUI

// MARK: - Was jemand vorhat

enum OnboardingZiel: String, CaseIterable, Identifiable {
    case licht, trend, haare, outfit, swap, objekte, hintergrund, schaerfe, paar, identitaet

    var id: String { rawValue }

    /// Kurz und in der ersten Person — es ist die Antwort des Nutzers, nicht
    /// der Name eines Werkzeugs.
    var titel: String {
        switch self {
        case .licht:      return "Better light"
        case .trend:      return "TikTok looks"
        case .haare:      return "New hair"
        case .outfit:     return "Try an outfit"
        case .swap:       return "Put me in a photo"
        case .objekte:    return "Remove objects"
        case .hintergrund:return "Change background"
        case .schaerfe:   return "Sharpen to 4K"
        case .paar:       return "Couple pictures"
        case .identitaet: return "Keep my face exactly"
        }
    }

    var symbol: String {
        switch self {
        case .licht:      return "sun.max"
        case .trend:      return "sparkles"
        case .haare:      return "scissors"
        case .outfit:     return "tshirt"
        case .swap:       return "person.crop.rectangle.stack"
        case .objekte:    return "eraser"
        case .hintergrund:return "photo.on.rectangle.angled"
        case .schaerfe:   return "arrow.up.left.and.arrow.down.right"
        case .paar:       return "person.2"
        case .identitaet: return "face.smiling"
        }
    }

    /// Was der Director daraus liest. Bewusst ganze Saetze: sie landen
    /// woertlich in seinem Kontext, nicht als Schluesselwort.
    var hinweis: String {
        switch self {
        case .licht:      return "wants better light and colour above all"
        case .trend:      return "wants the current TikTok camera looks"
        case .haare:      return "is open to hair changes"
        case .outfit:     return "is open to outfit changes"
        case .swap:       return "wants to be placed into other photos"
        case .objekte:    return "wants distracting objects removed"
        case .hintergrund:return "is open to background changes"
        case .schaerfe:   return "cares about resolution and sharpness"
        case .paar:       return "shoots couple and group pictures"
        case .identitaet: return "insists the face stays exactly as it is"
        }
    }

    static let speicherSchluessel = "clavic.onboardingGoals"

    /// Was im Einstieg angetippt wurde, als Satz fuer den Director.
    static var gemerkterHinweis: String? {
        let roh = UserDefaults.standard.string(forKey: speicherSchluessel) ?? ""
        let ziele = roh.split(separator: ",").compactMap { OnboardingZiel(rawValue: String($0)) }
        guard !ziele.isEmpty else { return nil }
        return "The user said at setup that they " + ziele.map(\.hinweis).joined(separator: ", ") + "."
    }
}

// MARK: - Fliessendes Raster

/// Zeilenumbruch nach Inhalt, nicht nach fester Spaltenzahl.
///
/// Ein `LazyVGrid` mit zwei Spalten zwingt jede Pille auf dieselbe Breite;
/// „New hair" bekaeme dann genauso viel Platz wie „Keep my face exactly" und
/// das Raster sieht nach Formular aus. In der Vorlage sind die Pillen
/// unterschiedlich breit und brechen um, wenn die Zeile voll ist.
struct FlussLayout: Layout {
    var abstand: CGFloat = 9

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let breite = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, zeilenHoehe: CGFloat = 0
        for teil in subviews {
            let s = teil.sizeThatFits(.unspecified)
            if x + s.width > breite, x > 0 {
                x = 0; y += zeilenHoehe + abstand; zeilenHoehe = 0
            }
            x += s.width + abstand
            zeilenHoehe = max(zeilenHoehe, s.height)
        }
        return CGSize(width: breite, height: y + zeilenHoehe)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout Void) {
        var x = bounds.minX, y = bounds.minY, zeilenHoehe: CGFloat = 0
        for teil in subviews {
            let s = teil.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += zeilenHoehe + abstand; zeilenHoehe = 0
            }
            teil.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + abstand
            zeilenHoehe = max(zeilenHoehe, s.height)
        }
    }
}

// MARK: - Der Schritt

struct OnboardingZieleView: View {
    var schritt: Int
    var vonSchritten: Int
    var onZurueck: () -> Void
    var onWeiter: ([OnboardingZiel]) -> Void

    @State private var gewaehlt: Set<OnboardingZiel> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            kopfzeile

            Text("I want to use Clavic to…")
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 26)

            Text("(Choose as many as you want)")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                FlussLayout(abstand: 9) {
                    ForEach(OnboardingZiel.allCases) { ziel in
                        pille(ziel)
                    }
                }
                .padding(.top, 26)
                .padding(.bottom, 12)
            }

            weiterKnopf
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var kopfzeile: some View {
        HStack {
            Button(action: onZurueck) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            Spacer()
            Text("\(schritt) of \(vonSchritten)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            // „Skip" ist kein Zierrat: wer nichts antippt, soll nicht
            // feststecken. Der Director laeuft dann wie bisher ohne Vorwissen.
            Button("Skip") { onWeiter([]) }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 44, height: 44, alignment: .trailing)
        }
    }

    private func pille(_ ziel: OnboardingZiel) -> some View {
        let an = gewaehlt.contains(ziel)
        return Button {
            withAnimation(.spring(duration: 0.26)) {
                if an { gewaehlt.remove(ziel) } else { gewaehlt.insert(ziel) }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: ziel.symbol)
                    .font(.system(size: 14, weight: .medium))
                Text(ziel.titel)
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(an ? Theme.accent : Theme.textPrimary)
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background(an ? Theme.accentSoft : Theme.surface, in: Capsule())
            .overlay(
                Capsule().strokeBorder(an ? Theme.accent : Theme.stroke,
                                       lineWidth: an ? 1.6 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var weiterKnopf: some View {
        // Grau, solange nichts gewaehlt ist — genau wie in der Vorlage. Der
        // Knopf ist damit selbst der Hinweis, dass hier etwas zu tun ist.
        Button {
            onWeiter(Array(gewaehlt))
        } label: {
            Text("Continue")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(gewaehlt.isEmpty ? Theme.textSecondary : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    Capsule().fill(gewaehlt.isEmpty
                                   ? AnyShapeStyle(Theme.surfaceHigh)
                                   : AnyShapeStyle(Theme.accent))
                )
        }
        .buttonStyle(.plain)
        .disabled(gewaehlt.isEmpty)
        .animation(.easeInOut(duration: 0.22), value: gewaehlt.isEmpty)
    }
}

#Preview {
    ZStack {
        Theme.background.ignoresSafeArea()
        OnboardingZieleView(schritt: 4, vonSchritten: 4, onZurueck: {}, onWeiter: { _ in })
    }
}
