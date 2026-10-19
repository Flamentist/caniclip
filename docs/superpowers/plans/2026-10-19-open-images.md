# Open Images Implementation Plan (Part 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open, drop or paste any common image into CaniClip's editor.

**Architecture:** A pure `ImageImporter` turns a file URL, image data or a pasteboard into a normalised `CGImage` plus a title. `CaptureCoordinator` gains import entry points that open the existing editor (titled, with annotation sizes scaled to the window fit), record a history entry, and never disturb a capture in progress. The hub, File menu, menu bar menu, Dock icon and Finder call those entry points.

**Tech Stack:** Swift 6.2 (Swift 5 mode), AppKit, SwiftUI, ImageIO, UniformTypeIdentifiers, XCTest. XcodeGen project (`project.yml`).

**Spec:** `docs/superpowers/specs/2026-10-19-import-images-and-videos-design.md` (Part 1 and "Living alongside captures")

## Global Constraints

- macOS 15+, arm64. No new third-party dependencies; system frameworks only.
- Never write to the file that was opened. Save writes a new PNG to the save folder.
- Imports always open the editor, whatever "After capture" says.
- Oversized images: above 50,000,000 pixels, downscale to 8192 px on the long side. The downscaled image is then the image.
- Sizing like screenshots: pixels divided by the screen scale, fit to 80% of the screen. DPI metadata is ignored.
- Default stroke width (4) and text size (24) scale by 1/fit for imports; screenshots are unchanged.
- An import never changes AppState while it is `.selecting`, `.recording` or `.finishing`.
- No usable image: system beep plus an alert, "There's no image on the clipboard" or "CaniClip can't open this file".
- Extra files beyond the first are ignored silently.
- Windows created in tests set `isReleasedWhenClosed = false`. Pasteboard tests use a private named pasteboard.
- Test command: `xcodebuild test -project CaniClip.xcodeproj -scheme CaniClip -destination 'platform=macOS,arch=arm64' -only-testing:CaniClipTests/<Class>`.

## Review Focus

1. A phone JPEG with EXIF orientation 6 must open upright (pinned in Task 1).
2. Copying a non-image file in Finder puts its *icon* on the clipboard as TIFF. Paste must refuse it, not paste the icon (pinned in Task 1).
3. Grayscale, 16-bit or CMYK images must still render, pixelate and export. The importer normalises to 8-bit sRGB RGBA (pinned in Task 1).
4. Opening a file during a recording must leave the record shortcut able to stop it (pinned in Task 3).
5. Pressing ⌘V in the hub with text on the clipboard must not open an empty editor (pinned in Task 3, via the clipboard error path).

---

### Task 1: ImageImporter

**Files:**
- Create: `CaniClip/Import/ImageImporter.swift`
- Test: `CaniClipTests/ImageImporterTests.swift`

**Interfaces:**
- Produces:
  - `struct ImportedImage { let image: CGImage; let title: String }`
  - `enum ImportError: LocalizedError, Equatable { case noImageOnClipboard; case unreadableFile }`, with the descriptions "There's no image on the clipboard" and "CaniClip can't open this file".
  - `enum ImageImporter`:
    - `static let maxPixels = 50_000_000`
    - `static let maxLongSide = 8192`
    - `static func image(contentsOf url: URL) throws -> ImportedImage` (title = `url.lastPathComponent`)
    - `static func image(from data: Data, title: String) throws -> ImportedImage`
    - `static func image(from pasteboard: NSPasteboard) throws -> ImportedImage` (title "Pasted Image" for data, the file name for a file URL)
    - `static func isImageFile(_ url: URL) -> Bool` (UTType conforms to `.image`)

Decode with `CGImageSourceCreateThumbnailAtIndex(source, 0, options)` using:
- `kCGImageSourceCreateThumbnailFromImageAlways: true`
- `kCGImageSourceCreateThumbnailWithTransform: true` (applies EXIF orientation)
- `kCGImageSourceThumbnailMaxPixelSize`: the long side, or 8192 when width × height > 50,000,000

Then redraw into an 8-bit sRGB `premultipliedLast` context. Pasteboard order:
1. File URLs (`readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])`). If any are present, use the first image file. If none is an image, throw `.noImageOnClipboard`; never fall through to data.
2. `.png`, then `.tiff` data.
3. `NSImage(pasteboard:)`.
4. Otherwise throw `.noImageOnClipboard`.

