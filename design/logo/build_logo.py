#!/usr/bin/env python3
"""Builds the CaniClip logo masters from exact geometry.

Every stroke is described as a centreline of straight lines and circular arcs
with round caps, then expanded into a filled outline (concentric arcs and
parallel lines), so the masters contain no strokes, text, filters or rasters.

Run:  python3 design/logo/build_logo.py
"""
import math
from pathlib import Path

OUT = Path(__file__).resolve().parent / "kit" / "masters"
INK = "#16161A"
YELLOW = "#FFC83D"


def fmt(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s == "-0" else s


class Stroke:
    """A tangent-continuous centreline of lines and arcs, expanded with round caps."""

    def __init__(self, x, y):
        self.start = (x, y)
        self.pos = (x, y)
        self.segs = []

    def H(self, x):
        return self.L(x, self.pos[1])

    def V(self, y):
        return self.L(self.pos[0], y)

    def L(self, x, y):
        if (x, y) != self.pos:
            self.segs.append(("L", self.pos, (x, y)))
            self.pos = (x, y)
        return self

    def arc(self, cx, cy, ex, ey, sweep):
        """Arc around (cx, cy) from the current point to (ex, ey); sweep 1 = clockwise on screen."""
        r = math.hypot(self.pos[0] - cx, self.pos[1] - cy)
        a0 = math.atan2(self.pos[1] - cy, self.pos[0] - cx)
        a1 = math.atan2(ey - cy, ex - cx)
        self.segs.append(("A", (cx, cy), r, a0, a1, sweep))
        self.pos = (ex, ey)
        return self

    # -- geometry helpers --------------------------------------------------
    @staticmethod
    def _dir(seg, at_end):
        if seg[0] == "L":
            (x0, y0), (x1, y1) = seg[1], seg[2]
            l = math.hypot(x1 - x0, y1 - y0)
            return ((x1 - x0) / l, (y1 - y0) / l)
        _, c, r, a0, a1, s = seg
        a = a1 if at_end else a0
        return (-math.sin(a), math.cos(a)) if s == 1 else (math.sin(a), -math.cos(a))

    @staticmethod
    def _span(a0, a1, s):
        d = (a1 - a0) if s == 1 else (a0 - a1)
        return d % (2 * math.pi) or 2 * math.pi

    def outline(self, w):
        d = w / 2
        out = []

        def side(seg, sign, reverse):
            if seg[0] == "L":
                p0, p1 = seg[1], seg[2]
                ux, uy = self._dir(seg, False)
                nx, ny = -uy * sign, ux * sign
                a, b = (p0, p1) if not reverse else (p1, p0)
                return (a[0] + d * nx, a[1] + d * ny), f"L {fmt(b[0] + d * nx)} {fmt(b[1] + d * ny)}"
            _, (cx, cy), r, a0, a1, s = seg
            rr = (r - d if s == 1 else r + d) if sign > 0 else (r + d if s == 1 else r - d)
            if reverse:
                a0, a1, s = a1, a0, 1 - s
            large = 1 if self._span(a0, a1, s) > math.pi else 0
            start = (cx + rr * math.cos(a0), cy + rr * math.sin(a0))
            end = (cx + rr * math.cos(a1), cy + rr * math.sin(a1))
            return start, f"A {fmt(rr)} {fmt(rr)} 0 {large} {s} {fmt(end[0])} {fmt(end[1])}"

        def cap(p, u, d_from_sign):
            # Round cap: from the +n side through p + d*u to the -n side (or the reverse).
            ux, uy = u
            tip = (p[0] + d * ux, p[1] + d * uy)
            nx, ny = -uy * d_from_sign, ux * d_from_sign
            far = (p[0] - d * nx, p[1] - d * ny)
            return [f"A {fmt(d)} {fmt(d)} 0 0 0 {fmt(tip[0])} {fmt(tip[1])}",
                    f"A {fmt(d)} {fmt(d)} 0 0 0 {fmt(far[0])} {fmt(far[1])}"]

        first, _ = side(self.segs[0], +1, False)
        out.append(f"M {fmt(first[0])} {fmt(first[1])}")
        for seg in self.segs:
            _, cmd = side(seg, +1, False)
            out.append(cmd)
        out += cap(self.pos, self._dir(self.segs[-1], True), +1)
        for seg in reversed(self.segs):
            _, cmd = side(seg, -1, True)
            out.append(cmd)
        u0 = self._dir(self.segs[0], False)
        out += cap(self.start, (-u0[0], -u0[1]), +1)
        out.append("Z")
        return " ".join(out)


def ring(cx, cy, r, w):
    """Circle stroke as an even-odd ring."""
    ro, ri = r + w / 2, r - w / 2
    return (f"M {fmt(cx - ro)} {fmt(cy)} A {fmt(ro)} {fmt(ro)} 0 1 0 {fmt(cx + ro)} {fmt(cy)} "
            f"A {fmt(ro)} {fmt(ro)} 0 1 0 {fmt(cx - ro)} {fmt(cy)} Z "
            f"M {fmt(cx - ri)} {fmt(cy)} A {fmt(ri)} {fmt(ri)} 0 1 0 {fmt(cx + ri)} {fmt(cy)} "
            f"A {fmt(ri)} {fmt(ri)} 0 1 0 {fmt(cx - ri)} {fmt(cy)} Z")


def dot(cx, cy, r):
    return (f"M {fmt(cx - r)} {fmt(cy)} A {fmt(r)} {fmt(r)} 0 1 0 {fmt(cx + r)} {fmt(cy)} "
            f"A {fmt(r)} {fmt(r)} 0 1 0 {fmt(cx - r)} {fmt(cy)} Z")


# ---------------------------------------------------------------- symbol ----
def symbol_paths(small=False, thin=0.0):
    """The Question Frame on a 256 grid.

    Regular: stroke 26, dot r16. Small cut (for 16–32 px): stroke 34, larger
    dot and wider gaps so the counter and the stem/dot gap stay open.
    """
    if not small:
        w = 26 - thin
        q = (Stroke(120, 44).H(184).arc(184, 72, 212, 72, 1).V(84)
             .arc(184, 84, 184, 112, 1).arc(184, 134, 162, 134, 0).V(150))
        corner = Stroke(44, 160).V(184).arc(72, 184, 72, 212, 0).H(104)
        d = dot(162, 196, 16 - thin / 2)
    else:
        w = 34 - thin
        q = (Stroke(124, 44).H(182).arc(182, 74, 212, 74, 1).V(82)
             .arc(182, 82, 182, 112, 1).arc(182, 132, 162, 132, 0).V(144))
        corner = Stroke(44, 156).V(180).arc(76, 180, 76, 212, 0).H(100)
        d = dot(162, 205, 20 - thin / 2)
    return [q.outline(w), corner.outline(w), d]


def symbol_group(fill, small=False, thin=0.0):
    return "\n".join(f'    <path fill="{fill}" d="{p}"/>' for p in symbol_paths(small, thin))


# -------------------------------------------------------------- wordmark ----
# Monoline geometric lowercase built from the symbol's vocabulary: round caps,
# circular bowls, and i-dots drawn like the question's dot.
WM_W = 22          # stroke (regular)
R = 38             # bowl centreline radius (1 unit overshoot past the x-height)
BASE, XTOP, CY = 176, 80, 128
DOT_Y = 52


def set_weight(w):
    """Stem ends depend on the stroke so outer edges stay on the x-height, baseline, ascender and descender."""
    global WM_W, TOP_C, BOT_C, ASC_C, DESC_C, DOT_R
    WM_W = w
    TOP_C, BOT_C = XTOP + w / 2, BASE - w / 2
    ASC_C, DESC_C = 48 + w / 2, 222 - w / 2
    DOT_R = 14 * w / 22


set_weight(22)


def letter_c(cx):
    s = math.sin(math.radians(45)) * R
    return [Stroke(cx + s, CY - s).arc(cx, CY, cx + s, CY + s, 0).outline(WM_W)], []


def letter_a(cx):
    return [Stroke(cx + R, TOP_C).V(BOT_C).outline(WM_W)], [ring(cx, CY, R, WM_W)]


def letter_n(sx):
    stem = Stroke(sx, TOP_C).V(BOT_C).outline(WM_W)
    arch = Stroke(sx, CY).arc(sx + R, CY, sx + 2 * R, CY, 1).V(BOT_C).outline(WM_W)
    return [stem, arch], []


def letter_i(x):
    return [Stroke(x, TOP_C).V(BOT_C).outline(WM_W), dot(x, DOT_Y, DOT_R)], []


def letter_l(x):
    return [Stroke(x, ASC_C).V(BOT_C).outline(WM_W)], []


def letter_p(sx):
    return [Stroke(sx, TOP_C).V(DESC_C).outline(WM_W)], [ring(sx + R, CY, R, WM_W)]


def wordmark_paths():
    # Positions from optical spacing: round–round 16, straight–straight 24,
    # straight–round 20, l squeezed to 18 against the round c.
    solids, rings = [], []
    for fn, x in [(letter_c, 49), (letter_a, 152), (letter_n, 236), (letter_i, 358),
                  (letter_c, 438), (letter_l, 505), (letter_i, 551), (letter_p, 597)]:
        s, r = fn(x)
        solids += s
        rings += r
    return solids, rings


WORDMARK_WIDTH = 684


def wordmark_group(fill, dx=0, dy=0, thin=0.0):
    set_weight(22 - thin)
    solids, rings = wordmark_paths()
    set_weight(22)
    body = [f'    <path fill="{fill}" d="{" ".join(solids)}"/>',
            f'    <path fill="{fill}" fill-rule="evenodd" d="{" ".join(rings)}"/>']
    return f'  <g id="wordmark" transform="translate({dx} {dy})">\n' + "\n".join(body) + "\n  </g>"


# ----------------------------------------------------------------- files ----
def svg(view, title, body, w=None, h=None):
    vw, vh = view.split()[2:]
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view}" width="{w or vw}" height="{h or vh}" '
            f'role="img" aria-labelledby="title">\n  <title id="title">{title}</title>\n{body}\n</svg>\n')


