# CaniClip Capture Hub — Design Spec

Date: 2026-10-15
Status: Draft for review
Builds on: `2026-10-15-caniclip-design.md` (v1, merged to main)

## 1. Purpose

v1 is a menu bar app with no window of its own. The capture hub gives CaniClip a face: a real window with large capture actions and a browsable history of everything captured, so past screenshots and GIFs are findable and recoverable without digging through the save folder.

Success looks like this:

- Choose "Open CaniClip" from the menu (or launch for the first time) and see a window with three big capture tiles and a grid of recent captures.
- A screenshot copied to the clipboard an hour ago, never saved, can be reopened in the editor from the hub.
- Hover a card to copy, reveal, reopen or delete it; double-click opens it.
- While the hub is open the app has a Dock icon and menus; close it and the app is a menu bar item again.

## 2. Library (data)

### 2.1 Storage

```
~/Library/Application Support/CaniClip/Library/
  index.json                 [CaptureRecord], newest first
  assets/<id>.png            library copy of a screenshot (original pixels at capture)
  thumbs/<id>.jpg            thumbnail, long side 480 px, JPEG quality 0.8
```

Screenshots are copied into `assets/` at capture time so clipboard-only shots and ones closed without saving stay recoverable. GIFs are not duplicated: the record points at the saved file (or the kept temp file when the save folder was unwritable) and only a thumbnail of the first frame is stored.

### 2.2 Model

```swift
enum CaptureKindRecord: String, Codable { case screenshot, gif }

struct CaptureRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: CaptureKindRecord
    let createdAt: Date
    var pixelWidth: Int
    var pixelHeight: Int
    var fileSizeBytes: Int64          // of savedPath if present, else of the library asset
    var savedPath: String?            // where the user saved it; nil for clipboard-only
    var hasLibraryAsset: Bool         // assets/<id>.png exists (screenshots only)
    var durationSeconds: Double?      // gifs
    var frameCount: Int?              // gifs
}
```

`CaptureRecord` computed helpers: `bestFileURL` (savedPath if the file exists, else the library asset), `thumbnailURL`.

### 2.3 Store

```swift
@MainActor
final class CaptureLibrary: ObservableObject {
    @Published private(set) var records: [CaptureRecord]   // newest first
    init(rootURL: URL)                                      // tests pass a temp dir
    static let shared: CaptureLibrary                       // Application Support root

    @discardableResult func addScreenshot(_ image: CGImage) throws -> CaptureRecord
    @discardableResult func addGif(url: URL, summary: GifSummary, pixelSize: CGSize) throws -> CaptureRecord
    func markSaved(id: UUID, to url: URL, annotated: CGImage?) throws   // updates savedPath, size, thumbnail
    func delete(id: UUID) throws                                        // record + library files only
    func prune(olderThan days: Int, now: Date = Date()) throws          // 0 = keep forever
    func image(for id: UUID) -> CGImage?                                // loads the library asset
}
```

Writes are atomic: `index.json` is written to a temp file and renamed. Thumbnail generation runs synchronously on the main actor for v1 (images are already in memory; a 480 px downscale is a few milliseconds). Errors are surfaced to the caller; the capture flows treat a library failure as non-fatal: they log it and continue delivering the capture as v1 does today.

### 2.4 Retention

New preference `historyRetentionDays: Int` with options 7, 30, 90 and 0 (forever); default 30. `prune` runs at launch and after each addition. Pruning deletes the record, asset and thumbnail; never the user's saved file.

## 3. Hub window

### 3.1 Structure

`HubWindowController` (NSWindowController) hosting SwiftUI `HubView`, default size 900×600, minimum 640×420, remembers frame via `setFrameAutosaveName`. Title "CaniClip". Toolbar: a gear button opening Settings and an "Open Save Folder" button.

`HubView` layout:

