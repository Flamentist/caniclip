import XCTest
@testable import CaniClip

final class PreferencesTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "caniclip.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testDefaultsMatchSpec() {
        let p = Preferences()
        XCTAssertEqual(p.afterCapture, .openEditor)
        XCTAssertEqual(p.gifFPS, 15)
        XCTAssertEqual(p.gifQuality, 90)
        XCTAssertEqual(p.gifMaxWidth, .w1200)
        XCTAssertTrue(p.showCursorInRecording)
        XCTAssertEqual(p.maxRecordingSeconds, 60)
        XCTAssertFalse(p.launchAtLogin)
    }

    func testRoundTripThroughStore() async throws {
        let defaults = freshDefaults()
        let store = await PreferencesStore(defaults: defaults, key: "prefs")
        var p = Preferences()
        p.gifFPS = 20
        p.afterCapture = .copyToClipboard
        await MainActor.run { store.preferences = p }
        let reloaded = await PreferencesStore(defaults: defaults, key: "prefs")
        let value = await MainActor.run { reloaded.preferences }
        XCTAssertEqual(value, p)
    }

    func testMissingKeysFallBackToDefaults() throws {
        let json = #"{"gifFPS": 30}"#.data(using: .utf8)!
        let p = try JSONDecoder().decode(Preferences.self, from: json)
        XCTAssertEqual(p.gifFPS, 30)
        XCTAssertEqual(p.gifQuality, 90)
        XCTAssertEqual(p.afterCapture, .openEditor)
    }

    func testGifMaxWidthValue() {
        XCTAssertEqual(GifMaxWidth.w800.maxWidthValue, 800)
        XCTAssertNil(GifMaxWidth.original.maxWidthValue)
    }
}
