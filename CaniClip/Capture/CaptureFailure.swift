import Foundation
import ScreenCaptureKit

enum CaptureFailure {
    /// True when ScreenCaptureKit refused because Screen Recording access is not
    /// (yet) effective. This is the ordinary first-run case: the user granted
    /// access in the system dialog, but macOS applies it only after a relaunch.
    static func isPermissionDenied(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == SCStreamErrorDomain && ns.code == SCStreamError.Code.userDeclined.rawValue
    }
}
