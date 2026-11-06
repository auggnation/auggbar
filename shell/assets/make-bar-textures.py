#!/usr/bin/env python3
"""Generate the white-on-transparent spray / dry-brush masks used by
components/GraffitiBar.qml (the shell tints them with the wallpaper palette).

  bar-center.png  tileable middle section: solid core, torn + speckled top/bottom edge
  bar-cap.png     left end cap: ragged vertical edge fading out in spray speckle
(the right cap is the left one mirrored)
"""
import math, random
from PIL import Image

H = 34
random.seed(11)

def jag(x, period, amp, seeds):
    return sum(a * math.sin(2 * math.pi * k * x / period + ph) for a, k, ph in seeds) * amp

def seeds(n=5):
    return [(random.uniform(0.4, 1.0) / (i + 1), i + 2, random.uniform(0, 6.28)) for i in range(n)]

# ---- tileable centre strip -------------------------------------------------
P = 256
top_s, bot_s = seeds(), seeds()
center = Image.new("RGBA", (P, H), (255, 255, 255, 0)); px = center.load()
drips = {random.randint(0, P - 1): random.randint(3, 9) for _ in range(9)}   # paint runs at the bottom
for x in range(P):
    top_edge = 5 + jag(x, P, 2.4, top_s) + random.uniform(-0.8, 0.8)
    bot_edge = H - 6 + jag(x, P, 2.4, bot_s) + random.uniform(-0.8, 0.8)
    drip = max((d - abs(x - dx) * 1.6 for dx, d in drips.items()), default=0)
    for y in range(H):
        if top_edge <= y <= bot_edge + max(0, drip):
            a = 255
        else:
            d = (top_edge - y) if y < top_edge else (y - bot_edge - max(0, drip))
            p = max(0.0, 1.0 - d / 5.5) ** 1.8          # spray density falls off with distance
            a = random.randint(90, 235) if random.random() < p * 0.8 else 0
        px[x, y] = (255, 255, 255, a)

# ---- end cap ---------------------------------------------------------------
W = 96
cap = Image.new("RGBA", (W, H), (255, 255, 255, 0)); cp = cap.load()
edge_s = seeds(6)
streak = [random.uniform(-10, 14) for _ in range(H)]       # dry-brush streaks: some rows reach further
for y in range(H):
    edge = 34 + jag(y, H, 9, edge_s) + streak[y] * 0.6
    top_clip = 5 + (2.2 * math.sin(y * 0.9))
    for x in range(W):
        if y < 3 or y > H - 4:
            vis = 0.0
        else:
            d = edge - x
            if d <= 0: vis = 1.0                           # solid body to the right of the edge
            else: vis = max(0.0, 1.0 - d / 30.0) ** 2.2    # spray fade to the left
        # soften the same torn top / bottom edge as the centre strip
        if y < top_clip: vis *= max(0.0, 1 - (top_clip - y) / 5.0) ** 1.6
        if y > H - top_clip: vis *= max(0.0, 1 - (y - (H - top_clip)) / 5.0) ** 1.6
        if vis >= 1.0: a = 255
        else: a = random.randint(90, 235) if random.random() < vis * 0.85 else 0
        cp[x, y] = (255, 255, 255, a)

center.save("bar-center.png"); cap.save("bar-cap.png")
print("wrote bar-center.png", center.size, "bar-cap.png", cap.size)

# ---- masking tape ------------------------------------------------------------
def tape(w=84, h=22, seed=5):
    random.seed(seed)
    im = Image.new("RGBA", (w, h), (255, 255, 255, 0)); p = im.load()
    left = [random.randint(0, 6) for _ in range(h)]
    right = [random.randint(0, 6) for _ in range(h)]
    for y in range(h):
        streak = random.randint(-22, 22)                 # fibre streaks along the tape
        for x in range(w):
            if x < left[y] or x >= w - right[y]: continue
            a = 205 + streak + random.randint(-14, 14)
            if y < 2 or y >= h - 2: a -= 25             # slightly thinner, lifted edges
            p[x, y] = (255, 255, 255, max(60, min(235, a)))
    return im
tape(84, 22, 5).save("tape-a.png"); tape(72, 20, 9).save("tape-b.png")
print("wrote tape-a.png tape-b.png")