1. **Action row**: three `ActionTile`s — Capture Area, Capture Full Screen, Record GIF — each with an SF Symbol, title and the live shortcut string from `KeyboardShortcuts.getShortcut(for:)`. Clicking runs the same coordinator path as the hotkey. The hub window hides itself before a selection overlay appears and comes back after the capture finishes, so it never ends up in its own screenshot and never blocks the drag.
2. **Filter bar**: segmented control All / Screenshots / GIFs; a count label on the right.
3. **Grid**: `LazyVGrid` of `CaptureCard`s, adaptive columns of 200–260 pt. Card: thumbnail with fixed 16:10 frame and `.fill` scaling, a kind badge (camera or film symbol) in the corner, below it relative time ("2 min ago") and pixel size × file size. Hover shows an action strip: Open (screenshots), Copy, Reveal, Delete. Context menu offers the same. Double-click opens. Keyboard: Delete removes the selected card after a confirmation sheet; Return opens it.
4. **Empty state**: a centred illustration-free message listing the three shortcuts.

### 3.2 View model

```swift
@MainActor
final class HubViewModel: ObservableObject {
    enum Filter: CaseIterable { case all, screenshots, gifs }
    @Published var filter: Filter = .all
    @Published var selection: UUID?
    var visibleRecords: [CaptureRecord]            // library records after filter
    func sectionTitle(for date: Date, now: Date) -> String   // Today / Yesterday / This Week / Earlier
    static func relativeTime(_ date: Date, now: Date) -> String
}
```

Actions are closures injected by the coordinator so the view model stays testable without AppKit.

### 3.3 Actions

- **Open**: screenshots load `library.image(for:)` (or the saved file if the asset is gone) into a new editor; the editor keeps the record id so Save calls `markSaved`. GIFs open in the default app via `NSWorkspace`.
- **Copy**: screenshots put the image on the pasteboard (annotated saved file if present, else the original asset); GIFs copy the file URL.
- **Reveal**: `activateFileViewerSelecting` on `bestFileURL`; disabled when no file exists on disk.
- **Delete**: confirmation sheet "Remove from history? The file in your save folder is not affected." then `library.delete`.

## 4. Dock, menus and launch

- `LSUIElement` stays true. Opening the hub calls `NSApp.setActivationPolicy(.regular)` and activates the app; when the last hub window closes the policy returns to `.accessory`. Editor and settings windows do not change the policy.
- `MainMenu` gains a **File** menu: Capture Area, Capture Full Screen, Record GIF (with their shortcuts shown via `setShortcut(for:)`), separator, Open CaniClip (⌘0). The App menu gains "Settings…" (⌘,).
- Status item menu gains "Open CaniClip" as the first enabled item.
- First launch (no `hasLaunchedBefore` flag) opens the hub automatically; later launches do not. Preference "Open window at launch" (default off) overrides this.
- Clicking the Dock icon while the hub is closed reopens it (`applicationShouldHandleReopen`).

## 5. Data flow

Capture (hotkey, menu, hub tile) → coordinator → image or GIF → `CaptureLibrary.add…` (non-fatal on failure) → existing delivery (editor / clipboard / save / popover) → editor Save → `markSaved`. The hub observes `library.records` and re-renders.

## 6. Error handling

- Library root unwritable: log once, show a one-time alert "History is unavailable" with the path, and continue capturing without history.
- Missing asset or saved file for a record: card shows a "file missing" badge; Open and Reveal are disabled; Delete works.
- Thumbnail generation failure: record is kept with a placeholder thumbnail.

## 7. Testing

- `CaptureLibraryTests` (temp root): addScreenshot writes asset + thumbnail + index; addGif stores only a thumbnail; markSaved updates path, size and thumbnail; delete removes files; prune removes only old records and never touches a saved path; index round-trips across a second `CaptureLibrary` instance; records are newest first.
- `HubViewModelTests`: filter, section titles across day boundaries, relative time strings.
- `PreferencesTests`: new retention key defaults and normalisation (allowed values only).
- Smoke test additions: open hub from menu and first launch; tiles capture and the hub hides during the overlay; cards reopen, copy, reveal, delete; Dock icon appears and disappears; Dock click reopens; retention setting prunes.

## 8. Milestones

1. Library model, store, thumbnails, retention (tests).
2. Wire into coordinator and editor; retention preference in Settings.
3. Hub window, view model, cards, actions, Dock policy, menus, first-launch behaviour.
4. Smoke test pass and polish.

## 9. Out of scope

Search, tags or renaming in the hub; cloud sync; editing GIFs; importing existing files from the save folder; multiple libraries.
