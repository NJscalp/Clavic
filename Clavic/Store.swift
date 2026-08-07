//
//  Store.swift
//  Clavic
//
//  Monetarisierung mit StoreKit 2:
//   • Clavic Pro (Abo, wöchentlich/jährlich) → unbegrenzte Generierungen
//   • Credit-Packs (einmalig) → Guthaben aufladen
//  Free-Nutzer zahlen pro Video Credits (Kosten = Dauer in Sekunden).
//
//  Hinweis: Für Tests im Simulator muss im Schema unter
//  „Run › Options › StoreKit Configuration" die Datei „Products.storekit"
//  ausgewählt sein.
//

import Foundation
import StoreKit

enum StoreIDs {
    static let weekly = "Clavic.W"
    static let yearly = "Clavic.Y"
    // Credit-Packs. Die Produkt-IDs heißen historisch .10/.30/.75, die
    // gewährte Credit-Menge ist aber großzügiger gestaffelt (siehe creditPacks).
    // Auch nach 30 % Apple + AI-Kosten bleiben ~52–58 % Marge.
    static let credits10 = "Clavic.10"
    static let credits30 = "Clavic.30"
    static let credits75 = "Clavic.75"

    static let subscriptions: Set<String> = [weekly, yearly]
    // Pro Produkt-ID die gewährte Credit-Menge. FAIRE Bulk-Preise (mehr Credits
    // als die Abos pro $), trotzdem profitabel selbst wenn der User ALLE Credits
    // ins teuerste Template (Fruit Story / Veo) steckt:
    //   $24,99→40 (~$0,62/cr) · $69,99→110 (~$0,64/cr) · $135,99→220 (~$0,62/cr).
    static let creditPacks: [String: Int] = [credits10: 40, credits30: 110, credits75: 220]
    static let all: [String] = [weekly, yearly, credits10, credits30, credits75]

    /// Credits, die ein Abo pro Abrechnungszeitraum gutschreibt (1 Credit = 1 Video).
    static let subscriptionCredits: [String: Int] = [weekly: 10, yearly: 150]
}

enum StoreError: Error {
    case failedVerification
    /// Credit-Packs nur mit aktivem Abo kaufbar.
    case subscriptionRequired
}

@Observable
@MainActor
final class Store {
    static let creditsKey = "clavic.credits"
    static let grantedTxKey = "clavic.grantedTransactions"
    /// Willkommens-Credits für neue Nutzer (einmalig nach Anmeldung).
    static let welcomeCredits = 3
    static let defaultCredits = 0
    static let welcomeGrantedKey = "clavic.welcomeCreditsGranted"

    private(set) var products: [Product] = []
    private(set) var isPro = false
    private(set) var isLoadingProducts = false

    /// Verbleibendes Guthaben. Wird persistiert.
    var credits: Int {
        didSet { UserDefaults.standard.set(credits, forKey: Self.creditsKey) }
    }

