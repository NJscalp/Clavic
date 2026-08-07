//
//  DiscoverView.swift
//  Clavic
//
//  Entdecken-Startseite: Hero, Trending, Kategorien und Template-Raster.
//

import SwiftUI

struct DiscoverView: View {
    let onSelect: (VideoTemplate) -> Void

    @Environment(TemplateStore.self) private var store
    @State private var category: TemplateCategory = .all

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
                clavicToolsSection
                categorySection
                gridSection
            }
            .padding(.top, 8)
            .padding(.bottom, 16)   // Tab-Bar-Freiraum wird via safeAreaInset gesichert
        }
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
                ForEach(TemplateCategory.allCases) { item in
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
