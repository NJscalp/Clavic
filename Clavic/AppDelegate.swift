//
//  AppDelegate.swift
//  Clavic
//
//  Bindet das AppsFlyer-SDK in den App-Lifecycle (Install-Attribution, Session-
//  Start, Deeplinks, Conversion-Daten) und steuert die ATT-Abfrage. Wird über
//  `@UIApplicationDelegateAdaptor` in `ClavicApp` eingehängt.
//

import UIKit
import AppTrackingTransparency

#if canImport(AppsFlyerLib)
import AppsFlyerLib
#endif

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if AppsFlyerEventTracker.configureFromInfoPlist() {
            AppsFlyerEventTracker.setDelegate(self)
            AppsFlyerEventTracker.markAppFirstOpenPendingIfNeeded()
            AppsFlyerEventTracker.registerSessionListener(launchOptions: launchOptions)
        }
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        AppsFlyerEventTracker.notifyAppDidBecomeActive()
        AppsFlyerEventTracker.notifyATTResolvedIfNeeded()
        AdTracking.requestAuthorizationIfAppropriate()
    }

    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        AppsFlyerEventTracker.handleOpenURL(url, options: options)
        return true
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        AppsFlyerEventTracker.handleUserActivity(userActivity)
        return true
    }
}

#if canImport(AppsFlyerLib)
extension AppDelegate: AppsFlyerLibDelegate {
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        AppsFlyerEventTracker.applyConversionData(conversionInfo)
    }
    func onConversionDataFail(_ error: Error) {
        print("AppsFlyer conversion data failed: \(error.localizedDescription)")
    }
}
#endif

/// ATT-Abfrage (App Tracking Transparency). Wird erst nach dem Onboarding
/// gezeigt (in-context), damit Apple sie akzeptiert und die Opt-in-Rate steigt.
enum AdTracking {
    private static var requestedThisSession = false

    /// Vom App-Code aufrufen, sobald das Onboarding abgeschlossen ist
    /// (z. B. beim Erscheinen der Paywall) – oder automatisch bei becomeActive.
    static func requestAuthorizationIfAppropriate() {
        guard #available(iOS 14, *) else { return }
        // Erst nach Onboarding fragen (Apple-Vorgabe: in-context).
        guard UserDefaults.standard.bool(forKey: "hasSeenOnboarding") else { return }
        #if DEBUG
        // UI-Review (Simulator): ATT-Dialog unterdrücken, damit Screens frei sind.
        if ProcessInfo.processInfo.environment["UITEST_SKIP_ATT"] != nil { return }
        #endif

        let status = ATTrackingManager.trackingAuthorizationStatus
        if status != .notDetermined {
            AppsFlyerEventTracker.notifyATTResolvedIfNeeded()
            return
        }
        guard !requestedThisSession else { return }
        guard UIApplication.shared.applicationState == .active else { return }
        requestedThisSession = true

        ATTrackingManager.requestTrackingAuthorization { _ in
            AppsFlyerEventTracker.notifyATTResolved()
        }
    }
}
