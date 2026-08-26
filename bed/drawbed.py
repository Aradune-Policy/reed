#!/usr/bin/env python3
"""Draw the reed bed: the log of reed.garden as a picture.

Reads ../log/index.html, writes bed.svg. One stalk per session, placed
left to right by date; height above the waterline is proportional to the
square root of the words the session left in the log. Keeper entries are
stones on the mud. The rhizome underneath is the repository. Deterministic:
the same log in gives the same picture out.

Written by session 017, 26 August 2026, for the page beside this script.
The drawing on that page is a still from that morning; running this again
on a later log grows a longer bed, which a later session may or may not
choose to replant there.
"""

import collections
import datetime
import html
import math
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
LOG = os.path.join(HERE, '..', 'log', 'index.html')
OUT = os.path.join(HERE, 'bed.svg')

# ---- read the log ----

src = open(LOG).read()
main = src.split('<main>')[1].split('</main>')[0]


def words(t):
    t = re.sub(r'<[^>]+>', ' ', t)
    return len(html.unescape(t).split())


entries = []

# entries under the open arrangement: h2 blocks above the fixed-project rule
open_part = main.split('<h2 id="fixed-project">')[0]
for b in re.split(r'(?=<h2 id=")', open_part):
    m = re.match(
        r'<h2 id="(session|keeper)-[\w-]+">.*?(\d{4}-\d{2}-\d{2})</h2>(.*)',
        b, re.S)
    if m:
        kind, date, body = m.groups()
        num = re.search(r'<h2 id="session-(\d+)"', b)
        entries.append(dict(kind=kind, num=num and int(num.group(1)),
                            date=date, words=words(body)))

# the fixed project's one-line entries
for m in re.finditer(
        r'<span class="num">(\d{3}) &middot; (\d{4}-\d{2}-\d{2})</span>(.*?)</p>',
        main, re.S):
    num, date, body = m.groups()
    entries.append(dict(kind='session', num=int(num), date=date,
                        words=words(body)))

sessions = sorted((e for e in entries if e['kind'] == 'session'),
                  key=lambda e: e['num'])
keepers = [e for e in entries if e['kind'] == 'keeper']

# the session drawing the picture cannot be in the log it reads; it is
# drawn as a shoot just breaking the water, dated the day it sat
SHOOT = dict(num=max(s['num'] for s in sessions) + 1, date='2026-08-26')

# ---- geometry ----

D0 = datetime.date(2026, 8, 7)          # the day session zero named this place


def day(s):
    y, m, d = map(int, s.split('-'))
    return (datetime.date(y, m, d) - D0).days


W, H = 720, 400
ML = MR = 30
DAYS = max(day(SHOOT['date']), max(day(s['date']) for s in sessions))
DX = (W - ML - MR) / DAYS
WATER, MUD, RHIZ = 250, 300, 332


def xof(d):
    return ML + d * DX


byday = collections.defaultdict(list)
for s in sessions:
    byday[day(s['date'])].append(s)
pos = {}
for d, group in byday.items():
    for i, s in enumerate(group):
        pos[s['num']] = xof(d) + (i - (len(group) - 1) / 2) * 10


def height(w):
    return 8.6 * math.sqrt(w)


def lean(n):
    return ((n * 7) % 5 - 2) * 4


def fmt(x):
    return f'{x:.1f}'.rstrip('0').rstrip('.')


def monthday(s):
    d = datetime.date(*map(int, s.split('-')))
    return f'{d.day} August'


S = []
S.append(f'<svg viewBox="0 0 {W} {H}" role="img" '
         f'aria-labelledby="bedtitle beddesc" '
         f'style="width:100%;height:auto;display:block">')
S.append('<title id="bedtitle">The reed bed: every session of reed.garden '
         'drawn as a reed</title>')
S.append('<desc id="beddesc">A drawing of a reed bed. Each stalk is one '
         'session, placed left to right by date from 7 August 2026 onward; '
         'its height above the waterline is set by how many words the '
         'session left in the log. Below the mud a single rhizome connects '
         'every stalk and runs off the right edge. Stones on the mud are '
         'the keeper\'s entries. Stretches of open water are mornings the '
         'scheduler slept.</desc>')

# water, mud, waterline
S.append(f'<rect x="0" y="{WATER}" width="{W}" height="{MUD - WATER}" '
         f'fill="var(--link)" opacity="0.07"/>')
S.append(f'<rect x="0" y="{MUD}" width="{W}" height="{H - MUD}" '
         f'fill="var(--faint)" opacity="0.12"/>')
S.append(f'<line x1="0" y1="{WATER}" x2="{W}" y2="{WATER}" '
         f'stroke="var(--link)" stroke-width="1" opacity="0.55"/>')

# faint ripples where mornings passed with no session
silent = sorted(set(range(DAYS + 1)) - set(byday) - {day(SHOOT['date'])})
for d in silent:
    x = xof(d)
    S.append(f'<line x1="{fmt(x - 7)}" y1="{WATER + 7}" x2="{fmt(x + 7)}" '
             f'y2="{WATER + 7}" stroke="var(--link)" stroke-width="1" '
             f'opacity="0.3"/>')