- [ ] **Step 1: Write the failing tests** in `ImageImporterTests` (helpers write fixtures with `CGImageDestination` into a temp folder; pasteboard via `NSPasteboard(name: .init("caniclip.tests.\(UUID())"))`, released in tearDown):
  - `testOpensAPNGFileWithItsNameAsTitle`: 40×20 PNG → image 40×20, title `"a.png"`.
  - `testAnimatedGIFOpensAsItsFirstFrame`: 2-frame GIF (red then blue, 10×10) → centre pixel red.
  - `testCorruptFileThrowsUnreadable`: bytes `"nope"` saved as `x.png` → `XCTAssertThrowsError`, error == `.unreadableFile`.
  - `testRotatedJPEGOpensUpright`: 40×20 JPEG with `kCGImagePropertyOrientation: 6` → image 20×40.
  - `testOversizedImageIsDownscaledToTheLongSideLimit`: 10000×6000 PNG (60 MP) → width 8192, height 4915 ± 1.
  - `testGrayscaleImageIsNormalisedToRGBA`: 8×8 gray PNG → `bitsPerComponent == 8`, `colorSpace?.model == .rgb`, alpha info `.premultipliedLast`.
  - `testPasteboardFileURLToAnImageWins`: write a file URL to a PNG and unrelated TIFF data → title is the file's name.
  - `testPasteboardPNGDataIsPastedImage`: PNG data only → title `"Pasted Image"`, size matches.
  - `testPasteboardTIFFDataIsAccepted`: TIFF data only → succeeds.
  - `testPasteboardFileURLToANonImageIsRefusedEvenWithIconData`: file URL to `notes.txt` plus TIFF icon data → throws `.noImageOnClipboard`.
  - `testEmptyPasteboardThrowsNoImage`: only a string → throws `.noImageOnClipboard`.
- [ ] **Step 2: Run** `-only-testing:CaniClipTests/ImageImporterTests`. Expected: build failure, `cannot find 'ImageImporter'`.
- [ ] **Step 3: Implement** `CaniClip/Import/ImageImporter.swift` per the interfaces above. Run `xcodegen generate` so the new folder is in the project.
- [ ] **Step 4: Run** the same tests. Expected: 11/11 pass.
- [ ] **Step 5: Commit** `feat(import): load images from files, data and the clipboard`.

### Task 2: Editor sizing, title and style scale

**Files:**
- Modify: `CaniClip/Editor/EditorDocument.swift` (init)
- Modify: `CaniClip/Editor/EditorWindowController.swift:32-58` (init, sizing)
- Modify: `CaniClip/Editor/EditorView.swift` (slider range, stroke menu)
- Test: `CaniClipTests/EditorWindowControllerTests.swift`, `CaniClipTests/EditorDocumentTests.swift`

**Interfaces:**
- Produces:
  - `EditorDocument.init(image: CGImage, styleScale: CGFloat = 1)` and `let styleScale: CGFloat`. The initial style is `strokeWidth = (4 * styleScale).rounded()` and `fontSize = (24 * styleScale).rounded()`.
  - `static func EditorWindowController.layout(imagePixels: CGSize, scale: CGFloat, screen: CGRect) -> (content: CGSize, fit: CGFloat)`. This is today's arithmetic moved out of init: `fit = min(1, maxW/naturalW, maxH/naturalH)`; content is at least 480 × 320, with 44 added for the toolbar.
  - `EditorWindowController.init(image: CGImage, preferences: PreferencesStore, title: String = "Screenshot", scalesStyleToFit: Bool = false)`. When the flag is true, `styleScale = 1 / fit`.
  - In EditorView, the stroke slider's range is `1*s...14*s` (step `s`) and the menu entries are `strokeWidths.map { $0 * s }`. Labels show `Int((width / s).rounded())`, where `s = document.styleScale`.

- [ ] **Step 1: Write the failing tests:**
  - `testLayoutFitsALargeImageToEightyPercentOfTheScreen`: pixels 8000×4000, scale 2, screen 1440×900 → fit == `1152/4000`, content width 1152.
  - `testLayoutKeepsSmallImagesAtFullSize`: 400×200 @2 → fit 1, content 480×320 (minimums).
  - `testImportedEditorUsesItsTitleAndScaledStyle`: 8000×4000 image with `title: "photo.jpg", scalesStyleToFit: true` → `window?.title == "photo.jpg"`, `editorDocument.styleScale > 1`, `style.strokeWidth == (4 * styleScale).rounded()`.
  - `testScreenshotEditorKeepsDefaultStyle`: default init → styleScale 1, strokeWidth 4, fontSize 24.
  - `testSaveNeverWritesToTheOpenedFile`: open via `ImageImporter.image(contentsOf:)` from a temp file whose bytes are recorded; add a rect and save → the returned URL ≠ the original, and the original's bytes are unchanged.
