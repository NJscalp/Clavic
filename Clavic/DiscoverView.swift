//
//  DiscoverView.swift
//  Clavic
//
//  Entdecken-Startseite: Hero, Trending, Kategorien und Template-Raster.
//

import SwiftUI

struct DiscoverView: View {
    let onSelect: (VideoTemplate) -> Void
    /// Der Solo Shot ist kein Template — er hat keinen Prompt und keine
    /// Kachel-Vorschau, sondern eine eigene Kamera. Deshalb ein eigener Weg
    /// hinaus statt eines erfundenen Eintrags in der Vorlagen-Liste.
    var onSoloShot: () -> Void = {}
    /// Der zweite Kamera-Modus: jemand fotografiert mich und kann es nicht.
    /// Er hängt am Solo-Shot-Bild, weil beide dieselbe Frage beantworten —
    /// „wie komme ich auf ein gutes Bild von mir" — nur mit und ohne Begleitung.
    var onDirector: () -> Void = {}

    @Environment(TemplateStore.self) private var store
    /// „Looks" statt „Alles": die ersten anderthalb Sekunden entscheiden, und
    /// sie sollen zeigen, wofür die App gedacht ist — nicht das komplette Lager.
    @State private var category: TemplateCategory = .looks

    /// Nur drei Ziele, in dieser Reihenfolge. `TemplateCategory.allCases`
    /// stünde hier nicht: die alten Nischen-Fälle leben weiter, damit
    /// Server-Vorlagen sie noch benennen können, sie sind nur kein Ziel mehr.
    ///
    /// „Trends" steht mit dabei, obwohl die Vorgabe nur Looks · Tools · Fun
    /// nannte: es gibt Vorlagen, die weder Look noch Werkzeug noch Fun sind,
    /// und ohne diesen Chip wäre keine einzige davon erreichbar.
    private let chips: [TemplateCategory] = [.looks, .tools, .trends, .fun]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var gridTemplates: [VideoTemplate] {
        store.filtered(by: category)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                soloShotHero
                clavicToolsSection
                categorySection
                gridSection
            }
            .padding(.top, 8)
            .padding(.bottom, 16)   // Tab-Bar-Freiraum wird via safeAreaInset gesichert
        }
    }

    // MARK: - Solo Shot ganz oben

    /// Halbe Bildschirmhöhe, laufendes Beispiel: das Erste, was man sieht, ist
    /// das, was die App von anderen unterscheidet — sich selbst an einen Ort
    /// stellen, an dem niemand mitgekommen ist.
    ///
    /// Als Beispiel läuft der Vorher/Nachher-Wischer über echte Aufnahmen. Ein
    /// eigenes Beispiel-VIDEO liegt nicht im Bundle; sobald es eines gibt,
    /// gehört an diese Stelle ein `LoopingVideoView`.
    @ViewBuilder
    private var soloShotHero: some View {
        Button(action: onSoloShot) {
            ZStack(alignment: .bottomLeading) {
                if let before = UIImage(named: "sc_garage_before"),
                   let after = UIImage(named: "sc_garage_after") {
                    BeforeAfterSlider(before: before, after: after, sweepDuration: 3.4, showLabels: false)
                } else {
                    Theme.brandGradient
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text("SOLO SHOT")
                        .font(.system(size: 11.5, weight: .black, design: .rounded))
                        .kerning(1.1)
                        .foregroundStyle(.white.opacity(0.85))
                    Text("Fotos von dir — ganz allein unterwegs")
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
            }
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical) { height, _ in height * 0.5 }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 16, y: 7)
            .padding(.horizontal, Theme.screenPadding)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) { directorPill }
    }

    /// Eigener Knopf ÜBER der Hero-Fläche, nicht in ihr: ein Knopf im Label
    /// eines anderen Knopfes bekommt in SwiftUI keine eigenen Tipps ab.
    private var directorPill: some View {
        Button(action: onDirector) {
            Label("Regie", systemImage: "person.2.wave.2.fill")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.trailing, Theme.screenPadding + 14)
        .padding(.bottom, 18)
    }

    // MARK: - Clavic Tools (App-eigene Pro-Werkzeuge ganz oben)

    private var clavicToolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clavic Tools")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.screenPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(store.filtered(by: .tools)) { template in
                        Button {
                            onSelect(template)
                        } label: {
                            TemplateTile(template: template, width: 170, height: 220)
                        }
                        .buttonStyle(.plain)
                        .disabled(template.comingSoon)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
            }
        }
    }

    // MARK: - Kategorien

    private var categorySection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { item in
                    CategoryChip(title: item.rawValue, isSelected: category == item) {
                        withAnimation(.spring(duration: 0.3)) { category = item }
                    }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
        }
    }

    // MARK: - Raster

    private var gridSection: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(gridTemplates) { template in
                Button {
                    onSelect(template)
                } label: {
                    TemplateTile(template: template, width: nil, height: 210)
                }
                .buttonStyle(.plain)
                .disabled(template.comingSoon)
            }
        }
        .padding(.horizontal, Theme.screenPadding)
    }
}

// MARK: - Hero-Karte

struct HeroCard: View {
    let template: VideoTemplate

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            template.gradient
            decoration
            TemplatePreviewOverlay(template: template)
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(template.subtitle.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                Text(template.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(18)

            NicheBadge(category: template.category)
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 300, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
    }

    private var decoration: some View {
        Image(systemName: template.icon)
            .font(.system(size: 120, weight: .semibold))
            .foregroundStyle(.white.opacity(0.18))
            .rotationEffect(.degrees(-12))
            .offset(x: 90, y: -10)
    }
}

// MARK: - Nischen-Badge

struct NicheBadge: View {
    let category: TemplateCategory

    var body: some View {
        if let icon = category.badgeIcon {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                Text(category.rawValue)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.vertical, 5)
            .padding(.horizontal, 9)
            .background(.black.opacity(0.35), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
        }
    }
}

// MARK: - Template-Kachel

struct TemplateTile: View {
    let template: VideoTemplate
    let width: CGFloat?
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            template.gradient
            Image(systemName: template.icon)
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.white.opacity(0.22))
                .offset(x: 40, y: -16)
            TemplatePreviewOverlay(template: template)
            LinearGradient(
                colors: [.clear, .black.opacity(0.5)],
                startPoint: .center,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(template.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)

            NicheBadge(category: template.category)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if template.comingSoon {
                comingSoonOverlay
            }
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

    private var comingSoonOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
            Text("Coming soon")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.vertical, 7)
                .padding(.horizontal, 14)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
        }
    }
}
