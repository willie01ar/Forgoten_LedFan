import math, sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops

S = 4                      # supersample
N = 1024 * S
C = N / 2
OUT = sys.argv[1] if len(sys.argv) > 1 else "."
SMALL = len(sys.argv) > 2 and sys.argv[2] == "small"

FONT = {  # 5x7, rows top->bottom
    "H": ["10001","10001","10001","11111","10001","10001","10001"],
    "E": ["11111","10000","10000","11110","10000","10000","11111"],
    "L": ["10000","10000","10000","10000","10000","10000","11111"],
    "#": ["11111"]*7,
    "O": ["01110","10001","10001","10001","10001","10001","01110"],
}
TEXT = "HELLO"
if SMALL: TEXT = "#####"
COLUMNS, ROWS = 156, 11
R_IN, R_OUT = 0.232 * N, 0.372 * N           # LED band, hub to tip
RED = (255, 59, 48)

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))

def squircle_mask(size, full_bleed):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    if full_bleed:
        d.rectangle([0, 0, size, size], fill=255)
    else:  # macOS grid: 824pt body, 100pt inset, ~185pt radius
        k = size / 1024
        d.rounded_rectangle([100*k, 100*k, 924*k, 924*k], radius=185.4*k, fill=255)
    return m

def radial(size, inner, outer, r0, r1, cx=None, cy=None):
    cx = size/2 if cx is None else cx; cy = size/2 if cy is None else cy
    img = Image.new("RGB", (size, size), outer); d = ImageDraw.Draw(img)
    steps = 160
    for i in range(steps, -1, -1):
        t = i / steps; r = r0 + (r1 - r0) * t
        d.ellipse([cx-r, cy-r, cx+r, cy+r], fill=lerp(inner, outer, t))
    return img

def background():
    # near-black, slightly warm at top so the red reads as light, not paint
    bg = Image.new("RGB", (N, N))
    d = ImageDraw.Draw(bg)
    for y in range(0, N, S):
        t = y / N
        d.rectangle([0, y, N, y+S], fill=lerp((38, 36, 42), (12, 12, 15), t))
    return bg

