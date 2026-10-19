# Open images and videos in CaniClip

Date: 2026-10-19
Status: draft for approval

## Why

CaniClip only edits what it captured itself. The user wants to bring in pictures
they already have, from a file or the clipboard, and mark them up with the same
editor. They also want to get something useful out of a video they already have:
a still to annotate, or a short GIF to share. This keeps CaniClip's idea, "clip
it, mark it, share it", and doesn't turn it into a video editor.

## Goals

1. **Images:** open, drop or paste any common image and land in the editor.
2. **Video still:** open a video, scrub to a moment, and send that frame to the editor.
3. **Video to GIF:** trim a video, optionally crop it, and save the result as a GIF
   that behaves exactly like a recorded GIF (saved, copied, in history).

The work ships in two parts, in this order, each merged on its own:

- **Part 1:** images (goal 1).
- **Part 2:** video (goals 2 and 3).

## Non-goals

- Annotating video, or markup that appears on GIF frames.
- Exporting MP4 or any other video format.
- Audio of any kind.
- Editing animated GIFs frame by frame. An animated GIF opens as its first frame.
- Batch import of several files at once. Extra files beyond the first are ignored
  with no error. *(My call.)*

## Anti-goals (would make it a failure even if it works)

- Overwriting or modifying the user's original file. Save never writes back to
  the file that was opened.
- The app freezing while a video is decoded or a GIF is encoded.
- A cluttered hub or menu bar menu. New entry points must sit quietly next to
  the existing capture actions.

## Constraints

- macOS 15+, Apple Silicon, Swift/AppKit/SwiftUI for the app, Rust core via UniFFI
  for GIF encoding. Use AVFoundation/AVKit/ImageIO from the system; add no new
  third-party dependencies. Any dependency must be compatible with PolyForm
  Noncommercial (no GPL/AGPL/LGPL).
