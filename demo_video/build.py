# -*- coding: utf-8 -*-
"""RoadResQ demo video builder.

Renders a narrated 1920x1080 walkthrough from real app screenshots + report
diagrams (re-drawn natively so they can be animated), then encodes with ffmpeg.
"""
import os
import sys
import math
import json
import wave
import subprocess
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = r"C:\Users\Admin\OneDrive\Desktop\gopal\roadresq"
OUT = os.path.join(ROOT, "demo_video")
AUD = os.path.join(OUT, "audio")
os.makedirs(AUD, exist_ok=True)

W, H = 1920, 1080
FPS = 30
SR = 22050

FIG = os.path.join(ROOT, "figs")

# ---------------------------------------------------------------- palette
BG_TOP = (7, 11, 22)
BG_BOT = (16, 24, 42)
RED = (226, 58, 58)
RED_D = (176, 38, 38)
BLUE = (37, 78, 190)
WHITE = (245, 247, 252)
MUTED = (150, 162, 184)
DIM = (94, 106, 128)
CARD = (20, 28, 46)
CARD_HI = (27, 38, 61)
LINE = (46, 58, 82)

F = "C:/Windows/Fonts/"
def font(name, size):
    return ImageFont.truetype(F + name, size)

FB = lambda s: font("segoeuib.ttf", s)
FR = lambda s: font("segoeui.ttf", s)
FL = lambda s: font("segoeuil.ttf", s)
FM = lambda s: font("consola.ttf", s)
FMB = lambda s: font("consolab.ttf", s)

# ---------------------------------------------------------------- scenes
SCENES = [
    dict(kind="title", kicker="", title="RoadResQ",
         narration="RoadResQ is an on-demand roadside rescue platform. Here is how a breakdown turns into a dispatched mechanic, "
                   "and where AI really does the work."),
    dict(kind="problem", kicker="01 · THE PROBLEM", title="A breakdown is a bad moment\nto make decisions",
         narration="A breakdown is a bad moment to make decisions. Drivers do not know who to call, what it should cost, "
                   "or when help will actually arrive. Most platforms leave them guessing."),
    dict(kind="roles", kicker="02 · ONE APP, FOUR ROLES", title="Customer, mechanic, garage,\nand the assistant",
         narration="RoadResQ runs as a single Flutter app with four roles: the customer who needs help, the mechanic, "
                   "the partner garage, and the assistant who rides with the crew."),
    dict(kind="request", kicker="03 · THE REQUEST IS STRUCTURED", title="A rescue request is data,\nnot a phone call",
         narration="A request captures the GPS fix, the reported issue and the vehicle class. That structured record, not free text, "
                   "is what the decision layer can actually reason about."),
    dict(kind="pipeline", kicker="04 · THE PIPELINE", title="Nine stages, end to end",
         narration="From there a nine stage pipeline runs. Trigger event, context capture, request validation, candidate retrieval, "
                   "scoring and ranking, offer and dispatch, acceptance and tracking, settlement, and rating. "
                   "Ratings and settled outcomes feed back into the ranking terms, so the system recalibrates instead of staying fixed."),
    dict(kind="alloc", kicker="05 · THE ALLOCATION ENGINE", title="Retrieve, filter, score, offer",
         narration="The core is the allocation engine. First a radius query over the geo index of available crews. Then eligibility: "
                   "verified, online, available, service compatible, with a fresh position inside the region. Survivors are scored on six "
                   "weighted terms: proximity, service match, availability, verification, workload and rating. "
                   "Rank one gets the offer. A decline promotes the next rank, and if nobody accepts, the request escalates to an administrator."),
    dict(kind="log", kicker="06 · EVERY DECISION IS PROVABLE", title="No black box",
         narration="Every decision is written to an allocation log: candidate count, the eligible set, each rejection reason, "
                   "the selected mechanic and the assignment time. That is the difference between an intelligent system and a black box."),
    dict(kind="realtime", kicker="07 · REAL TIME", title="Tracking moves with the vehicle",
         narration="Once a crew accepts, a Socket IO position stream keeps the customer's map live. ETA is recomputed from the streamed "
                   "position, so the tracking screen moves with the vehicle instead of refreshing on a timer."),
    dict(kind="framing", kicker="08 · WHERE THE AI SITS", title="A decision layer,\nnot a chatbot",
         narration="So where is the AI? It is the decision layer, not a chatbot. Ranking and triage are explainable and deterministic by default. "
                   "Fault classification starts as a rule based prototype and only graduates to a trained model when it can be measured. "
                   "No invented confidence scores, and a human escalation path when the engine fails."),
    dict(kind="closing", kicker="", title="RoadResQ",
         narration="Flutter on the client, Flask and Mongo behind it, real time on Socket IO. "
                   "That is RoadResQ: rescue, with a reason behind every assignment."),
]

# ---------------------------------------------------------------- TTS
PS_TTS = r'''
Add-Type -AssemblyName System.Speech
$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
$s.SelectVoice("{voice}")
$s.Rate = {rate}
$s.SetOutputToWaveFile("{path}")
$s.Speak([Console]::In.ReadToEnd())
$s.Dispose()
'''


def tts(text, path, voice="Microsoft Zira Desktop", rate=0):
    script = PS_TTS.format(voice=voice, rate=rate, path=path.replace("'", "''"))
    p = subprocess.run(["powershell", "-NoProfile", "-Command", script],
                       input=text.encode("utf-8"), capture_output=True)
    if not os.path.exists(path):
        raise RuntimeError("TTS failed: " + p.stderr.decode("utf-8", "ignore"))


def wav_info(path):
    with wave.open(path, "rb") as w:
        return w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()


def read_wav(path):
    with wave.open(path, "rb") as w:
        n = w.getnframes()
        data = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float32) / 32768.0
        ch = w.getnchannels()
        if ch > 1:
            data = data.reshape(-1, ch).mean(axis=1)
        return data, w.getframerate()


