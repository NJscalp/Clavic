//
//  DirectorInkNotes.swift
//  Clavic
//
//  Der Stift geht ueber das fertige Foto.
//
//  Sobald der Director gelesen hat, zeichnet sich auf dem Abzug nacheinander
//  auf, was ihm aufgefallen ist: ein Kringel um das Motiv, eine Wellenlinie
//  durch eine tote Flaeche, eine Ecke, die weg koennte — dazu je zwei, drei
//  Woerter in Handschrift. Die Stellen kommen aus `DirectorReadMarks`, sind
//  also am Bild gemessen und nicht dekoriert.
//
//  ZWEI DINGE MACHEN DEN UNTERSCHIED ZWISCHEN „STIFT" UND „VEKTORGRAFIK":
//
//  1. GEZOGEN, NICHT EINGEBLENDET. Jede Linie ist ein `Shape` und waechst
//     ueber `trim(to:)` von ihrem Anfang zu ihrem Ende. Ein Kringel, der als
//     Ganzes aufblendet, sieht gestempelt aus; einer, der gezogen wird, sieht
//     aus, als denke jemand mit.
//
//  2. UNSAUBER MIT ABSICHT. Auf jeden Radius liegt eine langsame Sinuswelle,
//     der Kringel dreht 1,08 Runden statt genau einer und schliesst deshalb
//     mit einem kleinen Ueberschlag. Eine exakte Ellipse liest sich sofort als
//     Maschine.
//
//  DIE FARBE IST ROT (`Theme.danger`), nicht die Markenfarbe. Blau waere
//  hier eine Verzierung; rot ist die Farbe der Korrektur — man sieht auf
//  einen Blick, dass etwas ANGEMERKT wird, nicht geschmueckt.
//

import SwiftUI

struct DirectorInkNotes: View {
    let marks: [ReadMark]
    /// Startet den Stift. Von aussen gesteuert, damit die Striche erst laufen,
    /// wenn das Foto wirklich steht.
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Wie weit jeder Strich gezogen ist, 0…1.
    @State private var drawn: [Int: CGFloat] = [:]
    @State private var labelsShown: Set<Int> = []

    /// Wie lange ein Strich braucht und wie weit die Striche auseinander liegen.
    private static let stroke: Double = 0.55
    private static let gap: Double = 0.42

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(marks) { mark in
                    let rect = CGRect(
                        x: mark.area.minX * geo.size.width,
                        y: mark.area.minY * geo.size.height,
                        width: mark.area.width * geo.size.width,
                        height: mark.area.height * geo.size.height
                    )
                    let progress = drawn[mark.id] ?? 0

                    InkStroke(kind: mark.kind)
                        .trim(from: 0, to: progress)
                        .stroke(ink(mark).opacity(0.82),
                                style: StrokeStyle(lineWidth: mark.kind == .ring ? 2.6 : 2.2,
                                                   lineCap: .round, lineJoin: .round))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                    handwriting(mark, in: rect, bounds: geo.size)
                }
            }
        }
        .allowsHitTesting(false)
        .task(id: taskKey) { await draw() }
    }

    /// Neu zeichnen, wenn ein anderes Foto gelesen wurde ODER der Stift
    /// angeschaltet wird. Ohne die Marken im Schluessel blieben beim zweiten
    /// Zug die alten Striche stehen.
    private var taskKey: String {
        "\(active)-" + marks.map { "\($0.id)\($0.label)" }.joined()
    }

    private func draw() async {
        drawn = [:]
        labelsShown = []
        guard active, !marks.isEmpty else { return }

        guard !reduceMotion else {
            // Bei „Bewegung reduzieren" stehen die Anmerkungen sofort da. Sie
            // sind Inhalt, nicht Zierrat — weglassen waere der falsche Weg.
            for mark in marks { drawn[mark.id] = 1 }
            labelsShown = Set(marks.map(\.id))
            return
        }

        for mark in marks {
            withAnimation(.easeInOut(duration: Self.stroke)) { drawn[mark.id] = 1 }
            // Die Schrift kommt, wenn der Strich fast durch ist — so, wie man
            // erst zeigt und dann danebenschreibt.
            try? await Task.sleep(for: .seconds(Self.stroke * 0.75))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.28)) { _ = labelsShown.insert(mark.id) }
            try? await Task.sleep(for: .seconds(Self.gap))
            guard !Task.isCancelled else { return }
        }
    }

    /// Die zwei, drei Woerter neben dem Strich.
    ///
    /// Sie sitzen AUSSEN am Strich, auf der Seite mit mehr Platz — steht der
    /// Kringel rechts im Bild, schreibt die Hand links davon. Ohne das lag die
    /// Schrift bei einem Hochformat regelmaessig ausserhalb des Fotos.
    /// Rot fuer das, was stoert; gruen fuer das, was schon sitzt. Ein Stift
    /// mit zwei Farben — so geht ein Regisseur einen Abzug durch.
    private func ink(_ mark: ReadMark) -> Color {
        mark.isPraise ? Theme.go : Theme.danger
    }

    @ViewBuilder
    private func handwriting(_ mark: ReadMark, in rect: CGRect, bounds: CGSize) -> some View {
        let onLeft = rect.midX > bounds.width * 0.5
        // Eine Randbahn ist so breit oder so hoch wie das ganze Bild. „Knapp
        // unter dem Strich" landet dann mitten im Motiv — bei einem Hochformat
        // genau auf dem Gesicht. Bei der Klammer schreibt die Hand deshalb IN
        // die Bahn hinein, nicht darunter.
        let inBand = mark.kind == .bracket
        Text(mark.label)
            .font(.system(size: 13, weight: .semibold, design: .serif))
            .italic()
            .foregroundStyle(ink(mark))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.papier.opacity(0.86), in: Capsule())
            .rotationEffect(.degrees(onLeft ? -3.5 : 3.5))
            .fixedSize()
            .opacity(labelsShown.contains(mark.id) ? 1 : 0)
            .position(
                x: inBand
                    ? (rect.width > rect.height ? bounds.width - 62 : rect.midX)
                    : (onLeft ? max(46, rect.minX - 6) : min(bounds.width - 46, rect.maxX + 6)),
                y: inBand
                    ? (rect.width > rect.height ? rect.midY : bounds.height - 20)
                    : min(bounds.height - 14, rect.maxY + 11)
            )
    }
}

