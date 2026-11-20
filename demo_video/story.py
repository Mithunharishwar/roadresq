# -*- coding: utf-8 -*-
"""Illustrated customer journey: breakdown -> mechanic -> token -> garage -> close.

Two-voice dialogue + narrator, built on the AI-generated illustrations in
demo_video/story/img, with app-UI overlays for request, allocation, token and
settlement.
"""
import os
import sys
import math
import wave
import subprocess
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build as B

STORY_DIR = os.path.join(B.OUT, "story")
AUD = os.path.join(STORY_DIR, "audio")
os.makedirs(AUD, exist_ok=True)

W, H, FPS = 1920, 1080, 24
SR = 22050

# speaker -> (SAPI voice, rate)
VOICE = {
    "nar": ("Microsoft David", 0),
    "p": ("Microsoft Zira", 1),
    "m": ("Microsoft Mark", 0),
    "g": ("Microsoft David", -2),
}
SPK = {
    "nar": ("", (150, 160, 180)),
    "p": ("PRIYA · CUSTOMER", (232, 92, 92)),
    "m": ("KARTHIK · MECHANIC", (242, 169, 59)),
    "g": ("ANAND · PARTNER GARAGE", (110, 160, 240)),
}

STORY = [
    dict(kind="ill", img="s1_road.png", focus=(0.60, 0.42),
         kicker="01 · 6:40 PM · BEACH ROAD, CHENNAI",
         beats=[("nar", "Six forty in the evening. Priya's scooter cuts out two kilometres from home."),
                ("p", "Not now. Not here."),
                ("p", "Who do I even call at this hour?")]),
    dict(kind="ill", img="s2_phone.png", focus=(0.58, 0.40),
         kicker="02 · THE REQUEST", panels=[("req", [(0, 1)])],
         beats=[("nar", "She opens RoadResQ. The phone's GPS fills in the location; she only picks two things."),
                ("p", "Battery problem. Scooter. Send."),
                ("nar", "One structured request: where, what, and which vehicle.")]),
    dict(kind="g_alloc", kicker="03 · THE SYSTEM DECIDES",
         beats=[("nar", "The engine first filters: verified, online, available, and able to service a battery fault."),
                ("nar", "The survivors are scored on distance, service match, availability, verification, workload and rating."),
                ("nar", "Rank one gets the offer. Every rejected crew is written down with a reason.")]),
    dict(kind="ill", img="s3_ride.png", focus=(0.55, 0.45),
         kicker="04 · 6:47 PM · THE CREW ACCEPTS",
         beats=[("nar", "Karthik is two kilometres away and battery-capable. He accepts without a phone call."),
                ("m", "RoadResQ job. Battery. I'm on my way."),
                ("nar", "From the moment he accepts, his position streams to her map.")]),
    dict(kind="ill", img="s4_fix.png", focus=(0.62, 0.45),
         kicker="05 · 6:58 PM · ROADSIDE DIAGNOSIS",
         beats=[("p", "It just died. No lights, no kick."),
                ("m", "Battery terminal's burnt. The cell is fine, the connector isn't."),
                ("p", "Can you fix it here?"),
                ("m", "Not safely. The garage has the part — I'll log the handover there.")]),
    dict(kind="ill", img="s5_token.png", focus=(0.58, 0.42),
         kicker="06 · 7:10 PM · THE DIGITAL TOKEN",
         panels=[("token", [(0, 1), (2, 2)])],
         beats=[("nar", "Because the scooter now moves to a garage, the app issues a digital vehicle token: six characters and a QR code."),
                ("p", "So this code follows my scooter?"),
                ("m", "Every handover. The garage scans it, and you see the same status I do."),
                ("nar", "Three parties hold the same token: customer, crew, garage.")]),
    dict(kind="ill", img="s6_garage.png", focus=(0.55, 0.45),
         kicker="07 · 8:05 PM · PARTNER GARAGE",
         panels=[("token_row", [(0, 3), (1, 4)])],
         beats=[("g", "Token's valid. Vehicle logged in — repair starts now."),
                ("nar", "Repair started. When the part is fitted, the garage marks it ready for pickup."),
                ("p", "I get the same update on my phone.")]),
    dict(kind="g_pay", kicker="08 · NEXT MORNING · CLOSING THE LOOP",
         beats=[("nar", "The token only closes after payment is verified on the server, not in the app's browser."),
                ("p", "Paid. And five stars for Karthik."),
                ("nar", "That rating becomes an input to the next allocation decision.")]),
    dict(kind="ill", img="s7_sunrise.png", focus=(0.52, 0.45),
         kicker="09 · 9:15 AM · BACK ON THE ROAD",
         beats=[("nar", "Breakdown at six forty. Repaired, documented and closed by morning."),
                ("m", "Ride safe."),
                ("p", "Thank you, Karthik.")]),
    dict(kind="end", kicker="",
         beats=[("nar", "RoadResQ. Every assignment has a reason behind it.")]),
]