def led_positions():
    lit, unlit = [], []
    pixels = set()
    width = len(TEXT) * 6 - 1
    start = -(width // 2)
    for li, ch in enumerate(TEXT):
        for gy, row in enumerate(FONT[ch]):
            for gx, bit in enumerate(row):
                if bit == "1":
                    pixels.add((start + li*6 + gx, gy + 2))
                    if SMALL: pixels.add((start + li*6 + 5, gy + 2))  # rows 2..8 of 11
    step = 360 / COLUMNS
    for col in range(COLUMNS):
        rel = col - COLUMNS // 2
        rel_col = rel if rel <= COLUMNS//2 else rel - COLUMNS
        angle = math.radians(-90 + rel * step)
        for row in range(ROWS):
            r = R_OUT - (R_OUT - R_IN) * row / (ROWS - 1)   # row 0 = outermost
            p = (C + r*math.cos(angle), C + r*math.sin(angle), r)
            (lit if (rel, row) in pixels else unlit).append(p)
    return lit, unlit

def fan_layer():
    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    # motion-blurred blade disc
    disc = radial(N, (46, 46, 54), (26, 26, 31), 0, 0.43*N)
    dm = Image.new("L", (N, N), 0)
    ImageDraw.Draw(dm).ellipse([C-0.43*N, C-0.43*N, C+0.43*N, C+0.43*N], fill=255)
    dm = dm.filter(ImageFilter.GaussianBlur(3*S))
    layer.paste(disc, (0, 0), dm)
    # faint blade sweeps
    sweep = Image.new("L", (N, N), 0); sd = ImageDraw.Draw(sweep)
    for a in (20, 140, 260):
        sd.pieslice([C-0.41*N, C-0.41*N, C+0.41*N, C+0.41*N], a, a+70, fill=26)
    sweep = sweep.filter(ImageFilter.GaussianBlur(18*S))
    layer.paste(Image.new("RGB", (N, N), (120, 120, 135)), (0, 0), ImageChops.multiply(sweep, dm))
    # rim
    ImageDraw.Draw(layer).ellipse([C-0.43*N, C-0.43*N, C+0.43*N, C+0.43*N],
                                  outline=(70, 70, 80, 255), width=int(2.5*S))
    return layer

def hub_layer():
    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    r = 0.19 * N
    hub = radial(N, (30, 30, 34), (6, 6, 8), 0, r, cx=C, cy=C - 0.04*N)
    m = Image.new("L", (N, N), 0); ImageDraw.Draw(m).ellipse([C-r, C-r, C+r, C+r], fill=255)
    layer.paste(hub, (0, 0), m)
    ImageDraw.Draw(layer).ellipse([C-r, C-r, C+r, C+r], outline=(58, 58, 66, 255), width=int(2*S))
    return layer

def leds_layer():
    lit, unlit = led_positions()
    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for x, y, r in unlit:
        s = 3.1 * S * (r / R_OUT) ** 0.3
        d.ellipse([x-s, y-s, x+s, y+s], fill=(255, 255, 255, 20))
    glow = Image.new("RGBA", (N, N), (0, 0, 0, 0)); g = ImageDraw.Draw(glow)
    for x, y, r in lit:
        s = 9 * S
        g.ellipse([x-s, y-s, x+s, y+s], fill=RED + (255,))
    wide = glow.filter(ImageFilter.GaussianBlur(26*S))
    tight = glow.filter(ImageFilter.GaussianBlur(8*S))
    for _ in range(2):
        layer = Image.alpha_composite(layer, wide)
    layer = Image.alpha_composite(layer, tight)
    d = ImageDraw.Draw(layer)
    for x, y, r in lit:
        s = 6.2 * S * (r / R_OUT) ** 0.3
        d.ellipse([x-s, y-s, x+s, y+s], fill=(255, 92, 78, 255))
        c = s * 0.5
        d.ellipse([x-c, y-c, x+c, y+c], fill=(255, 214, 205, 255))
    return layer

def scale_into_grid(img):
    # fan artwork is drawn for a full-bleed square; shrink it into the 824 body
    k = 824 / 1024
    small = img.resize((int(N*k), int(N*k)), Image.LANCZOS)
    out = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    out.alpha_composite(small, (int(100*S), int(100*S)))
    return out

bg, fan, hub, leds = background(), fan_layer(), hub_layer(), leds_layer()
art = Image.alpha_composite(Image.alpha_composite(fan, hub), leds)

def down(img): return img.resize((1024, 1024), Image.LANCZOS)

# Icon Composer layers (full-bleed square, system applies the shape)
down(bg.convert("RGBA")).save(f"{OUT}/layer-0-background.png")
down(fan).save(f"{OUT}/layer-1-disc.png")
down(hub).save(f"{OUT}/layer-2-hub.png")
down(leds).save(f"{OUT}/layer-3-leds.png")

# Classic macOS icon: squircle body on the 1024 grid, with drop shadow
body = Image.alpha_composite(bg.convert("RGBA"), art)
body_scaled = scale_into_grid(body)
mask = squircle_mask(N, False)
icon_body = Image.new("RGBA", (N, N), (0, 0, 0, 0))
icon_body.paste(body_scaled, (0, 0), ImageChops.multiply(mask, body_scaled.getchannel("A")))
# inner hairline
edge = Image.new("RGBA", (N, N), (0, 0, 0, 0))
k = S
ImageDraw.Draw(edge).rounded_rectangle([100*k, 100*k, 924*k, 924*k], radius=185.4*k,
                                       outline=(255, 255, 255, 28), width=2*k)
icon_body = Image.alpha_composite(icon_body, edge)
shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
sm = mask.point(lambda v: v * 0.45)
shadow.paste(Image.new("RGBA", (N, N), (0, 0, 0, 255)), (0, int(10*S)), sm)
shadow = shadow.filter(ImageFilter.GaussianBlur(14*S))
final = Image.alpha_composite(shadow, icon_body)
down(final).save(f"{OUT}/icon_1024.png")
print("ok")