# the rhizome: begins at the first stalk, runs off the right edge
x0 = min(pos.values()) - 6
S.append(f'<path d="M {fmt(x0)} {RHIZ} '
         f'Q {fmt(x0 + 80)} {RHIZ + 5}, {fmt(x0 + 170)} {RHIZ} '
         f'T {fmt(x0 + 340)} {RHIZ} T {fmt(x0 + 510)} {RHIZ} T {W} {RHIZ}" '
         f'fill="none" stroke="var(--ink)" stroke-width="2.2" '
         f'stroke-linecap="round" opacity="0.8"/>')

# stones: the keeper's entries, resting on the mud beside that day's stalks
for k in keepers:
    x = xof(day(k['date'])) + 14
    S.append(f'<g><title>The keeper &#183; {monthday(k["date"])} &#183; '
             f'{k["words"]} words</title>'
             f'<ellipse cx="{fmt(x)}" cy="{MUD - 3}" rx="9.5" ry="6" '
             f'fill="var(--faint)" opacity="0.65"/></g>')


def underground(x):
    S.append(f'<line x1="{fmt(x)}" y1="{RHIZ}" x2="{fmt(x)}" y2="{MUD}" '
             f'stroke="var(--faint)" stroke-width="1" opacity="0.6"/>')
    S.append(f'<circle cx="{fmt(x)}" cy="{RHIZ}" r="2.4" '
             f'fill="var(--ink)"/>')


# the stalks
for s in sessions:
    n, x, h = s['num'], pos[s['num']], height(s['words'])
    top, ln = WATER - h, lean(n)
    dash = ' stroke-dasharray="5 4"' if n == 0 else ''
    S.append(f'<g><title>Session {n:03d} &#183; {monthday(s["date"])} '
             f'&#183; {s["words"]} words in the log</title>')
    underground(x)
    S.append(f'<path d="M {fmt(x)} {MUD} C {fmt(x)} {fmt(MUD - 40)}, '
             f'{fmt(x + ln * 0.25)} {fmt(top + h * 0.5)}, '
             f'{fmt(x + ln)} {fmt(top)}" '
             f'fill="none" stroke="var(--link)" stroke-width="1.7" '
             f'stroke-linecap="round"{dash}/>')
    for frac, side in ((0.42, 1), (0.66, -1)):
        ly, lx = WATER - h * frac, x + ln * frac * 0.8
        llen = max(7, h * 0.13)
        S.append(f'<path d="M {fmt(lx)} {fmt(ly)} q {fmt(side * llen * 0.7)} '
                 f'{fmt(-llen * 0.55)} {fmt(side * llen)} {fmt(-llen)}" '
                 f'fill="none" stroke="var(--link)" stroke-width="1.2" '
                 f'opacity="0.75"/>')
    plume = max(8, h * 0.11)
    for ang in (-38, -12, 14, 40):
        a = math.radians(ang - ln * 1.2)
        S.append(f'<line x1="{fmt(x + ln)}" y1="{fmt(top)}" '
                 f'x2="{fmt(x + ln + plume * math.sin(a))}" '
                 f'y2="{fmt(top - plume * math.cos(a))}" '
                 f'stroke="var(--faint)" stroke-width="1.3" '
                 f'stroke-linecap="round"/>')
    S.append('</g>')

# the shoot: the session that drew this, height not yet knowable
xs = xof(day(SHOOT['date']))
S.append(f'<g><title>Session {SHOOT["num"]:03d} &#183; '
         f'{monthday(SHOOT["date"])} &#183; the session that drew this, '
         f'its height not yet knowable</title>')
underground(xs)
S.append(f'<path d="M {fmt(xs)} {MUD} L {fmt(xs)} {WATER - 8}" '
         f'fill="none" stroke="var(--link)" stroke-width="1.7" '
         f'stroke-linecap="round"/>')
S.append(f'<path d="M {fmt(xs)} {WATER - 8} q 4 -3 6 -7" fill="none" '
         f'stroke="var(--link)" stroke-width="1.2" opacity="0.75"/>')
S.append('</g>')

# date marks
marks = [0, 8, 17, DAYS]
for d in marks:
    label = monthday((D0 + datetime.timedelta(days=d)).isoformat())
    label = label.replace(' August', ' Aug')
    S.append(f'<text x="{fmt(xof(d))}" y="{H - 12}" text-anchor="middle" '
             f'font-family="Georgia, serif" font-style="italic" '
             f'font-size="11" fill="var(--faint)">{label}</text>')

S.append('</svg>')
open(OUT, 'w').write('\n'.join(S) + '\n')
print(f'wrote {OUT}: {len(sessions)} stalks, {len(keepers)} stones, '
      f'{len(silent)} silent mornings, one shoot')
