"""Generate the Keramika / Ада brand logo.
Design: rich rose-to-peach rounded squircle with a crisp glossy-white "K"
monogram and an AI sparkle accent. Produces all launcher / splash sizes.
"""
import math
from PIL import Image, ImageDraw


SS = 4  # supersample factor


def horizontal_gradient(size, c1, c2):
    w, h = size
    img = Image.new("RGB", size)
    px = img.load()
    for x in range(w):
        t = x / max(1, w - 1)
        col = tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))
        for y in range(h):
            px[x, y] = col
    return img


def rounded_rect_mask(size, radius):
    w, h = size
    mask = Image.new("L", size, 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=radius, fill=255)
    return mask


def make_tile(base, radius_frac, colors, glow=False):
    """Rounded squircle tile with a diagonal gradient and soft inner glow."""
    w, h = base
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    grad = Image.new("RGB", (w, h))
    gpx = grad.load()
    c1, c2 = colors
    for y in range(h):
        for x in range(w):
            t = (x / max(1, w - 1) + y / max(1, h - 1)) / 2
            gpx[x, y] = tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))
    mask = rounded_rect_mask((w, h), int(w * radius_frac))
    im.paste(grad, (0, 0), mask)
    if glow:
        # inner white glow to lift center
        glow_layer = Image.new("L", (w, h), 0)
        gd = ImageDraw.Draw(glow_layer)
        cx, cy = w / 2, h / 2
        r = w * 0.42
        for i in range(60, 0, -1):
            rr = r * i / 60
            alpha = int(35 * (i / 60) ** 2)
            gd.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=alpha)
        white = Image.new("RGBA", (w, h), (255, 255, 255, 255))
        im.paste(white, (0, 0), Image.composite(glow_layer, Image.new("L", (w, h), 0), mask))
    return im


def draw_k(d, cx, cy, s, width, color, shadow=None):
    """Bold round-cap 'K'. s = half of vertical span; diagonals meet at middle."""
    x0 = cx - s
    x1 = cx + s
    y0 = cy - s
    y2 = cy - s * 0.05
    yb = cy + s
    rr = width / 2
    segs = [
        (x0, y0, x0, yb),
        (x0, y0, x1, y2),
        (x0, y2, x1, yb),
    ]
    if shadow:
        sx, sy = shadow
        for (ax, ay, bx, by) in segs:
            d.line([ax + sx, ay + sy, bx + sx, by + sy],
                   fill=(120, 40, 50, 110), width=width, joint="curve")
            for px_, py_ in [(ax + sx, ay + sy), (bx + sx, by + sy)]:
                d.ellipse([px_ - rr, py_ - rr, px_ + rr, py_ + rr],
                          fill=(120, 40, 50, 110))
    for (ax, ay, bx, by) in segs:
        d.line([ax, ay, bx, by], fill=color, width=width, joint="curve")
        for px_, py_ in [(ax, ay), (bx, by)]:
            d.ellipse([px_ - rr, py_ - rr, px_ + rr, py_ + rr], fill=color)


def draw_sparkle(d, cx, cy, r, color):
    pts = []
    for a_deg in (-90, 0, 90, 180):
        a = math.radians(a_deg)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    d.polygon(
        [
            pts[0],
            (cx + r * 0.34, cy + r * 0.34),
            pts[1],
            (cx - r * 0.34, cy + r * 0.34),
            pts[2],
            (cx - r * 0.34, cy - r * 0.34),
            pts[3],
            (cx + r * 0.34, cy - r * 0.34),
        ],
        fill=color,
    )
    dr = int(r * 0.20)
    d.ellipse([cx + r * 1.2 - dr, cy - r * 1.05 - dr, cx + r * 1.2 + dr, cy - r * 1.05 + dr],
              fill=color)
    d.ellipse([cx - r * 1.15 - dr, cy + r * 1.1 - dr, cx - r * 1.15 + dr, cy + r * 1.1 + dr],
              fill=color)


def build_logo(size):
    """Full emblem tile (splash avatar, notification large)."""
    w = h = size
    W = H = w * SS
    colors = ((232, 96, 132), (255, 158, 120))  # rose -> tangerine
    tile = make_tile((W, H), 0.25, colors, glow=True)
    d = ImageDraw.Draw(tile)
    s = 0.27 * W
    draw_k(d, 0.5 * W, 0.52 * H, s, int(0.20 * W), (255, 255, 255, 255),
           shadow=(int(0.015 * W), int(0.04 * H)))
    draw_sparkle(d, 0.72 * W, 0.28 * H, 0.075 * W, (255, 251, 240, 255))
    return tile.resize((w, h), Image.LANCZOS)


def build_foreground(size):
    """Full logo tile (gradient + K + sparkle) filling the whole canvas.
    Launcher mask (circle/squircle) clips it to the icon shape, so the
    icon looks exactly like the splash logo: rose→tangerine gradient with
    white K. Background gradient XML matches, so any sliver between the
    mask and the icon edge still shows the same gradient."""
    w = h = size
    W = H = w * SS
    colors = ((232, 96, 132), (255, 158, 120))  # rose -> tangerine
    # full-bleed gradient (no rounded corners — the mask shapes it)
    grad = Image.new("RGB", (W, H))
    gpx = grad.load()
    c1, c2 = colors
    for y in range(H):
        for x in range(W):
            t = (x / max(1, W - 1) + y / max(1, H - 1)) / 2
            gpx[x, y] = tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))
    canvas = grad.convert("RGBA")
    # soft inner glow to lift center (same as splash tile)
    glow = Image.new("L", (W, H), 0)
    gd = ImageDraw.Draw(glow)
    cx, cy = W / 2, H / 2
    r = W * 0.42
    for i in range(60, 0, -1):
        rr = r * i / 60
        alpha = int(35 * (i / 60) ** 2)
        gd.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=alpha)
    white = Image.new("RGBA", (W, H), (255, 255, 255, 255))
    mask = Image.new("L", (W, H), 255)
    canvas.paste(white, (0, 0), Image.composite(glow, Image.new("L", (W, H), 0), mask))
    d = ImageDraw.Draw(canvas)
    # K centered in the safe zone (~66% of the icon), same proportions as splash
    s = 0.21 * W
    draw_k(d, 0.5 * W, 0.52 * H, s, int(0.16 * W), (255, 255, 255, 255),
           shadow=(int(0.015 * W), int(0.04 * H)))
    draw_sparkle(d, 0.70 * W, 0.30 * H, 0.075 * W, (255, 251, 240, 255))
    return canvas.resize((w, h), Image.LANCZOS)


def build_monochrome(size):
    """White silhouette glyph for themed (tinted) icons."""
    w = h = size
    W = H = w * SS
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(canvas)
    s = 0.27 * W
    draw_k(d, 0.5 * W, 0.52 * H, s, int(0.17 * W), (255, 255, 255, 255))
    return canvas.resize((w, h), Image.LANCZOS)


def main():
    build_logo(768).save("assets/keramika.png")
    build_foreground(432).save("android/app/src/main/res/drawable/ic_launcher_foreground.png")
    build_monochrome(432).save("android/app/src/main/res/drawable/ic_launcher_monochrome.png")
    build_logo(216).save("android/app/src/main/res/drawable-nodpi/ic_notification_large.png")
    print("done")


if __name__ == "__main__":
    main()