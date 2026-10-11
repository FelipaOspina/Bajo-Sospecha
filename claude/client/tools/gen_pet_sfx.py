#!/usr/bin/env python3
"""Sintetiza los sonidos de la mascota del lobby (client/assets/audio/pets/*.wav).

Son obra propia del proyecto: no usan grabaciones, muestras ni bancos de sonido de
terceros. Cada sonido se construye desde cero con osciladores, ruido y filtros
(síntesis fuente-filtro: una "voz" con armónicos pasa por los formantes de una vocal,
como hace la garganta de un animal). Son aproximaciones caricaturescas, no grabaciones
reales: sirven de marcador hasta tener grabaciones con licencia adecuada (por ejemplo
CC0), que pueden sustituirlos dejando un WAV con el mismo nombre.

Uso (solo necesita Python 3, sin librerías externas):
    python3 client/tools/gen_pet_sfx.py            # escribe en client/assets/audio/pets/
    python3 client/tools/gen_pet_sfx.py otra/carpeta

Las semillas del ruido son fijas: ejecutarlo dos veces da los mismos archivos.
"""

import math
import os
import random
import struct
import sys
import wave

SR = 22050
TAU = 2.0 * math.pi


# ───── Piezas básicas ─────

def silence(dur):
    return [0.0] * int(dur * SR)


def env_points(n, points):
    """Envolvente por tramos rectos: points = [(t_segundos, valor), ...]."""
    out = [0.0] * n
    pts = sorted(points)
    j = 0
    for i in range(n):
        t = i / SR
        while j < len(pts) - 2 and t > pts[j + 1][0]:
            j += 1
        (t0, v0), (t1, v1) = pts[j], pts[min(j + 1, len(pts) - 1)]
        if t <= t0:
            out[i] = v0
        elif t >= t1:
            out[i] = v1
        else:
            out[i] = v0 + (v1 - v0) * (t - t0) / (t1 - t0)
    return out


def contour(n, points):
    """Curva de valores en el tiempo (frecuencia, formantes...) por tramos rectos."""
    return env_points(n, points)


def voice(f0, n, harmonics=14, tilt=1.0, jitter=0.0, rng=None):
    """Fuente "de garganta": suma de armónicos (cae ~1/k^tilt) con f0 variable.

    f0 es una lista (Hz por muestra). jitter añade aspereza (variación de tono)."""
    out = [0.0] * n
    phase = 0.0
    wob = 0.0
    for i in range(n):
        f = f0[i]
        if jitter and rng is not None:
            wob += (rng.uniform(-1.0, 1.0) - wob) * 0.02
            f *= 1.0 + jitter * wob
        phase += TAU * f / SR
        s = 0.0
        for k in range(1, harmonics + 1):
            if k * f >= SR * 0.45:
                break
            s += math.sin(k * phase) / (k ** tilt)
        out[i] = s
    return out


def sine(f0, n):
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        phase += TAU * f0[i] / SR
        out[i] = math.sin(phase)
    return out


def noise(n, rng):
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def pulses(rate, n, width=0.004, rng=None, jitter=0.0):
    """Tren de pulsos suaves (ronroneo, castañeteo): rate es una lista (Hz)."""
    out = [0.0] * n
    phase = 0.0
    w = max(1, int(width * SR))
    i = 0
    nxt = 0
    while i < n:
        if i >= nxt:
            amp = 1.0 + (rng.uniform(-jitter, jitter) if rng else 0.0)
            for j in range(w):
                if i + j < n:
                    out[i + j] += amp * math.sin(math.pi * j / w) ** 2
            period = SR / max(rate[min(i, n - 1)], 1.0)
            if rng and jitter:
                period *= 1.0 + rng.uniform(-jitter, jitter) * 0.3
            nxt = i + int(period)
        i += 1
    return out