- [ ] **Step 2: Run** `-only-testing:CaniClipTests/EditorWindowControllerTests -only-testing:CaniClipTests/EditorDocumentTests`. Expected: compile errors for `layout`, `title:` and `styleScale`.
- [ ] **Step 3: Implement** the interfaces above. Existing callers keep compiling through the defaults.
- [ ] **Step 4: Run** the same tests plus `EditorToolbarTests`. Expected: all pass.
- [ ] **Step 5: Commit** `feat(editor): titled editors with annotation sizes scaled to the window fit`.

### Task 3: Coordinator import flow

**Files:**
- Modify: `CaniClip/App/CaptureCoordinator.swift` (`openEditor`, new import section)
- Test: `CaniClipTests/CaptureCoordinatorTests.swift`

**Interfaces:**
- Consumes: Task 1 `ImageImporter`, `ImportedImage`, `ImportError`; Task 2 `EditorWindowController.init(image:preferences:title:scalesStyleToFit:)`.
- Produces on `CaptureCoordinator`:
  - `func openImported(_ imported: ImportedImage)` opens the editor with the title and `scalesStyleToFit: true`, then records history with `library.addScreenshot` and `attachRecord`.
  - `func openFiles(_ urls: [URL])` uses the first URL only. A non-image or an unreadable file gets the beep and an alert titled "Could not open".
  - `func pasteImage(from pasteboard: NSPasteboard = .general)` reports failures with the beep and an alert titled "Could not paste".
  - `func showOpenPanel()` uses `NSOpenPanel` with `allowedContentTypes: [.image]`, one file, then calls `openFiles`. It's not unit-tested.
  - `openEditor(_:recordID:)` (and the import path) only transitions to `.editing` when the mode is `.idle` or `.editing`.

- [ ] **Step 1: Write the failing tests** (use `ErrorPresenter.handler` as the existing tests do):
  - `testOpeningAFileOpensATitledEditorAndRecordsHistory`: PNG file → `openEditorCount == 1`, editor window title == file name, `library.records.count == 1`, mode `.editing`.
  - `testPastingWithNoImageReportsAndOpensNothing`: private pasteboard holding a string → `presented == [("Could not paste", "There's no image on the clipboard")]`, `openEditorCount == 0`.
  - `testOpeningANonImageFileReports`: a `.txt` URL → one presented error titled "Could not open", no editor.
  - `testOnlyTheFirstOfSeveralFilesOpens`: two PNG URLs → `openEditorCount == 1`.
  - `testImportDuringARecordingLeavesTheRecordingInCharge`: `appState.transition(to: .recording)`, then open a PNG → mode still `.recording`, `appState.action(for: .areaRecording) == .stopRecording`. Closing the editor leaves the mode `.recording`.
- [ ] **Step 2: Run** `-only-testing:CaniClipTests/CaptureCoordinatorTests`. Expected: compile errors for the new methods.
- [ ] **Step 3: Implement** the interfaces above. The beep is `NSSound.beep()`, before `ErrorPresenter.present`.
- [ ] **Step 4: Run** the same tests. Expected: all pass.
- [ ] **Step 5: Commit** `feat(import): open and paste images into the editor`.

### Task 4: Entry points

**Files:**
- Modify: `CaniClip/App/MainMenu.swift`, `CaniClip/App/StatusItemController.swift`, `CaniClip/App/AppDelegate.swift`
- Modify: `CaniClip/Hub/HubActions.swift`, `CaniClip/Hub/HubView.swift`, `CaniClip/Hub/HubWindowController.swift`, `CaniClip/Hub/ActionTile.swift`
- Modify: `CaniClip/App/CaptureCoordinator.swift` (`hubActions()`)
- Modify: `CaniClip/Resources/Info.plist`
- Update callers in `CaniClipTests` that build `StatusMenuActions` and `HubActions`.
- Test: `CaniClipTests/HubImportTests.swift`

