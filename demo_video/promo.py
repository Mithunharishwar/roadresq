# -*- coding: utf-8 -*-
"""30-second promo cut: same visual language as the full demo, tighter narrative."""
import os
import sys
import wave
import subprocess
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build as B

PRO = os.path.join(B.OUT, "promo")
AUD = os.path.join(PRO, "audio")
os.makedirs(AUD, exist_ok=True)

SCENES = [
    dict(kind="hook", narration="Your car just died. Now what?"),
    dict(kind="title", narration="RoadResQ turns that into a dispatched mechanic."),
    dict(kind="preq", narration="One tap sends your position, your issue and your vehicle."),
    dict(kind="prank", narration="The engine filters eligible crews, scores them, and dispatches rank one."),
    dict(kind="ptrack", narration="You watch the approach live, with a real ETA."),
    dict(kind="closing", narration="RoadResQ. Rescue, with a reason behind it."),
]


def sc_hook(t, dur):
    img = B.backdrop()
    edge_pts = [(980, 1042), (1590, 520), (2200, 1042)]
    d = ImageDraw.Draw(img)
    d.line([edge_pts[0], edge_pts[1]], fill=(70, 50, 58), width=3)
    d.line([edge_pts[2], edge_pts[1]], fill=(70, 50, 58), width=3)
    B.put(img, "Your car", (170, 250), "segoeuib.ttf", 92, B.WHITE, B.fade(t, 0.05, 0.5))
    B.put(img, "just died.", (170, 348), "segoeuib.ttf", 92, B.WHITE, B.fade(t, 0.25, 0.5))
    if t > 1.4:
        B.put(img, "Now what?", (166, 512), "segoeuib.ttf", 118, B.RED, B.fade(t, 1.4, 0.45))
    B.put(img, "RoadResQ · on-demand roadside rescue", (172, 900), "segoeui.ttf", 24, B.MUTED,
          B.fade(t, 0.6, 0.7))
    return B.grain(img, int(t * 10) % 7)


def sc_preq(t, dur):
    img = B.backdrop()
    B.put(img, "ONE REQUEST · ONE RECORD", (120, 108), "segoeuib.ttf", 21, B.RED, B.fade(t, 0.05), spacing=3)
    B.put(img, "Position. Issue.\nVehicle.", (118, 156), "segoeuib.ttf", 62, B.WHITE, B.fade(t, 0.1), line_gap=1.1)
    src = B._CACHE.get("img_req")
    px, py, ph = 1080, 118, 800
    B.place_phone(img, src, ph, px, py, zoom=1.0 + 0.05 * min(1, t / dur), focus=(0.5, 0.42),
                  alpha=B.fade(t, 0.25, 0.6))
    labels = ["GPS fix captured", "Issue: battery", "Vehicle: scooter"]
    for i, s in enumerate(labels):
        a = B.fade(t, 0.7 + i * 0.45, 0.4)
        B.chip(img, s, (120, 500 + i * 74), a, size=22, pad=(18, 11))
    B.put(img, "No call centre. No explaining twice.", (120, 830), "segoeui.ttf", 24, B.WHITE,
          B.fade(t, 2.0, 0.6))
    return B.grain(img, int(t * 10) % 7)


RANKS = [("M-1042", "1.8 km", 0.86, True), ("M-2019", "3.4 km", 0.74, False), ("M-3387", "5.1 km", 0.52, False)]


def sc_prank(t, dur):
    img = B.backdrop()
    B.put(img, "FILTER · SCORE · DISPATCH", (120, 108), "segoeuib.ttf", 21, B.RED, B.fade(t, 0.05), spacing=3)
    B.put(img, "Rank one\ngets the offer.", (118, 156), "segoeuib.ttf", 62, B.WHITE, B.fade(t, 0.1), line_gap=1.1)
    B.put(img, "eligible = verified · online · available · compatible", (120, 852),
          "segoeui.ttf", 21, B.MUTED, B.fade(t, 1.6, 0.6))

    px, py, pw = 930, 300, 850
    B.blit(img, B.card_img(pw, 430, 20, (16, 23, 38), B.LINE, 2), (px, py), B.fade(t, 0.3, 0.5))
    B.put(img, "RANKED CREWS", (px + 26, py + 22), "segoeuib.ttf", 18, B.MUTED, B.fade(t, 0.5, 0.5), spacing=2)
    for i, (cid, dist, score, best) in enumerate(RANKS):
        a = B.fade(t, 0.8 + i * 0.35, 0.4)
        if a <= 0.02:
            continue
        ry = py + 70 + i * 110
        if best and t > 2.0:
            d = ImageDraw.Draw(img)
            B.rrect(d, (px + 14, ry - 8, px + pw - 14, ry + 92), 14, fill=(30, 22, 26),
                    outline=(130, 50, 50), width=2)
        B.put(img, cid, (px + 30, ry + 6), "segoeuib.ttf", 28, B.WHITE, a)
        B.put(img, dist, (px + 250, ry + 12), "segoeui.ttf", 20, B.MUTED, a)
        B.put(img, f"{score:.2f}", (px + 600, ry + 8), "segoeuib.ttf", 26, B.WHITE, a)
        bw = int(160 * score * B.ease(min(1, max(0, (t - 1.0 - i * 0.35) / 0.6))))
        d = ImageDraw.Draw(img)
        if bw > 2:
            B.rrect(d, (px + 600, ry + 52, px + 760, ry + 62), 5, fill=(38, 48, 70))
            B.rrect(d, (px + 600, ry + 52, px + 600 + bw, ry + 62), 5,
                    fill=B.RED if best else (90, 108, 140))
        if best and t > 2.4:
            B.chip(img, "DISPATCHED", (px + 30, ry + 56), B.fade(t, 2.4, 0.4),
                   fill=(120, 30, 30), outline=(180, 60, 60), size=14, pad=(11, 4))
    return B.grain(img, int(t * 10) % 7)


