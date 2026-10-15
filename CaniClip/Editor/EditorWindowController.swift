import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let editorDocument: EditorDocument
    private let preferences: PreferencesStore
    var onClose: (() -> Void)?

    init(image: CGImage, preferences: PreferencesStore) {
        self.editorDocument = EditorDocument(image: image)
        self.preferences = preferences

        let screenFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let maxSize = CGSize(width: screenFrame.width * 0.8, height: screenFrame.height * 0.8 - 44)
        let natural = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let fit = min(1, maxSize.width / natural.width, maxSize.height / natural.height)
        let content = CGSize(width: max(480, natural.width * fit), height: max(320, natural.height * fit + 44))

        let window = NSWindow(contentRect: CGRect(origin: .zero, size: content),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Screenshot"
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 480, height: 320)
        super.init(window: window)
        window.delegate = self

        let root = EditorView(document: editorDocument, actions: EditorActions(
            copy: { [weak self] in self?.copyToClipboard() },
            save: { [weak self] in self?.saveReportingErrors() },
            saveAs: { [weak self] in self?.saveAs() }
        ))
        window.contentView = NSHostingView(rootView: root)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Actions

    func copyToClipboard() {
        guard let image = editorDocument.rasterize() else { return }
        ImageExporter.copyToClipboard(image)
    }

    /// Saves to the last saved location, or a new timestamped file in the preferred folder.
    @discardableResult
    func save() throws -> URL {
        guard let image = editorDocument.rasterize() else { throw ExportError.encodingFailed }
        let url = editorDocument.lastSavedURL
            ?? FileNamer.uniqueURL(in: preferences.preferences.saveFolderURL, ext: "png")
        try ImageExporter.writePNG(image, to: url)
        editorDocument.markSaved(to: url)
        return url
    }

    private func saveReportingErrors() {
        do {
            try save()
        } catch {
            ErrorPresenter.present(error, title: "Could not save")
            saveAs()
        }
    }

    func saveAs() {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = FileNamer.fileName(ext: "png")
        panel.directoryURL = preferences.preferences.saveFolderURL
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            guard let image = self.editorDocument.rasterize() else { return }
            do {
                try ImageExporter.writePNG(image, to: url)
                self.editorDocument.markSaved(to: url)
            } catch {
                ErrorPresenter.present(error, title: "Could not save")
            }
        }
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard editorDocument.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save your annotated screenshot?"
        alert.informativeText = "Your annotations will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            do { try save(); return true } catch {
                ErrorPresenter.present(error, title: "Could not save")
                return false
            }
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
