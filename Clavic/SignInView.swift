//
//  SignInView.swift
//  Clavic
//
//  Anmelde-Gate nach dem Onboarding (vor der Paywall). Stil wie in gängigen
//  Apps: großes Beispiel-Visual oben, darunter ein Bottom-Sheet mit
//  „Sign in with Apple". Die Anmeldung nutzt den Apple-Account (iCloud).
//

import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Binding var isSignedIn: Bool

    @State private var showError = false
    @State private var legalDocument: LegalDocument?

    private let example: OnboardingExample = .slider(
        before: "preview_glowup_swap_before",
        after: "preview_glowup_swap_after"
    )

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            // Beispiel-Visual oben
            VStack(spacing: 0) {
                ExampleCardView(example: example, corner: 28)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 18)
                    .padding(.top, 70)
                Spacer(minLength: 0)
            }

            sheet
        }
        .preferredColorScheme(.light)
        .sheet(item: $legalDocument) { doc in
            LegalTextView(document: doc)
        }
        .alert("Couldn't sign in", isPresented: $showError) {
            Button("Try again", role: .cancel) {}
        } message: {
            Text("Please try signing in again to continue.")
        }
    }

    // MARK: - Bottom-Sheet

    private var sheet: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Theme.textTertiary.opacity(0.5))
                .frame(width: 38, height: 5)
                .padding(.top, 10)

            Text("Sign in to finish setup")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 4)

            SignInWithAppleButton(.continue) { _ in
                // Keine zusätzlichen Scopes nötig.
            } onCompletion: { result in
                handle(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
            .padding(.top, 4)

            VStack(spacing: 2) {
                Text("By continuing, you agree to our")
                    .foregroundStyle(Theme.textTertiary)
                HStack(spacing: 4) {
                    Button("Terms of Use") { legalDocument = .terms }
                        .foregroundStyle(Theme.accent)
                    Text("and").foregroundStyle(Theme.textTertiary)
                    Button("Privacy Policy") { legalDocument = .privacy }
                        .foregroundStyle(Theme.accent)
                }
            }
            .font(.system(size: 12))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 28,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 28,
                style: .continuous
            )
            .fill(Theme.background)
            .shadow(color: .black.opacity(0.12), radius: 20, y: -6)
        )
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Apple Sign-in

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success:
            withAnimation { isSignedIn = true }
        case .failure(let error):
            // Abbruch durch den Nutzer → auf dem Screen bleiben.
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            // Andere Fehler (z. B. fehlende Capability im Dev-Build) sollen den
            // Nutzer nicht aussperren – weiter zur App/Paywall.
            withAnimation { isSignedIn = true }
        }
    }
}
