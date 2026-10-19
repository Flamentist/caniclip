import Foundation

struct HubActions {
    var captureArea: () -> Void
    var captureFullScreen: () -> Void
    var recordArea: () -> Void
    var openSettings: () -> Void
    var openSaveFolder: () -> Void
    var openRecord: (CaptureRecord) -> Void
    var copyRecord: (CaptureRecord) -> Void
    var revealRecord: (CaptureRecord) -> Void
    var deleteRecord: (CaptureRecord) -> Void
    var openFile: () -> Void = {}
    var pasteImage: () -> Void = {}
    var openURLs: ([URL]) -> Void = { _ in }
    var openImageData: (Data) -> Void = { _ in }
}
