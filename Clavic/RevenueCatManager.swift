//
//  RevenueCatManager.swift
//  Clavic
//
//  RevenueCat-Anbindung im „Observer Mode": Die Käufe laufen weiterhin über
//  unsere eigene StoreKit-2-Logik (siehe Store.swift), RevenueCat trackt aber
//  zusätzlich Installs/Nutzer („Downloads"), Paywall-Käufe und In-App-Käufe.
//
//  EINRICHTUNG (einmalig):
//   1. RevenueCat-Account: App + Produkte (Clavic.W, Clavic.Y, Clavic.10/30/75)
//      anlegen und mit App Store Connect verbinden (App-spezifisches
//      Shared-Secret in RevenueCat hinterlegen, damit Käufe validiert werden).
//   2. Den „Public SDK Key" (Project → API Keys, beginnt mit „appl_") unten in
//      `RevenueCatConfig.apiKey` eintragen.
//  Solange kein gültiger Key gesetzt ist, bleibt RevenueCat inaktiv – die App
//  funktioniert normal weiter.
//

import Foundation
import StoreKit
import RevenueCat

enum RevenueCatConfig {
    /// RevenueCat SDK Key (im App-Binary einbettbar / „publishable").
    ///
    /// Produktiv-Key (Apple App Store) aus RevenueCat → Clavic → API Keys.
    /// Trackt echte App-Store-Käufe + Downloads im RevenueCat-Dashboard.
    /// (Test-Key war zuvor: "test_…" für den RevenueCat Test Store.)
    static let apiKey = "appl_XgJlswsDexLZsaYEpfGCGmhKpfU"

    /// Nur aktiv, wenn ein echter Key eingetragen wurde (nicht der Platzhalter).
    static var isEnabled: Bool { !apiKey.isEmpty && !apiKey.contains("REPLACE") }
}

enum RevenueCatManager {
    private static var didConfigure = false

    /// Einmalig beim App-Start aufrufen. Konfiguriert RevenueCat im
    /// Observer-Mode (unsere App führt die Käufe selbst über StoreKit 2 aus).
    /// Allein das Konfigurieren legt den (anonymen) Nutzer an → „Downloads"
    /// werden getrackt.
    static func configure() {
        guard !didConfigure, RevenueCatConfig.isEnabled else { return }
        didConfigure = true
        Purchases.logLevel = .warn
        Purchases.configure(
            withAPIKey: RevenueCatConfig.apiKey,
            appUserID: nil,
            purchasesAreCompletedBy: .myApp,
            storeKitVersion: .storeKit2
        )
    }

    /// Meldet das Ergebnis eines StoreKit-2-Kaufs an RevenueCat
    /// (Paywall-Käufe & In-App-Käufe → Tracking/Umsatz).
    static func record(_ result: Product.PurchaseResult) async {
        guard RevenueCatConfig.isEnabled, Purchases.isConfigured else { return }
        _ = try? await Purchases.shared.recordPurchase(result)
    }

    /// Meldet eine bereits abgeschlossene Transaktion anhand der Produkt-ID
    /// (z. B. Abo-Verlängerungen aus `Transaction.updates`).
    static func record(productID: String) {
        guard RevenueCatConfig.isEnabled, Purchases.isConfigured else { return }
        Purchases.shared.recordPurchase(productID: productID) { _, _ in }
    }
}
