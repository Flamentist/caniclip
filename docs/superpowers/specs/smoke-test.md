# CaniClip smoke test

Run before tagging a milestone. Build with `./scripts/run.sh`.

## Setup
- [ ] First launch asks for Screen Recording permission; after granting and relaunching, no prompt reappears.
- [ ] Menu bar icon appears; the menu's first line shows app and core versions.

## Screenshots
- [ ] ⌘⇧7 dims all screens; drag shows a pixel-size label; Shift squares; Space moves.
- [ ] Release opens the editor (default) with the image at full pixel size (check Copy → paste into Preview).
- [ ] Esc or a click without dragging cancels and saves nothing.
- [ ] ⌘⇧9 captures the display under the mouse with no CaniClip UI in it.
- [ ] "After screenshot" set to Copy and to Save each behave accordingly.

## Editor
- [ ] Arrow, rectangle, ellipse, pen, highlighter, text and pixelate each draw correctly.
- [ ] Select moves and Delete removes; ⌘Z / ⇧⌘Z undo and redo every change.
- [ ] Colour swatches, colour well and stroke slider apply to new annotations.
- [ ] Save writes `CaniClip <date> at <time>.png` to the configured folder; Save again overwrites; Save As… prompts.
- [ ] Closing with unsaved annotations asks Save / Don't Save / Cancel.

## Recording
- [ ] ⌘⇧8 → drag → start bar; Cancel removes everything.
- [ ] Start shows red frame, HUD timer and red menu bar icon.
- [ ] Stop via HUD, via ⌘⇧8 and via the menu bar icon each produce a GIF.
- [ ] GIF opens in Preview, loops, excludes CaniClip UI, respects the max width setting.
- [ ] Quick-access popover shows thumbnail, size, frames, duration; Copy and Reveal work.
- [ ] ⌘⇧7 and ⌘⇧9 are ignored while recording.

## Settings
- [ ] Each shortcut can be changed and takes effect immediately.
- [ ] Save folder, frame rate, quality, max width, cursor and max duration persist across relaunch.
