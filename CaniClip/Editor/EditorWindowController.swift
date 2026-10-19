import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum UnsavedChoice {
    case save, discard, cancel
}

@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let editorDocument: EditorDocument
    private let preferences: PreferencesStore
    var onClose: (() -> Void)?
    /// Reports every successful save (URL and rasterised image) so history can follow it.
    var onSaved: ((URL, CGImage) -> Void)?

    /// Asks the user what to do with unsaved annotations. Replaceable for tests.
    var unsavedPrompt: () -> UnsavedChoice = {
        let alert = NSAlert()
        alert.messageText = "Save your annotated screenshot?"
        alert.informativeText = "Your annotations will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertSecondButtonReturn: return .discard
        default: return .cancel
        }
    }

    /// Window content size for an image, and how much the image is shrunk to fit
    /// 80% of the screen. Images are shown like screenshots: pixels / screen scale.
    static func layout(imagePixels: CGSize, scale: CGFloat, screen: CGRect) -> (content: CGSize, fit: CGFloat) {
        let maxSize = CGSize(width: screen.width * 0.8, height: screen.height * 0.8 - 44)
        let natural = CGSize(width: imagePixels.width / scale, height: imagePixels.height / scale)
        let fit = min(1, maxSize.width / natural.width, maxSize.height / natural.height)
        let content = CGSize(width: max(480, natural.width * fit), height: max(320, natural.height * fit + 44))
        return (content, fit)
    }

    /// `scalesStyleToFit`: imported images get annotation sizes scaled to the fit;
    /// screenshots keep the defaults.
    init(image: CGImage, preferences: PreferencesStore, title: String = "Screenshot", scalesStyleToFit: Bool = false) {
        let screenFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let layout = Self.layout(imagePixels: CGSize(width: image.width, height: image.height), scale: scale, screen: screenFrame)
        // A whole-number scale keeps stroke widths on the toolbar's menu steps.
        let styleScale = scalesStyleToFit ? max(1, (1 / layout.fit).rounded()) : 1
        self.editorDocument = EditorDocument(image: image, styleScale: styleScale)
        self.preferences = preferences

        let window = NSWindow(contentRect: CGRect(origin: .zero, size: layout.content),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 480, height: 320)
        super.init(window: window)
        window.delegate = self

        let root = EditorView(document: editorDocument, actions: EditorActions(
            copy: { [weak self] in self?.copyToClipboard() },
            save: { [weak self] in self?.saveReportingErrors() },
            saveAs: { [weak self] in self?.saveAs() }
        ))
        window.contentView = EditorHostingView(rootView: root)
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
        onSaved?(url, image)
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
                self.onSaved?(url, image)
            } catch {
                ErrorPresenter.present(error, title: "Could not save")
            }
        }
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        confirmClose()
    }

    /// True when the window may close: clean, saved on request, or discarded.
    /// Shared by the close button and app termination so ⌘Q cannot bypass it.
    func confirmClose() -> Bool {
        guard editorDocument.isDirty else { return true }
        switch unsavedPrompt() {
        case .save:
            do { try save(); return true } catch {
                ErrorPresenter.present(error, title: "Could not save")
                return false
            }
        case .discard:
            return true
        case .cancel:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