if __name__ == "__main__" and sys.argv[1:2] == ["tts"]:
    for i, sc in enumerate(SCENES):
        p = os.path.join(AUD, f"n{i:02d}.wav")
        tts(sc["narration"], p)
        ch, sw, sr, n = wav_info(p)
        print(i, f"{n / sr:.2f}s", sr, ch)

# ================================================================ drawing kit
_CACHE = {}


def ease(x):
    x = max(0.0, min(1.0, x))
    return 1 - (1 - x) ** 3


def fade(t, t0, dur=0.55):
    return max(0.0, min(1.0, (t - t0) / dur))


def _font(name, size):
    key = ("f", name, size)
    if key not in _CACHE:
        _CACHE[key] = ImageFont.truetype(F + name, size)
    return _CACHE[key]


def text_img(text, fname, size, fill, spacing=0.0, line_gap=1.18):
    """Cached RGBA render of (possibly multiline) text."""
    key = ("t", text, fname, size, fill, spacing, line_gap)
    if key in _CACHE:
        return _CACHE[key]
    f = _font(fname, size)
    lines = text.split("\n")
    # measure
    widths = []
    for ln in lines:
        if spacing:
            w = sum(f.getlength(c) for c in ln) + spacing * max(0, len(ln) - 1)
        else:
            w = f.getlength(ln)
        widths.append(w)
    asc, desc = f.getmetrics()
    lh = int((asc + desc) * line_gap)
    img = Image.new("RGBA", (max(1, int(max(widths)) + 4), lh * len(lines) + 6), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i, ln in enumerate(lines):
        y = i * lh + 2
        if spacing:
            x = 0
            for c in ln:
                d.text((x, y), c, font=f, fill=fill)
                x += f.getlength(c) + spacing
        else:
            d.text((0, y), ln, font=f, fill=fill)
    _CACHE[key] = img
    return img


def blit(base, ov, xy, alpha=1.0, dy=0.0):
    if alpha <= 0.01:
        return
    x, y = int(xy[0]), int(xy[1] + dy)
    if alpha < 0.999:
        ov = ov.copy()
        ov.putalpha(ov.getchannel("A").point(lambda v: int(v * alpha)))
    base.paste(ov, (x, y), ov)


def put(base, text, xy, fname="segoeui.ttf", size=30, fill=WHITE, alpha=1.0,
        spacing=0.0, dy=0.0, line_gap=1.18):
    blit(base, text_img(text, fname, size, fill, spacing, line_gap), xy, alpha, dy)


def rrect(d, box, r, fill=None, outline=None, width=1):
    d.rounded_rectangle(box, radius=r, fill=fill, outline=outline, width=width)


def card_img(w, h, r=22, fill=CARD, outline=LINE, width=2):
    key = ("card", w, h, r, fill, outline, width)
    if key not in _CACHE:
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        rrect(d, (1, 1, w - 2, h - 2), r, fill=fill, outline=outline, width=width)
        _CACHE[key] = img
    return _CACHE[key]


def dashed_line(d, pts, fill, width=2, dash=10, gap=7):
    for (x1, y1), (x2, y2) in zip(pts[:-1], pts[1:]):
        L = math.hypot(x2 - x1, y2 - y1)
        if L == 0:
            continue
        ux, uy = (x2 - x1) / L, (y2 - y1) / L
        s = 0.0
        while s < L:
            e = min(s + dash, L)
            d.line([(x1 + ux * s, y1 + uy * s), (x1 + ux * e, y1 + uy * e)], fill=fill, width=width)
            s = e + gap


def arrow_head(d, x, y, ang, size=10, fill=RED):
    a = ang
    p1 = (x, y)
    p2 = (x - size * math.cos(a - 0.42), y - size * math.sin(a - 0.42))
    p3 = (x - size * math.cos(a + 0.42), y - size * math.sin(a + 0.42))
    d.polygon([p1, p2, p3], fill=fill)


# ---------------------------------------------------------------- backdrop
def backdrop():
    if "bg" in _CACHE:
        return _CACHE["bg"].copy()
    g = np.zeros((H, W, 3), dtype=np.float32)
    for y in range(H):
        k = y / (H - 1)
        for c in range(3):
            g[y, :, c] = BG_TOP[c] * (1 - k) + BG_BOT[c] * k
    # red glow bottom right
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    d2 = ((xx - 1560) ** 2 + (yy - 980) ** 2) / (2 * 620.0 ** 2)
    glow = np.exp(-d2)[..., None]
    g = g + glow * np.array([90, 16, 16], dtype=np.float32)
    # blue glow top left
    d3 = ((xx - 180) ** 2 + (yy - 60) ** 2) / (2 * 700.0 ** 2)
    g = g + np.exp(-d3)[..., None] * np.array([10, 22, 60], dtype=np.float32)
    img = Image.fromarray(np.clip(g, 0, 255).astype(np.uint8), "RGB")
    _CACHE["bg"] = img
    return img.copy()


def grain(base, seed=0):
    rng = np.random.default_rng(seed)
    n = rng.normal(0, 3.2, (H // 2, W // 2)).astype(np.float32)
    n = np.stack([n] * 3, axis=2)
    small = Image.fromarray(np.clip(128 + n, 0, 255).astype(np.uint8), "RGB")
    small = small.filter(ImageFilter.GaussianBlur(0.6)).resize((W, H), Image.BILINEAR)
    return Image.blend(base, small, 0.05)


def chip(base, text, xy, alpha=1.0, fill=(28, 38, 58), outline=LINE, fg=WHITE, size=20, pad=(14, 7), mono=False):
    fname = "consola.ttf" if mono else "segoeui.ttf"
    timg = text_img(text, fname, size, fg)
    w, h = timg.width + pad[0] * 2, timg.height + pad[1] * 2
    key = ("chip", text, fill, outline, fg, size, pad, mono)
    if key not in _CACHE:
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        rrect(d, (1, 1, w - 2, h - 2), h // 2, fill=fill, outline=outline, width=2)
        _CACHE[key] = img
    blit(base, _CACHE[key], xy, alpha)
    blit(base, timg, (xy[0] + pad[0], xy[1] + pad[1]), alpha)
    return w, h


# ---------------------------------------------------------------- phone
def phone_frame(h, source, zoom=1.0, focus=(0.5, 0.42)):
    bezel = 13
    w = int(h * 0.482)
    iw, ih = w - bezel * 2, h - bezel * 2
    src = source.copy()
    ar = iw / ih
    sa = src.width / src.height
    if sa > ar:
        bh = src.height / zoom
        bw = bh * ar
    else:
        bw = src.width / zoom
        bh = bw / ar
    cx = (src.width - bw) * focus[0]
    cy = (src.height - bh) * focus[1]
    crop = src.crop((int(cx), int(cy), int(cx + bw), int(cy + bh))).resize((iw, ih), Image.LANCZOS)
    mask = Image.new("L", (iw, ih), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, iw - 1, ih - 1), radius=36, fill=255)
    inner = Image.new("RGBA", (iw, ih), (0, 0, 0, 0))
    inner.paste(crop.convert("RGBA"), (0, 0), mask)
    body = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(body)
    rrect(d, (0, 0, w - 1, h - 1), 48, fill=(10, 11, 15), outline=(52, 56, 68), width=2)
    body.paste(inner, (bezel, bezel), inner)
    return body


def shadow(w, h, r=48, blur=26, alpha=150):
    key = ("sh", w, h, r, blur, alpha)
    if key not in _CACHE:
        img = Image.new("RGBA", (w + blur * 4, h + blur * 4), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        rrect(d, (blur * 2, blur * 2, blur * 2 + w, blur * 2 + h), r, fill=(0, 0, 0, alpha))
        img = img.filter(ImageFilter.GaussianBlur(blur))
        _CACHE[key] = img
    return _CACHE[key]


def phone_geom(h, source, zoom=1.0, focus=(0.5, 0.42)):
    """Maps normalised source coords (0..1) to on-screen coords relative to the phone box."""
    bezel = 13
    w = int(h * 0.482)
    iw, ih = w - bezel * 2, h - bezel * 2
    ar = iw / ih
    sa = source.width / source.height
    if sa > ar:
        bh = source.height / zoom
        bw = bh * ar
    else:
        bw = source.width / zoom
        bh = bw / ar
    cx = (source.width - bw) * focus[0]
    cy = (source.height - bh) * focus[1]

    def m(nx, ny):
        return ((nx * source.width - cx) / bw * iw + bezel,
                (ny * source.height - cy) / bh * ih + bezel)
    return m


def place_phone(base, source, h, x, y, zoom=1.0, focus=(0.5, 0.42), alpha=1.0):
    pf = phone_frame(h, source, zoom, focus)
    sh = shadow(pf.width - 26, pf.height - 26)
    blit(base, sh, (x - 26, y - 26), alpha * 0.85)
    blit(base, pf, (x, y), alpha)
    return pf


# ---------------------------------------------------------------- scenes
def sc_title(t, dur):
    img = backdrop()
    a = fade(t, 0.05, 0.9)
    # icon tile
    tile = 132
    tx, ty = W // 2 - tile // 2, 250 + (1 - ease(min(1, t / 0.9))) * 18
    badge = Image.new("RGBA", (tile, tile), (0, 0, 0, 0))
    d = ImageDraw.Draw(badge)
    rrect(d, (0, 0, tile - 1, tile - 1), 34, fill=RED)
    # simple white car glyph
    d.rounded_rectangle((tile * 0.17, tile * 0.46, tile * 0.83, tile * 0.68), radius=9, fill=WHITE)
    d.rounded_rectangle((tile * 0.30, tile * 0.33, tile * 0.70, tile * 0.50), radius=7, fill=WHITE)
    r = 7
    for cx in (tile * 0.33, tile * 0.67):
        d.ellipse((cx - r, tile * 0.63 - r, cx + r, tile * 0.63 + r), fill=RED)
        d.ellipse((cx - r + 3, tile * 0.63 - r + 3, cx + r - 3, tile * 0.63 + r - 3), fill=WHITE)
    blit(img, badge, (tx, ty), a)

    ti = text_img("RoadResQ", "segoeuib.ttf", 108, WHITE, 1.0)
    blit(img, ti, (W // 2 - ti.width // 2, 424), fade(t, 0.35, 0.8), dy=(1 - ease(min(1, t / 1.0))) * 10)
    sub = "How a breakdown becomes a dispatched mechanic"
    si = text_img(sub, "segoeui.ttf", 34, MUTED)
    blit(img, si, (W // 2 - si.width // 2, 600), fade(t, 0.7, 0.8))

    # accent rule
    rw = int(160 * ease(min(1, (t - 0.8) / 0.8)))
    d = ImageDraw.Draw(img)
    if rw > 2:
        d.rounded_rectangle((W // 2 - rw // 2, 574, W // 2 + rw // 2, 578), radius=2, fill=RED)

    for i, s in enumerate(["Flutter client", "Flask + MongoDB", "Socket.IO realtime"]):
        a2 = fade(t, 1.0 + i * 0.15, 0.6)
        cw, ch = text_img(s, "segoeui.ttf", 21, MUTED).width + 34, 44
        x = W // 2 - (3 * 250) // 2 + i * 250 + (250 - cw) // 2
        chip(img, s, (x, 692), a2, size=21)
    return grain(img, int(t * 10) % 7)


def sc_problem(t, dur):
    img = backdrop()
    put(img, "01 · THE PROBLEM", (120, 120), "segoeuib.ttf", 22, RED, fade(t, 0.05), spacing=3)
    put(img, "A breakdown is a bad moment\nto make decisions", (118, 172), "segoeuib.ttf", 62, WHITE,
        fade(t, 0.15), line_gap=1.12)

    cards = [
        ("Who do I call?", "No trusted, verified help is one tap away at the roadside."),
        ("What will it cost?", "Pricing is agreed after the fact, over the phone, under pressure."),
        ("When will they come?", "ETA is a guess, and nobody can see the vehicle move."),
    ]
    # faint perspective road on the right
    if t > 0.4:
        aa = fade(t, 0.4, 1.1)
        vx, vy = 1590, 520
        g = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        gd = ImageDraw.Draw(g)
        edge = (int(74 * aa), int(54 * aa), int(62 * aa), 255)
        dash = (int(96 * aa), int(64 * aa), int(72 * aa), 255)
        gd.line([(980, 1042), (vx, vy)], fill=edge, width=3)
        gd.line([(2200, 1042), (vx, vy)], fill=edge, width=3)
        for k in range(9):
            p0, p1 = k / 9.0, k / 9.0 + 0.055
            y0 = 1042 + (vy - 1042) * p0
            y1 = 1042 + (vy - 1042) * p1
            w0, w1 = 11 * (1 - p0) + 1, 11 * (1 - p1) + 1
            gd.polygon([(vx - w0, y0), (vx + w0, y0), (vx + w1, y1), (vx - w1, y1)], fill=dash)
        blit(img, g, (0, 0), 1.0)

    for i, (h1, body) in enumerate(cards):
        a = fade(t, 1.05 + i * 0.3, 0.6)
        y = 480 + i * 152 + (1 - ease(min(1, max(0, (t - 1.05 - i * 0.3) / 0.6)))) * 24
        w, hh = 720, 128
        blit(img, card_img(w, hh), (120, y), a)
        d = ImageDraw.Draw(img)
        if a > 0.05:
            d.rounded_rectangle((120, y + 24, 126, y + hh - 24), radius=3, fill=RED)
        put(img, h1, (156, y + 26), "segoeuib.ttf", 34, WHITE, a)
        put(img, body, (156, y + 76), "segoeui.ttf", 20, MUTED, a)
    return grain(img, int(t * 10) % 7)


def sc_roles(t, dur):
    img = backdrop()
    put(img, "02 · ONE APP, FOUR ROLES", (120, 120), "segoeuib.ttf", 22, RED, fade(t, 0.05), spacing=3)
    put(img, "Customer, mechanic, garage,\nand the assistant", (118, 172), "segoeuib.ttf", 60, WHITE,
        fade(t, 0.15), line_gap=1.12)

    roles = [("Customer", "Requests rescue, tracks the crew, pays"),
             ("Mechanic", "Accepts jobs, services the vehicle"),
             ("Assistant", "Rides with the crew, picks up the customer"),
             ("Garage", "Receives the vehicle token, updates repair status")]
    for i, (r, dsc) in enumerate(roles):
        a = fade(t, 0.9 + i * 0.28, 0.6)
        y = 470 + i * 118
        blit(img, card_img(700, 100, 18, CARD_HI if i == 0 else CARD), (118, y), a)
        dot = (17, 26, 44)
        d = ImageDraw.Draw(img)
        if a > 0.05:
            d.ellipse((146, y + 38, 170, y + 62), fill=RED if i == 0 else (58, 72, 100))
        put(img, r, (196, y + 22), "segoeuib.ttf", 30, WHITE, a)
        put(img, dsc, (196, y + 60), "segoeui.ttf", 21, MUTED, a)

    src = _CACHE.get("img_home")
    place_phone(img, src, 820, 1130, 130, zoom=1.0 + 0.05 * min(1, t / dur), focus=(0.5, 0.30),
                alpha=fade(t, 0.45, 0.8))
    return grain(img, int(t * 10) % 7)


def sc_request(t, dur):
    img = backdrop()
    put(img, "03 · THE REQUEST IS STRUCTURED", (120, 104), "segoeuib.ttf", 22, RED, fade(t, 0.05), spacing=3)
    put(img, "A rescue request is data,\nnot a phone call", (118, 152), "segoeuib.ttf", 58, WHITE,
        fade(t, 0.15), line_gap=1.12)

    src = _CACHE.get("img_req")
    px, py, ph = 1070, 128, 790
    zoom = 1.0 + 0.04 * min(1, t / dur)
    place_phone(img, src, ph, px, py, zoom=zoom, focus=(0.5, 0.36), alpha=fade(t, 0.4, 0.8))
    m = phone_geom(ph, src, zoom, (0.5, 0.36))

    fields = [
        ("GPS fix", "lat / lng captured automatically", 0.292),
        ("Issue taxonomy", "\"Battery Problem\"", 0.665),
        ("Vehicle class", "\"Scooter\"", 0.755),
    ]
    for i, (k, v, ny) in enumerate(fields):
        a = fade(t, 1.2 + i * 0.5, 0.45)
        y = 470 + i * 130
        d = ImageDraw.Draw(img)
        if a > 0.05:
            d.ellipse((120, y - 4, 164, y + 40), fill=RED)
        put(img, str(i + 1), (134, y + 3), "segoeuib.ttf", 22, WHITE, a)
        put(img, k, (184, y - 6), "segoeuib.ttf", 28, WHITE, a)
        put(img, v, (184, y + 32), "segoeui.ttf", 20, MUTED, a)
        mx, my = m(0.055, ny)
        if a > 0.05:
            d.ellipse((px + mx - 15, py + my - 15, px + mx + 15, py + my + 15), fill=(190, 40, 40))
        put(img, str(i + 1), (px + mx - 5, py + my - 11), "segoeuib.ttf", 15, WHITE, a)

    put(img, "One record  →  one decision problem", (120, 900), "segoeui.ttf", 26, WHITE, fade(t, 2.9, 0.7))
    return grain(img, int(t * 10) % 7)


PIPE = [
    ("S1", "Trigger", "SOS, voice, or impact"),
    ("S2", "Context capture", "GPS, vehicle, issue"),
    ("S3", "Validation", "Duplicate + state checks"),
    ("S4", "Candidates", "Geo-radius retrieval"),
    ("S5", "Scoring", "Six weighted terms"),
    ("S6", "Offer & dispatch", "Rank 1, then next"),
    ("S7", "Accept & track", "Position stream, ETA"),
    ("S8", "Settle", "Payment + receipt"),
    ("S9", "Rate", "Updates ranking terms"),
]


def sc_pipeline(t, dur):
    img = backdrop()
    put(img, "04 · THE PIPELINE", (120, 104), "segoeuib.ttf", 22, RED, fade(t, 0.05), spacing=3)
    put(img, "Nine stages, end to end", (118, 152), "segoeuib.ttf", 58, WHITE, fade(t, 0.15))

    bw, bh, gx, gy = 476, 146, 38, 36
    x0 = (W - (3 * bw + 2 * gx)) // 2
    y0 = 278
    step_dur = max(0.35, (dur - 3.0) / 9)
    active = int(max(0, min(8, (t - 1.4) / step_dur)))

    d = ImageDraw.Draw(img)
    for i, (code, name, sub) in enumerate(PIPE):
        r, c = divmod(i, 3)
        x, y = x0 + c * (bw + gx), y0 + r * (bh + gy)
        done = i < active
        on = i == active and t > 1.4
        fill = CARD_HI if on else CARD
        outline = RED if on else ((64, 80, 112) if done else LINE)
        rrect(d, (x, y, x + bw, y + bh), 18, fill=fill, outline=outline, width=3 if on else 2)
        # number badge
        bx, by = x + 20, y + 18
        rrect(d, (bx, by, bx + 46, by + 46), 12, fill=RED if (on or done) else (34, 45, 68))
        put(img, code, (bx + 8, by + 9), "segoeuib.ttf", 20, WHITE if (on or done) else MUTED, 1.0)
        put(img, name, (x + 20, y + 70), "segoeuib.ttf", 25, WHITE if (on or done) else (198, 208, 224),
            1.0 if on or done else 0.75)
        put(img, sub, (x + 20, y + 103), "segoeui.ttf", 17, MUTED if (on or done) else DIM,
            1.0 if on or done else 0.6)

    # recalibration loop
    if t > 1.4 + 9 * step_dur - 1.2:
        a = fade(t, 1.4 + 9 * step_dur - 1.2, 0.8)
        d = ImageDraw.Draw(img)
        sx, sy = x0 + 2 * (bw + gx) + bw / 2, y0 + 2 * (bh + gy) + bh + 4
        ex, ey = x0 + bw + gx + bw / 2, y0 + 2 * (bh + gy) + bh + 4
        mid = sy + 54
        col = (190, 70, 70)
        dashed_line(d, [(sx, sy), (sx, mid), (ex, mid), (ex, ey)], col, width=2)
        arrow_head(d, ex, ey, -math.pi / 2, 9, (190, 70, 70))
        put(img, "Settled outcomes and ratings recalibrate the ranking terms",
            (x0 + 40, mid + 14), "segoeui.ttf", 20, (198, 150, 150), a)
    return grain(img, int(t * 10) % 7)


# ---------------------------------------------------------------- allocation engine
CAND = [
    ("M-1042", "1.8 km", "battery · tyre", "1 job", "4.7", 0.86, True),
    ("M-2019", "3.4 km", "battery", "0 jobs", "4.9", 0.74, False),
    ("M-3387", "5.1 km", "engine · towing", "2 jobs", "4.5", 0.52, False),
]


def sc_alloc(t, dur):
    img = backdrop()
    put(img, "05 · THE ALLOCATION ENGINE", (120, 104), "segoeuib.ttf", 22, RED, fade(t, 0.05), spacing=3)
    put(img, "Retrieve, filter, score, offer", (118, 152), "segoeuib.ttf", 56, WHITE, fade(t, 0.15))

    stages = [
        ("1", "Radius query", "Geo index of available crews · R = 10 km"),
        ("2", "Eligibility", "verified · online · available · compatible · fresh fix"),
        ("3", "Weighted score", "proximity · service · availability · verification · load · rating"),
        ("4", "Offer & fallback", "rank 1 → decline → next rank → admin escalation"),
    ]
    seg = (dur - 2.2) / 4
    for i, (n, name, sub) in enumerate(stages):
        a = fade(t, 0.55 + i * 0.22, 0.55)
        on = t > 1.9 + i * seg
        y = 300 + i * 126
        blit(img, card_img(660, 108, 16, CARD_HI if on else CARD,
                           RED if on else LINE, 3 if on else 2), (120, y), a)
        d = ImageDraw.Draw(img)
        if a > 0.05:
            d.ellipse((142, y + 30, 186, y + 74), fill=RED if on else (40, 52, 78))
        put(img, n, (157, y + 38), "segoeuib.ttf", 22, WHITE, a)
        put(img, name, (204, y + 20), "segoeuib.ttf", 27, WHITE, a)
        put(img, sub, (204, y + 58), "segoeui.ttf", 18, MUTED, a)

    # results panel
    px, py, pw = 830, 292, 970
    blit(img, card_img(pw, 470, 20, (16, 23, 38), LINE, 2), (px, py), fade(t, 0.9, 0.6))
    put(img, "ELIGIBLE CREWS, RANKED", (px + 28, py + 24), "segoeuib.ttf", 18, MUTED, fade(t, 1.1, 0.6), spacing=2)
    put(img, "illustrative candidates · weights are configurable", (px + 28, py + 428),
        "segoeui.ttf", 16, DIM, fade(t, 1.4, 0.6))

    cols = [(px + 28, "crew"), (px + 180, "distance"), (px + 300, "services"), (px + 520, "load"),
            (px + 610, "rating"), (px + 700, "score")]
    if t > 1.5:
        for cx, label in cols:
            put(img, label, (cx, py + 62), "segoeui.ttf", 17, DIM, fade(t, 1.5, 0.5))
        d = ImageDraw.Draw(img)
        d.line([(px + 24, py + 92), (px + pw - 24, py + 92)], fill=(44, 56, 82), width=1)

    for i, (cid, dist, svc, load, rating, score, best) in enumerate(CAND):
        a = fade(t, 2.2 + i * 0.28, 0.5)
        ry = py + 108 + i * 96
        if a <= 0.02:
            continue
        if best and t > 3.0:
            d = ImageDraw.Draw(img)
            rrect(d, (px + 16, ry - 6, px + pw - 16, ry + 82), 14, fill=(30, 22, 26), outline=(120, 46, 46), width=2)
        put(img, cid, (px + 28, ry + 8), "segoeuib.ttf", 24, WHITE, a, )
        put(img, dist, (px + 180, ry + 12), "segoeui.ttf", 19, MUTED, a)
        put(img, svc, (px + 300, ry + 12), "segoeui.ttf", 17, MUTED, a)
        put(img, load, (px + 520, ry + 12), "segoeui.ttf", 18, MUTED, a)
        put(img, rating, (px + 610, ry + 12), "segoeui.ttf", 18, MUTED, a)
        put(img, f"{score:.2f}", (px + 700, ry + 10), "segoeuib.ttf", 22, WHITE, a)
        # score bar
        bwid = int(100 * score * ease(min(1, max(0, (t - 2.4 - i * 0.28) / 0.7))))
        d = ImageDraw.Draw(img)
        if bwid > 2:
            rrect(d, (px + 700, ry + 48, px + 800, ry + 56), 4, fill=(38, 48, 70))
            rrect(d, (px + 700, ry + 48, px + 700 + bwid, ry + 56), 4, fill=RED if best else (90, 108, 140))
        if best and t > 3.4:
            chip(img, "OFFERED", (px + 836, ry + 20), fade(t, 3.4, 0.5), fill=(120, 30, 30),
                 outline=(180, 60, 60), size=15, pad=(11, 4))
    return grain(img, int(t * 10) % 7)


# ---------------------------------------------------------------- allocation log
LOG = [
    ('{', DIM),
    ('  "requestId": "req_8f31",', WHITE),
    ('  "regionId": "chennai-south",', WHITE),
    ('  "hubId": "hub-adyar",', WHITE),
    ('  "candidateCount": 7,', WHITE),
    ('  "eligibleCount": 3,', WHITE),
    ('  "candidates": [', WHITE),
    ('    { "id": "M-2019", "rejected": "service_mismatch" },', (232, 150, 150)),
    ('    { "id": "M-3387", "rejected": "outside_region" },', (232, 150, 150)),
    ('    { "id": "M-4410", "rejected": "position_stale" }', (232, 150, 150)),
    ('  ],', WHITE),
    ('  "selectedMechanicId": "M-1042",', (255, 190, 190)),
    ('  "assignmentTimeMs": 412,', WHITE),
    ('  "status": "ASSIGNED"', WHITE),
    ('}', DIM),
]


def sc_log(t, dur):
    img = backdrop()
    put(img, "06 · EVERY DECISION IS PROVABLE", (120, 104), "segoeuib.ttf", 22, RED, fade(t, 0.05), spacing=3)
    put(img, "No black box", (118, 152), "segoeuib.ttf", 58, WHITE, fade(t, 0.15))

    cx, cy, cw, ch = 150, 268, 900, 640
    blit(img, card_img(cw, ch, 18, (13, 18, 30), (44, 56, 82), 2), (cx, cy), fade(t, 0.4, 0.6))
    for i, (line, col) in enumerate(LOG):
        tx = t - 0.9 - i * 0.22
        if tx < 0:
            continue
        a = fade(tx, 0, 0.22)
        put(img, line, (cx + 32, cy + 28 + i * 39), "consola.ttf", 21, col, a)

    bx = 1090
    points = [
        ("Rejection reasons", "Every filtered-out crew is recorded with why."),
        ("Assignment latency", "Time from request to accepted offer is stored."),
        ("Reproducible runs", "The same inputs can be replayed and audited."),
    ]
    for i, (h1, body) in enumerate(points):
        a = fade(t, 2.6 + i * 0.55, 0.55)
        y = 300 + i * 180
        blit(img, card_img(720, 148, 18, CARD), (bx, y), a)
        d = ImageDraw.Draw(img)
        if a > 0.05:
            d.rounded_rectangle((bx, y + 26, bx + 6, y + 122), radius=3, fill=RED)
        put(img, h1, (bx + 34, y + 28), "segoeuib.ttf", 28, WHITE, a)
        put(img, body, (bx + 34, y + 74), "segoeui.ttf", 20, MUTED, a)
    put(img, "record shape shown · values illustrative", (bx, 860), "segoeui.ttf", 17, DIM, fade(t, 3.6, 0.6))
    return grain(img, int(t * 10) % 7)


# ---------------------------------------------------------------- realtime
def sc_realtime(t, dur):
    img = backdrop()
    put(img, "07 · REAL TIME", (120, 104), "segoeuib.ttf", 22, RED, fade(t, 0.05), spacing=3)
    put(img, "Tracking moves\nwith the vehicle", (118, 152), "segoeuib.ttf", 58, WHITE, fade(t, 0.15), line_gap=1.12)

    events = [("mechanic_location_update", "every few seconds"),
              ("request status → en route", "state machine emits"),
              ("eta_recomputed", "from streamed position")]
    for i, (ev, sub) in enumerate(events):
        a = fade(t, 0.9 + i * 0.6, 0.5)
        y = 440 + i * 120
        if a > 0.02:
            chip(img, ev, (120, y), a, mono=True, size=20, pad=(16, 10))
        put(img, sub, (140, y + 52), "segoeui.ttf", 19, MUTED, a)

    put(img, "No manual refresh, no polling loop on screen.", (120, 830), "segoeui.ttf", 24, WHITE,
        fade(t, 3.1, 0.6))

    # animated live position stream
    if t > 0.7:
        rx0, rx1, ry = 660, 960, 560
        d = ImageDraw.Draw(img)
        dashed_line(d, [(rx0, ry), (rx1, ry)], (66, 78, 104), width=2, dash=7, gap=9)
        cx = rx0 + (rx1 - rx0) * ((t * 0.32) % 1.0)
        d.ellipse((cx - 8, ry - 8, cx + 8, ry + 8), fill=RED)
        put(img, "live position stream", (rx0, ry + 24), "segoeui.ttf", 16, DIM, fade(t, 0.9, 0.6))

    src = _CACHE.get("img_track")
    place_phone(img, src, 850, 1200, 110, zoom=1.0 + 0.05 * min(1, t / dur), focus=(0.5, 0.42),
                alpha=fade(t, 0.4, 0.8))
    return grain(img, int(t * 10) % 7)


# ---------------------------------------------------------------- AI framing
def sc_framing(t, dur):
    img = backdrop()
    put(img, "08 · WHERE THE AI SITS", (120, 104), "segoeuib.ttf", 22, RED, fade(t, 0.05), spacing=3)
    put(img, "A decision layer,\nnot a chatbot", (118, 152), "segoeuib.ttf", 58, WHITE, fade(t, 0.15), line_gap=1.12)

    cols = [
        ("DECIDES", RED, ["Ranking by six weighted terms", "ETA from streamed position", "Issue → service triage"]),
        ("PROVES", (60, 120, 200), ["Allocation log per attempt", "Metrics from stored events", "Prototype labels kept honest"]),
        ("ESCALATES", (150, 120, 60), ["No eligible crew → admin", "Decline → next rank", "Timeout → backup crews"]),
    ]
    cw = 500
    x0 = (W - (3 * cw + 2 * 40)) // 2
    for i, (head, col, items) in enumerate(cols):
        a = fade(t, 1.0 + i * 0.5, 0.6)
        x = x0 + i * (cw + 40)
        y = 400
        blit(img, card_img(cw, 330, 20, CARD), (x, y), a)
        d = ImageDraw.Draw(img)
        if a > 0.05:
            d.rounded_rectangle((x + 30, y + 34, x + 90, y + 40), radius=3, fill=col)
        put(img, head, (x + 30, y + 58), "segoeuib.ttf", 22, col, a, spacing=3)
        for j, it in enumerate(items):
            ay = y + 116 + j * 66
            aa = fade(t, 1.4 + i * 0.5 + j * 0.18, 0.45)
            d = ImageDraw.Draw(img)
            if aa > 0.05:
                d.ellipse((x + 34, ay + 10, x + 44, ay + 20), fill=(90, 104, 130))
            put(img, it, (x + 62, ay), "segoeui.ttf", 21, (206, 214, 230), aa)
    put(img, "Rule-based triage ships first; a trained model only when it can be measured.",
        (x0, 772), "segoeui.ttf", 22, MUTED, fade(t, 3.2, 0.7))
    return grain(img, int(t * 10) % 7)


# ---------------------------------------------------------------- closing
def sc_closing(t, dur):
    img = backdrop()
    a = fade(t, 0.1, 0.8)
    tile = 108
    tx, ty = W // 2 - tile // 2, 300
    badge = Image.new("RGBA", (tile, tile), (0, 0, 0, 0))
    d = ImageDraw.Draw(badge)
    rrect(d, (0, 0, tile - 1, tile - 1), 28, fill=RED)
    d.rounded_rectangle((tile * .17, tile * .46, tile * .83, tile * .68), radius=8, fill=WHITE)
    d.rounded_rectangle((tile * .30, tile * .33, tile * .70, tile * .50), radius=6, fill=WHITE)
    for cx in (tile * .33, tile * .67):
        d.ellipse((cx - 6, tile * .63 - 6, cx + 6, tile * .63 + 6), fill=RED)
        d.ellipse((cx - 3, tile * .63 - 3, cx + 3, tile * .63 + 3), fill=WHITE)
    blit(img, badge, (tx, ty), a)

    ti = text_img("RoadResQ", "segoeuib.ttf", 92, WHITE, 0.5)
    blit(img, ti, (W // 2 - ti.width // 2, 440), fade(t, 0.35, 0.7))
    sub = "Rescue, with a reason behind every assignment"
    si = text_img(sub, "segoeui.ttf", 32, MUTED)
    blit(img, si, (W // 2 - si.width // 2, 560), fade(t, 0.7, 0.7))

    stack = ["Flutter", "Flask", "MongoDB", "Socket.IO", "Google Maps", "Razorpay"]
    widths = [text_img(s, "segoeui.ttf", 20, MUTED).width + 34 for s in stack]
    total = sum(widths) + 14 * (len(stack) - 1)
    x = W // 2 - total // 2
    for i, s in enumerate(stack):
        chip(img, s, (x, 680), fade(t, 0.95 + i * 0.09, 0.5), size=20)
        x += widths[i] + 14
    put(img, "roadresq.app", (W // 2 - 92, 790), "segoeui.ttf", 24, (214, 160, 160), fade(t, 1.6, 0.7))
    return grain(img, int(t * 10) % 7)


RENDERERS = dict(title=sc_title, problem=sc_problem, roles=sc_roles, request=sc_request,
                 pipeline=sc_pipeline, alloc=sc_alloc, log=sc_log, realtime=sc_realtime,
                 framing=sc_framing, closing=sc_closing)


# ---------------------------------------------------------------- audio
def build_audio(starts, total):
    n = int((total + 0.6) * SR)
    mix = np.zeros(n, dtype=np.float32)
    for i in range(len(SCENES)):
        data, sr = read_wav(os.path.join(AUD, f"n{i:02d}.wav"))
        if sr != SR:
            idx = np.linspace(0, len(data) - 1, int(len(data) * SR / sr))
            data = np.interp(idx, np.arange(len(data)), data).astype(np.float32)
        s = int(starts[i] * SR)
        e = min(n, s + len(data))
        mix[s:e] += data[: e - s]

    # soft pad bed
    chords = [[220.0, 261.63, 329.63], [174.61, 220.0, 261.63], [196.0, 246.94, 293.66],
              [164.81, 196.0, 246.94], [220.0, 261.63, 329.63], [174.61, 220.0, 261.63]]
    bar = 9.0
    t = np.arange(n) / SR
    pad = np.zeros(n, dtype=np.float32)
    for bi in range(int(total / bar) + 2):
        ch = chords[bi % len(chords)]
        s, e = int(bi * bar * SR), min(n, int((bi + 1) * bar * SR))
        if e <= s:
            continue
        tt = t[s:e] - bi * bar
        env = np.minimum(1, tt / 2.2) * np.minimum(1, np.maximum(0, (bar - tt) / 1.6))
        seg = np.zeros(e - s, dtype=np.float32)
        for k, f0 in enumerate(ch):
            seg += np.sin(2 * np.pi * f0 * tt + k) * 0.22
            seg += np.sin(2 * np.pi * (f0 * 2.003) * tt) * 0.06
        pad[s:e] += seg * env
    pad *= 0.11
    mix = mix * 1.0 + pad * 0.5
    # gentle fades
    fi = int(1.2 * SR)
    mix[:fi] *= np.linspace(0, 1, fi)
    fo = int(2.2 * SR)
    mix[-fo:] *= np.linspace(1, 0, fo)
    peak = np.max(np.abs(mix)) or 1.0
    if peak > 0.95:
        mix *= 0.95 / peak
    pcm = (mix * 32767).astype(np.int16)
    path = os.path.join(OUT, "mix.wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return path


# ---------------------------------------------------------------- main
def main():
    durs = []
    for i in range(len(SCENES)):
        data, sr = read_wav(os.path.join(AUD, f"n{i:02d}.wav"))
        durs.append(len(data) / sr)
    starts, acc = [], 0.0
    for i, d in enumerate(durs):
        pad_before = 0.6 if i == 0 else 0.9
        starts.append(acc + pad_before)
        acc += pad_before + d + (0.55 if i < len(durs) - 1 else 1.3)
    total = acc
    print("total duration", round(total, 2), "s")

    _CACHE["img_home"] = Image.open(os.path.join(FIG, "fig_ui_home.png")).convert("RGB")
    _CACHE["img_req"] = Image.open(os.path.join(FIG, "fig_ui_request.png")).convert("RGB")
    _CACHE["img_track"] = Image.open(os.path.join(FIG, "fig_ui_track.png")).convert("RGB")

    audio = build_audio(starts, total)
    ff = r"C:\Users\Admin\AppData\Roaming\Accio\pre-install\bd5ff2c6816a\python\Lib\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe"
    silent = os.path.join(OUT, "video_silent.mp4")
    cmd = [ff, "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS),
           "-i", "-", "-an", "-c:v", "libx264", "-preset", "medium", "-crf", "19",
           "-pix_fmt", "yuv420p", silent]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    nframes = int(total * FPS)
    bounds = [0] + [s for s in starts[1:]] + [total + 1]
    for f in range(nframes):
        T = f / FPS
        idx = 0
        for i in range(len(SCENES)):
            if T >= starts[i]:
                idx = i
        t = T - starts[idx]
        sc = SCENES[idx]
        frame = RENDERERS[sc["kind"]](t, starts[idx + 1] - starts[idx] if idx + 1 < len(starts) else total - starts[idx])
        # crossfade with previous scene tail
        cf = 0.34
        if idx > 0 and t < cf:
            prev = idx - 1
            pt = (starts[idx] - starts[prev]) - 0.001
            pframe = RENDERERS[SCENES[prev]["kind"]](pt, starts[idx] - starts[prev])
            frame = Image.blend(pframe.convert("RGB"), frame.convert("RGB"), ease(t / cf))

        # chrome
        d = ImageDraw.Draw(frame)
        d.rectangle((0, 1042, W, H), fill=(6, 9, 17))
        prog = T / total
        d.rectangle((0, 1037, W, 1042), fill=(22, 28, 42))
        d.rectangle((0, 1037, int(W * prog), 1042), fill=RED)
        for s in starts[1:]:
            x = int(W * s / total)
            d.rectangle((x, 1037, x + 2, 1042), fill=(8, 11, 20))
        put(frame, "RoadResQ", (60, 1056), "segoeuib.ttf", 18, (150, 158, 175), 1.0)
        put(frame, "how it works", (168, 1056), "segoeui.ttf", 18, (88, 98, 118), 1.0)
        ts = f"{int(T // 60)}:{int(T % 60):02d}"
        tw = text_img(ts, "consola.ttf", 17, (120, 130, 150)).width
        put(frame, ts, (W - 60 - tw, 1057), "consola.ttf", 17, (120, 130, 150), 1.0)

        proc.stdin.write(frame.convert("RGB").tobytes())
        if f % 300 == 0:
            print(f"  frame {f}/{nframes}", flush=True)

    proc.stdin.close()
    proc.wait()

    final = os.path.join(ROOT, "RoadResQ_Demo.mp4")
    subprocess.run([ff, "-y", "-i", silent, "-i", audio, "-c:v", "copy", "-c:a", "aac", "-b:a", "160k",
                    "-shortest", "-movflags", "+faststart", final],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("wrote", final, round(os.path.getsize(final) / 1e6, 1), "MB")


if __name__ == "__main__" and sys.argv[1:2] != ["tts"]:
    main()