def biquad(x, kind, freq, q=0.7):
    """Filtro RBJ. freq puede ser un número o una lista (Hz por muestra)."""
    n = len(x)
    y = [0.0] * n
    x1 = x2 = y1 = y2 = 0.0
    varying = isinstance(freq, list)
    coeffs = None
    for i in range(n):
        if coeffs is None or (varying and i % 32 == 0):
            f = min(max(freq[i] if varying else freq, 20.0), SR * 0.45)
            w0 = TAU * f / SR
            cw, sw = math.cos(w0), math.sin(w0)
            alpha = sw / (2.0 * q)
            if kind == "lp":
                b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
            elif kind == "hp":
                b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
            else:  # "bp": ganancia 1 en el centro
                b0, b1, b2 = alpha, 0.0, -alpha
            a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
            coeffs = (b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
        b0, b1, b2, a1, a2 = coeffs
        xi = x[i]
        yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, xi, y1, yi
        y[i] = yi
    return y


def formants(x, f1, f2, f3=None, q=6.0, gains=(1.0, 0.6, 0.25)):
    """Filtro de vocal: suma de tres pasabandas (F1, F2, F3; números o listas)."""
    n = len(x)
    out = [0.0] * n
    bands = [(f1, gains[0]), (f2, gains[1])]
    if f3 is not None:
        bands.append((f3, gains[2]))
    for f, g in bands:
        y = biquad(x, "bp", f, q)
        for i in range(n):
            out[i] += g * y[i]
    return out


def mul(a, b):
    return [p * q for p, q in zip(a, b)]


def add(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, v in enumerate(t):
            out[i] += v
    return out


def gain(x, g):
    return [v * g for v in x]


def place(base, x, at):
    """Mezcla x dentro de base empezando en el segundo at (alarga base si hace falta)."""
    start = int(at * SR)
    need = start + len(x)
    if len(base) < need:
        base = base + [0.0] * (need - len(base))
    for i, v in enumerate(x):
        base[start + i] += v
    return base


def normalize(x, rms_target, ceiling=0.95):
    """Iguala el volumen percibido (RMS) y redondea los picos con un limitador suave."""
    rms = math.sqrt(sum(v * v for v in x) / max(len(x), 1))
    k = rms_target / max(rms, 1e-9)
    return [ceiling * math.tanh(v * k / ceiling) for v in x]


def reverb(x, mix=0.18, room=0.78):
    """Sala pequeña (Schroeder: 4 peines y 2 pasatodo) para que no suene "seco"."""
    tail = int(0.35 * SR)
    src = x + [0.0] * tail
    n = len(src)
    wet = [0.0] * n
    for d in (1116, 1188, 1277, 1356):
        d = int(d * SR / 44100)
        buf = [0.0] * n
        for i in range(n):
            buf[i] = src[i] + (room * buf[i - d] if i >= d else 0.0)
        for i in range(n):
            wet[i] += buf[i] * 0.25
    for d in (556, 441):
        d = int(d * SR / 44100)
        out = [0.0] * n
        for i in range(n):
            xd = wet[i - d] if i >= d else 0.0
            yd = out[i - d] if i >= d else 0.0
            out[i] = -0.5 * wet[i] + xd + 0.5 * yd
        wet = out
    return [src[i] * (1 - mix) + wet[i] * mix for i in range(n)]


def fade(x, fin=0.005, fout=0.03):
    n = len(x)
    a, b = int(fin * SR), int(fout * SR)
    for i in range(min(a, n)):
        x[i] *= i / a
    for i in range(min(b, n)):
        x[n - 1 - i] *= i / b
    return x


# ───── Sonidos ─────

def vocal(dur, f0_pts, amp_pts, f1, f2, f3=None, harmonics=14, tilt=1.0, breath=0.0, jitter=0.0, seed=1, q=6.0):
    """Una "sílaba" animal: voz con armónicos + aliento, por los formantes de una vocal."""
    rng = random.Random(seed)
    n = int(dur * SR)
    src = voice(contour(n, f0_pts), n, harmonics, tilt, jitter, rng)
    if breath:
        src = add(src, gain(noise(n, rng), breath))
    f1v = contour(n, f1) if isinstance(f1, list) else f1
    f2v = contour(n, f2) if isinstance(f2, list) else f2
    f3v = contour(n, f3) if isinstance(f3, list) else f3
    return mul(formants(src, f1v, f2v, f3v, q), env_points(n, amp_pts))


def gato_feliz():   # maullido "mi-a-u"
    d = 0.75
    return reverb(vocal(d, [(0, 620), (0.25, 860), (0.5, 760), (d, 520)], [(0, 0), (0.06, 1), (0.55, 0.85), (d, 0)],
                        [(0, 320), (0.25, 820), (0.55, 760), (d, 380)], [(0, 2300), (0.25, 1400), (0.55, 1200), (d, 800)],
                        3000, harmonics=16, breath=0.06, jitter=0.02, seed=11), 0.12)


def gato_caricia():   # ronroneo: pulsos de ~26 Hz al espirar y al inspirar
    rng = random.Random(12)
    d = 1.9
    n = int(d * SR)
    p = pulses(contour(n, [(0, 25), (d, 27)]), n, 0.006, rng, 0.25)
    p = add(p, gain(noise(n, rng), 0.12))
    body = biquad(biquad(p, "lp", 650, 0.9), "hp", 60)
    cycle = env_points(n, [(0, 0), (0.1, 1), (0.8, 0.85), (0.95, 0.35), (1.05, 0.7), (1.75, 0.6), (d, 0)])
    return mul(body, cycle)


def perro_feliz():   # dos ladridos cortos y alegres
    out = []
    for k, at in enumerate((0.0, 0.26)):
        b = vocal(0.16, [(0, 520 + 60 * k), (0.04, 470 + 60 * k), (0.16, 330)], [(0, 0), (0.008, 1), (0.05, 0.75), (0.16, 0)],
                  720, 1250, 2600, harmonics=18, tilt=0.8, breath=0.35, jitter=0.08, seed=21 + k, q=4.0)
        out = place(out, b, at)
    return reverb(out, 0.12)


def perro_caricia():   # jadeo contento con un gemidito
    rng = random.Random(22)
    d = 1.3
    n = int(d * SR)
    pant = biquad(noise(n, rng), "bp", 1900, 1.2)
    rhythm = [max(0.0, math.sin(math.pi * 5.0 * i / SR)) ** 2 for i in range(n)]
    whine = gain(mul(sine(contour(n, [(0, 900), (0.5, 1180), (d, 980)]), n), env_points(n, [(0, 0), (0.3, 0.0), (0.5, 0.35), (1.0, 0.25), (d, 0)])), 0.6)
    return add(mul(pant, rhythm), whine)


def lobo_feliz():   # aullido suave
    d = 1.7
    n = int(d * SR)
    f0 = contour(n, [(0, 340), (0.45, 520), (1.2, 540), (d, 420)])
    f0 = [f * (1 + 0.012 * math.sin(TAU * 5.0 * i / SR)) for i, f in enumerate(f0)]
    rng = random.Random(31)
    src = add(voice(f0, n, 6, 1.8, 0.0, rng), gain(noise(n, rng), 0.03))
    x = mul(formants(src, contour(n, [(0, 380), (0.6, 520), (d, 420)]), 900, 2400, 7.0), env_points(n, [(0, 0), (0.25, 0.8), (1.2, 1), (d, 0)]))
    return reverb(x, 0.3, 0.84)


def lobo_caricia():   # gemido cariñoso
    out = []
    for k, at in enumerate((0.0, 0.42)):
        n = int(0.34 * SR)
        s = mul(sine(contour(n, [(0, 950 + 80 * k), (0.15, 1120 + 80 * k), (0.34, 900)]), n), env_points(n, [(0, 0), (0.06, 1), (0.25, 0.7), (0.34, 0)]))
        out = place(out, s, at)
    return reverb(out, 0.2)


def leon_feliz():   # gruñido-rugido suave (nada de miedo)
    d = 1.0
    x = vocal(d, [(0, 120), (0.3, 140), (d, 85)], [(0, 0), (0.18, 1), (0.6, 0.8), (d, 0)],
              [(0, 520), (0.4, 640), (d, 480)], [(0, 980), (d, 850)], 2300, harmonics=26, tilt=0.9, breath=0.55, jitter=0.25, seed=41, q=3.0)
    return reverb(x, 0.22)


def leon_caricia():   # retumbo grave y tranquilo
    rng = random.Random(42)
    d = 1.4
    n = int(d * SR)
    p = add(pulses([46.0] * n, n, 0.008, rng, 0.3), gain(noise(n, rng), 0.25))
    x = biquad(biquad(p, "lp", 380, 0.8), "hp", 40)
    am = [0.7 + 0.3 * math.sin(TAU * 5.5 * i / SR) for i in range(n)]
    return mul(mul(x, am), env_points(n, [(0, 0), (0.2, 1), (1.1, 0.9), (d, 0)]))


def _chuff(seed, dur=0.13):
    """Resoplido de tigre (prusten): aire por la nariz con los labios vibrando."""
    rng = random.Random(seed)
    n = int(dur * SR)
    air = biquad(noise(n, rng), "bp", 650, 1.1)
    flutter = [0.55 + 0.45 * math.sin(TAU * 34.0 * i / SR) for i in range(n)]
    return mul(mul(air, flutter), env_points(n, [(0, 0), (0.01, 1), (0.05, 0.6), (dur, 0)]))


def tigre_feliz():   # tres resoplidos amistosos
    out = []
    for k, at in enumerate((0.0, 0.2, 0.4)):
        out = place(out, gain(_chuff(51 + k), 1.0 - 0.15 * k), at)
    return reverb(out, 0.12)


def tigre_caricia():   # resoplido largo con retumbo
    rng = random.Random(53)
    d = 1.2
    n = int(d * SR)
    rumble = biquad(add(pulses([38.0] * n, n, 0.008, rng, 0.3), gain(noise(n, rng), 0.2)), "lp", 300, 0.8)
    rumble = mul(rumble, env_points(n, [(0, 0), (0.25, 0.8), (0.9, 0.7), (d, 0)]))
    return place(rumble, gain(_chuff(54, 0.2), 0.8), 0.05)


def zorro_feliz():   # tres "yips" agudos
    out = []
    for k, at in enumerate((0.0, 0.14, 0.3)):
        y = vocal(0.1, [(0, 980), (0.03, 1450 - 60 * k), (0.1, 900)], [(0, 0), (0.008, 1), (0.1, 0)],
                  900, 2100, 3300, harmonics=10, tilt=0.9, breath=0.15, jitter=0.05, seed=61 + k, q=5.0)
        out = place(out, y, at)
    return reverb(out, 0.15)


def zorro_caricia():   # "gekker" bajito: castañeteo contento
    rng = random.Random(62)
    d = 0.9
    n = int(d * SR)
    clicks = pulses(contour(n, [(0, 16), (d, 20)]), n, 0.012, rng, 0.4)
    tone = voice([620.0] * n, n, 8, 1.0)
    x = formants(mul(tone, clicks), 800, 1700, None, 5.0)
    return mul(x, env_points(n, [(0, 0), (0.05, 1), (0.75, 0.8), (d, 0)]))


def oso_feliz():   # dos resoplidos graves "jumf"
    out = []
    for k, at in enumerate((0.0, 0.32)):
        h = vocal(0.26, [(0, 100), (0.26, 80)], [(0, 0), (0.03, 1), (0.12, 0.7), (0.26, 0)],
                  430, 780, None, harmonics=18, tilt=1.0, breath=0.7, jitter=0.15, seed=71 + k, q=3.0)
        out = place(out, h, at)
    return reverb(out, 0.2)


def oso_caricia():   # zumbido contento "mmm"
    d = 1.3
    n = int(d * SR)
    f0 = [125.0 * (1 + 0.02 * math.sin(TAU * 4.5 * i / SR)) for i in range(n)]
    x = biquad(voice(f0, n, 12, 1.2), "lp", 520, 1.0)
    return reverb(mul(x, env_points(n, [(0, 0), (0.15, 1), (1.0, 0.9), (d, 0)])), 0.15)


def panda_feliz():   # balido (los pandas gigantes balan como cabritas)
    d = 0.65
    n = int(d * SR)
    f0 = contour(n, [(0, 480), (0.2, 560), (d, 470)])
    f0 = [f * (1 + 0.06 * math.sin(TAU * 11.0 * i / SR)) for i, f in enumerate(f0)]
    rng = random.Random(81)
    src = add(voice(f0, n, 14, 1.0, 0.03, rng), gain(noise(n, rng), 0.05))
    x = mul(formants(src, 520, 1850, 2600, 6.0), env_points(n, [(0, 0), (0.05, 1), (0.45, 0.8), (d, 0)]))
    return reverb(x, 0.15)


def panda_caricia():   # chillidos suaves de cachorro
    out = []
    for k, at in enumerate((0.0, 0.16, 0.36)):
        n = int(0.09 * SR)
        s = mul(sine(contour(n, [(0, 1250 + 100 * k), (0.05, 1650), (0.09, 1400)]), n), env_points(n, [(0, 0), (0.01, 1), (0.09, 0)]))
        out = place(out, gain(s, 0.8), at)
    return reverb(out, 0.2)


def conejo_feliz():   # golpe de pata y dos "honks" nasales
    n = int(0.16 * SR)
    thump = mul(sine(contour(n, [(0, 120), (0.16, 55)]), n), env_points(n, [(0, 0), (0.004, 1), (0.16, 0)]))
    out = list(thump)
    for k, at in enumerate((0.22, 0.38)):
        h = vocal(0.09, [(0, 300), (0.09, 270)], [(0, 0), (0.01, 1), (0.09, 0)], 260, 2100, None,
                  harmonics=16, tilt=0.8, breath=0.2, seed=91 + k, q=5.0)
        out = place(out, gain(h, 0.7), at)
    return reverb(out, 0.12)


def conejo_caricia():   # "ronroneo" de dientes: clics muy suaves
    rng = random.Random(92)
    d = 1.0
    n = int(d * SR)
    clicks = pulses(contour(n, [(0, 18), (d, 22)]), n, 0.003, rng, 0.5)
    x = biquad(mul(noise(n, rng), clicks), "bp", 3200, 1.5)
    return mul(x, env_points(n, [(0, 0), (0.1, 1), (0.85, 0.8), (d, 0)]))


def mapache_feliz():   # trino-castañeteo
    d = 0.6
    n = int(d * SR)
    trill = [0.5 + 0.5 * math.copysign(1.0, math.sin(TAU * 24.0 * i / SR)) for i in range(n)]
    trill = biquad(trill, "lp", 200, 0.7)
    tone = voice(contour(n, [(0, 1150), (d, 950)]), n, 8, 1.0)
    x = mul(formants(tone, 1000, 2300, None, 5.0), trill)
    return reverb(mul(x, env_points(n, [(0, 0), (0.03, 1), (0.45, 0.8), (d, 0)])), 0.15)


def mapache_caricia():   # ronroneo agudo
    rng = random.Random(102)
    d = 1.2
    n = int(d * SR)
    p = add(pulses([38.0] * n, n, 0.005, rng, 0.25), gain(noise(n, rng), 0.1))
    x = biquad(biquad(p, "lp", 1000, 0.9), "hp", 90)
    return mul(x, env_points(n, [(0, 0), (0.12, 1), (0.95, 0.85), (d, 0)]))


def _hoot(dur, f_start, f_end, seed):
    rng = random.Random(seed)
    n = int(dur * SR)
    tone = voice(contour(n, [(0, f_start), (dur, f_end)]), n, 3, 2.2)
    breath = biquad(noise(n, rng), "bp", f_start * 2, 2.0)
    x = add(tone, gain(breath, 0.12))
    return mul(x, env_points(n, [(0, 0), (dur * 0.25, 1), (dur * 0.7, 0.85), (dur, 0)]))


def buho_feliz():   # "hu-huuu"
    out = _hoot(0.28, 430, 410, 111)
    out = place(out, _hoot(0.6, 440, 380, 112), 0.42)
    return reverb(out, 0.3, 0.84)


def buho_caricia():   # trino grave
    d = 0.75
    n = int(d * SR)
    tone = voice(contour(n, [(0, 330), (d, 300)]), n, 4, 1.8)
    am = [0.5 + 0.5 * math.sin(TAU * 13.0 * i / SR) for i in range(n)]
    return reverb(mul(mul(tone, am), env_points(n, [(0, 0), (0.08, 1), (0.6, 0.8), (d, 0)])), 0.25)


def pinguino_feliz():   # rebuzno de pingüino (el canto de cortejo), en miniatura
    out = []
    times = (0.0, 0.17, 0.34, 0.51)
    for k, at in enumerate(times):
        inhale = k % 2 == 1
        dur = 0.3 if k == len(times) - 1 else 0.14
        h = vocal(dur, [(0, 380 if inhale else 640), (dur, 340 if inhale else 560)], [(0, 0), (0.01, 1), (dur * 0.7, 0.8), (dur, 0)],
                  700, 1300, 2500, harmonics=20, tilt=0.8, breath=0.2, jitter=0.06, seed=121 + k, q=4.0)
        out = place(out, gain(h, 0.7 if inhale else 1.0), at)
    return reverb(out, 0.15)


def pinguino_caricia():   # piídos suaves
    out = []
    for k, at in enumerate((0.0, 0.15, 0.32)):
        n = int(0.08 * SR)
        s = mul(sine(contour(n, [(0, 1500), (0.08, 1850 - 80 * k)]), n), env_points(n, [(0, 0), (0.01, 1), (0.08, 0)]))
        out = place(out, s, at)
    return reverb(out, 0.18)


def comer():   # tres mordiscos crujientes
    out = []
    for k, at in enumerate((0.0, 0.22, 0.44)):
        rng = random.Random(131 + k)
        n = int(0.09 * SR)
        crackle = [rng.uniform(-1, 1) * (1.0 if rng.random() < 0.18 else 0.25) for _ in range(n)]
        c = biquad(biquad(crackle, "hp", 1800), "lp", 6000)
        c = mul(c, env_points(n, [(0, 0), (0.003, 1), (0.09, 0)]))
        out = place(out, c, at)
    return reverb(out, 0.08)


def beber():   # lengüetazos
    out = []
    for k, at in enumerate((0.0, 0.13, 0.26, 0.39, 0.52)):
        rng = random.Random(141 + k)
        n = int(0.05 * SR)
        plip = mul(sine(contour(n, [(0, 1250 - 40 * k), (0.05, 480)]), n), env_points(n, [(0, 0), (0.004, 1), (0.05, 0)]))
        splash = mul(biquad(noise(n, rng), "bp", 2400, 1.5), env_points(n, [(0, 0.5), (0.02, 0)]))
        out = place(out, add(plip, gain(splash, 0.4)), at)
    return reverb(out, 0.15)


def lleno():   # "mm-mm" de "no, gracias"
    out = []
    for k, (at, f) in enumerate(((0.0, 300), (0.24, 225))):
        n = int(0.2 * SR)
        h = biquad(voice([float(f)] * n, n, 10, 1.2), "lp", 700, 1.0)
        out = place(out, mul(h, env_points(n, [(0, 0), (0.03, 1), (0.15, 0.8), (0.2, 0)])), at)
    return reverb(out, 0.12)


SOUNDS = {
    "leon_feliz": leon_feliz, "leon_caricia": leon_caricia,
    "lobo_feliz": lobo_feliz, "lobo_caricia": lobo_caricia,
    "tigre_feliz": tigre_feliz, "tigre_caricia": tigre_caricia,
    "zorro_feliz": zorro_feliz, "zorro_caricia": zorro_caricia,
    "gato_feliz": gato_feliz, "gato_caricia": gato_caricia,
    "perro_feliz": perro_feliz, "perro_caricia": perro_caricia,
    "oso_feliz": oso_feliz, "oso_caricia": oso_caricia,
    "panda_feliz": panda_feliz, "panda_caricia": panda_caricia,
    "conejo_feliz": conejo_feliz, "conejo_caricia": conejo_caricia,
    "mapache_feliz": mapache_feliz, "mapache_caricia": mapache_caricia,
    "buho_feliz": buho_feliz, "buho_caricia": buho_caricia,
    "pinguino_feliz": pinguino_feliz, "pinguino_caricia": pinguino_caricia,
    "comer": comer, "beber": beber, "lleno": lleno,
}

# Volumen (RMS) de cada tipo: las caricias, más bajitas.
LOUDNESS = {"feliz": 0.16, "caricia": 0.11}


def write_wav(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in samples))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "assets", "audio", "pets")
    os.makedirs(out_dir, exist_ok=True)
    for name, fn in SOUNDS.items():
        kind = name.split("_")[-1]
        x = fade(normalize(biquad(fn(), "hp", 35.0), LOUDNESS.get(kind, 0.13)))
        path = os.path.join(out_dir, name + ".wav")
        write_wav(path, x)
        print("%-18s %.2f s  %s" % (name, len(x) / SR, os.path.relpath(path)))
    print("%d sonidos en %s" % (len(SOUNDS), os.path.normpath(out_dir)))


if __name__ == "__main__":
    main()
