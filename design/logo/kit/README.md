# CaniClip logo kit

**Final direction:** Question Frame, a selection frame whose top-right corner turns into a question mark. Read [guidelines.md](guidelines.md) for usage.

## Files
| Folder | What's inside |
|---|---|
| `masters/` | Source SVGs: symbol, small-size cut, wordmark, horizontal and stacked lockups (Ink and thinner reversed versions), macOS icon tiles, menu bar template |
| `symbol/` | Symbol in black, Clip Yellow, white, square avatar, favicon and app-icon SVGs, each with 64, 256 and 1024 px PNGs |
| `lockups/` | Horizontal, stacked and wordmark in Ink, black, Clip Yellow and white, SVG plus 1200 px PNG |
| `web/` | favicon.ico, favicon.svg, 16/32/48 px favicons, apple-touch-icon, PWA icons, site.webmanifest, head-snippet.html |
| `macos/` | `AppIcon.appiconset` and `MenuBarIcon.imageset`, ready to drop into an Xcode asset catalog |
| `board/` | Presentation (`caniclip-presentation.html`) with five slides exported as PNGs in `board/slides/` |

## Tests run
- `svg_audit.py` on every master: 100/100, no warnings (no strokes, text, rasters or filters; single colour; centred).
- Test sheet at 96 and 32 px, one-colour and reversed; the small cut keeps its counter and dot gap open at 16 to 32 px.
- Presentation mockups checked for colour on yellow tiles and dark surfaces.

## Open items
- **Trademark:** not searched. Run a professional trademark search and a reverse image search before public launch.
- **App integration:** the icon sets are not yet wired into the Xcode project; the app still uses an SF Symbol in the menu bar and the default app icon.
- **Print:** CMYK and Pantone values are approximations; no PDF or EPS masters were produced (no vector print tool available here).
