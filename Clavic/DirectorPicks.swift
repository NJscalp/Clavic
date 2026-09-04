//
//  DirectorPicks.swift
//  Clavic
//
//  Was der Director nach dem Blick aufs Foto zeigt.
//
//  DREI WEGE, NICHT EIN MENÜ:
//
//    1. Zwei Vorschläge — die zwei Ideen, die er für DIESES Foto am stärksten
//       findet. Sie liegen offen da, groß, ohne dass man etwas aufklappen muss.
//       Zwei und nicht vier: ein Creative Director sagt „das sind meine zwei
//       besten Ideen", er legt keinen Katalog hin.
//
//    2. Trends — hinter EINER Zeile, die man antippt. Der Nutzer soll nicht
//       durch eine Vorlagen-Bibliothek suchen; der Director hat sie bereits
//       nach Passung zu diesem Foto sortiert. Passt keiner, taucht die Zeile
//       gar nicht erst auf. Kein leeres Fach.
//
//    3. Eigene Idee — führt in die Eingabezeile, die ohnehin schon da ist.
//       Kein eigener Bereich, keine zweite Texteingabe.
//
//  ES WIRD NICHTS GERENDERT, bevor hier etwas angetippt wurde. Jeder Tipp
//  kostet Credits, deshalb ist jeder Tipp eine bewusste Entscheidung.
//

import SwiftUI

struct DirectorPicks: View {
    let picks: [DirectorAPI.Option]
    let trends: [DirectorAPI.Option]
    /// false = der Wurf läuft noch.
    let landed: Bool
    let throwToken: Int
    /// Das Foto, über das gesprochen wird — liegt auf Karten, die es erhalten.
    let sourcePhoto: Data?
    var onPick: (DirectorAPI.Option) -> Void = { _ in }
    var onOwnIdea: () -> Void = {}

    @State private var trendsOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Der Kartenblock zeichnet über seine Layouthöhe hinaus nach oben
            // (der Nebelstreifen, aus dem sie kommen). Im Auftakt liegt darüber
            // die Figur, hier die Überschrift — ohne Ausgleich schöben sich die
            // Karten darüber. Im Simulator genau so gesehen.
            DirectorPolaroids(
                items: picks.map { PolaroidItem($0, sourcePhoto: sourcePhoto) },
                landed: landed,
                throwToken: throwToken,
                onPick: { item in
                    guard let option = picks.first(where: { $0.id == item.id }) else { return }
                    onPick(option)
                }
            )
            .padding(.top, DirectorPolaroids.topOverhang)

            // Erst wenn die Karten liegen. Vorher wäre es eine Zeile, die
            // unter einer laufenden Animation zappelt.
            if landed {
                if !trends.isEmpty {
                    trendRow
                }
                ownIdeaRow
            }
        }
        .animation(.easeOut(duration: 0.35), value: landed)
    }

    // MARK: - Trends

    private var trendRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { trendsOpen.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text("Trending right now")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(trends.count)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .rotationEffect(.degrees(trendsOpen ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if trendsOpen {
                // Schon nach Passung sortiert — der beste steht vorn, und der
                // Nutzer muss nichts vergleichen.
                VStack(spacing: 8) {
                    ForEach(trends) { trend in
                        Button { onPick(trend) } label: { trendCard(trend) }
                            .buttonStyle(.plain)
                    }
                }
                .transition(.opacity.combined(with: .offset(y: -8)))
            }
        }
    }

    private func trendCard(_ trend: DirectorAPI.Option) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Rectangle().fill(Theme.surfaceHigh)
                if let name = trend.preview, UIImage(named: name) != nil {
                    Image(name).resizable().scaledToFill()
                } else if let data = sourcePhoto, trend.mode.keepsPhoto, let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().scaledToFill()
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(trend.label)
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(trend.caption)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.accent)
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Eigene Idee

    private var ownIdeaRow: some View {
        Button(action: onOwnIdea) {
            HStack(spacing: 8) {
                Image(systemName: "pencil.and.scribble")
                    .font(.system(size: 13, weight: .bold))
                Text("Something else? Just say it.")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