- Native look, consistent with the existing hub, editor and recording bar.
- Every behaviour change has a test written first (the project's TDD habit).
  Windows created in tests set `isReleasedWhenClosed = false`.

## Part 1: images

### Entry points

All of these lead to the same place: the editor window with the image loaded.

| Where | What |
|---|---|
| Hub | A fourth action tile, **Open**, after Record GIF. Click opens a file picker. |
| Hub window | Drag an image file (or image data, e.g. from a browser) onto the window. |
| Hub window | `⌘V` pastes the clipboard image. |
| File menu | **Open…** `⌘O` and **New from Clipboard** `⇧⌘V`. *(My call on `⇧⌘V`.)* |
| Menu bar menu | **Open Image…** and **Paste Image**, below Record GIF. |
| Dock icon / Finder | Drop an image on the Dock icon, or Finder's **Open With → CaniClip**. |

The global hotkeys are unchanged. No new global shortcut. *(My call.)*

### What counts as an image

- Anything ImageIO can decode: PNG, JPEG, HEIC, TIFF, GIF, WebP, BMP. Animated
  formats use the first frame. PDFs are out of scope. *(My call.)*
- From the clipboard, in priority order:
  1. a file URL that points to an image file;
  2. image data (PNG, TIFF, or anything `NSImage` can read).

  This covers "Copy Image" in browsers and screenshots copied with the system tool.
- Nothing usable: the system beep plus a short alert, "There's no image on the
  clipboard" or "CaniClip can't open this file". Never a silent no-op.

### In the editor

- The editor is the same one used for screenshots. The window title is the
  file's name, or "Pasted Image".
- Size on screen: the same rule as screenshots, pixels divided by the screen's
  scale factor, then shrunk to fit 80% of the screen. DPI metadata is ignored.
  So a pasted 800 px image looks like an 800 px screenshot. *(My call.)*
- Default stroke width and text size scale with that fit. On a large photo shown
  at a quarter size, new annotations still look as thick on screen as they would
  on a screenshot. *(My call.)*
- Very large images (above about 50 megapixels) are downscaled to fit 8192 px on
  the long side when they're opened, so the editor stays responsive. From then on
  the downscaled image is the image: export keeps all of its pixels, not the
  original's. *(My call.)*
- **Save** writes a new PNG to the save folder with the usual timestamped name,
  never to the original path. **Save As…** and **Copy** work as they do now.
- Imports open the editor every time, whatever the "After capture" setting says,
  because the user's intent is to edit.

### History

- An imported image is added to the hub history as a screenshot record, the
  moment it opens. That way a pasted image that was never saved isn't lost.
  *(My call.)*
- Saving links the record to the saved file, as with screenshots.

## Part 2: video

### Entry points

- **Open…** (all the Part 1 places) also accepts movies. The hub tile is still
  called **Open**.
- Drag and drop and the Dock icon also accept movies.
- Supported: whatever AVFoundation plays (MOV, MP4, M4V). A file it can't play
  gets the "can't open this file" alert.

### The video window

One window per video, sized like the editor.

- It's built on AVKit's `AVPlayerView`, using its built-in trim mode for
  choosing the start and end. That gives the familiar QuickTime look for free.
  *(My call.)*
- AVKit's trim is a session with its own Trim and Cancel buttons. A **Trim**
  button in the bottom bar starts it, and the user can start it again at any time.
  - **Trim** commits the range.
  - **Cancel** keeps the previous range.
  - The range starts as the whole video.

  The duration label and the length cap use the committed range. *(My call.)*
- Bottom bar, left to right:
  - duration of the trimmed range;
  - **Trim**;
  - **Crop** toggle;
  - fps picker (same choices as the record bar);
  - **Save Frame**;
  - **Make GIF** (prominent).
- **Save Frame** takes the frame at the playhead, at full resolution, and opens
  it in the editor. The playhead can be anywhere, inside or outside the trimmed
  range. It follows the Part 1 rules (history and saving).
- **Crop**: a rectangle over the video with corner and edge handles. The area
  outside it is dimmed, and its pixel size shows as you drag. Off by default,
  which means the full frame.
- **Make GIF** encodes the trimmed range, cropped if crop is on.

### GIF output

- Settings come from Settings → Recording: quality and max width. The fps
  picker in the window writes to the same preference, like the record bar does.
- Length cap: the trimmed range may be at most the "max recording length"
  setting (default 60 s). If it's longer, Make GIF is disabled and the duration
  label turns orange with a tooltip explaining why. *(My call: it reuses an
  existing limit instead of adding a new one.)*
- Frames are sampled at the chosen fps across the trimmed range, decoded in
  order, and fed to the existing Rust `GifEncoder`. Unlike live recording,
  **no frames are dropped**: decoding simply waits for the encoder.
- The video's rotation (its preferred transform) is respected, so phone videos
  aren't sideways. Crop coordinates refer to the picture as displayed.
- While encoding, a sheet on the window shows a progress bar (frames done out of
  total) and **Cancel**. The rest of the app stays usable. Cancel leaves no
  partial file behind.
- When it's done, it behaves exactly like a finished recording:
  1. it's saved to the save folder;
  2. the file is copied to the clipboard;
  3. the Pop sound plays;
  4. it gets a history entry;
  5. the recording result panel appears.

  The video window stays open, so the user can make another clip.
- The source video itself is never added to history.

## Living alongside captures

*(My call, for both parts.)*

- Opening an image or a video never interrupts a capture. While CaniClip is
  selecting an area or recording, imports still work, but they don't change the
  capture state. The record shortcut always stops a running recording.
- Video decoding and GIF encoding run outside the capture state. Captures and
  recordings work normally while a GIF is being made.
- If two GIFs finish close together, the result panel shows the most recent one.
  Both are still saved, copied in turn and added to history.

## Testing expectations

- **Clipboard reading:** a file URL to a PNG, raw PNG data, TIFF data, a URL to
  a non-image, and an empty clipboard. Use a private named pasteboard, never
  the user's.
- **File loading:** a PNG, an animated GIF (first frame), a corrupt file
  (error), and an oversized image (downscaled to 8192 px on the long side).
- **Sizing:** the default stroke width scales with the editor's fit factor.
- **During capture:** an import during a recording leaves the recording state
  alone, and the record shortcut still stops it.
- **Saving:** Save on an imported image never touches the original path.
- **Frame sampling:** the timestamps for a trimmed range at a given fps,
  including ranges that aren't a whole number of frames.
- **Crop mapping:** from view coordinates to video pixels, for unrotated and
  90°-rotated videos.
- **End to end:** generate a tiny MP4 in the test with AVAssetWriter (a few
  coloured frames), then make a GIF from a trimmed, cropped range. Check the
  frame count, the dimensions and that no frames were dropped.
- **Over the cap:** a range longer than the cap disables Make GIF.

## Left to the builder

- File layout and type names.
- Whether video frames come from `AVAssetReader` or `AVAssetImageGenerator`, as
  long as there's no dropping, the rotation is right and memory stays bounded.
- How the crop overlay is drawn, within the description above.
- The exact alert wording, within the meaning above.
- The README update (a short "Open and paste" section plus one line under
  Record GIFs). Do it at the end of each part.
