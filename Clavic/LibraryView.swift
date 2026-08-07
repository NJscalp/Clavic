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

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

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

                    LazyVGrid(columns: columns, alignment: .center, spacing: 12) {
                        ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                            NavigationLink(value: project) {
                                // Nummerierung chronologisch: älteste = #1.
                                ProjectCard(project: project, number: projects.count - index)
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
            Text("Pick a template in Discover or tap\nthe wand below to start creating.")
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
    var number: Int = 1

    /// Name des genutzten Templates (Fallback für freie Generierungen).
    private var displayName: String {
        project.templateTitle.isEmpty ? "Custom video" : project.templateTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnail
            // Feste Höhe → alle Karten sind gleich hoch, auch bei langen Namen
            // (verhindert ungleiche/überlappende Container im Raster).
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("Creation #\(number)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    statusBadge
                    Spacer()
                    Text(project.createdAt, format: .relative(presentation: .named))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                .padding(.top, 2)
            }
            .frame(height: 78, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .cardStyle()
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
    }

    private var thumbnail: some View {
        // Feste 4:3-Kachel, deren Größe von Color.clear (nicht vom Bild) bestimmt
        // wird. So werden ALLE Creations im Raster in der gleichen Standardgröße
        // angezeigt – egal welches Seitenverhältnis das Video hat. Das echte
        // Format sieht man erst beim Öffnen.
        Color.clear
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
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

    private var statusBadge: some View {
        let (color, text): (Color, String) = {
            switch project.status {
            case .queued, .running: return (Theme.warning, project.status.label)
            case .succeeded: return (Theme.success, project.isImageOutput ? "Image" : "\(project.duration)s · \(project.resolution.rawValue)")
            case .failed: return (Theme.danger, "Error")
            case .cancelled: return (Theme.textTertiary, "Cancelled")
            }
        }()

        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
