//
//  AppsFlyerEventTracker.swift
//  Clavic
//
//  AppsFlyer-Attribution + In-App-Events für Ad-Tracking (TikTok Ads Manager
//  via AppsFlyer als MMP). Sendet Install/Open/Onboarding/Paywall/Purchase an
//  AppsFlyer; AppsFlyer leitet die Postbacks (inkl. Revenue/ROAS) an den im
//  AppsFlyer-Dashboard verbundenen TikTok-Channel weiter.
//
//  Der Code ist mit `#if canImport(AppsFlyerLib)` geschützt – ohne das SDK
//  kompiliert er als No-Op (Build bleibt grün, bis das SPM-Paket aktiv ist).
//

import Foundation
import UIKit
import AppTrackingTransparency
import RevenueCat

#if canImport(AppsFlyerLib)
import AppsFlyerLib
#endif

enum AppsFlyerEventTracker {

    struct PurchaseContext {
        let value: Double
        let currency: String
        let productId: String
        let plan: String?
        /// StoreKit-2-Transaktions-ID → Dedup + TikTok/AppsFlyer-Order-Matching.
        var transactionId: String?
    }

    private static let customerUserIdKey = "appsflyer.customerUserId.v1"
    private static let lastSyncedAppsFlyerUIDKey = "appsflyer.lastSyncedUID.v1"
    private static let appFirstOpenTrackedKey = "appsflyer.appFirstOpenTracked.v1"
    private static let pendingAppFirstOpenKey = "appsflyer.pendingAppFirstOpen.v1"
    private static let trackedTransactionIdsKey = "appsflyer.trackedTransactionIds.v1"
    private static let maxTrackedTransactionIds = 64

    private enum Event {
        static let completeRegistration = "af_complete_registration"
        static let contentView = "af_content_view"
        static let initiatedCheckout = "af_initiated_checkout"
        static let subscribe = "af_subscribe"
        static let purchase = "af_purchase"
    }

    private enum Param {
        static let revenue = "af_revenue"
        static let currency = "af_currency"
        static let contentId = "af_content_id"
        static let contentType = "af_content_type"
    }

    #if canImport(AppsFlyerLib)
    private static var isConfigured = false
    private static var hasStarted = false
    private static var hasRegisteredSessionListener = false
    private static var didLogATTResolution = false
    private static var pendingEvents: [(name: String, values: [String: Any])] = []
    #endif

    // MARK: - SDK-Bootstrap (AppDelegate)

    @discardableResult
    static func configureFromInfoPlist() -> Bool {
        #if canImport(AppsFlyerLib)
        guard
            let info = Bundle.main.infoDictionary,
            let devKey = info["AppsFlyerDevKey"] as? String,
            let appleAppID = info["AppsFlyerAppleAppID"] as? String,
            !devKey.isEmpty,
            !appleAppID.isEmpty
        else {
            print("AppsFlyer not configured: missing Info.plist keys.")
            return false
        }

        let appsFlyer = AppsFlyerLib.shared()
        appsFlyer.appsFlyerDevKey = devKey
        appsFlyer.appleAppID = appleAppID
        if #available(iOS 14, *) {
            // IDFA erst nach ATT — SDK startet trotzdem sofort (Install-Attribution + SKAN).
            appsFlyer.waitForATTUserAuthorization(timeoutInterval: 60)
        }
        appsFlyer.disableSKAdNetwork = false
        #if DEBUG
        appsFlyer.isDebug = true
        #endif

