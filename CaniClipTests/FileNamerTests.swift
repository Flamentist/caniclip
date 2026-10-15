import XCTest
@testable import CaniClip

final class FileNamerTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_792_000_323) // 2026-10-14 17:52:03 UTC

    func testFileNameFollowsPattern() {
        let name = FileNamer.fileName(date: date, ext: "png", timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(name, "CaniClip 2026-10-14 at 17.52.03.png")
    }

    func testUniqueURLAppendsCounterWhenFileExists() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = FileNamer.uniqueURL(in: folder, date: date, ext: "gif", timeZone: TimeZone(identifier: "UTC")!)
        try Data().write(to: first)
        let second = FileNamer.uniqueURL(in: folder, date: date, ext: "gif", timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(second.lastPathComponent, "CaniClip 2026-10-14 at 17.52.03 2.gif")
        try Data().write(to: second)
        let third = FileNamer.uniqueURL(in: folder, date: date, ext: "gif", timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(third.lastPathComponent, "CaniClip 2026-10-14 at 17.52.03 3.gif")
    }
}