# ---------------------------------------------------------------- text helpers
def wrap(text, fname, size, maxw):
    f = B._font(fname, size)
    words, lines, cur = text.split(), [], ""
    for wd in words:
        trial = (cur + " " + wd).strip()
        if f.getlength(trial) <= maxw or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = wd
    if cur:
        lines.append(cur)
    return lines


def para(text, fname, size, fill, maxw, line_gap=1.28):
    lines = wrap(text, fname, size, maxw)
    return "\n".join(lines), len(lines)


# ---------------------------------------------------------------- overlays
_BOTTOM_GRAD = None
_TOP_GRAD = None


def gradients():
    global _BOTTOM_GRAD, _TOP_GRAD
    if _BOTTOM_GRAD is None:
        g = np.zeros((H, W, 4), dtype=np.uint8)
        for y in range(H):
            a = 0
            if y > 560:
                a = int(min(1, (y - 560) / 380) ** 1.5 * 235)
            g[y, :, 3] = a
        _BOTTOM_GRAD = Image.fromarray(g, "RGBA")
        t = np.zeros((H, W, 4), dtype=np.uint8)
        for y in range(420):
            t[y, :, 3] = int((1 - y / 420) ** 1.4 * 190)
        _TOP_GRAD = Image.fromarray(t, "RGBA")
    return _BOTTOM_GRAD, _TOP_GRAD


def illustration(name, zoom, focus):
    src = B._CACHE.get(("ill", name))
    if src is None:
        src = Image.open(os.path.join(STORY_DIR, "img", name)).convert("RGB")
        B._CACHE[("ill", name)] = src
    # cover-crop to 16:9 then zoom
    ar = W / H
    sa = src.width / src.height
    if sa > ar:
        cw, ch = src.height * ar, src.height
    else:
        cw, ch = src.width, src.width / ar
    cw, ch = cw / zoom, ch / zoom
    cx = min(max((src.width - cw) * focus[0], 0), src.width - cw)
    cy = min(max((src.height - ch) * focus[1], 0), src.height - ch)
    crop = src.crop((int(cx), int(cy), int(cx + cw), int(cy + ch)))
    return crop.resize((W, H), Image.LANCZOS)


def kicker(img, text, alpha=1.0):
    if not text:
        return
    B.put(img, text, (90, 66), "segoeuib.ttf", 20, B.RED, alpha, spacing=3)


def narration(img, text, alpha, xy=(92, 104), maxw=880, size=31):
    if alpha <= 0.01:
        return
    body, n = para(text, "segoeuii.ttf", size, (214, 221, 234), maxw)
    B.blit(img, B.text_img(body, "segoeuii.ttf", size, (0, 0, 0), 0, 1.32), (xy[0] + 2, xy[1] + 3), alpha * 0.55)
    B.blit(img, B.text_img(body, "segoeuii.ttf", size, (222, 228, 240), 0, 1.32), xy, alpha)


