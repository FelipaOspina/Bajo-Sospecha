#!/usr/bin/env python3
"""Genera los biseles del modal de inspección (PNG con fondo transparente, aptos para 9-slice).

    python3 tools/generate_bezels.py        # requiere Pillow y numpy

Escribe en client/assets/ui/bezels/:
  bezel_smartphone.png       celular de cristal oscuro      (9-slice: 64 px, estirado)
  bezel_monitor.png          monitor / terminal cibernética (9-slice: 40 px, centro en mosaico)
  bezel_paper_clipboard.png  carpeta con papel rugoso       (9-slice: 44 px, centro en mosaico)
Los márgenes 9-slice están también en las vistas (scripts/ui/frames/*Frame.gd → bezel_patch()).
Paleta: UiPalette (navy #0B0F19, ámbar #E5A93C, cian #00E5FF). Determinista (semilla fija).
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "client" / "assets" / "ui" / "bezels"
SS = 2  # supersampling para bordes suaves
rng = np.random.default_rng(7)


def rounded_mask(size, box, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius, fill=255)
    return m


def vertical_gradient(size, top, bottom):
    w, h = size
    t = np.linspace(0, 1, h)[:, None, None]
    a, b = np.array(top, float), np.array(bottom, float)
    arr = (a * (1 - t) + b * t).repeat(w, axis=1)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def shadow(size, box, radius, blur, offset=(0, 0), alpha=150):
    m = Image.new("L", size, 0)
    x0, y0, x1, y1 = box
    ImageDraw.Draw(m).rounded_rectangle((x0 + offset[0], y0 + offset[1], x1 + offset[0], y1 + offset[1]), radius=radius, fill=alpha)
    m = m.filter(ImageFilter.GaussianBlur(blur))
    s = Image.new("RGBA", size, (0, 0, 0, 0))
    s.putalpha(m)
    return s


def layer(size, fill, mask):
    img = Image.new("RGBA", size, fill)
    img.putalpha(ImageChops.multiply(mask, Image.new("L", size, fill[3])))
    return img


def finish(img, name):
    img = img.resize((img.width // SS, img.height // SS), Image.LANCZOS)
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / name, optimize=True)
    print("ok", OUT / name, img.size)


# ───── Celular de cristal oscuro ─────
def smartphone():
    W, H = 320 * SS, 560 * SS
    size = (W, H)
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    pad = 10 * SS
    body = (pad, pad, W - pad, H - pad)
    img.alpha_composite(shadow(size, body, 46 * SS, 6 * SS, (0, 3 * SS), 170))
    # Marco metálico oscuro con un filo ámbar muy tenue.
    img.alpha_composite(layer(size, (229, 169, 60, 90), rounded_mask(size, body, 46 * SS)))
    inner = tuple(v + d for v, d in zip(body, (2 * SS, 2 * SS, -2 * SS, -2 * SS)))
    grad = vertical_gradient(size, (34, 40, 56, 255), (12, 15, 25, 255))
    grad.putalpha(rounded_mask(size, inner, 44 * SS))
    img.alpha_composite(grad)
    # Pantalla (cristal negro azulado) y reflejo diagonal.
    screen = (body[0] + 14 * SS, body[1] + 14 * SS, body[2] - 14 * SS, body[3] - 14 * SS)
    img.alpha_composite(layer(size, (7, 10, 18, 255), rounded_mask(size, screen, 34 * SS)))
    glare = Image.new("L", size, 0)
    ImageDraw.Draw(glare).polygon([(screen[0], screen[1]), (screen[0] + 150 * SS, screen[1]), (screen[0], screen[1] + 260 * SS)], fill=22)
    glare = ImageChops.multiply(glare.filter(ImageFilter.GaussianBlur(30 * SS)), rounded_mask(size, screen, 34 * SS))
    g = Image.new("RGBA", size, (255, 255, 255, 0))
    g.putalpha(glare)
    img.alpha_composite(g)
    # Botones laterales.
    d = ImageDraw.Draw(img)
    for y0, y1 in ((120, 170), (185, 235)):
        d.rounded_rectangle((pad - 3 * SS, y0 * SS, pad + 1 * SS, y1 * SS), radius=2 * SS, fill=(60, 66, 84, 255))
    d.rounded_rectangle((W - pad - 1 * SS, 150 * SS, W - pad + 3 * SS, 215 * SS), radius=2 * SS, fill=(60, 66, 84, 255))
    finish(img, "bezel_smartphone.png")


# ───── Monitor / terminal cibernética ─────
def monitor():
    W, H = 640 * SS, 400 * SS
    size = (W, H)
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    pad = 8 * SS
    body = (pad, pad, W - pad, H - pad)
    img.alpha_composite(shadow(size, body, 14 * SS, 6 * SS, (0, 3 * SS), 170))
    # Metal cepillado: gris azulado con vetas horizontales.
    base = vertical_gradient(size, (70, 78, 96, 255), (32, 37, 50, 255))
    streaks = rng.normal(0, 7, (H, 1)).repeat(W, axis=1)
    arr = np.asarray(base).astype(float)
    arr[..., :3] = np.clip(arr[..., :3] + streaks[..., None], 0, 255)
    metal = Image.fromarray(arr.astype(np.uint8), "RGBA")
    metal.putalpha(rounded_mask(size, body, 14 * SS))
    img.alpha_composite(metal)
    # Bisel interior biselado y pantalla con brillo cian.
    screen = (body[0] + 20 * SS, body[1] + 20 * SS, body[2] - 20 * SS, body[3] - 20 * SS)
    lip = tuple(v + d for v, d in zip(screen, (-4 * SS, -4 * SS, 4 * SS, 4 * SS)))
    img.alpha_composite(layer(size, (10, 12, 18, 255), rounded_mask(size, lip, 9 * SS)))
    glow = Image.new("L", size, 0)
    ImageDraw.Draw(glow).rounded_rectangle(screen, radius=6 * SS, outline=180, width=3 * SS)
    glow = glow.filter(ImageFilter.GaussianBlur(4 * SS))
    c = Image.new("RGBA", size, (0, 229, 255, 0))
    c.putalpha(glow)
    img.alpha_composite(layer(size, (3, 6, 12, 255), rounded_mask(size, screen, 6 * SS)))
    img.alpha_composite(c)
    # Líneas de barrido CRT muy sutiles.
    scan = Image.new("L", size, 0)
    ds = ImageDraw.Draw(scan)
    for y in range(screen[1], screen[3], 3 * SS):
        ds.line((screen[0], y, screen[2], y), fill=14, width=SS)
    scan = ImageChops.multiply(scan, rounded_mask(size, screen, 6 * SS))
    sl = Image.new("RGBA", size, (0, 229, 255, 0))
    sl.putalpha(scan)
    img.alpha_composite(sl)
    # LED de encendido, en la esquina (las esquinas del 9-slice no se estiran).
    d = ImageDraw.Draw(img)
    cx, cy = body[2] - 14 * SS, body[3] - 9 * SS
    d.ellipse((cx - 3 * SS, cy - 3 * SS, cx + 3 * SS, cy + 3 * SS), fill=(0, 229, 255, 255))
    finish(img, "bezel_monitor.png")


# ───── Carpeta con papel rugoso ─────
def paper_clipboard():
    W, H = 480 * SS, 600 * SS
    size = (W, H)
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    pad = 12 * SS
    folder = (pad, pad + 6 * SS, W - pad, H - pad)
    img.alpha_composite(shadow(size, folder, 10 * SS, 8 * SS, (2 * SS, 5 * SS), 160))
    # Carpeta de cartón kraft.
    kraft = vertical_gradient(size, (150, 112, 70, 255), (118, 86, 52, 255))
    karr = np.asarray(kraft).astype(float)
    karr[..., :3] = np.clip(karr[..., :3] + rng.normal(0, 6, (H, W, 1)), 0, 255)
    kraft = Image.fromarray(karr.astype(np.uint8), "RGBA")
    kraft.putalpha(rounded_mask(size, folder, 10 * SS))
    img.alpha_composite(kraft)
    # Hoja con bordes rugosos: rectángulo con desplazamiento aleatorio del contorno.
    sheet = (folder[0] + 16 * SS, folder[1] + 14 * SS, folder[2] - 16 * SS, folder[3] - 16 * SS)
    pts = []
    def edge(a, b, n):
        for i in range(n + 1):
            t = i / n
            x = a[0] + (b[0] - a[0]) * t + rng.normal(0, 0.9 * SS)
            y = a[1] + (b[1] - a[1]) * t + rng.normal(0, 0.9 * SS)
            pts.append((x, y))
    x0, y0, x1, y1 = sheet
    edge((x0, y0), (x1, y0), 160); edge((x1, y0), (x1, y1), 200)
    edge((x1, y1), (x0, y1), 160); edge((x0, y1), (x0, y0), 200)
    sm = Image.new("L", size, 0)
    ImageDraw.Draw(sm).polygon(pts, fill=255)
    img.alpha_composite(shadow(size, sheet, 2 * SS, 3 * SS, (SS, 2 * SS), 110))
    paper = Image.new("RGBA", size, (245, 237, 214, 255))
    parr = np.asarray(paper).astype(float)
    blotches = Image.fromarray(((rng.normal(0, 1, (H // 6, W // 6)) * 30) + 128).clip(0, 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)
    grain = rng.normal(0, 4, (H, W, 1)) + (np.asarray(blotches).astype(float)[..., None] - 128) * 0.08
    parr[..., :3] = np.clip(parr[..., :3] + grain, 0, 255)
    paper = Image.fromarray(parr.astype(np.uint8), "RGBA")
    paper.putalpha(sm)
    img.alpha_composite(paper)
    finish(img, "bezel_paper_clipboard.png")


if __name__ == "__main__":
    smartphone()
    monitor()
    paper_clipboard()