def write(name, content):
    (OUT / name).write_text(content)
    print("wrote", OUT / name)


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    # Reversed artwork (yellow/white on dark) is drawn ~6 % thinner to offset irradiation.
    for fill, tag, thin in [(INK, "ink", 0.0), (YELLOW, "reversed", 1.5)]:
        write(f"caniclip-symbol-{tag}.svg",
              svg("0 0 256 256", "CaniClip logo", f'  <g id="symbol">\n{symbol_group(fill, False, thin)}\n  </g>'))
        write(f"caniclip-symbol-small-{tag}.svg",
              svg("0 0 256 256", "CaniClip logo (small sizes)", f'  <g id="symbol">\n{symbol_group(fill, True, thin)}\n  </g>'))
        write(f"caniclip-wordmark-{tag}.svg",
              svg(f"0 0 {WORDMARK_WIDTH} 256", "CaniClip wordmark", wordmark_group(fill, thin=thin)))
        # Horizontal: symbol, a gap of one dot-diameter-plus-stroke, wordmark centred on the x-height.
        hx = 269
        write(f"caniclip-horizontal-{tag}.svg",
              svg(f"0 0 {hx + WORDMARK_WIDTH + 31} 256", "CaniClip logo",
                  f'  <g id="symbol">\n{symbol_group(fill, False, thin)}\n  </g>\n{wordmark_group(fill, hx, 0, thin)}'))
        sw = WORDMARK_WIDTH + 62
        write(f"caniclip-stacked-{tag}.svg",
              svg(f"0 0 {sw} 490", "CaniClip logo",
                  f'  <g id="symbol" transform="translate({(sw - 256) / 2} 0)">\n{symbol_group(fill, False, thin)}\n  </g>\n'
                  f'{wordmark_group(fill, 31, 236, thin)}'))
    # Menu bar template: small cut, black on transparent, tight square crop.
    write("caniclip-menubar-template.svg",
          svg("27 27 202 202", "CaniClip menu bar icon", f'  <g id="symbol">\n{symbol_group("#000000", True)}\n  </g>',
              w=202, h=202))
    # macOS app icon: ink mark on a Clip Yellow squircle tile (1024 grid, 824 tile, 100 inset).
    for small in (False, True):
        scale = 2.62
        tx, ty = 512 - 128 * scale, 504 - 128 * scale
        tile = (f'  <defs>\n    <linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">\n'
                f'      <stop offset="0" stop-color="#FFD35A"/>\n      <stop offset="1" stop-color="#FFC02F"/>\n'
                f'    </linearGradient>\n  </defs>\n'
                f'  <rect x="100" y="100" width="824" height="824" rx="185" fill="url(#tile)"/>\n'
                f'  <g id="symbol" transform="translate({fmt(tx)} {fmt(ty)}) scale({scale})">\n{symbol_group(INK, small)}\n  </g>')
        write(f"caniclip-macos-icon{'-small' if small else ''}.svg",
              svg("0 0 1024 1024", "CaniClip app icon", tile))


if __name__ == "__main__":
    build()