**Interfaces:**
- Consumes: Task 3 `openFiles`, `pasteImage`, `showOpenPanel`, `openImported`; Task 1 `ImageImporter.image(from:title:)`.
- Produces:
  - `MenuActions.openFile` and `.pasteImage` (closures with `@objc` actions). File menu items, after Record GIF and before the separator: **Open…** `⌘O` and **New from Clipboard** `⇧⌘V`.
  - `StatusMenuActions.openImage` and `.pasteImage`. Status menu items after Record GIF: **Open Image…** and **Paste Image**.
  - `HubActions.openFile`, `.pasteImage`, `.openURLs: ([URL]) -> Void` and `.openImageData: (Data) -> Void`.
  - `ActionTile.init(title:symbol:shortcutName:tint:action:)` stays; add `init(title:symbol:shortcutText:tint:action:)` for a fixed label. The hub's fourth tile is **Open**, symbol `photo.badge.plus`, tint `.teal`, text `"⌘O"`.
  - `final class HubHostingView: NSHostingView<HubView>`: `performKeyEquivalent` sends plain ⌘V (exactly `.command`, character "v") to `rootView.actions.pasteImage` and returns true; everything else goes to super. `HubWindowController` uses it.
  - Hub drop: `.onDrop(of: [.fileURL, .image], isTargeted:)` on the whole hub, with a subtle accent overlay while targeted. File URLs go to `openURLs`, otherwise the image data goes to `openImageData`. The provider loading lives in `enum HubDrop { static func load(_ providers: [NSItemProvider], completion: @escaping @MainActor (HubDrop.Content?) -> Void) }`, with `enum Content: Equatable { case urls([URL]), data(Data) }`.
  - `AppDelegate.application(_:open:)` calls `coordinator?.openFiles(urls)`.
  - Info.plist: `CFBundleDocumentTypes` gets one entry with name "Image", `LSItemContentTypes` `[public.image]`, `CFBundleTypeRole` Viewer and `LSHandlerRank` Alternate.

- [ ] **Step 1: Write the failing tests** in `HubImportTests`:
  - `testCommandVInTheHubPastes`: host `HubHostingView` (window with `isReleasedWhenClosed = false`), send a ⌘V keyDown via `performKeyEquivalent` → it returns true and `pasteImage` was called once.
  - `testOtherKeysPassThrough`: ⌘W → returns false, paste not called.
  - `testDropOfAFileURLLoadsURLs`: `NSItemProvider(object: fileURL as NSURL)` → `.urls([fileURL])`.
  - `testDropOfImageDataLoadsData`: `NSItemProvider(item: pngData as NSData, typeIdentifier: UTType.png.identifier)` → `.data(pngData)`.
  - `testStatusMenuHasOpenAndPasteItems`: a `StatusItemController` menu contains the titles "Open Image…" and "Paste Image", and invoking each item's action calls its closure. Add a `menuItem(titled:)` test helper if needed.
  - `testFileMenuHasOpenAndNewFromClipboard`: after `MainMenu.install`, the File menu has "Open…" (key "o") and "New from Clipboard" (key "v", modifiers `[.command, .shift]`).
- [ ] **Step 2: Run** `-only-testing:CaniClipTests/HubImportTests`. Expected: compile errors.
- [ ] **Step 3: Implement** the interfaces above and wire them in `AppDelegate` and `hubActions()`.
- [ ] **Step 4: Run** the full suite. Expected: all pass, 0 failures.
- [ ] **Step 5: Commit** `feat(import): open and paste from the hub, menus, Dock and Finder`.

### Task 5: README and visual check

**Files:**
- Modify: `README.md`; `CaniClipTests/ReadmeAssetTests.swift` (hub render now shows four tiles)
- Regenerate: `docs/media/hub.png`

- [ ] **Step 1: Add** a "📥 Open and paste" section after Annotate:
  - drop or open an image, or `⇧⌘V` / `⌘V` in CaniClip to paste;
  - it opens in the editor;
  - the original is never changed.

  Add rows to the shortcuts table for `⌘O` and `⇧⌘V`.
- [ ] **Step 2: Regenerate the hub image:** `TEST_RUNNER_CANICLIP_README_ASSETS="$PWD/docs/media" xcodebuild test … -only-testing:CaniClipTests/ReadmeAssetTests/testRenderHub`. View `docs/media/hub.png`: four tiles, no truncation.
- [ ] **Step 3: Run** the full suite plus `cd core && cargo test`. Expected: all green.
- [ ] **Step 4: Commit** `docs: open and paste images`.
