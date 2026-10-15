import AppKit
import SwiftUI

@MainActor
final class QuickAccessPresenter {
    private let statusItem: StatusItemController
    private var popover: NSPopover?
    private var dismissTask: Task<Void, Never>?

    init(statusItem: StatusItemController) {
        self.statusItem = statusItem
    }

    func show(output: RecordingController.Output) {
        guard let button = statusItem.button else { return }
        dismissTask?.cancel()
        popover?.performClose(nil)

        let size = ByteCountFormatter.string(fromByteCount: Int64(output.summary.fileSizeBytes), countStyle: .file)
        let seconds = String(format: "%.1f s", output.summary.durationSecs)
        let detail = "\(size) · \(output.summary.frameCount) frames · \(seconds) · copied to clipboard"
        let view = QuickAccessView(
            thumbnail: NSImage(contentsOf: output.url),
            fileName: output.url.lastPathComponent,
            detail: detail,
            onCopy: { ImageExporter.copyFileToClipboard(output.url) },
            onReveal: { NSWorkspace.shared.activateFileViewerSelecting([output.url]) }
        )
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: view)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = popover

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.popover?.performClose(nil)
            self?.popover = nil
        }
    }
}
