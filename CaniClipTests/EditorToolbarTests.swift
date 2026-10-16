import XCTest
import SwiftUI
@testable import CaniClip

/// The editor toolbar adapts to the window width, so its keyboard shortcuts must
/// not depend on which layout is showing: each must fire exactly once at every width.
@MainActor
final class EditorToolbarTests: XCTestCase {
    private final class Counter {
        var copy = 0, save = 0, saveAs = 0
        var all: [Int] { [copy, save, saveAs] }
    }

    private static let widths: [CGFloat] = [480, 700, 1100]

    private func key(_ characters: String, keyCode: UInt16, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: keyCode)!
    }

    /// Hosts a fresh editor the way EditorWindowController does and sends one key equivalent.
    @discardableResult
    private func press(_ event: NSEvent, width: CGFloat, counter: Counter = Counter(),
                       prepare: (EditorDocument) -> Void = { _ in }) -> (Bool, EditorDocument) {
        let doc = EditorDocument(image: TestImages.solid(width: 160, height: 100, color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)))
        prepare(doc)
        let host = EditorHostingView(rootView: EditorView(document: doc, actions: EditorActions(
            copy: { counter.copy += 1 }, save: { counter.save += 1 }, saveAs: { counter.saveAs += 1 })))
        host.frame = CGRect(x: 0, y: 0, width: width, height: 420)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        // Windows made in code free themselves on close by default; under ARC that
        // over-releases and crashes the test host.
        window.isReleasedWhenClosed = false
        window.contentView = host
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let handled = host.performKeyEquivalent(with: event)
        window.close()
        return (handled, doc)
    }

    func testCommandsMatchOnlyTheirExactModifiers() {
        XCTAssertEqual(EditorCommand(key("z", keyCode: 6, [.command])), .undo)
        // A real keyboard reports Shift-Z as "Z".
        XCTAssertEqual(EditorCommand(key("Z", keyCode: 6, [.command, .shift])), .redo)
        XCTAssertEqual(EditorCommand(key("z", keyCode: 6, [.command, .shift])), .redo)
        XCTAssertEqual(EditorCommand(key("C", keyCode: 8, [.command, .shift])), .copy)
        XCTAssertEqual(EditorCommand(key("s", keyCode: 1, [.command])), .save)
        XCTAssertEqual(EditorCommand(key("S", keyCode: 1, [.command, .shift])), .saveAs)
        XCTAssertEqual(EditorCommand(key("s", keyCode: 1, [.command, .capsLock])), .save)
        // Plain ⌘C stays with text fields; extra modifiers are someone else's shortcut.
        XCTAssertNil(EditorCommand(key("c", keyCode: 8, [.command])))
        XCTAssertNil(EditorCommand(key("s", keyCode: 1, [.command, .option])))
        XCTAssertNil(EditorCommand(key("z", keyCode: 6, [.control])))
    }

    func testCopyShortcutFiresOnceAtEveryWidth() {
        for width in Self.widths {
            let counter = Counter()
            XCTAssertTrue(press(key("C", keyCode: 8, [.command, .shift]), width: width, counter: counter).0)
            XCTAssertEqual(counter.all, [1, 0, 0], "⇧⌘C at \(width)")
        }
    }

    func testSaveShortcutFiresOnceAtEveryWidth() {
        for width in Self.widths {
            let counter = Counter()
            XCTAssertTrue(press(key("s", keyCode: 1, [.command]), width: width, counter: counter).0)
            XCTAssertEqual(counter.all, [0, 1, 0], "⌘S at \(width)")
        }
    }

    func testSaveAsShortcutFiresOnceAtEveryWidth() {
        for width in Self.widths {
            let counter = Counter()
            XCTAssertTrue(press(key("S", keyCode: 1, [.command, .shift]), width: width, counter: counter).0)
            XCTAssertEqual(counter.all, [0, 0, 1], "⇧⌘S at \(width)")
        }
    }

    func testUndoAndRedoShortcutsWorkAtEveryWidth() {
        let addOne: (EditorDocument) -> Void = { $0.add(Annotation(kind: .rect(CGRect(x: 10, y: 10, width: 40, height: 30)))) }
        for width in Self.widths {
            let (undone, afterUndo) = press(key("z", keyCode: 6, [.command]), width: width, prepare: addOne)
            XCTAssertTrue(undone)
            XCTAssertEqual(afterUndo.annotations.count, 0, "⌘Z at \(width)")
            let (redone, afterRedo) = press(key("Z", keyCode: 6, [.command, .shift]), width: width) { doc in
                addOne(doc)
                doc.undoManager.undo()
            }
            XCTAssertTrue(redone)
            XCTAssertEqual(afterRedo.annotations.count, 1, "⇧⌘Z at \(width)")
        }
    }

    func testOtherKeyEquivalentsAreLeftAlone() {
        let counter = Counter()
        let (handled, _) = press(key("w", keyCode: 13, [.command]), width: 700, counter: counter)
        XCTAssertFalse(handled)
        XCTAssertEqual(counter.all, [0, 0, 0])
    }
}
