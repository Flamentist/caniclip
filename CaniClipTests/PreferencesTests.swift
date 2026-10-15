import XCTest
import Combine
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
        var mutable = Preferences()
        mutable.gifFPS = 20
        mutable.afterCapture = .copyToClipboard
        let p = mutable
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

    func testNormalizedClampsOutOfRangeValues() {
        var p = Preferences()
        p.gifQuality = 250
        p.gifFPS = 0
        p.maxRecordingSeconds = 1
        let n = p.normalized()
        XCTAssertEqual(n.gifQuality, 100)
        XCTAssertEqual(n.gifFPS, 1)
        XCTAssertEqual(n.maxRecordingSeconds, 5)
        p.gifQuality = 0
        p.gifFPS = 999
        p.maxRecordingSeconds = 10_000
        let m = p.normalized()
        XCTAssertEqual(m.gifQuality, 1)
        XCTAssertEqual(m.gifFPS, 60)
        XCTAssertEqual(m.maxRecordingSeconds, 600)
    }

    func testHistoryDefaultsAndNormalisation() {
        let p = Preferences()
        XCTAssertEqual(p.historyRetentionDays, 30)
        XCTAssertFalse(p.openHubAtLaunch)
        var bad = Preferences()
        bad.historyRetentionDays = 12
        XCTAssertEqual(bad.normalized().historyRetentionDays, 30)
        bad.historyRetentionDays = 0
        XCTAssertEqual(bad.normalized().historyRetentionDays, 0)
        bad.historyRetentionDays = 90
        XCTAssertEqual(bad.normalized().historyRetentionDays, 90)
    }

    func testHistoryKeysDecodeWithDefaultsWhenMissing() throws {
        let json = #"{"gifFPS": 30}"#.data(using: .utf8)!
        let p = try JSONDecoder().decode(Preferences.self, from: json)
        XCTAssertEqual(p.historyRetentionDays, 30)
        XCTAssertFalse(p.openHubAtLaunch)
    }

    func testShowInDockDefaultsOnAndDecodesWhenMissing() throws {
        XCTAssertTrue(Preferences().showInDock)
        let json = #"{"gifFPS": 30}"#.data(using: .utf8)!
        XCTAssertTrue(try JSONDecoder().decode(Preferences.self, from: json).showInDock)
        let off = #"{"showInDock": false}"#.data(using: .utf8)!
        XCTAssertFalse(try JSONDecoder().decode(Preferences.self, from: off).showInDock)
    }
}

@MainActor
final class PreferencesStoreLaunchAtLoginTests: XCTestCase {
    private func makeStore() -> PreferencesStore {
        let defaults = UserDefaults(suiteName: "caniclip.tests.launch.\(UUID().uuidString)")!
        return PreferencesStore(defaults: defaults, key: "prefs")
    }

    func testReconcileOverwritesStalePreferenceWithSystemState() {
        let store = makeStore()
        store.preferences.launchAtLogin = true
        store.reconcileLaunchAtLogin(isEnabled: false)
        XCTAssertFalse(store.preferences.launchAtLogin, "the toggle must follow what the system reports")
        store.reconcileLaunchAtLogin(isEnabled: true)
        XCTAssertTrue(store.preferences.launchAtLogin)
    }

    func testReconcileLeavesMatchingPreferenceUntouched() {
        let store = makeStore()
        store.preferences.launchAtLogin = true
        var changes = 0
        let sub = store.$preferences.dropFirst().sink { _ in changes += 1 }
        store.reconcileLaunchAtLogin(isEnabled: true)
        XCTAssertEqual(changes, 0, "no write when the stored value already matches")
        sub.cancel()
    }

    func testFirstLaunchIsConsumedOnce() {
        let name = "caniclip.tests.firstlaunch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let store = PreferencesStore(defaults: defaults, key: "prefs")
        XCTAssertTrue(store.consumeFirstLaunch())
        XCTAssertFalse(store.consumeFirstLaunch())
        let reloaded = PreferencesStore(defaults: defaults, key: "prefs")
        XCTAssertFalse(reloaded.consumeFirstLaunch(), "the flag persists in the same defaults")
    }
}