def bubble(img, speaker, text, alpha, dur_t):
    if alpha <= 0.01:
        return
    label, col = SPK[speaker]
    maxw = 820
    body, n = para(text, "segoeuib.ttf", 31, B.WHITE, maxw)
    tw = max(B._font("segoeuib.ttf", 31).getlength(l) for l in body.split("\n"))
    pad = 26
    bw = int(tw + pad * 2)
    bh = int(34 + n * 41 + pad * 2)
    left = speaker == "p"
    x = 90 if left else W - 90 - bw
    y = 960 - bh
    panel = Image.new("RGBA", (bw, bh + 18), (0, 0, 0, 0))
    d = ImageDraw.Draw(panel)
    B.rrect(d, (0, 0, bw - 1, bh - 1), 22, fill=(11, 15, 26, 238), outline=col + (110,), width=2)
    # tail
    tx = 48 if left else bw - 48
    d.polygon([(tx - 13, bh - 2), (tx + 13, bh - 2), (tx, bh + 15)], fill=(11, 15, 26, 238))
    d.text((pad, 16), label, font=B._font("segoeuib.ttf", 17), fill=col)
    d.multiline_text((pad, 46), body, font=B._font("segoeuib.ttf", 31), fill=B.WHITE, spacing=9)
    B.blit(img, panel, (x, y), alpha)


def status_dot(img, x, y, filled, col):
    d = ImageDraw.Draw(img)
    if filled:
        d.ellipse((x - 7, y - 7, x + 7, y + 7), fill=col)
    else:
        d.ellipse((x - 7, y - 7, x + 7, y + 7), outline=(90, 100, 122), width=2)


# ---------------------------------------------------------------- panels
def panel_shell(img, x, y, w, h, alpha, title=None):
    card = B.card_img(w, h, 20, (13, 18, 30), (52, 62, 86), 2)
    B.blit(img, card, (x, y), alpha)
    if title:
        B.put(img, title, (x + 26, y + 22), "segoeuib.ttf", 17, B.MUTED, alpha, spacing=2)


def panel_request(img, x, y, alpha):
    w, h = 640, 392
    panel_shell(img, x, y, w, h, alpha, "RESCUE REQUEST")
    rows = [("LOCATION", "13.0356, 80.1601 — auto"),
            ("ISSUE", "Battery problem"),
            ("VEHICLE", "Scooter"),
            ("CREW", "searching · 7 candidates")]
    for i, (k, v) in enumerate(rows):
        ry = y + 66 + i * 70
        B.put(img, k, (x + 26, ry), "segoeuib.ttf", 15, (120, 132, 152), alpha, spacing=2)
        B.put(img, v, (x + 26, ry + 22), "segoeui.ttf", 24, B.WHITE, alpha)
    if alpha > 0.5:
        B.chip(img, "request created", (x + 26, y + h - 58), alpha, fill=(24, 46, 32),
               outline=(52, 110, 70), fg=(150, 220, 170), size=17, pad=(14, 7))


def qr_block(img, x, y, size, alpha, seed_txt="RSQ7K4"):
    n = 25
    cell = size / n
    rng = np.random.default_rng(abs(hash(seed_txt)) % (2 ** 32))
    q = Image.new("RGB", (size, size), (255, 255, 255))
    d = ImageDraw.Draw(q)
    finders = [(0, 0), (0, n - 7), (n - 7, 0)]
    def in_zone(r, c, pad=1):
        for fr, fc in finders:
            if fr - pad <= r <= fr + 6 + pad and fc - pad <= c <= fc + 6 + pad:
                return True
        return False
    for r in range(n):
        for c in range(n):
            if in_zone(r, c):
                continue
            if rng.random() < 0.44:
                d.rectangle((c * cell, r * cell, (c + 1) * cell - 1, (r + 1) * cell - 1), fill=(14, 14, 18))
    for fr, fc in finders:
        d.rectangle((fc * cell, fr * cell, (fc + 7) * cell - 1, (fr + 7) * cell - 1), fill=(14, 14, 18))
        d.rectangle(((fc + 1) * cell, (fr + 1) * cell, (fc + 6) * cell - 1, (fr + 6) * cell - 1), fill=(255, 255, 255))
        d.rectangle(((fc + 2) * cell, (fr + 2) * cell, (fc + 5) * cell - 1, (fr + 5) * cell - 1), fill=(14, 14, 18))
    B.blit(img, q.convert("RGBA"), (x, y), alpha)


TOKEN_STEPS = ["generated", "handed to garage", "repair started", "ready for pickup", "closed"]


