//
//  Notifications.swift
//  Clavic
//
//  Lokale Mitteilungen: „Dein Video ist fertig". Generierungen dauern
//  2–5 Minuten — Nutzer wechseln währenddessen die App. Die Notification
//  holt sie zurück, sobald das Ergebnis da ist (oder fehlgeschlagen ist).
//
//  Erlaubnis wird erst beim Start der ERSTEN Generierung angefragt —
//  in dem Moment wartet der Nutzer auf ein Ergebnis und versteht sofort,
//  wofür die Mitteilung gut ist (höhere Opt-in-Rate als beim App-Start).
//

import Foundation
import UserNotifications
import UIKit

@MainActor
enum Notifier {
    /// Fragt einmalig nach Erlaubnis (nur solange der Status „notDetermined" ist).
    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    /// Meldet ein fertiges/fehlgeschlagenes Ergebnis — nur wenn die App gerade
    /// NICHT im Vordergrund ist (im Vordergrund sieht der Nutzer es in der UI).
    static func generationFinished(templateTitle: String, success: Bool, isImage: Bool) {
        guard UIApplication.shared.applicationState != .active else { return }

        let what = isImage ? "image" : "video"
        let name = templateTitle.isEmpty ? "Your \(what)" : templateTitle
        let content = UNMutableNotificationContent()
        if success {
            content.title = "\(name) is ready 🎉"
            content.body = "Your \(what) just finished — open Clavic to watch, save and share it."
        } else {
            content.title = "\(name) didn’t finish"
            content.body = "Something went wrong and your credits were refunded. Tap to try again."
        }
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
