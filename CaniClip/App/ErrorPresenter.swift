import AppKit

enum ErrorPresenter {
    /// How errors reach the user. Tests replace this to observe presentations
    /// without a modal alert.
    @MainActor static var handler: (Error, String) -> Void = alertHandler

    @MainActor
    static let alertHandler: (Error, String) -> Void = { error, title in
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// True while a handler is running. `runModal` pumps the run loop, so a
    /// second failure can arrive while the first alert is still up; stacking
    /// a second modal on top would leave the user with two alerts to dismiss.
    @MainActor private(set) static var isPresenting = false

    @MainActor
    static func present(_ error: Error, title: String) {
        guard !isPresenting else {
            NSLog("ErrorPresenter: dropped \"%@\" while another alert is up: %@", title, error.localizedDescription)
            return
        }
        isPresenting = true
        defer { isPresenting = false }
        handler(error, title)
    }
}
