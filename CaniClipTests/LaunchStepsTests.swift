import XCTest
@testable import CaniClip

final class LaunchStepsTests: XCTestCase {
    private let photo = URL(fileURLWithPath: "/tmp/photo.png")

    /// A file opened from Finder at launch must end up in front of the hub.
    func testFilesOpenAfterTheHubSoTheyEndUpInFront() {
        XCTAssertEqual(LaunchSteps.order(openHub: true, pendingFiles: [photo]), [.openHub, .openFiles([photo])])
    }

    func testNothingPendingOnlyOpensTheHubWhenAsked() {
        XCTAssertEqual(LaunchSteps.order(openHub: true, pendingFiles: []), [.openHub])
        XCTAssertEqual(LaunchSteps.order(openHub: false, pendingFiles: []), [])
        XCTAssertEqual(LaunchSteps.order(openHub: false, pendingFiles: [photo]), [.openFiles([photo])])
    }
}
