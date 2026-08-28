#!/usr/bin/env python3
"""Draw map.svg for the Downstream room from data.json.

The two attractors are laid out exactly (the sixteen-member circle as a
ring, the two-member flicker as a pair of opposed arcs); the tributary
streams are drawn schematically, with hand-placed curves, since the full
chains are printed on the page itself. Colours follow style.css, with a
dark scheme via prefers-color-scheme inside the SVG so it works from an
<img> tag.
"""
import json
import math
import pathlib

HERE = pathlib.Path(__file__).parent
data = json.loads((HERE / "data.json").read_text())

W, H = 840, 600
CX, CY, R = 570, 250, 145
ring = data["attractors"]["circle"]["members"]

# Nodes where a tributary arrives (marked in the accent colour).
ENTRY = {"Knowledge", "Science", "Thought"}
# Nodes whose labels sit inside the ring (an entry stream, or another
# label, occupies the space outside them).
INSIDE = ENTRY | {"Matter"}


def ringpos(i, r=R):
    th = math.radians(210 + i * 22.5)  # y-down coords; sequence runs clockwise
    return CX + r * math.cos(th), CY + r * math.sin(th), th


def fmt(x):
    return f"{x:.1f}"


parts = []
parts.append(
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" '
    f'font-family="Georgia, \'Times New Roman\', serif" '
    f'role="img" aria-label="A map of eleven first-link chains draining into '
    f'two closed loops: a sixteen-article circle and the two-article '
    f'Existence-Reality flicker.">'
)
parts.append("""<style>
  .ink   { fill: #2b2a24; }
  .faint { fill: #857e70; }
  .lnk   { fill: #3d6b4f; }
  .sInk    { stroke: #2b2a24; fill: none; }
  .sAccent { stroke: #3d6b4f; fill: none; }
  @media (prefers-color-scheme: dark) {
    .ink   { fill: #d8d3c3; }
    .faint { fill: #7f7869; }
    .lnk   { fill: #93bda2; }
    .sInk    { stroke: #d8d3c3; }
    .sAccent { stroke: #93bda2; }
  }
  text { font-size: 12.5px; }
  .small  { font-size: 11px; font-style: italic; }
  .title  { font-size: 15px; font-style: italic; }
</style>
<defs>
  <marker id="arrI" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
    <path d="M0.5,0.5 L7.5,4 L0.5,7.5 z" class="ink" stroke="none"/>
  </marker>
  <marker id="arrA" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
    <path d="M0.5,0.5 L7.5,4 L0.5,7.5 z" class="lnk" stroke="none"/>
  </marker>
</defs>""")

# --- the circle -------------------------------------------------------------
parts.append(f'<text x="{CX}" y="42" text-anchor="middle" class="ink title">The Circle</text>')
parts.append(f'<text x="{CX}" y="62" text-anchor="middle" class="faint small">sixteen articles, each the next one&#8217;s first link</text>')

n = len(ring)
for i in range(n):
    x1, y1, _ = ringpos(i)
    # arc from just past this node to just before the next
    a1 = math.radians(210 + i * 22.5 + 4.5)
    a2 = math.radians(210 + (i + 1) * 22.5 - 6.5)
    sx, sy = CX + R * math.cos(a1), CY + R * math.sin(a1)
    ex, ey = CX + R * math.cos(a2), CY + R * math.sin(a2)
    parts.append(
        f'<path d="M{fmt(sx)},{fmt(sy)} A{R},{R} 0 0 1 {fmt(ex)},{fmt(ey)}" '
        f'class="sInk" stroke-width="1.1" marker-end="url(#arrI)"/>'
    )