def panel_token(img, x, y, w, level, alpha):
    h = 500
    panel_shell(img, x, y, w, h, alpha, "DIGITAL VEHICLE TOKEN")
    code = "RSQ7K4"
    B.put(img, code, (x + 26, y + 58), "consolab.ttf", 46, B.WHITE, alpha, spacing=5)
    B.put(img, "tokenCode · 6 alphanumeric", (x + 28, y + 116), "segoeui.ttf", 16, B.MUTED, alpha)
    qr_block(img, x + w - 180, y + 56, 150, alpha, code)
    # lifecycle
    for i, s in enumerate(TOKEN_STEPS):
        ry = y + 196 + i * 48
        on = i < level
        status_dot(img, x + 40, ry + 8, on, B.RED)
        if i < len(TOKEN_STEPS) - 1:
            d = ImageDraw.Draw(img)
            d.line([(x + 40, ry + 15), (x + 40, ry + 48)], fill=(70, 82, 106) if i >= level - 1 else (150, 60, 60), width=2)
        B.put(img, s, (x + 66, ry - 4), "segoeui.ttf", 23, B.WHITE if on else (110, 122, 144), alpha)
        if on and i == level - 1:
            B.chip(img, "current", (x + 66 + B._font("segoeui.ttf", 23).getlength(s) + 16, ry - 4), alpha,
                   fill=(110, 30, 30), outline=(170, 60, 60), size=14, pad=(10, 4))
    B.put(img, "illustrative record", (x + 26, y + h - 34), "segoeui.ttf", 15, (96, 106, 126), alpha)


def panel_token_row(img, x, y, level, alpha):
    steps = ["generated", "handed over", "repair", "ready", "closed"]
    cx = x
    for i, st in enumerate(steps):
        on = i < level
        w = B.text_img(st, "segoeuib.ttf", 16, B.WHITE).width + 30
        card = Image.new("RGBA", (w, 40), (0, 0, 0, 0))
        d = ImageDraw.Draw(card)
        B.rrect(d, (0, 0, w - 1, 39), 20, fill=(96, 26, 26) if on else (18, 24, 38),
                outline=(178, 58, 58) if on else (54, 64, 88), width=2)
        B.blit(img, card, (cx, y), alpha)
        B.put(img, st, (cx + 15, y + 9), "segoeuib.ttf", 16, B.WHITE if on else (130, 142, 164), alpha)
        cx += w + 6
        if i < len(steps) - 1:
            B.put(img, "›", (cx, y + 6), "segoeuib.ttf", 22, (100, 112, 136), alpha)
            cx += 22
    B.put(img, "token RSQ7K4 · shared by customer, crew, garage", (x, y + 52),
          "segoeui.ttf", 16, (120, 132, 152), alpha)


# ---------------------------------------------------------------- graphic scenes
def graphic_line(img, sc, t, beat_rel, bi):
    spk, text = sc["beats"][bi][0], sc["beats"][bi][1]
    local = t - beat_rel[bi]
    a = B.fade(local, 0.05, 0.35)
    if spk == "nar":
        narration(img, text, a, xy=(92, 892), maxw=1180, size=30)
    else:
        bubble(img, spk, text, a, local)