    /// IDs bereits gutgeschriebener Abo-Transaktionen (verhindert Doppel-Gutschrift).
    private var grantedTransactionIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.grantedTxKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.grantedTxKey) }
    }

    private var updatesTask: Task<Void, Never>?

    init() {
        self.credits = UserDefaults.standard.object(forKey: Self.creditsKey) as? Int ?? Self.defaultCredits
        updatesTask = listenForTransactions()
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    // MARK: - Produkte

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: StoreIDs.all)
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            products = []
        }
    }

    /// Lädt Produkte und Entitlements erneut (z. B. „Retry" in der Paywall).
    func reload() async {
        await loadProducts()
        await refreshEntitlements()
    }

    var subscriptions: [Product] {
        products.filter { $0.type == .autoRenewable }.sorted { $0.price < $1.price }
    }

    /// Alias für Paywall — Weekly + Yearly.
    var mainSubscriptions: [Product] { subscriptions }

    var creditPacks: [Product] {
        products.filter { $0.type == .consumable }.sorted { $0.price < $1.price }
    }

    // MARK: - Kauf

    @discardableResult
    func purchase(_ product: Product) async throws -> Bool {
        guard canPurchase(product) else {
            throw StoreError.subscriptionRequired
        }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            // Erst Entitlement/Credits verarbeiten (setzt isPro) – das darf NIE
            // von RevenueCat abhängen oder durch dessen Netzwerk blockiert werden.
            await handle(transaction)
            await transaction.finish()
            // Kauf an RevenueCat melden – nicht-blockierend.
            Task { await RevenueCatManager.record(result) }
            // Revenue-Event an AppsFlyer (→ TikTok ROAS-Postback).
            AppsFlyerEventTracker.trackSubscriptionPurchase(.init(
                value: NSDecimalNumber(decimal: product.price).doubleValue,
                currency: transaction.currency?.identifier ?? Locale.current.currency?.identifier ?? "USD",
                productId: product.id,
                plan: product.id,
                transactionId: String(transaction.id)
            ))
            return true
        case .userCancelled, .pending:
            Task { await RevenueCatManager.record(result) }
            return false
        @unknown default:
            return false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    // MARK: - Entitlements

    func refreshEntitlements() async {
        var pro = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if StoreIDs.subscriptions.contains(transaction.productID) {
                pro = true
            }
        }
        isPro = pro
    }

    private func handle(_ transaction: Transaction) async {
        if StoreIDs.subscriptions.contains(transaction.productID) {
            // Abo: Credits jede Abrechnungsperiode (Kauf + jede Verlängerung).
            if let amount = StoreIDs.subscriptionCredits[transaction.productID] {
                grantCredits(amount, for: transaction)
            }
            // Direkt aus der verifizierten Transaktion freischalten. NICHT über
            // refreshEntitlements gehen – `Transaction.currentEntitlements` meldet
            // einen frischen Kauf teils verzögert und würde isPro fälschlich auf
            // false zurücksetzen (Paywall bliebe stehen).
            let active = transaction.revocationDate == nil
                && (transaction.expirationDate.map { $0 > .now } ?? true)
            isPro = active
        } else if let amount = StoreIDs.creditPacks[transaction.productID] {
            // Credit-Pack: Credits bei jedem Kauf. Jeder Kauf hat eine eigene
            // Transaction-ID → beim nächsten Kauf wird erneut gutgeschrieben.
            grantCredits(amount, for: transaction)
        }
    }

    /// Schreibt Credits genau einmal pro Transaktion gut. Verhindert
    /// Doppel-Gutschrift, falls dieselbe Transaktion erneut zugestellt wird
    /// (z. B. nach App-Neustart vor `finish()`), erlaubt aber jeden neuen Kauf
    /// und jede Abo-Verlängerung (eigene Transaction-ID).
    private func grantCredits(_ amount: Int, for transaction: Transaction) {
        let key = String(transaction.id)
        guard !grantedTransactionIDs.contains(key) else { return }
        credits += amount
        grantedTransactionIDs.insert(key)
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { continue }
                if let transaction = try? await self.checkVerifiedAsync(result) {
                    await self.handle(transaction)
                    // Verlängerungen/aktualisierte Transaktionen an RevenueCat melden.
                    RevenueCatManager.record(productID: transaction.productID)
                    await transaction.finish()
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    private nonisolated func checkVerifiedAsync<T>(_ result: VerificationResult<T>) async throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Credit-Logik

    /// Kosten einer Generierung: 1 Credit pro Video (unabhängig von der Dauer).
    func cost(forDuration duration: Int) -> Int { 1 }

    /// Generieren ist nur mit aktivem Abo möglich (Credit-Packs laden nur Guthaben auf).
    var canCreate: Bool { isPro }

    /// Credit-Packs nur mit aktivem Abo kaufbar.
    var canPurchaseCredits: Bool { isPro }

    func canPurchase(_ product: Product) -> Bool {
        if StoreIDs.creditPacks[product.id] != nil {
            return isPro
        }
        return true
    }

    /// Kann der Nutzer eine Generierung mit diesen Kosten starten?
    func canAfford(_ cost: Int) -> Bool { credits >= cost }

    /// Einmalige Willkommens-Credits nach der ersten Anmeldung.
    func grantWelcomeCreditsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.welcomeGrantedKey) else { return }
        credits += Self.welcomeCredits
        UserDefaults.standard.set(true, forKey: Self.welcomeGrantedKey)
    }

    /// Zieht Credits ab.
    func consume(_ cost: Int) {
        credits = max(0, credits - cost)
    }

    /// Erstattet Credits zurück (z. B. bei fehlgeschlagener Generierung).
    func refund(_ cost: Int) {
        credits += cost
    }
}
