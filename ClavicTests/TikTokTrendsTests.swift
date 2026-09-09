import XCTest
@testable import Clavic

final class TikTokTrendsTests: XCTestCase {
    func testUnreviewedTemplatesCannotReappearAsTrends() {
        let unreviewed = DirectorAPI.Option(id: "sunsetbeach", label: "Viral sunset",
            caption: "", mode: .grade, prompt: "Replace everything", preview: "https://example.com/photo.jpg")
        let result = TikTokTrends.options(ranked: [unreviewed])
        XCTAssertEqual(result.map(\.id), ["g7xflash", "goldenhour", "redsunset", "y2kdigicam", "redlight", "bluehour"])
        XCTAssertFalse(result.contains { $0.preview?.hasPrefix("http") == true })
    }

    func testLegacyIDKeepsRankingButUsesPairedPreviewAndReviewedRecipe() {
        let old = DirectorAPI.Option(id: "sunlitglow", label: "Old title", caption: "",
            mode: .grade, prompt: "Unrelated scene", preview: "old_image", isBestMatch: true)
        let result = TikTokTrends.options(ranked: [old, old])
        XCTAssertEqual(result.first?.id, "goldenhour")
        XCTAssertEqual(result.first?.preview, "trend_goldenhour_after")
        XCTAssertEqual(result.first?.isBestMatch, true)
        XCTAssertEqual(Set(result.map(\.id)).count, 6)
        XCTAssertFalse(result.first!.prompt.contains("Unrelated scene"))
    }

    func testRestagingDoesNotInheritAPhotoFilterRecommendation() {
        let wrong = DirectorAPI.Option(id: "g7xflash", label: "", caption: "",
            mode: .restage, prompt: "", preview: nil, isBestMatch: true)
        XCTAssertFalse(TikTokTrends.options(ranked: [wrong]).contains(where: \.isBestMatch))
    }

    func testEachPreviewIsADistinctAlignedImagePair() throws {
        for look in TikTokTrends.all {
            let before = try XCTUnwrap(UIImage(named: look.before))
            let after = try XCTUnwrap(UIImage(named: look.after))
            XCTAssertEqual(before.size, after.size, look.title)
            XCTAssertEqual(before.size.width / before.size.height, 0.75, accuracy: 0.001)
            XCTAssertNotEqual(before.pngData(), after.pngData(), "\(look.title) must show an actual edit")
        }
    }

    func testAnimationShowsBothCompletePhotosAndReturnsSmoothly() {
        XCTAssertEqual(TrendPhotoPreview.progress(at: 0), 0)
        XCTAssertEqual(TrendPhotoPreview.progress(at: 1.9), 0)
        XCTAssertEqual(TrendPhotoPreview.progress(at: 3), 0.5)
        XCTAssertEqual(TrendPhotoPreview.progress(at: 4), 1)
        XCTAssertEqual(TrendPhotoPreview.progress(at: 5.9), 1)
        XCTAssertEqual(TrendPhotoPreview.progress(at: 7), 0.5)
        XCTAssertEqual(TrendPhotoPreview.progress(at: 8), 0)
    }
}
