import AppKit
import KeyboardShortcuts

/// Target for main-menu items; the delegate keeps one instance alive.
final class MenuActions: NSObject {
    var captureArea: () -> Void = {}
    var captureFullScreen: () -> Void = {}
    var recordArea: () -> Void = {}
    var openHub: () -> Void = {}
    var openSettings: () -> Void = {}
    var openFile: () -> Void = {}
    var pasteImage: () -> Void = {}

    @objc func captureAreaAction(_ sender: Any?) { captureArea() }
    @objc func captureFullScreenAction(_ sender: Any?) { captureFullScreen() }
    @objc func recordAreaAction(_ sender: Any?) { recordArea() }
    @objc func openHubAction(_ sender: Any?) { openHub() }
    @objc func openSettingsAction(_ sender: Any?) { openSettings() }
    @objc func openFileAction(_ sender: Any?) { openFile() }
    @objc func pasteImageAction(_ sender: Any?) { pasteImage() }
}

/// The main menu is visible only while the hub is open (regular activation
/// policy); its key equivalents work in every window at all times.
enum MainMenu {
    static func install(actions: MenuActions) {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(MenuActions.openSettingsAction(_:)), keyEquivalent: ",")
        settings.target = actions
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit CaniClip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let file = NSMenu(title: "File")
        let area = file.addItem(withTitle: "Capture Area", action: #selector(MenuActions.captureAreaAction(_:)), keyEquivalent: "")
        area.target = actions
        area.setShortcut(for: .captureArea)
        let full = file.addItem(withTitle: "Capture Full Screen", action: #selector(MenuActions.captureFullScreenAction(_:)), keyEquivalent: "")
        full.target = actions
        full.setShortcut(for: .captureFullScreen)
        let record = file.addItem(withTitle: "Record GIF", action: #selector(MenuActions.recordAreaAction(_:)), keyEquivalent: "")
        record.target = actions
        record.setShortcut(for: .recordArea)
        file.addItem(.separator())
        let open = file.addItem(withTitle: "Open…", action: #selector(MenuActions.openFileAction(_:)), keyEquivalent: "o")
        open.target = actions
        let paste = file.addItem(withTitle: "New from Clipboard", action: #selector(MenuActions.pasteImageAction(_:)), keyEquivalent: "v")
        paste.keyEquivalentModifierMask = [.command, .shift]
        paste.target = actions
        file.addItem(.separator())
        let hub = file.addItem(withTitle: "Open CaniClip", action: #selector(MenuActions.openHubAction(_:)), keyEquivalent: "0")
        hub.target = actions
        fileItem.submenu = file
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }
}
