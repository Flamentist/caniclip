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

    @MainActor
    static func present(_ error: Error, title: String) {
        handler(error, title)
    }
}
