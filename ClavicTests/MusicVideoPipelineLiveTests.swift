//
//  MusicVideoPipelineLiveTests.swift
//  ClavicTests
//
//  Live-Durchlauf der Musikvideo-Pipeline (echtes Backend → Seedance → fal →
//  AVFoundation-Merge). Verbraucht echte Provider-Credits, daher als eigener,
//  bewusst gestarteter Test. Das Ergebnis wird in den Test-Temp-Ordner
//  geschrieben (= host-erreichbarer Pfad unter CoreSimulator) und der Pfad
//  ausgegeben, damit man das Video prüfen kann.
//

import XCTest
import AVFoundation
@testable import Clavic

@MainActor
final class MusicVideoPipelineLiveTests: XCTestCase {

    func testMusicVideoPipelineLive() async throws {
        guard ProcessInfo.processInfo.environment["CLAVIC_RUN_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Set CLAVIC_RUN_LIVE_TESTS=1 to run this credit-consuming backend test.")
        }

        // Testfoto aus dem Test-Bundle laden.
        let bundle = Bundle(for: type(of: self))
        guard let photoURL = bundle.url(forResource: "clav_face", withExtension: "jpg"),
              let photo = try? Data(contentsOf: photoURL) else {
            throw XCTSkip("Testfoto clav_face.jpg nicht im Test-Bundle gefunden.")
        }

        // Prompt aus dem echten Template ziehen.
        guard let template = TemplateLibrary.all.first(where: { $0.useMusicLipSync }) else {
            return XCTFail("Musikvideo-Template (useMusicLipSync) nicht gefunden.")
        }

        // Kompletter Durchlauf der echten iOS-Pipeline.
        let outURL = try await MusicVideoPipeline.run(
            key: template.musicVideoKey,
            prompt: template.prompt,
            photoJPEG: photo
        ) { stage in
            print("PIPELINE_STAGE: \(stage)")
        }

        // Ergebnis prüfen.
        XCTAssertTrue(FileManager.default.fileExists(atPath: outURL.path), "Kein Ergebnis-Video erzeugt.")
        let asset = AVURLAsset(url: outURL)
        let durationTime: CMTime = try await asset.load(.duration)
        let duration = durationTime.seconds
        let hasAudio = try await !asset.loadTracks(withMediaType: AVMediaType.audio).isEmpty
        let hasVideo = try await !asset.loadTracks(withMediaType: AVMediaType.video).isEmpty

        print("PIPELINE_OUTPUT_PATH: \(outURL.path)")
        print("PIPELINE_OUTPUT_DURATION: \(duration)")
        print("PIPELINE_OUTPUT_HAS_AUDIO: \(hasAudio)")
        print("PIPELINE_OUTPUT_HAS_VIDEO: \(hasVideo)")

        XCTAssertGreaterThan(duration, 8.0, "Video sollte die volle Länge (~11 s) haben, nicht nur 5 s.")
        XCTAssertTrue(hasAudio, "Ergebnis sollte den Original-Song als Audiospur enthalten.")
        XCTAssertTrue(hasVideo, "Ergebnis sollte eine Videospur enthalten.")
    }
}
