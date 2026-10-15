#!/usr/bin/env python3
"""Draws the README hero illustration (docs/media/hero.svg).

A Clip Yellow banner with the CaniClip lockup above a stylised Mac window:
a selection marquee picks out part of a chart, an annotation arrow points at
it, and a GIF badge floats beside it. The lockup reuses the logo's exact
geometry from design/logo/build_logo.py.

Run:  python3 design/readme/build_hero.py
"""
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "design" / "logo"))
import build_logo as logo  # noqa: E402

W, H = 1280, 640
INK, YELLOW = logo.INK, logo.YELLOW
DEEP = "#F5B82A"        # a shade of Clip Yellow for depth
PAPER = "#FFFDF7"
CORAL = "#FF4D3A"       # the editor's default annotation red
FONT = "ui-rounded, -apple-system, 'SF Pro Rounded', 'Helvetica Neue', Arial, sans-serif"


def lockup(x, y, scale):
    body = logo.symbol_group(INK) + "\n" + logo.wordmark_group(INK, 269, 0)
    return f'<g transform="translate({x} {y}) scale({scale})">\n{body}\n</g>'


def window():
    x0, y0, w, h = 250, 228, 780, 470
    bars = [118, 170, 140, 214, 262, 188, 236]
    bw, gap, base = 64, 34, 612
    bx0 = x0 + (w - (len(bars) * bw + (len(bars) - 1) * gap)) / 2
    sel = (bx0 + 2 * (bw + gap) - 22, 330, 3 * bw + 2 * gap + 44, base - 330 + 14)
    out = [
        # window
        f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" rx="30" fill="{PAPER}" stroke="{INK}" stroke-width="8"/>',
        f'<line x1="{x0}" y1="{y0 + 62}" x2="{x0 + w}" y2="{y0 + 62}" stroke="{INK}" stroke-width="6"/>',
    ]
    for i, c in enumerate(["#FF5F57", "#FEBC2E", "#28C840"]):
        out.append(f'<circle cx="{x0 + 40 + i * 32}" cy="{y0 + 31}" r="10" fill="{c}" stroke="{INK}" stroke-width="3"/>')
    # chart bars: the three inside the selection are Clip Yellow
    for i, bh in enumerate(bars):
        bx = bx0 + i * (bw + gap)
        inside = 2 <= i <= 4
        fill = YELLOW if inside else "#E8E4DA"
        stroke = f' stroke="{INK}" stroke-width="5"' if inside else ""
        out.append(f'<rect x="{bx:.1f}" y="{base - bh}" width="{bw}" height="{bh}" rx="12" fill="{fill}"{stroke}/>')
    # selection marquee with corner handles and a size label
    sx, sy, sw, sh = sel
    out.append(f'<rect x="{sx:.1f}" y="{sy}" width="{sw}" height="{sh}" rx="4" fill="none" stroke="{INK}" '
               f'stroke-width="5" stroke-dasharray="18 12" stroke-linecap="round"/>')
    for cx, cy in [(sx, sy), (sx + sw, sy), (sx, sy + sh), (sx + sw, sy + sh)]:
        out.append(f'<rect x="{cx - 9:.1f}" y="{cy - 9}" width="18" height="18" rx="4" fill="{PAPER}" stroke="{INK}" stroke-width="5"/>')
    lx, ly = sx + 14, sy - 52
    out.append(f'<rect x="{lx:.1f}" y="{ly}" width="138" height="38" rx="10" fill="{INK}"/>')
    out.append(f'<text x="{lx + 69:.1f}" y="{ly + 26}" text-anchor="middle" font-family="{FONT}" font-size="20" '
               f'font-weight="700" fill="{PAPER}">680 × 580</text>')
    return "\n".join(out), sel


def arrow(sel):
    sx, sy, sw, sh = sel
    start = (sx + sw + 230, sy + 22)
    end = (sx + sw + 18, sy + 96)
    ctrl = (sx + sw + 150, sy - 50)
    # arrowhead along the curve's end tangent
    tx, ty = end[0] - ctrl[0], end[1] - ctrl[1]
    a = math.atan2(ty, tx)
    head = 30
    pts = [(end[0] - head * math.cos(a - s), end[1] - head * math.sin(a - s)) for s in (0.5, -0.5)]
    return (f'<path d="M {start[0]:.1f} {start[1]:.1f} Q {ctrl[0]:.1f} {ctrl[1]:.1f} {end[0]:.1f} {end[1]:.1f}" fill="none" '
            f'stroke="{CORAL}" stroke-width="12" stroke-linecap="round"/>'
            f'<path d="M {pts[0][0]:.1f} {pts[0][1]:.1f} L {end[0]:.1f} {end[1]:.1f} L {pts[1][0]:.1f} {pts[1][1]:.1f}" fill="none" '
            f'stroke="{CORAL}" stroke-width="12" stroke-linecap="round" stroke-linejoin="round"/>')


def gif_badge(x, y, angle):
    w, h = 176, 112
    holes = "".join(f'<rect x="{12 + i * 30}" y="10" width="16" height="12" rx="3" fill="{YELLOW}"/>'
                    f'<rect x="{12 + i * 30}" y="{h - 22}" width="16" height="12" rx="3" fill="{YELLOW}"/>' for i in range(6))
    return (f'<g transform="translate({x} {y}) rotate({angle})">'
            f'<rect width="{w}" height="{h}" rx="16" fill="{INK}"/>{holes}'
            f'<text x="{w / 2}" y="{h / 2 + 15}" text-anchor="middle" font-family="{FONT}" font-size="42" font-weight="800" '
            f'fill="{PAPER}" letter-spacing="2">GIF</text></g>')


def pen_badge(x, y, angle):
    # a highlighter swipe card: three strokes
    return (f'<g transform="translate({x} {y}) rotate({angle})">'
            f'<rect width="150" height="96" rx="16" fill="{PAPER}" stroke="{INK}" stroke-width="6"/>'
            f'<rect x="22" y="24" width="106" height="16" rx="8" fill="{YELLOW}"/>'
            f'<rect x="22" y="50" width="78" height="10" rx="5" fill="{INK}"/>'
            f'<rect x="22" y="68" width="96" height="10" rx="5" fill="#C9C4B8"/></g>')


def build():
    win, sel = window()
    parts = [
        f'<rect width="{W}" height="{H}" fill="{YELLOW}"/>',
        f'<circle cx="80" cy="610" r="210" fill="{DEEP}"/>',
        f'<circle cx="1230" cy="40" r="170" fill="{DEEP}"/>',
        # sparkles
        *(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{INK}"/>' for cx, cy, r in
          [(170, 300, 7), (205, 340, 4), (1110, 430, 6), (1150, 470, 4), (1080, 560, 8)]),
        lockup(W / 2 - 984 * 0.42 / 2, 38, 0.42),
        win,
        arrow(sel),
        gif_badge(1052, 250, 8),
        pen_badge(92, 420, -8),
    ]
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" role="img" '
           f'aria-labelledby="t">\n<title id="t">CaniClip: screenshot, annotate and record GIFs on your Mac</title>\n'
           f'<defs><clipPath id="banner"><rect width="{W}" height="{H}" rx="28"/></clipPath></defs>\n'
           f'<g clip-path="url(#banner)">\n' + "\n".join(parts) + "\n</g>\n</svg>\n")
    out = ROOT / "docs" / "media" / "hero.svg"
    out.write_text(svg)
    print("wrote", out)


if __name__ == "__main__":
    build()
