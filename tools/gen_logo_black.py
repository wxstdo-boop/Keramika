# -*- coding: utf-8 -*-
"""Быстрая генерация чёрной эмблемы «K» (без долгих Python-циклов).

Строит один холст 2048x2048 (чёрный фон + белая K + искра + мягкое свечение),
затем ресайзит во все нужные размеры. Градиент считается на маленьком холсте
и растягивается LANCZOS'ом — вместо 16M пикселей в чистых циклах.

Записывает:
  assets/keramika.png (1024)                          — сплэш + ава у «Выйти»
  drawable/ic_launcher_foreground.png (432)           — полноцветная иконка
  drawable/ic_launcher_monochrome.png (432)           — белый силуэт (монохром)
  drawable-nodpi/ic_notification_large.png (216)      — иконка уведомлений
  mipmap-*/ic_launcher.png + ic_launcher_round.png (48..192)
"""
import math
import os
from PIL import Image, ImageDraw

BASE = r'C:\Wettixal\keramika-current'
BIG = 2048  # рабочее разрешение: SS=2 для 1024px
BLACK_A = (18, 18, 20)
BLACK_B = (0, 0, 0)
WHITE = (255, 255, 255, 255)
SPARKLE = (255, 251, 240, 255)


def _diag_gradient(size, c1, c2):
    """Диагональный градиент между двумя цветами (быстро: маленький холст)."""
    small = Image.new('RGB', (64, 64))
    px = small.load()
    for y in range(64):
        for x in range(64):
            t = (x / 63 + y / 63) / 2
            px[x, y] = tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))
    return small.resize(size, Image.LANCZOS)


def _glow(size, cx, cy, r, strength=35):
    """Мягкое внутреннее свечение (60 вложенных эллипсов)."""
    layer = Image.new('L', size, 0)
    d = ImageDraw.Draw(layer)
    for i in range(60, 0, -1):
        rr = r * i / 60
        alpha = int(strength * (i / 60) ** 2)
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=alpha)
    return layer


def _draw_k(d, cx, cy, s, width, color):
    """Крупная белая «K» с круглыми концами (как в старом логотипе)."""
    x0 = cx - s
    x1 = cx + s
    y0 = cy - s
    y2 = cy - s * 0.05
    yb = cy + s
    rr = width / 2
    for (ax, ay, bx, by) in [
        (x0, y0, x0, yb),
        (x0, y0, x1, y2),
        (x0, y2, x1, yb),
    ]:
        d.line([ax, ay, bx, by], fill=color, width=width, joint='curve')
        for p in [(ax, ay), (bx, by)]:
            d.ellipse([p[0] - rr, p[1] - rr, p[0] + rr, p[1] + rr], fill=color)


def _draw_sparkle(d, cx, cy, r, color):
    pts = []
    for a_deg in (-90, 0, 90, 180):
        a = math.radians(a_deg)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    d.polygon(
        [pts[0], (cx + r * 0.34, cy + r * 0.34), pts[1],
         (cx - r * 0.34, cy + r * 0.34), pts[2],
         (cx - r * 0.34, cy - r * 0.34), pts[3],
         (cx + r * 0.34, cy - r * 0.34)],
        fill=color,
    )


def _emblem(full_bleed):
    """Холст 2048x2048: чёрный фон + свечение + K + искра."""
    canvas = _diag_gradient((BIG, BIG), BLACK_A, BLACK_B).convert('RGBA')
    white = Image.new('RGBA', (BIG, BIG), (255, 255, 255, 255))
    glow = _glow((BIG, BIG), BIG / 2, BIG / 2, BIG * 0.42)
    canvas.paste(white, (0, 0), glow)
    if not full_bleed:
        # Скруглённый квадрат (как бейдж): прозрачные углы.
        mask = Image.new('L', (BIG, BIG), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [0, 0, BIG - 1, BIG - 1], radius=int(BIG * 0.25), fill=255)
        canvas.putalpha(mask)
    d = ImageDraw.Draw(canvas)
    _draw_k(d, 0.5 * BIG, 0.52 * BIG, 0.27 * BIG, int(0.20 * BIG), WHITE)
    _draw_sparkle(d, 0.72 * BIG, 0.28 * BIG, 0.075 * BIG, SPARKLE)
    return canvas


def _monochrome():
    """Белый силуэт «K» на прозрачном (для themed-иконок Android)."""
    canvas = Image.new('RGBA', (BIG, BIG), (0, 0, 0, 0))
    d = ImageDraw.Draw(canvas)
    _draw_k(d, 0.5 * BIG, 0.52 * BIG, 0.27 * BIG, int(0.17 * BIG), WHITE)
    return canvas


def main():
    res = os.path.join(BASE, 'android', 'app', 'src', 'main', 'res')
    # Сплэш / ава у «Выйти» — скруглённая плитка.
    tile = _emblem(full_bleed=False)
    tile.resize((1024, 1024), Image.LANCZOS).save(
        os.path.join(BASE, 'assets', 'keramika.png'))
    tile.resize((216, 216), Image.LANCZOS).save(
        os.path.join(res, 'drawable-nodpi', 'ic_notification_large.png'))
    # Лончер — full-bleed (маска сама обрежет углы).
    full = _emblem(full_bleed=True)
    full.resize((432, 432), Image.LANCZOS).save(
        os.path.join(res, 'drawable', 'ic_launcher_foreground.png'))
    _monochrome().resize((432, 432), Image.LANCZOS).save(
        os.path.join(res, 'drawable', 'ic_launcher_monochrome.png'))
    for d, size in [('mipmap-mdpi', 48), ('mipmap-hdpi', 72),
                    ('mipmap-xhdpi', 96), ('mipmap-xxhdpi', 144),
                    ('mipmap-xxxhdpi', 192)]:
        rgb = full.resize((size, size), Image.LANCZOS).convert('RGB')
        rgb.save(os.path.join(res, d, 'ic_launcher.png'))
        rgb.save(os.path.join(res, d, 'ic_launcher_round.png'))
    print('done')


if __name__ == '__main__':
    main()