//
//  Theme.swift
//  Clavic
//
//  Zentrales Design-System (Light Mode): Farben, Abstände, Komponenten-Stile.
//

import SwiftUI

enum Theme {

    // MARK: - Farben

    /// Seitenhintergrund – exakt der Weißton aus dem Intro-Video (#F1F1F3)
    static let background = Color(red: 0.945, green: 0.945, blue: 0.953)
    /// Karten / erhöhte Flächen
    static let surface = Color.white
    /// Chips / Eingabefelder
    static let surfaceHigh = Color(red: 0.93, green: 0.93, blue: 0.95)
    /// Feine Trennlinien / Ränder
    static let stroke = Color.black.opacity(0.06)

    static let textPrimary = Color(red: 0.07, green: 0.07, blue: 0.10)
    static let textSecondary = Color.black.opacity(0.55)
    static let textTertiary = Color.black.opacity(0.32)

    /// Marken-Akzent (Blau)
    static let accent = Color(red: 0.16, green: 0.50, blue: 1.0)
    static let accentSoft = Color(red: 0.16, green: 0.50, blue: 1.0).opacity(0.12)

    static let success = Color(red: 0.20, green: 0.72, blue: 0.45)
    static let warning = Color(red: 0.95, green: 0.62, blue: 0.10)
    static let danger = Color(red: 0.95, green: 0.26, blue: 0.30)

    /// Marken-Verlauf für Buttons & Highlights
    static let brandGradient = LinearGradient(
        colors: [
            Color(red: 0.16, green: 0.50, blue: 1.0),
            Color(red: 0.50, green: 0.35, blue: 1.0)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Maße

    static let cornerLarge: CGFloat = 22
    static let cornerMedium: CGFloat = 16
    static let cornerSmall: CGFloat = 12
    static let screenPadding: CGFloat = 18
}

// MARK: - Wiederverwendbare Stile

/// Karten-Hintergrund mit feinem Rand und dezentem Schatten
struct CardBackground: ViewModifier {
    var corner: CGFloat = Theme.cornerMedium

    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }
}

extension View {
    func cardStyle(corner: CGFloat = Theme.cornerMedium) -> some View {
        modifier(CardBackground(corner: corner))
    }
}

/// Cleaner Eingabefeld-Hintergrund mit Fokus-Rahmen (Apple-Stil)
struct InputFieldContainer: ViewModifier {
    var focused: Bool
    var corner: CGFloat = Theme.cornerMedium

    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(focused ? Theme.accent : Theme.stroke,
                                  lineWidth: focused ? 2 : 1)
            )
            .shadow(color: .black.opacity(focused ? 0.06 : 0.03), radius: focused ? 8 : 5, y: 3)
            .animation(.easeInOut(duration: 0.18), value: focused)
    }
}

extension View {
    /// Für einzeilige/mehrzeilige `TextField`s: setzt Schrift, Padding und Fokus-Rahmen.
    func inputFieldStyle(focused: Bool) -> some View {
        self
            .font(.system(size: 16))
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 54, alignment: .topLeading)
            .modifier(InputFieldContainer(focused: focused))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
    }

    /// Für Container, die selbst ein Editor-Feld (z. B. `TextEditor`) enthalten.
    func inputFieldContainerStyle(focused: Bool) -> some View {
        modifier(InputFieldContainer(focused: focused))
    }
}

/// Primärer Verlaufs-Button
struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                isEnabled ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color.gray.opacity(0.35)),
                in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// Sekundärer, dezenter Button
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.textPrimary)
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Auswahl-Chip mit Akzent (z. B. Seitenverhältnis, Auflösung)
struct SelectableChip: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
            .padding(.vertical, 9)
            .padding(.horizontal, 14)
            .background(
                isSelected ? AnyShapeStyle(Theme.accentSoft) : AnyShapeStyle(Theme.surfaceHigh),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? Theme.accent.opacity(0.6) : Theme.stroke,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.25), value: isSelected)
    }
}

/// Kategorie-Chip (dunkel ausgewählt, wie auf der Startseite)
struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? .white : Theme.textPrimary)
                .padding(.vertical, 9)
                .padding(.horizontal, 16)
                .background(
                    isSelected ? AnyShapeStyle(Theme.textPrimary) : AnyShapeStyle(Theme.surface),
                    in: Capsule()
                )
                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: isSelected ? 0 : 1))
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.25), value: isSelected)
    }
}

/// Abschnitts-Überschrift in Formularen
struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
