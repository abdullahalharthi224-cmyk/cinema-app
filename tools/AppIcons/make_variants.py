"""Alternate app icons: Cinema's "C" monogram (a ring cradling a play button) in eight styles."""
import math, random, sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops, ImageFont

S = 2048
OUT = sys.argv[1]

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))

def linear(c1, c2, angle=90, size=256, stops=None):
    """A gradient drawn small then scaled up (smooth and fast)."""
    g = Image.new("RGB", (size, size)); px = g.load()
    ax, ay = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    vals = [x * ax + y * ay for x in (0, size) for y in (0, size)]
    lo, hi = min(vals), max(vals)
    for y in range(size):
        for x in range(size):
            t = ((x * ax + y * ay) - lo) / (hi - lo)
            if stops:
                for i in range(len(stops) - 1):
                    (t0, a), (t1, b) = stops[i], stops[i + 1]
                    if t <= t1:
                        px[x, y] = lerp(a, b, (t - t0) / (t1 - t0) if t1 > t0 else 0); break
            else:
                px[x, y] = lerp(c1, c2, t)
    return g.resize((S, S), Image.BICUBIC)

def radial(center, radius, inner, outer, size=256):
    img = Image.new("RGB", (size, size), outer); px = img.load()
    k = size / S
    cx, cy, r = center[0] * k, center[1] * k, radius * k
    for y in range(size):
        for x in range(size):
            d = min(math.hypot(x - cx, y - cy) / r, 1)
            px[x, y] = lerp(inner, outer, d * d * (3 - 2 * d))
    return img.resize((S, S), Image.BICUBIC)

def solid(c): return Image.new("RGB", (S, S), c)

def smooth(mask, r):
    return mask.filter(ImageFilter.GaussianBlur(r)).point(lambda v: 255 if v > 127 else 0)

def ring_mask(scale=1.0):
    ring = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(ring)
    r = S * 0.33 * scale; t = S * 0.075 * scale
    d.arc((S/2 - r, S/2 - r, S/2 + r, S/2 + r), start=50, end=310, fill=255, width=int(t))
    for ang in (50, 310):
        a = math.radians(ang); rr = r - t / 2
        x, y = S/2 + rr * math.cos(a), S/2 + rr * math.sin(a)
        d.ellipse((x - t/2, y - t/2, x + t/2, y + t/2), fill=255)
    return smooth(ring, 14)

def play_mask(scale=1.0):
    m = Image.new("L", (S, S), 0)
    h = S * 0.27 * scale; w = h * math.sqrt(3) / 2
    cx, cy = S/2 + S * 0.01, S/2
    x0 = cx - w * 0.42
    ImageDraw.Draw(m).polygon([(x0, cy - h/2), (x0, cy + h/2), (x0 + w, cy)], fill=255)
    return smooth(m, 26)

RING, PLAY = ring_mask(), play_mask()
LOGO = ImageChops.lighter(RING, PLAY)

def paint(img, fill, mask):
    if isinstance(fill, tuple): fill = solid(fill)
    img.paste(fill, (0, 0), mask)
    return img

def glow(img, color, mask, blur, strength):
    g = mask.filter(ImageFilter.GaussianBlur(blur)).point(lambda v: min(255, int(v * strength)))
    return Image.composite(solid(color), img, g)

def shadow(img, mask, offset, blur, alpha):
    s = Image.new("L", (S, S), 0); s.paste(mask, (0, offset))
    s = s.filter(ImageFilter.GaussianBlur(blur)).point(lambda v: int(v * alpha))
    return Image.composite(solid((0, 0, 0)), img, s)

def gloss(img, mask, top_alpha):
    hl = Image.new("L", (S, S), 0)
    ImageDraw.Draw(hl).ellipse((-S * 0.3, -S * 0.75, S * 1.3, S * 0.48), fill=top_alpha)
    hl = hl.filter(ImageFilter.GaussianBlur(10))
    img.paste((255, 255, 255), (0, 0), ImageChops.multiply(hl, mask))
    return img

def light():
    img = linear((252, 252, 253), (232, 233, 238), 90)
    img = shadow(img, LOGO, 18, 40, 0.18)
    paint(img, (28, 28, 32), RING)
    return paint(img, (201, 169, 98), PLAY)

def dark():
    img = solid((6, 6, 8))
    paint(img, (246, 246, 248), RING)
    return paint(img, (246, 246, 248), PLAY)

