import XCTest
import SwiftUI
import UniformTypeIdentifiers
@testable import CaniClip

@MainActor
final class HubImportTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("caniclip-hub-import-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func key(_ characters: String, keyCode: UInt16, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: keyCode)!
    }

    /// Hosts the hub like HubWindowController does and sends one key equivalent.
    private func press(_ event: NSEvent, pastes: inout Int) -> Bool {
        var count = 0
        var actions = HubActions(captureArea: {}, captureFullScreen: {}, recordArea: {}, openSettings: {}, openSaveFolder: {},
                                 openRecord: { _ in }, copyRecord: { _ in }, revealRecord: { _ in }, deleteRecord: { _ in })
        actions.pasteImage = { count += 1 }
        let host = HubHostingView(rootView: HubView(viewModel: HubViewModel(library: CaptureLibrary(rootURL: root)), actions: actions))
        host.frame = CGRect(x: 0, y: 0, width: 760, height: 520)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let handled = host.performKeyEquivalent(with: event)
        window.close()
        pastes = count
        return handled
    }

    func testCommandVInTheHubPastes() {
        var pastes = 0
        XCTAssertTrue(press(key("v", keyCode: 9, [.command]), pastes: &pastes))
        XCTAssertEqual(pastes, 1)
    }

    func testOtherKeysPassThrough() {
        var pastes = 0
        XCTAssertFalse(press(key("w", keyCode: 13, [.command]), pastes: &pastes))
        XCTAssertFalse(press(key("v", keyCode: 9, [.command, .shift]), pastes: &pastes))
        XCTAssertEqual(pastes, 0)
    }

    private func load(_ providers: [NSItemProvider]) -> HubDrop.Content? {
        let done = expectation(description: "drop loaded")
        var result: HubDrop.Content?
        HubDrop.load(providers) { content in
            result = content
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return result
    }

    func testDropOfAFileURLLoadsURLs() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("drop.png")
        try ImageExporter.writePNG(TestImages.solid(width: 4, height: 4, color: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)), to: url)
        XCTAssertEqual(load([NSItemProvider(object: url as NSURL)]), .urls([url]))
    }

    func testDropOfImageDataLoadsData() throws {
        let png = try ImageExporter.pngData(from: TestImages.solid(width: 4, height: 4, color: CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)))
        let provider = NSItemProvider(item: png as NSData, typeIdentifier: UTType.png.identifier)
        XCTAssertEqual(load([provider]), .data(png))
    }

    func testStatusMenuHasOpenAndPasteItems() throws {
        var opened = 0, pasted = 0
        var actions = StatusMenuActions(captureArea: {}, captureFullScreen: {}, recordArea: {}, openHub: {}, openSettings: {}, quit: {})
        actions.openImage = { opened += 1 }
        actions.pasteImage = { pasted += 1 }
        let status = StatusItemController(actions: actions)
        let open = try XCTUnwrap(status.menuItem(titled: "Open Image…"))
        let paste = try XCTUnwrap(status.menuItem(titled: "Paste Image"))
        NSApp.sendAction(try XCTUnwrap(open.action), to: open.target, from: open)
        NSApp.sendAction(try XCTUnwrap(paste.action), to: paste.target, from: paste)
        XCTAssertEqual([opened, pasted], [1, 1])
    }

    func testFileMenuHasOpenAndNewFromClipboard() throws {
        let previous = NSApp.mainMenu
        defer { NSApp.mainMenu = previous }
        MainMenu.install(actions: MenuActions())
        let file = try XCTUnwrap(NSApp.mainMenu?.items.first { $0.submenu?.title == "File" }?.submenu)
        let open = try XCTUnwrap(file.item(withTitle: "Open…"))
        XCTAssertEqual(open.keyEquivalent, "o")
        XCTAssertEqual(open.keyEquivalentModifierMask, [.command])
        let paste = try XCTUnwrap(file.item(withTitle: "New from Clipboard"))
        XCTAssertEqual(paste.keyEquivalent, "v")
        XCTAssertEqual(paste.keyEquivalentModifierMask, [.command, .shift])
    }
}