for i, name in enumerate(ring):
    x, y, th = ringpos(i)
    c, s = math.cos(th), math.sin(th)
    entry = name in ENTRY
    parts.append(f'<circle cx="{fmt(x)}" cy="{fmt(y)}" r="{3.4 if entry else 2.6}" class="{"lnk" if entry else "ink"}"/>')
    if name in INSIDE:
        lx, ly = x - 13 * c, y - 13 * s
        anchor = "start" if c < 0 else "end"
        dy = 4
    else:
        lx, ly = x + 13 * c, y + 13 * s
        anchor = "middle" if abs(c) < 0.25 else ("start" if c > 0 else "end")
        dy = -4 if s < -0.5 else (11 if s > 0.5 else 4)
    label = name.replace("Outline of physical science", "Outline of physical science")
    parts.append(
        f'<text x="{fmt(lx)}" y="{fmt(ly + dy)}" text-anchor="{anchor}" class="ink">{label}</text>'
    )

# --- the flicker ------------------------------------------------------------
EX, EY = 165, 505
RX, RY = 345, 505
parts.append(f'<text x="{(EX+RX)//2}" y="573" text-anchor="middle" class="ink title">The Flicker</text>')
parts.append(f'<circle cx="{EX}" cy="{EY}" r="3.4" class="lnk"/>')
parts.append(f'<circle cx="{RX}" cy="{RY}" r="2.6" class="ink"/>')
parts.append(f'<text x="{EX}" y="{EY+26}" text-anchor="middle" class="ink">Existence</text>')
parts.append(f'<text x="{RX}" y="{RY+26}" text-anchor="middle" class="ink">Reality</text>')
parts.append(f'<path d="M{EX+10},{EY-7} Q{(EX+RX)//2},{EY-38} {RX-10},{RY-7}" class="sInk" stroke-width="1.1" marker-end="url(#arrI)"/>')
parts.append(f'<path d="M{RX-8},{RY+9} Q{(EX+RX)//2},{EY+38} {EX+8},{EY+9}" class="sInk" stroke-width="1.1" marker-end="url(#arrI)"/>')

# --- the streams (schematic) ------------------------------------------------
def stream(path_d, lines, lx, ly, anchor="start"):
    parts.append(f'<path d="{path_d}" class="sAccent" stroke-width="1.2" marker-end="url(#arrA)"/>')
    for k, line in enumerate(lines):
        parts.append(
            f'<text x="{lx}" y="{ly + 14 * k}" text-anchor="{anchor}" class="lnk small">{line}</text>'
        )

# into Knowledge (upper left of ring)
kx, ky, kth = ringpos(0)
stream(
    f"M150,78 C 250,84 380,118 {fmt(kx - 10)},{fmt(ky - 8)}",
    ["reed &#183; sedge &#183; common descent", "down Biology, 4&#8211;7 clicks"],
    150, 46,
)
# into Science (left of ring)
sx, sy, sth = ringpos(15)
stream(
    f"M60,208 C 160,203 300,218 {fmt(sx - 14)},{fmt(sy - 2)}",
    ["a town in Queensland &#183; a merchant of Aalborg", "down Geography, Earth and Physics, 12&#8211;13 clicks"],
    60, 176,
)
# into Thought (upper right of ring)
tx, ty, tth = ringpos(5)
stream(
    f"M762,50 C 742,72 712,112 {fmt(tx + 8)},{fmt(ty - 10)}",
    ["the Ship of Theseus", "down Logic, 4 clicks"],
    768, 28, anchor="end",
)
# into Existence, through Philosophy
stream(
    f"M48,340 C 60,390 100,450 {fmt(EX - 8)},{fmt(EY - 12)}",
    ["the <tspan font-style='italic'>Cosmographia</tspan> of 1544,", "through Philosophy itself, 5 clicks"],
    40, 312,
)
parts.append('<circle cx="85.8" cy="419.2" r="2.6" class="lnk"/>')
parts.append('<text x="98" y="423" class="faint small">Philosophy</text>')
# into Existence, down Entity
stream(
    f"M395,368 C 350,410 260,460 {fmt(EX + 12)},{fmt(EY - 10)}",
    ["a geodesist &#183; a village &#183; a campaign &#183; an album", "down Entity, 8&#8211;20 clicks"],
    415, 434,
)

parts.append("</svg>")
(HERE / "map.svg").write_text("\n".join(parts))
print("wrote", HERE / "map.svg")