def g_alloc(sc, t, dur, beat_rel, bi):
    img = B.backdrop()
    kicker(img, "03 · THE SYSTEM DECIDES")
    B.put(img, "Scored, not hand-picked.", (90, 108), "segoeuib.ttf", 56, B.WHITE, B.fade(t, 0.1))
    # eligibility
    B.put(img, "ELIGIBILITY FILTER", (92, 200), "segoeuib.ttf", 17, B.MUTED, B.fade(t, 0.3), spacing=2)
    cols = ["verified", "online", "available", "service match", "fresh position"]
    for i, c in enumerate(cols):
        a = B.fade(t, 0.45 + i * 0.16, 0.4)
        B.chip(img, c, (92 + i * 200, 230), a, size=18, pad=(14, 8))
    # table
    px, py, pw = 90, 330, 1180
    panel_shell(img, px, py, pw, 380, 1.0, "ELIGIBLE CREWS, RANKED")
    rows = [("M-1042", "1.8 km", "battery · tyre", "4.7", 0.86, True),
            ("M-2019", "3.4 km", "battery", "4.9", 0.74, False),
            ("M-3387", "5.1 km", "engine · towing", "4.5", 0.52, False)]
    for i, (cid, dist, svc, rating, score, best) in enumerate(rows):
        a = B.fade(t, 0.9 + i * 0.3, 0.45)
        ry = py + 74 + i * 96
        if best and t > 2.2:
            d = ImageDraw.Draw(img)
            B.rrect(d, (px + 16, ry - 8, px + pw - 16, ry + 78), 14, fill=(30, 21, 25),
                    outline=(130, 46, 46), width=2)
        B.put(img, cid, (px + 30, ry + 4), "segoeuib.ttf", 26, B.WHITE, a)
        B.put(img, dist, (px + 230, ry + 8), "segoeui.ttf", 19, B.MUTED, a)
        B.put(img, svc, (px + 360, ry + 8), "segoeui.ttf", 18, B.MUTED, a)
        B.put(img, rating, (px + 700, ry + 8), "segoeui.ttf", 18, B.MUTED, a)
        B.put(img, f"{score:.2f}", (px + 860, ry + 4), "segoeuib.ttf", 24, B.WHITE, a)
        bwid = int(150 * score * B.ease(min(1, max(0, (t - 1.1 - i * 0.3) / 0.6))))
        d = ImageDraw.Draw(img)
        if bwid > 2:
            B.rrect(d, (px + 860, ry + 44, px + 1010, ry + 52), 4, fill=(38, 48, 70))
            B.rrect(d, (px + 860, ry + 44, px + 860 + bwid, ry + 52), 4, fill=B.RED if best else (90, 108, 140))
        if best and t > 2.6:
            B.chip(img, "OFFERED", (px + 1040, ry + 20), B.fade(t, 2.6, 0.4), fill=(118, 30, 30),
                   outline=(180, 60, 60), size=15, pad=(11, 5))
    B.put(img, "illustrative candidates · weights configurable", (92, 736), "segoeui.ttf", 16, (100, 110, 130),
          B.fade(t, 1.0, 0.6))

    # right column: rejected reasons + log note
    rx = 1330
    items = [("filter -> rank -> offer", (198, 206, 222)),
             ("rejections kept", (232, 150, 150)),
             ("acceptance timed", (198, 206, 222))]
    for i, (s, col) in enumerate(items):
        a = B.fade(t, 1.6 + i * 0.4, 0.5)
        B.put(img, s, (rx, 360 + i * 54), "consola.ttf", 20, col, a)
    B.put(img, "one request, seven candidates,\nthree eligible, one offered", (rx, 560),
          "segoeui.ttf", 20, B.MUTED, B.fade(t, 2.4, 0.6), line_gap=1.4)
    graphic_line(img, sc, t, beat_rel, bi)
    return B.grain(img, int(t * 10) % 7)


