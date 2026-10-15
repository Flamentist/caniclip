import XCTest
@testable import CaniClip

@MainActor
final class ErrorPresenterTests: XCTestCase {
    private struct Boom: LocalizedError {
        let errorDescription: String? = "boom"
    }

    override func tearDown() {
        ErrorPresenter.handler = ErrorPresenter.alertHandler
    }

    func testASecondAlertIsNotStackedWhileOneIsUp() {
        var shown: [String] = []
        ErrorPresenter.handler = { _, title in
            shown.append(title)
            // A modal alert pumps the run loop, so another failure can try to
            // present while this one is still up.
            if title == "first" {
                ErrorPresenter.present(Boom(), title: "second")
            }
        }
        ErrorPresenter.present(Boom(), title: "first")
        XCTAssertEqual(shown, ["first"], "the nested presentation must not stack a second modal")
    }

    func testPresentingWorksAgainAfterTheAlertIsDismissed() {
        var shown: [String] = []
        ErrorPresenter.handler = { _, title in shown.append(title) }
        ErrorPresenter.present(Boom(), title: "first")
        ErrorPresenter.present(Boom(), title: "second")
        XCTAssertEqual(shown, ["first", "second"])
    }
}
