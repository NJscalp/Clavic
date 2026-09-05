//
//  LibraryView.swift
//  Clavic
//
//  Bibliothek: Alle eigenen Generierungen als Raster, mit Live-Status.
//

import SwiftUI
import SwiftData

struct LibraryView: View {
    @Query(sort: \VideoProject.createdAt, order: .reverse) private var projects: [VideoProject]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12),
              count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        Group {
            if projects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    HStack {
                        Text("My Creations")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.top, 8)

                    LazyVGrid(columns: columns, alignment: .center, spacing: 14) {
                        ForEach(projects) { project in
                            NavigationLink(value: project) {
                                ProjectCard(project: project)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 16)   // Tab-Bar-Freiraum via safeAreaInset gesichert
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.accentSoft)
                    .frame(width: 88, height: 88)
                Image(systemName: "film.stack")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            Text("Nothing here yet")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text("Open Director for guided looks or\nuse Chat and Studio to start creating.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Projekt-Karte

struct ProjectCard: View {
    let project: VideoProject

    /// Name des genutzten Templates (Fallback für freie Generierungen).
    private var displayName: String {
        project.templateTitle.isEmpty ? (project.isImageOutput ? "Custom photo" : "Custom video") : project.templateTitle
    }

    private var dateLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(project.createdAt) { return String(localized: "Today") }
        if calendar.isDateInYesterday(project.createdAt) { return String(localized: "Yesterday") }
        return project.createdAt.formatted(.dateTime.month(.abbreviated).day())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            thumbnail
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(displayName)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 6) {
                Text(dateLabel)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                statusBadge
            }
        }
        .padding(9)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
    }

    private var thumbnail: some View {
        // The chosen portrait grid keeps every card aligned. The detail view
        // retains the original aspect ratio and the existing image/video actions.
        Color.clear
            .aspectRatio(0.86, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                ZStack {
                    if let data = project.thumbnailData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else if project.status.isActive {
                        // Saubere Lade-Animation: das Intro-Video als Loop.
                        Rectangle().fill(Theme.background)
                        IntroLoader()
                            .frame(width: 76, height: 76)
                            .allowsHitTesting(false)
                    } else {
                        Rectangle().fill(Theme.surfaceHigh)
                        placeholderContent
                    }

                    if project.status == .succeeded && !project.isImageOutput {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.white.opacity(0.95))
                            .shadow(color: .black.opacity(0.4), radius: 8)
                    }
                }
            }
            .clipped()
    }

    @ViewBuilder
    private var placeholderContent: some View {
        switch project.status {
        case .queued, .running:
            VStack(spacing: 10) {
                ProgressView().tint(Theme.accent)
                Text(project.progressStage.isEmpty ? project.status.label : project.progressStage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 6)
                    .animation(.easeInOut(duration: 0.25), value: project.progressStage)
            }
        case .failed, .cancelled:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26))
                .foregroundStyle(Theme.danger.opacity(0.8))
        case .succeeded:
            Image(systemName: "film")
                .font(.system(size: 26))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch project.status {
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.success)
                .accessibilityLabel(project.isImageOutput ? "Photo ready" : "Video ready")
        case .queued, .running:
            Text(project.status.label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.warning)
                .lineLimit(1)
        case .failed:
            Label("Error", systemImage: "exclamationmark.circle.fill")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.danger)
        case .cancelled:
            Text("Cancelled")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
