import XCTest
@testable import Clavic

/// Der Wurf ist die Geste „hier sind deine Vorschläge" — er läuft zur
/// Begrüßung UND bei jedem neuen Vorschlagssatz. Eine Einmal-Sperre hatte
/// zur Folge, dass ab dem zweiten Mal die Übergabe ausblieb und die Karten
/// unsichtbar hängen blieben. Der Zähler verhindert genau das.
final class ThrowTokenTests: XCTestCase {

    @MainActor
    func testEinNeuerZaehlerstandLoestEinenNeuenWurfAus() {
        let view = MascotPlayerUIView()
        var handoffs = 0
        view.configure(throwURL: URL(fileURLWithPath: "/dev/null"),
                       idleURLs: [],
                       onHandoff: { handoffs += 1 },
                       onThrowFinished: {}, onReady: {})

        view.startThrow(token: 1)
        XCTAssertEqual(view.lastThrowTokenForTesting, 1)

        // Derselbe Stand darf NICHT neu starten — sonst würde updateUIView
        // den laufenden Wurf dauernd von vorn beginnen.
        view.startThrow(token: 1)
        XCTAssertEqual(view.lastThrowTokenForTesting, 1)

        // Ein neuer Stand schon — das war der Fehler.
        view.startThrow(token: 2)
        XCTAssertEqual(view.lastThrowTokenForTesting, 2)
    }

    @MainActor
    func testZaehlerstandNullWirftNicht() {
        let view = MascotPlayerUIView()
        view.configure(throwURL: URL(fileURLWithPath: "/dev/null"),
                       idleURLs: [], onHandoff: {}, onThrowFinished: {}, onReady: {})
        view.startThrow(token: 0)
        XCTAssertEqual(view.lastThrowTokenForTesting, 0)
    }
}