// MARK: - Die drei Striche

/// EIN Shape mit drei Formen statt drei Shapes.
///
/// Nicht Sparsamkeit, sondern Notwendigkeit: `trim(to:)` gibt es nur auf
/// `Shape`. Ein `@ViewBuilder`, der je nach Fall eine andere Form liefert,
/// ist bereits `some View` — und daran laesst sich nicht mehr ziehen. Genau
/// daran ist der erste Entwurf gescheitert.
private struct InkStroke: Shape {
    let kind: ReadMark.Kind

    func path(in r: CGRect) -> Path {
        switch kind {
        case .ring:    return InkRing().path(in: r)
        case .wave:    return InkWave().path(in: r)
        case .bracket: return InkBracket().path(in: r)
        }
    }
}

/// Ein Kringel, wie man ihn mit dem Stift zieht: leicht unrund, und er faehrt
/// am Ende ein Stueck ueber seinen Anfang hinaus.
private struct InkRing: Shape {
    func path(in r: CGRect) -> Path {
        var path = Path()
        let cx = r.midX, cy = r.midY
        let rx = r.width / 2 * 0.94, ry = r.height / 2 * 0.94
        // 1,08 Runden: der Ueberschlag ist das, was einen gezogenen Kringel
        // von einer Ellipse unterscheidet.
        let turns = 1.08
        let steps = 96
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let angle = -.pi / 2 + t * turns * 2 * .pi
            // Zwei ungleiche Wellen auf dem Radius — eine allein sieht wieder
            // regelmaessig aus.
            let wobble = 1 + 0.035 * sin(angle * 3 + 0.7) + 0.022 * sin(angle * 5 + 2.1)
            let point = CGPoint(x: cx + cos(angle) * rx * wobble,
                                y: cy + sin(angle) * ry * wobble)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// Eine Wellenlinie, wie man sie unter etwas Flaues setzt.
private struct InkWave: Shape {
    func path(in r: CGRect) -> Path {
        var path = Path()
        let y = r.midY
        let amplitude = min(r.height / 2, 9)
        let steps = 64
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let point = CGPoint(x: r.minX + r.width * t,
                                y: y + sin(t * 3.6 * 2 * .pi) * amplitude
                                    // Leicht abfallend: eine Hand zieht nicht waagerecht.
                                    + CGFloat(t) * 3)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// Eine Ecke, die weg koennte — zwei Striche, die sich nicht ganz treffen.
private struct InkBracket: Shape {
    func path(in r: CGRect) -> Path {
        var path = Path()
        let arm = min(r.width, r.height) * 0.42
        // Waagerecht liegende Bahn: die Klammer sitzt links; hochkant: oben.
        if r.width >= r.height {
            path.move(to: CGPoint(x: r.minX + arm, y: r.minY + 4))
            path.addLine(to: CGPoint(x: r.minX + 3, y: r.minY + 5))
            path.addLine(to: CGPoint(x: r.minX + 4, y: r.maxY - 4))
        } else {
            path.move(to: CGPoint(x: r.minX + 4, y: r.minY + arm))
            path.addLine(to: CGPoint(x: r.minX + 5, y: r.minY + 3))
            path.addLine(to: CGPoint(x: r.maxX - 4, y: r.minY + 4))
        }
        return path
    }
}