def star(img, cx, cy, r, fill, alpha=1.0):
    pts = []
    for k in range(10):
        ang = -math.pi / 2 + k * math.pi / 5
        rr = r if k % 2 == 0 else r * 0.44
        pts.append((cx + rr * math.cos(ang), cy + rr * math.sin(ang)))
    if alpha <= 0.02:
        return
    layer = Image.new("RGBA", (int(r * 3), int(r * 3)), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.polygon([(p[0] - cx + r * 1.5, p[1] - cy + r * 1.5) for p in pts], fill=fill)
    B.blit(img, layer, (cx - r * 1.5, cy - r * 1.5), alpha)


def g_pay(sc, t, dur, beat_rel, bi):
    img = B.backdrop()
    kicker(img, "08 · NEXT MORNING · CLOSING THE LOOP")
    B.put(img, "The token closes last.", (90, 108), "segoeuib.ttf", 56, B.WHITE, B.fade(t, 0.1))

    px, py, pw, ph = 90, 300, 700, 430
    panel_shell(img, px, py, pw, ph, 1.0, "SETTLEMENT")
    steps = [("payment verified server-side", 1),
             ("token closed", 2),
             ("rating recorded", 3)]
    for i, (s, need) in enumerate(steps):
        a = B.fade(t, 0.5 + i * 1.0, 0.5)
        ry = py + 76 + i * 74
        on = True
        status_dot(img, px + 34, ry + 10, on, B.RED)
        B.put(img, s, (px + 62, ry), "segoeui.ttf", 23, B.WHITE, a)
    B.put(img, "no client-side 'payment successful'", (px + 30, py + ph - 52), "segoeui.ttf", 16,
          (100, 110, 130), B.fade(t, 1.2, 0.6))

    # rating card
    qx, qy, qw = 880, 300, 620
    panel_shell(img, qx, qy, qw, 430, 1.0, "RATING")
    B.put(img, "Karthik", (qx + 30, qy + 66), "segoeuib.ttf", 34, B.WHITE, B.fade(t, 1.2, 0.5))
    B.put(img, "mechanic · battery service", (qx + 30, qy + 112), "segoeui.ttf", 18, B.MUTED, B.fade(t, 1.2, 0.5))
    for k in range(5):
        a = B.fade(t, 2.2 + k * 0.18, 0.3)
        star(img, qx + 60 + k * 62, qy + 200, 25, (242, 176, 60), a)
    B.put(img, "feeds the next allocation score", (qx + 30, qy + 270), "segoeui.ttf", 18, B.MUTED,
          B.fade(t, 3.0, 0.6))
    B.chip(img, "token closed · 09:12", (qx + 30, qy + 320), B.fade(t, 3.4, 0.5), fill=(24, 40, 34),
           outline=(50, 100, 70), fg=(150, 215, 170), size=17, pad=(14, 7))
    graphic_line(img, sc, t, beat_rel, bi)
    return B.grain(img, int(t * 10) % 7)


# ---------------------------------------------------------------- end card
def sc_end(t, dur, beats_active):
    img = B.backdrop()
    a = B.fade(t, 0.1, 0.7)
    tile = 104
    tx, ty = W // 2 - tile // 2, 300
    badge = Image.new("RGBA", (tile, tile), (0, 0, 0, 0))
    d = ImageDraw.Draw(badge)
    B.rrect(d, (0, 0, tile - 1, tile - 1), 27, fill=B.RED)
    d.rounded_rectangle((tile * .17, tile * .46, tile * .83, tile * .68), radius=8, fill=B.WHITE)
    d.rounded_rectangle((tile * .30, tile * .33, tile * .70, tile * .50), radius=6, fill=B.WHITE)
    for cx in (tile * .33, tile * .67):
        d.ellipse((cx - 6, tile * .63 - 6, cx + 6, tile * .63 + 6), fill=B.RED)
        d.ellipse((cx - 3, tile * .63 - 3, cx + 3, tile * .63 + 3), fill=B.WHITE)
    B.blit(img, badge, (tx, ty), a)
    ti = B.text_img("RoadResQ", "segoeuib.ttf", 88, B.WHITE, 0.5)
    B.blit(img, ti, (W // 2 - ti.width // 2, 436), B.fade(t, 0.3, 0.6))
    sub = "Every assignment has a reason."
    si = B.text_img(sub, "segoeui.ttf", 32, B.MUTED)
    B.blit(img, si, (W // 2 - si.width // 2, 556), B.fade(t, 0.6, 0.6))

    flow = ["request", "allocate", "crew", "token", "garage", "close"]
    widths = [B.text_img(s, "segoeui.ttf", 19, B.MUTED).width + 34 for s in flow]
    total = sum(widths) + 14 * (len(flow) - 1)
    x = W // 2 - total // 2
    for i, s in enumerate(flow):
        B.chip(img, s, (x, 664), B.fade(t, 0.9 + i * 0.1, 0.4), size=19)
        x += widths[i] + 14
    B.put(img, "illustrated story · product demonstration", (W // 2 - 218, 760), "segoeui.ttf", 18,
          (96, 106, 126), B.fade(t, 1.6, 0.6))
    return B.grain(img, int(t * 10) % 7)


# ---------------------------------------------------------------- scene assembly
def active_panel(panels, bi):
    level = 0
    for start_beat, lv in panels:
        if bi >= start_beat:
            level = lv
    return level


def render_ill(sc, t, dur, beat_times, beat_idx):
    img = illustration(sc["img"], 1.03 + 0.07 * min(1, t / max(dur, 0.1)), sc.get("focus", (0.5, 0.45)))
    bg, tg = gradients()
    img.paste(tg, (0, 0), tg)
    img.paste(bg, (0, 0), bg)
    kicker(img, sc["kicker"], B.fade(t, 0.05, 0.4))

    bi = max(0, beat_idx)
    spk, text = sc["beats"][bi][0], sc["beats"][bi][1]
    start = beat_times[bi] - beat_times[0] if bi < len(beat_times) else 0
    local = t - (beat_times[bi] - beat_times[0])
    a = B.fade(local, 0.05, 0.35)
    if spk == "nar":
        narration(img, text, a)
    else:
        bubble(img, spk, text, a, local)

    for pid, panels in sc.get("panels", []):
        lv = active_panel(panels, bi)
        if lv <= 0:
            continue
        pa = B.fade(t, 0.6, 0.5)
        if pid == "req":
            panel_request(img, 90, 250, pa)
        elif pid == "token":
            panel_token(img, 90, 252, 700, lv, pa)
        elif pid == "token_row":
            panel_token_row(img, 92, 112, lv, pa)
    return B.grain(img, int(t * 10) % 7)


# ---------------------------------------------------------------- audio
def scene_audio(i, sc):
    out = []
    for j, (spk, text) in enumerate(sc["beats"]):
        p = os.path.join(AUD, f"b{i:02d}_{j:02d}.wav")
        if not os.path.exists(p):
            voice, rate = VOICE[spk]
            B.tts(text, p, voice=voice, rate=rate)
        data, sr = B.read_wav(p)
        if sr != SR:
            idx = np.linspace(0, len(data) - 1, int(len(data) * SR / sr))
            data = np.interp(idx, np.arange(len(data)), data).astype(np.float32)
        out.append(data)
    return out


def main():
    clips = [scene_audio(i, sc) for i, sc in enumerate(STORY)]

    # timeline
    starts, beat_abs, beat_rel = [], [], []
    t = 0.0
    for i, sc in enumerate(STORY):
        starts.append(t)
        rel, cur = [], 0.75
        for j, clip in enumerate(clips[i]):
            rel.append(cur)
            cur += len(clip) / SR + 0.34
        beat_rel.append(rel)
        beat_abs.append([t + r for r in rel])
        t += cur + 0.55
    total = t + 0.6
    print("story duration", round(total, 2), "s")

    # audio bed
    n = int(total * SR)
    mix = np.zeros(n, dtype=np.float32)
    for i, sc in enumerate(STORY):
        for j, clip in enumerate(clips[i]):
            s = int(beat_abs[i][j] * SR)
            e = min(n, s + len(clip))
            mix[s:e] += clip[: e - s]

    chords = [[220.0, 261.63, 329.63], [196.0, 246.94, 293.66], [174.61, 220.0, 261.63],
              [164.81, 196.0, 246.94], [220.0, 261.63, 329.63], [174.61, 220.0, 261.63]]
    bar = 10.0
    tt = np.arange(n) / SR
    pad = np.zeros(n, dtype=np.float32)
    for bi in range(int(total / bar) + 2):
        ch = chords[bi % len(chords)]
        s, e = int(bi * bar * SR), min(n, int((bi + 1) * bar * SR))
        if e <= s:
            continue
        seg_t = tt[s:e] - bi * bar
        env = np.minimum(1, seg_t / 2.5) * np.minimum(1, np.maximum(0, (bar - seg_t) / 1.8))
        seg = np.zeros(e - s, dtype=np.float32)
        for k, f0 in enumerate(ch):
            seg += np.sin(2 * np.pi * f0 * seg_t + k) * 0.2
            seg += np.sin(2 * np.pi * f0 * 2.004 * seg_t) * 0.05
        pad[s:e] += seg * env
    mix = mix + pad * 0.055
    fi = int(1.0 * SR)
    mix[:fi] *= np.linspace(0, 1, fi)
    fo = int(2.0 * SR)
    mix[-fo:] *= np.linspace(1, 0, fo)
    peak = np.max(np.abs(mix)) or 1.0
    if peak > 0.95:
        mix *= 0.95 / peak
    audio = os.path.join(STORY_DIR, "mix.wav")
    with wave.open(audio, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((mix * 32767).astype(np.int16).tobytes())

    if os.environ.get("STORY_PREVIEW") == "1":
        prev_dir = os.path.join(STORY_DIR, "prev")
        os.makedirs(prev_dir, exist_ok=True)
        picks = {0: 2.5, 1: 5.0, 2: 4.5, 3: 5.0, 4: 7.5, 5: 7.0, 6: 6.0, 7: 4.5, 8: 4.5, 9: 1.5}
        for i, lt in picks.items():
            sc = STORY[i]
            bi = 0
            for j, b in enumerate(beat_rel[i]):
                if lt >= b:
                    bi = j
            dur = beat_rel[i][-1] + 2.0
            if sc["kind"] == "ill":
                fr = render_ill(sc, lt, dur, beat_rel[i], bi)
            elif sc["kind"] == "g_alloc":
                fr = g_alloc(sc, lt, dur, beat_rel[i], bi)
            elif sc["kind"] == "g_pay":
                fr = g_pay(sc, lt, dur, beat_rel[i], bi)
            else:
                fr = sc_end(lt, dur, bi)
            fr.save(os.path.join(prev_dir, f"s{i:02d}.png"))
            print("prev", i, sc["kind"])
        return

    # render
    ff = (r"C:\Users\Admin\AppData\Roaming\Accio\pre-install\bd5ff2c6816a\python\Lib"
          r"\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe")
    silent = os.path.join(STORY_DIR, "silent.mp4")
    proc = subprocess.Popen([ff, "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
                             "-r", str(FPS), "-i", "-", "-an", "-c:v", "libx264", "-preset", "medium",
                             "-crf", "19", "-pix_fmt", "yuv420p", silent],
                            stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    nframes = int(total * FPS)
    for f in range(nframes):
        T = f / FPS
        idx = 0
        for i in range(len(STORY)):
            if T >= starts[i]:
                idx = i
        t = T - starts[idx]
        sc = STORY[idx]
        dur = (starts[idx + 1] - starts[idx]) if idx + 1 < len(starts) else total - starts[idx]
        bi = 0
        for j, b in enumerate(beat_rel[idx]):
            if t >= b:
                bi = j
        if sc["kind"] == "ill":
            frame = render_ill(sc, t, dur, beat_rel[idx], bi)
        elif sc["kind"] == "g_alloc":
            frame = g_alloc(sc, t, dur, beat_rel[idx], bi)
        elif sc["kind"] == "g_pay":
            frame = g_pay(sc, t, dur, beat_rel[idx], bi)
        else:
            frame = sc_end(t, dur, bi)

        cf = 0.3
        if idx > 0 and t < cf:
            prev = STORY[idx - 1]
            pst = starts[idx] - starts[idx - 1]
            pbi = len(beat_rel[idx - 1]) - 1
            if prev["kind"] == "ill":
                pfr = render_ill(prev, pst - 0.001, pst, beat_rel[idx - 1], pbi)
            elif prev["kind"] == "g_alloc":
                pfr = g_alloc(prev, pst - 0.001, pst, beat_rel[idx - 1], pbi)
            elif prev["kind"] == "g_pay":
                pfr = g_pay(prev, pst - 0.001, pst, beat_rel[idx - 1], pbi)
            else:
                pfr = sc_end(pst - 0.001, pst, pbi)
            frame = Image.blend(pfr.convert("RGB"), frame.convert("RGB"), B.ease(t / cf))

        d = ImageDraw.Draw(frame)
        d.rectangle((0, 1048, W, H), fill=(6, 9, 17))
        d.rectangle((0, 1043, W, 1048), fill=(22, 28, 42))
        d.rectangle((0, 1043, int(W * T / total), 1048), fill=B.RED)
        B.put(frame, "RoadResQ", (60, 1060), "segoeuib.ttf", 17, (148, 156, 172), 1.0)
        B.put(frame, "illustrated journey", (166, 1060), "segoeui.ttf", 17, (86, 96, 116), 1.0)
        proc.stdin.write(frame.convert("RGB").tobytes())
        if f % 240 == 0:
            print("  frame", f, "/", nframes, flush=True)
    proc.stdin.close()
    proc.wait()

    final = os.path.join(B.ROOT, "RoadResQ_Story.mp4")
    subprocess.run([ff, "-y", "-i", silent, "-i", audio, "-c:v", "copy", "-c:a", "aac", "-b:a", "160k",
                    "-shortest", "-movflags", "+faststart", final],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("wrote", final, round(os.path.getsize(final) / 1e6, 1), "MB")


if __name__ == "__main__":
    setattr(B, "_font", B._font)
    main()