def gold():
    # A brushed-gold plate with the monogram pressed into it in black lacquer.
    img = linear(None, None, 60, stops=[(0, (255, 236, 179)), (0.35, (212, 170, 88)), (0.6, (245, 214, 140)), (1, (140, 98, 36))])
    rnd = random.Random(7)
    brush = Image.new("L", (S, S), 0); d = ImageDraw.Draw(brush)
    for _ in range(900):
        y = rnd.uniform(0, S); d.line((0, y, S, y + rnd.uniform(-8, 8)), fill=rnd.randint(0, 40), width=2)
    img = Image.composite(solid((255, 250, 230)), img, brush.filter(ImageFilter.GaussianBlur(1)).point(lambda v: v // 2))
    # Engraved edge: a light rim below, dark rim above.
    lo = Image.new("L", (S, S), 0); lo.paste(LOGO, (0, 10))
    img.paste((255, 244, 210), (0, 0), lo.point(lambda v: int(v * 0.8)))
    paint(img, linear((40, 32, 20), (8, 7, 6), 90), LOGO)
    return gloss(img, Image.new("L", (S, S), 255), 30)

def neon():
    img = radial((S/2, S/2), S * 0.75, (24, 10, 20), (4, 3, 6))
    tube_ring = ImageChops.subtract(RING, RING.filter(ImageFilter.MinFilter(41)))
    tube_ring = smooth(tube_ring, 6)
    pink, orange = (255, 60, 160), (255, 140, 40)
    img = glow(img, pink, RING, 120, 0.9)
    img = glow(img, pink, RING, 40, 1.4)
    paint(img, linear(orange, pink, 120), RING)
    paint(img, (255, 225, 240), RING.filter(ImageFilter.MinFilter(25)))
    img = glow(img, orange, PLAY, 70, 1.2)
    paint(img, orange, PLAY)
    return paint(img, (255, 236, 210), PLAY.filter(ImageFilter.MinFilter(21)))

def terminal():
    img = solid((3, 10, 5))
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 58)
    rnd = random.Random(42)
    words = ["let", "func", "play()", "{", "}", "if", "return", "stream", "0x1F", "await", "var", "=>", "true", "frame", "//", "C"]
    code = Image.new("L", (S, S), 0); d = ImageDraw.Draw(code)
    y = 40
    while y < S:
        x = 40 + rnd.choice([0, 0, 80, 160])
        line = " ".join(rnd.choice(words) for _ in range(rnd.randint(2, 6)))
        d.text((x, y), line, font=font, fill=rnd.randint(28, 62))
        y += 82
    img = Image.composite(solid((60, 255, 120)), img, code)
    # Scanlines.
    scan = Image.new("L", (S, S), 0); d = ImageDraw.Draw(scan)
    for yy in range(0, S, 10): d.line((0, yy, S, yy), fill=50, width=3)
    img = Image.composite(solid((0, 0, 0)), img, scan)
    # Dim the code behind the logo so it reads.
    img = Image.composite(solid((3, 10, 5)), img, LOGO.filter(ImageFilter.GaussianBlur(60)).point(lambda v: int(v * 0.9)))
    img = glow(img, (40, 255, 110), LOGO, 60, 0.9)
    paint(img, (70, 255, 130), RING)
    return paint(img, (190, 255, 205), PLAY)

def retro():
    horizon = int(S * 0.62)
    img = linear(None, None, 90, stops=[(0, (38, 8, 70)), (0.45, (150, 30, 140)), (0.62, (255, 110, 120)), (0.63, (20, 4, 40)), (1, (40, 6, 70))])
    # Striped sun sitting on the horizon.
    sun = Image.new("L", (S, S), 0); d = ImageDraw.Draw(sun)
    R = S * 0.36; d.ellipse((S/2 - R, horizon - R * 1.15, S/2 + R, horizon + R * 0.85), fill=255)
    cut = Image.new("L", (S, S), 0); dc = ImageDraw.Draw(cut)
    yy, gap = horizon - 40, 14
    while yy > horizon - R: dc.rectangle((0, yy, S, yy + gap), fill=255); yy -= 70; gap = max(gap - 2, 2)
    dc.rectangle((0, horizon, S, S), fill=255)
    sun = ImageChops.subtract(sun, cut)
    img = paint(img, linear((255, 220, 90), (255, 60, 140), 90), sun)
    # Perspective grid.
    grid = Image.new("L", (S, S), 0); d = ImageDraw.Draw(grid)
    for i in range(-12, 13):
        d.line((S/2 + i * 40, horizon, S/2 + i * 380, S), fill=255, width=6)
    k = 0
    while True:
        y = horizon + 18 * (1.45 ** k)
        if y > S: break
        d.line((0, y, S, y), fill=255, width=6); k += 1
    img = glow(img, (255, 60, 200), grid, 14, 1.0)
    img = paint(img, (255, 120, 230), grid)
    # Chrome monogram.
    img = shadow(img, LOGO, 16, 30, 0.6)
    img = glow(img, (80, 220, 255), LOGO, 60, 0.6)
    chrome = linear(None, None, 90, stops=[(0, (240, 250, 255)), (0.48, (120, 200, 255)), (0.52, (60, 30, 110)), (1, (255, 170, 240))])
    return paint(img, chrome, LOGO)

def aqua():
    img = linear(None, None, 90, stops=[(0, (120, 220, 255)), (0.5, (20, 140, 230)), (1, (8, 60, 150))])
    bub = Image.new("L", (S, S), 0); d = ImageDraw.Draw(bub)
    rnd = random.Random(3)
    for _ in range(14):
        r = rnd.uniform(20, 70); x, y = rnd.uniform(0, S), rnd.uniform(S * 0.5, S)
        d.ellipse((x - r, y - r, x + r, y + r), outline=90, width=6)
    img = Image.composite(solid((220, 245, 255)), img, bub.filter(ImageFilter.GaussianBlur(2)))
    img = shadow(img, LOGO, 26, 40, 0.45)
    glass = linear((255, 255, 255), (170, 225, 255), 90)
    paint(img, glass, LOGO)
    inner = LOGO.filter(ImageFilter.MinFilter(15))
    paint(img, linear((210, 240, 255), (60, 170, 240), 90), inner)
    img = gloss(img, LOGO, 200)
    return gloss(img, Image.new("L", (S, S), 255), 55)

styles = {"Light": light, "Dark": dark, "Gold": gold, "Neon": neon, "Terminal": terminal, "Retro": retro, "Aqua": aqua}
only = sys.argv[2:] or list(styles)
for name in only:
    styles[name]().resize((1024, 1024), Image.LANCZOS).save(f"{OUT}/AppIcon-{name}.png", optimize=True)
    print(name)