def sc_ptrack(t, dur):
    img = B.backdrop()
    B.put(img, "LIVE TRACKING", (120, 108), "segoeuib.ttf", 21, B.RED, B.fade(t, 0.05), spacing=3)
    B.put(img, "Watch the\napproach.", (118, 156), "segoeuib.ttf", 62, B.WHITE, B.fade(t, 0.1), line_gap=1.1)
    src = B._CACHE.get("img_track")
    B.place_phone(img, src, 810, 1130, 112, zoom=1.0 + 0.05 * min(1, t / dur), focus=(0.5, 0.42),
                  alpha=B.fade(t, 0.25, 0.6))
    for i, s in enumerate(["position stream", "ETA recomputed"]):
        B.chip(img, s, (120, 480 + i * 78), B.fade(t, 0.6 + i * 0.4, 0.4), size=21, pad=(16, 10))
    B.put(img, "No refresh button.", (120, 700), "segoeui.ttf", 26, B.WHITE, B.fade(t, 1.6, 0.6))
    return B.grain(img, int(t * 10) % 7)


RENDERERS = dict(hook=sc_hook, title=B.sc_title, preq=sc_preq, prank=sc_prank,
                 ptrack=sc_ptrack, closing=B.sc_closing)


def main():
    durs = []
    for i, sc in enumerate(SCENES):
        p = os.path.join(AUD, f"p{i:02d}.wav")
        if not os.path.exists(p):
            B.tts(sc["narration"], p, rate=1)
        data, sr = B.read_wav(p)
        durs.append(len(data) / sr)
        print(i, sc["kind"], round(durs[-1], 2))

    starts, acc = [], 0.0
    for i, d in enumerate(durs):
        pad_before = 0.45 if i == 0 else 0.55
        starts.append(acc + pad_before)
        acc += pad_before + d + (0.3 if i < len(durs) - 1 else 0.9)
    total = acc
    print("promo duration", round(total, 2), "s")

    B._CACHE["img_home"] = Image.open(os.path.join(B.FIG, "fig_ui_home.png")).convert("RGB")
    B._CACHE["img_req"] = Image.open(os.path.join(B.FIG, "fig_ui_request.png")).convert("RGB")
    B._CACHE["img_track"] = Image.open(os.path.join(B.FIG, "fig_ui_track.png")).convert("RGB")

    # audio: reuse the mixer from build.py against the promo scene list
    old_scenes, old_aud, old_out = B.SCENES, B.AUD, B.OUT
    B.SCENES, B.AUD, B.OUT = SCENES, AUD, PRO
    # promo files are named pNN.wav, so point the mixer at a compatible naming via symlink-free copy
    for i in range(len(SCENES)):
        src = os.path.join(AUD, f"p{i:02d}.wav")
        dst = os.path.join(AUD, f"n{i:02d}.wav")
        if not os.path.exists(dst):
            with open(src, "rb") as f:
                open(dst, "wb").write(f.read())
    audio = B.build_audio(starts, total)
    B.SCENES, B.AUD, B.OUT = old_scenes, old_aud, old_out

    ff = r"C:\Users\Admin\AppData\Roaming\Accio\pre-install\bd5ff2c6816a\python\Lib\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe"
    silent = os.path.join(PRO, "silent.mp4")
    proc = subprocess.Popen([ff, "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{B.W}x{B.H}",
                             "-r", str(B.FPS), "-i", "-", "-an", "-c:v", "libx264", "-preset", "medium",
                             "-crf", "19", "-pix_fmt", "yuv420p", silent],
                            stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    nframes = int(total * B.FPS)
    for f in range(nframes):
        T = f / B.FPS
        idx = 0
        for i in range(len(SCENES)):
            if T >= starts[i]:
                idx = i
        t = T - starts[idx]
        dur = (starts[idx + 1] - starts[idx]) if idx + 1 < len(starts) else total - starts[idx]
        frame = RENDERERS[SCENES[idx]["kind"]](t, dur)

        cf = 0.26
        if idx > 0 and t < cf:
            pt = (starts[idx] - starts[idx - 1]) - 0.001
            prev = RENDERERS[SCENES[idx - 1]["kind"]](pt, starts[idx] - starts[idx - 1])
            frame = Image.blend(prev.convert("RGB"), frame.convert("RGB"), B.ease(t / cf))

        d = ImageDraw.Draw(frame)
        d.rectangle((0, 1042, B.W, B.H), fill=(6, 9, 17))
        d.rectangle((0, 1037, B.W, 1042), fill=(22, 28, 42))
        d.rectangle((0, 1037, int(B.W * T / total), 1042), fill=B.RED)
        B.put(frame, "RoadResQ", (60, 1056), "segoeuib.ttf", 18, (150, 158, 175), 1.0)
        B.put(frame, "short cut", (168, 1056), "segoeui.ttf", 18, (88, 98, 118), 1.0)
        proc.stdin.write(frame.convert("RGB").tobytes())
        if f % 200 == 0:
            print("  frame", f, "/", nframes, flush=True)
    proc.stdin.close()
    proc.wait()

    final = os.path.join(B.ROOT, "RoadResQ_Promo.mp4")
    subprocess.run([ff, "-y", "-i", silent, "-i", audio, "-c:v", "copy", "-c:a", "aac", "-b:a", "160k",
                    "-shortest", "-movflags", "+faststart", final],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("wrote", final, round(os.path.getsize(final) / 1e6, 1), "MB")


if __name__ == "__main__":
    main()