        if let storedCustomerId = UserDefaults.standard.string(forKey: customerUserIdKey),
           !storedCustomerId.isEmpty {
            appsFlyer.customerUserID = storedCustomerId
        }
        isConfigured = true
        return true
        #else
        return false
        #endif
    }

    static func setDelegate(_ delegate: AnyObject) {
        #if canImport(AppsFlyerLib)
        if let afDelegate = delegate as? AppsFlyerLibDelegate {
            AppsFlyerLib.shared().delegate = afDelegate
        }
        #endif
    }

    static func registerSessionListener(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        #if canImport(AppsFlyerLib)
        guard isConfigured else { return }
        // Hinweis: `handleLaunchOptions` gibt es in der aktuellen AppsFlyer-SDK
        // (SPM) nicht mehr und ist nicht nötig – der Start läuft über start()
        // und die Deep-Link-Handler (handleOpen / continueUserActivity).
        _ = launchOptions
        registerStartListenerIfNeeded()
        startIfNeeded()
        #endif
    }

    static func notifyAppDidBecomeActive() {
        #if canImport(AppsFlyerLib)
        guard isConfigured else { return }
        registerStartListenerIfNeeded()
        startIfNeeded()
        #endif
    }

    /// Nach ATT (Allow/Deny): SDK auffrischen.
    static func notifyATTResolved() {
        #if canImport(AppsFlyerLib)
        guard isConfigured else { return }
        registerStartListenerIfNeeded()
        startIfNeeded(force: true)
        if !didLogATTResolution {
            didLogATTResolution = true
            print("AppsFlyer: ATT resolved — SDK refreshed.")
        }
        #endif
    }

    static func notifyATTResolvedIfNeeded() {
        #if canImport(AppsFlyerLib)
        guard isConfigured else { return }
        guard #available(iOS 14, *) else { notifyATTResolved(); return }
        guard ATTrackingManager.trackingAuthorizationStatus != .notDetermined else { return }
        notifyATTResolved()
        #endif
    }

    static func ensureSDKStarted() {
        #if canImport(AppsFlyerLib)
        guard isConfigured, !hasStarted else { return }
        registerStartListenerIfNeeded()
        startIfNeeded(force: true)
        #endif
    }

    /// Kauf darf nie an ATT-Deferral hängen — sonst landen Revenue-Events in der Queue.
    static func prepareForRevenueTracking() {
        #if canImport(AppsFlyerLib)
        guard isConfigured else { return }
        registerStartListenerIfNeeded()
        startIfNeeded(force: true)
        syncRevenueCatAppsFlyerIDIfNeeded()
        if Purchases.isConfigured {
            Purchases.shared.attribution.collectDeviceIdentifiers()
        }
        #endif
    }

    #if canImport(AppsFlyerLib)
    private static func registerStartListenerIfNeeded() {
        // Die aktuelle AppsFlyer-SDK (SPM) hat keinen `registerSessionReadyListener`
        // mehr – der Start erfolgt direkt über `startIfNeeded()`. No-op beibehalten,
        // damit die Aufrufstellen unverändert bleiben.
        guard !hasRegisteredSessionListener else { return }
        hasRegisteredSessionListener = true
    }
    #endif

    static func handleOpenURL(_ url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) {
        #if canImport(AppsFlyerLib)
        guard isConfigured else { return }
        AppsFlyerLib.shared().handleOpen(url, options: options)
        #endif
    }

    static func handleUserActivity(_ userActivity: NSUserActivity) {
        #if canImport(AppsFlyerLib)
        guard isConfigured else { return }
        AppsFlyerLib.shared().continue(userActivity, restorationHandler: nil)
        #endif
    }

    // MARK: - Customer ID (RevenueCat App-User-ID)

    static func setCustomerUserID(_ userID: String) {
        let trimmed = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: customerUserIdKey)
        #if canImport(AppsFlyerLib)
        guard isConfigured else { return }
        AppsFlyerLib.shared().customerUserID = trimmed
        if hasStarted { syncRevenueCatAppsFlyerIDIfNeeded() }
        #endif
    }

    static func syncRevenueCatAppsFlyerIDIfNeeded() {
        #if canImport(AppsFlyerLib)
        let syncBlock = {
            guard Purchases.isConfigured else { return }
            let uid = AppsFlyerLib.shared().getAppsFlyerUID()
            guard !uid.isEmpty else { return }
            guard UserDefaults.standard.string(forKey: lastSyncedAppsFlyerUIDKey) != uid else { return }
            UserDefaults.standard.set(uid, forKey: lastSyncedAppsFlyerUIDKey)
            Purchases.shared.attribution.setAppsflyerID(uid)
        }
        if Thread.isMainThread { syncBlock() } else { DispatchQueue.main.async(execute: syncBlock) }
        #endif
    }

    static func applyConversionData(_ conversionInfo: [AnyHashable: Any]) {
        logConversionSummary(conversionInfo)
        #if canImport(AppsFlyerLib)
        let applyBlock = {
            guard Purchases.isConfigured else { return }
            Purchases.shared.attribution.setAppsFlyerConversionData(conversionInfo)
            syncRevenueCatAppsFlyerIDIfNeeded()
        }
        if Thread.isMainThread { applyBlock() } else { DispatchQueue.main.async(execute: applyBlock) }
        #endif
    }

    private static func logConversionSummary(_ conversionInfo: [AnyHashable: Any]) {
        let mediaSource = (conversionInfo["media_source"] as? String) ?? "unknown"
        let campaign = (conversionInfo["campaign"] as? String) ?? "unknown"
        let afStatus = (conversionInfo["af_status"] as? String) ?? "unknown"
        print("AppsFlyer attribution: media_source=\(mediaSource), campaign=\(campaign), af_status=\(afStatus)")
    }

    // MARK: - Lifecycle / Funnel-Events

    static func markAppFirstOpenPendingIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: appFirstOpenTrackedKey) else { return }
        UserDefaults.standard.set(true, forKey: pendingAppFirstOpenKey)
    }

    static func trackAppFirstOpenIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: appFirstOpenTrackedKey) else { return }
        UserDefaults.standard.set(true, forKey: appFirstOpenTrackedKey)
        UserDefaults.standard.set(false, forKey: pendingAppFirstOpenKey)
        logEvent("app_first_open")
        logEvent("af_app_opened")
    }

    static func trackAppOpened() { logEvent("af_app_opened") }

    static func trackOnboardingComplete() {
        ensureSDKStarted()
        logEvent(Event.completeRegistration)
        logEvent("onboarding_complete")
    }

    static func trackPaywallView(plan: String? = nil) {
        prepareForRevenueTracking()
        var values: [String: Any] = [:]
        if let plan { values[Param.contentType] = plan }
        logEvent(Event.contentView, values: values)
        logEvent("paywall_view", values: values)
    }

    static func trackCheckoutInitiated(_ purchase: PurchaseContext) {
        prepareForRevenueTracking()
        logEvent(Event.initiatedCheckout, values: purchaseValues(purchase))
    }

    /// `af_subscribe` + `af_purchase` (Revenue) → AppsFlyer → TikTok-Postbacks (ROAS).
    static func trackSubscriptionPurchase(_ purchase: PurchaseContext) {
        prepareForRevenueTracking()
        if let txId = purchase.transactionId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !txId.isEmpty, hasTrackedTransaction(txId) {
            print("AppsFlyer: skip duplicate purchase event for transaction \(txId)")
            return
        }
        let values = purchaseValues(purchase)
        logEvent(Event.subscribe, values: values)
        logEvent(Event.purchase, values: values)
        if let txId = purchase.transactionId?.trimmingCharacters(in: .whitespacesAndNewlines), !txId.isEmpty {
            markTransactionTracked(txId)
        }
    }

    static func trackSubscriptionRestore(productId: String?, plan: String? = nil) {
        var values: [String: Any] = [:]
        if let productId { values[Param.contentId] = productId }
        if let plan { values[Param.contentType] = plan }
        logEvent("subscription_restore", values: values)
    }

    // MARK: - Privat

    #if canImport(AppsFlyerLib)
    private static func startIfNeeded(force: Bool = false) {
        guard isConfigured else { return }
        let appsFlyer = AppsFlyerLib.shared()
        let isFirstStart = !hasStarted
        // Beim ersten Mal (oder erzwungen) starten. `start()` ist idempotent –
        // die SDK ignoriert weitere Aufrufe innerhalb derselben Session.
        if force || isFirstStart {
            appsFlyer.start()
        }
        hasStarted = true
        flushPendingEvents()
        syncRevenueCatAppsFlyerIDIfNeeded()
        if isFirstStart {
            if UserDefaults.standard.bool(forKey: pendingAppFirstOpenKey),
               !UserDefaults.standard.bool(forKey: appFirstOpenTrackedKey) {
                trackAppFirstOpenIfNeeded()
            } else {
                trackAppOpened()
            }
        }
    }

    private static func flushPendingEvents() {
        guard !pendingEvents.isEmpty else { return }
        let queued = pendingEvents
        pendingEvents.removeAll()
        for event in queued {
            AppsFlyerLib.shared().logEvent(event.name, withValues: event.values)
        }
    }
    #endif

    private static func purchaseValues(_ purchase: PurchaseContext) -> [String: Any] {
        var values: [String: Any] = [
            Param.revenue: purchase.value,
            Param.currency: purchase.currency.uppercased(),
            Param.contentId: purchase.productId,
            "af_quantity": 1,
        ]
        if let plan = purchase.plan { values[Param.contentType] = plan }
        if let txId = purchase.transactionId?.trimmingCharacters(in: .whitespacesAndNewlines), !txId.isEmpty {
            values["af_order_id"] = txId
        }
        return values
    }

    private static func hasTrackedTransaction(_ id: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: trackedTransactionIdsKey) ?? []).contains(id)
    }

    private static func markTransactionTracked(_ id: String) {
        var tracked = UserDefaults.standard.stringArray(forKey: trackedTransactionIdsKey) ?? []
        guard !tracked.contains(id) else { return }
        tracked.append(id)
        if tracked.count > maxTrackedTransactionIds { tracked = Array(tracked.suffix(maxTrackedTransactionIds)) }
        UserDefaults.standard.set(tracked, forKey: trackedTransactionIdsKey)
    }

    private static func logEvent(_ name: String, values: [String: Any] = [:]) {
        #if canImport(AppsFlyerLib)
        guard isConfigured else { return }
        guard hasStarted else {
            pendingEvents.append((name: name, values: values))
            return
        }
        AppsFlyerLib.shared().logEvent(name, withValues: values)
        print("AppsFlyer event: \(name)")
        #endif
    }
}
