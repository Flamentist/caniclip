import XCTest
@testable import CaniClip

@MainActor
final class RecordingControllerTests: XCTestCase {
    func testEmptyEncoderErrorIsRewordedAsTooShort() {
        let mapped = RecordingController.userFacingError(CoreError.Encoding(message: "no frames were added"))
        XCTAssertEqual(mapped.localizedDescription, "Recording was too short to save.")
    }

    func testOtherErrorsPassThroughUnchanged() {
        let error = CoreError.Encoding(message: "gifski failed")
        XCTAssertEqual(RecordingController.userFacingError(error).localizedDescription, error.localizedDescription)
        let stopped = RecordingController.RecordingError.alreadyRecording
        XCTAssertEqual(RecordingController.userFacingError(stopped).localizedDescription, stopped.localizedDescription)
    }
}
