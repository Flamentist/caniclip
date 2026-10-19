import AppKit

struct StatusMenuActions {
    var captureArea: () -> Void
    var captureFullScreen: () -> Void
    var recordArea: () -> Void
    var openHub: () -> Void
    var openSettings: () -> Void
    var quit: () -> Void
    var openImage: () -> Void = {}
    var pasteImage: () -> Void = {}
}

enum StatusMenuTag: Int {
    case captureArea = 1
    case captureFullScreen
    case recordArea
}

/// Owns the NSStatusItem. Left click opens the menu, except while recording,
/// when the icon is a red dot and a click stops the recording.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let actions: StatusMenuActions
    private let menu = NSMenu()
    private(set) var isRecording = false
    var onStopRecordingClicked: (() -> Void)?

    var button: NSStatusBarButton? { statusItem.button }

    init(actions: StatusMenuActions) {
        self.actions = actions
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        buildMenu()
        updateIcon()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(buttonClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    func menuItem(for tag: StatusMenuTag) -> NSMenuItem? {
        menu.item(withTag: tag.rawValue)
    }

    func menuItem(titled title: String) -> NSMenuItem? {
        menu.item(withTitle: title)
    }

    func setRecording(_ recording: Bool) {
        isRecording = recording
        updateIcon()
    }

    private func buildMenu() {
        menu.autoenablesItems = false
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let about = NSMenuItem(title: "CaniClip \(shortVersion) · core \(coreVersion())", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        menu.addItem(.separator())
        menu.addItem(makeItem("Capture Area", #selector(captureArea), tag: .captureArea))
        menu.addItem(makeItem("Capture Full Screen", #selector(captureFullScreen), tag: .captureFullScreen))
        menu.addItem(makeItem("Record GIF", #selector(recordArea), tag: .recordArea))
        menu.addItem(makeItem("Open Image…", #selector(openImage), tag: nil))
        menu.addItem(makeItem("Paste Image", #selector(pasteImage), tag: nil))
        menu.addItem(.separator())
        let hub = makeItem("Open CaniClip", #selector(openHub), tag: nil)
        hub.keyEquivalent = "0"
        menu.addItem(hub)
        let settings = makeItem("Settings…", #selector(openSettings), tag: nil)
        settings.keyEquivalent = ","
        menu.addItem(settings)
        let quit = makeItem("Quit CaniClip", #selector(quit), tag: nil)
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func makeItem(_ title: String, _ selector: Selector, tag: StatusMenuTag?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        if let tag { item.tag = tag.rawValue }
        return item
    }

    private func updateIcon() {
        let image: NSImage?
        if isRecording {
            image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "CaniClip")
        } else {
            image = NSImage(named: "MenuBarIcon")
            image?.size = NSSize(width: 18, height: 18)
            image?.isTemplate = true
            image?.accessibilityDescription = "CaniClip"
        }
        statusItem.button?.image = image
        statusItem.button?.contentTintColor = isRecording ? .systemRed : nil
    }

    @objc private func buttonClicked() {
        if isRecording {
            onStopRecordingClicked?()
            return
        }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func captureArea() { actions.captureArea() }
    @objc private func captureFullScreen() { actions.captureFullScreen() }
    @objc private func recordArea() { actions.recordArea() }
    @objc private func openImage() { actions.openImage() }
    @objc private func pasteImage() { actions.pasteImage() }
    @objc private func openHub() { actions.openHub() }
    @objc private func openSettings() { actions.openSettings() }
    @objc private func quit() { actions.quit() }
}
