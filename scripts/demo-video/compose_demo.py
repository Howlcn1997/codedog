#!/usr/bin/env python3
"""风格样片：真实界面截图 + 镜头推拉 + 卡点字幕 + BGM，输出 build/demo-video/style-demo.mp4。

用法：python3 -I compose_demo.py
素材：build/demo-video/shots/{grid,waiting,detail,launcher}.png，build/demo-video/music/motivating-mornings.mp3
"""
import math, subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/demo-video"
SHOTS = OUT / "shots"
W, H, FPS = 1920, 1080, 30
FONT = "/System/Library/AssetsV2/com_apple_MobileAsset_Font8/86ba2c91f017a3749571a82f2c6d890ac7ffb2fb.asset/AssetData/PingFang.ttc"
SF = "/System/Library/Fonts/SFNS.ttf"
MUSIC = OUT / "music/motivating-mornings.mp3"
BEAT = 60 / 123.08
HIT = 5.85            # 音乐能量跃升在成片中的位置
MUSIC_OFFSET = 12.13 - HIT
BAR2 = 8 * BEAT       # 每个场景两小节


def font(size, weight="Semibold"):
    return ImageFont.truetype(FONT, size, index={"Regular": 3, "Medium": 7, "Semibold": 11}[weight])


def ease(t):  # easeInOutCubic
    t = max(0.0, min(1.0, t))
    return 4 * t ** 3 if t < 0.5 else 1 - (-2 * t + 2) ** 3 / 2


def ease_out(t):
    t = max(0.0, min(1.0, t))
    return 1 - (1 - t) ** 3


def spring(t):  # 带一点回弹
    t = max(0.0, min(1.0, t))
    return 1 - math.exp(-6 * t) * math.cos(9 * t)


# ---------------------------------------------------------------- 背景
def make_bg():
    bg = Image.new("RGB", (W + 200, H + 120), "#F4F1FA")
    blobs = Image.new("RGB", bg.size, "#F4F1FA")
    d = ImageDraw.Draw(blobs)
    for (x, y, r, c) in [(260, 180, 520, "#C9D8FF"), (1700, 240, 560, "#F7C8DE"), (1100, 1000, 620, "#D9CCFA"),
                         (300, 1050, 480, "#C8EEDD"), (1950, 1050, 420, "#FFE3C2")]:
        d.ellipse((x - r, y - r, x + r, y + r), fill=c)
    return blobs.filter(ImageFilter.GaussianBlur(160))


BG = make_bg()


def background(t):
    dx = int(100 + 60 * math.sin(t * 0.25))
    dy = int(60 + 40 * math.cos(t * 0.2))
    return BG.crop((dx, dy, dx + W, dy + H)).convert("RGBA")


# ---------------------------------------------------------------- 素材
def rounded(img, r):
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, img.width - 1, img.height - 1), r, fill=255)
    if img.mode == "RGBA":
        m = Image.composite(img.getchannel("A"), Image.new("L", img.size, 0), m)
    img = img.convert("RGBA")
    img.putalpha(m)
    return img


def with_shadow(img, blur=40, offset=24, alpha=70):
    pad = blur * 3
    canvas = Image.new("RGBA", (img.width + pad * 2, img.height + pad * 2), (0, 0, 0, 0))
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    a = img.getchannel("A").point(lambda v: v * alpha // 255)
    sh.paste((20, 20, 40, 255), (pad, pad + offset), a)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(sh)
    canvas.alpha_composite(img, (pad, pad))
    return canvas, pad


def load_window(name):
    img = Image.open(SHOTS / f"{name}.png").convert("RGBA")
    img = rounded(img, 26)
    return with_shadow(img)


WINDOWS = {n: load_window(n) for n in ("grid", "waiting", "detail")}
launcher_raw = Image.open(SHOTS / "launcher.png").convert("RGBA")
ICON = Image.open(ROOT / "docs/assets/icon.png").convert("RGBA")


def place(frame, src, cx, cy, scale):
    """把带阴影的素材 (img, pad) 以内容中心 (cx, cy) 和缩放 scale 贴到画面上。
    cx/cy 是源图内容坐标（不含阴影 pad）中想放到画面中心的点。"""
    img, pad = src
    sw, sh = int(img.width * scale), int(img.height * scale)
    im = img.resize((sw, sh), Image.BILINEAR)
    x = int(W / 2 - (cx + pad) * scale)
    y = int(H / 2 - (cy + pad) * scale)
    frame.alpha_composite(im, (x, y)) if 0 <= x and 0 <= y and x + sw <= W and y + sh <= H else paste_clip(frame, im, x, y)
    return x + pad * scale, y + pad * scale


def paste_clip(frame, im, x, y):
    l, t = max(0, -x), max(0, -y)
    r, b = min(im.width, W - x), min(im.height, H - y)
    if r > l and b > t:
        frame.alpha_composite(im.crop((l, t, r, b)), (x + l, y + t))


# ---------------------------------------------------------------- 字幕
def caption(frame, title, sub, t, dur):
    """底部居中的毛玻璃胶囊：标题 + 副标题。进场上滑淡入，退场淡出。"""
    a_in = ease_out((t - 0.15) / 0.45)
    a_out = 1 - ease((t - (dur - 0.35)) / 0.3)
    a = max(0.0, min(a_in, a_out))
    if a <= 0:
        return
    ft, fs = font(54), font(28, "Medium")
    tw = ft.getbbox(title)[2]
    sw = fs.getbbox(sub)[2] if sub else 0
    bw = max(tw, sw) + 120
    bh = 150 if sub else 104
    x0 = (W - bw) // 2
    y0 = H - bh - 56 + int(30 * (1 - a_in))
    # 毛玻璃：模糊背后的画面再叠深色
    region = frame.crop((x0, y0, x0 + bw, y0 + bh)).filter(ImageFilter.GaussianBlur(24))
    glass = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    glass.alpha_composite(region)
    glass.alpha_composite(Image.new("RGBA", (bw, bh), (22, 20, 34, 200)))
    mask = Image.new("L", (bw, bh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, bw - 1, bh - 1), 30, fill=int(255 * a))
    layer = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    layer.paste(glass, (0, 0), mask)
    d = ImageDraw.Draw(layer)
    d.text(((bw - tw) // 2, 22), title, font=ft, fill=(255, 255, 255, int(255 * a)))
    if sub:
        d.text(((bw - sw) // 2, 94), sub, font=fs, fill=(205, 200, 225, int(255 * a)))
    frame.alpha_composite(layer, (x0, y0))


def ring(frame, box, t, color=(255, 122, 40)):
    """高亮框：描边 + 呼吸。box 为画面坐标。"""
    a = ease_out(t / 0.4)
    if a <= 0:
        return
    pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi / (BEAT * 2))
    x0, y0, x1, y1 = box
    g = 6 + 6 * pulse
    layer = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle((x0 - g, y0 - g, x1 + g, y1 + g), 16, outline=color + (int(110 * a),), width=10)
    layer = layer.filter(ImageFilter.GaussianBlur(6))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle((x0 - 4, y0 - 4, x1 + 4, y1 + 4), 12, outline=color + (int(255 * a),), width=4)
    frame.alpha_composite(layer)


# ---------------------------------------------------------------- 场景
def cam(t, dur, a, b):
    """在 a → b 之间推镜头，(cx, cy, scale)。"""
    k = ease(t / dur)
    return tuple(a[i] + (b[i] - a[i]) * k for i in range(3))


def title_card(t, dur, outro=False):
    f = background(t)
    # 图标弹入
    k = spring((t - 0.2) / 0.9)
    size = int(220 * max(0.01, k))
    icon = ICON.resize((size, size), Image.LANCZOS)
    icon_s, pad = with_shadow(rounded(icon, int(size * 0.22)), blur=24, offset=14, alpha=60)
    cy = H // 2 - 110
    f.alpha_composite(icon_s, (W // 2 - size // 2 - pad, cy - size // 2 - pad))
    d = ImageDraw.Draw(f)
    a1 = ease_out((t - 0.7) / 0.5)
    fn = ImageFont.truetype(SF, 112)
    name = "codedog"
    nw = d.textbbox((0, 0), name, font=fn)[2]
    txt = Image.new("RGBA", f.size, (0, 0, 0, 0))
    ImageDraw.Draw(txt).text(((W - nw) // 2, cy + 130 + int(20 * (1 - a1))), name, font=fn, fill=(29, 29, 31, int(255 * a1)))
    a2 = ease_out((t - (1.6 if not outro else 1.2)) / 0.6)
    tag = "看见所有项目，最快打开它"
    ft = font(46, "Medium")
    tw = d.textbbox((0, 0), tag, font=ft)[2]
    ImageDraw.Draw(txt).text(((W - tw) // 2, cy + 290 + int(16 * (1 - a2))), tag, font=ft, fill=(90, 86, 110, int(255 * a2)))
    if outro:
        a3 = ease_out((t - 2.0) / 0.6)
        url = "github.com/Howlcn1997/codedog"
        fu = font(30, "Regular")
        uw = d.textbbox((0, 0), url, font=fu)[2]
        ImageDraw.Draw(txt).text(((W - uw) // 2, cy + 380), url, font=fu, fill=(120, 116, 140, int(255 * a3)))
    f.alpha_composite(txt)
    return f


def window_scene(name, t, dur, a, b, title, sub, rings=()):
    f = background(t)
    # 入场：轻微放大淡入
    cx, cy, s = cam(t, dur, a, b)
    k = ease_out(t / 0.35)
    s *= 1.04 - 0.04 * k
    ox, oy = place(f, WINDOWS[name], cx, cy, s)
    for (box, start) in rings:
        if t >= start:
            x0, y0, x1, y1 = box
            ring(f, (ox + x0 * s, oy + y0 * s, ox + x1 * s, oy + y1 * s), t - start)
    caption(f, title, sub, t, dur)
    if k < 1:  # 淡入
        f = Image.blend(prev_frame[0], f, k) if prev_frame[0] is not None else f
    return f


def launcher_scene(t, dur):
    f = background(t)
    # 暗一点的背景强调浮层
    f.alpha_composite(Image.new("RGBA", f.size, (30, 20, 60, int(40 * ease_out(t / 0.4)))))
    # 键帽 ⌘ ⇧ Space 逐拍弹出，随后启动器弹出
    keys = ["⌘", "⇧", "Space"]
    fk = ImageFont.truetype(SF, 64)
    widths = [130 if k != "Space" else 300 for k in keys]
    gap = 28
    x = (W - sum(widths) - gap * (len(keys) - 1)) // 2
    lift = ease(( t - BEAT * 4) / 0.4)              # 第 4 拍后键帽上移，给启动器让位
    y = int(H / 2 - 65 - 330 * lift)
    for i, (k, kw) in enumerate(zip(keys, widths)):
        a = spring((t - i * BEAT) / 0.5)
        if a <= 0.01:
            x += kw + gap; continue
        cap = Image.new("RGBA", (kw, 130), (0, 0, 0, 0))
        d = ImageDraw.Draw(cap)
        d.rounded_rectangle((0, 8, kw - 1, 129), 26, fill=(205, 200, 222, 255))
        d.rounded_rectangle((0, 0, kw - 1, 118), 26, fill=(255, 255, 255, 255))
        tw = d.textbbox((0, 0), k, font=fk)
        d.text(((kw - (tw[2] - tw[0])) // 2 - tw[0], (118 - (tw[3] - tw[1])) // 2 - tw[1]), k, font=fk, fill=(40, 36, 60, 255))
        sc = max(0.05, a) * (0.9 if lift < 1 else 0.7) + 0.0
        sc = max(0.05, a) * (1 - 0.35 * lift)
        cap = cap.resize((max(1, int(kw * sc)), max(1, int(130 * sc))), Image.BILINEAR)
        cap, pad = with_shadow(cap, blur=14, offset=8, alpha=50)
        cx = x + kw / 2
        cxs = W / 2 + (cx - W / 2) * (1 - 0.35 * lift)
        f.alpha_composite(cap, (int(cxs - cap.width / 2), int(y + 65 - cap.height / 2)))
        x += kw + gap
    tl = t - BEAT * 4
    if tl > 0:
        k = spring(tl / 0.6)
        s = 0.58 * (0.8 + 0.2 * k)
        src = with_shadow(launcher_raw, blur=40, offset=26, alpha=90)
        lay = Image.new("RGBA", f.size, (0, 0, 0, 0))
        place(lay, src, launcher_raw.width / 2, launcher_raw.height / 2 - 70, s)
        if k < 1:
            lay.putalpha(lay.getchannel("A").point(lambda v: int(v * min(1, k * 1.5))))
        f.alpha_composite(lay)
    caption(f, "在任何地方，一键呼出", "输入几个字母，回车用编辑器打开，Command + 回车续上 AI 会话", t, dur)
    return f


prev_frame = [None]

# 截图是 2x（2560×1600）；以下坐标都是截图像素
FULL = (1280, 800)
SCENES = [
    (HIT, lambda t, d: title_card(t, d)),
    (BAR2, lambda t, d: window_scene("grid", t, d, (1280, 820, 0.62), (1300, 760, 0.68),
                                     "自动发现电脑上的所有项目", "Git · Node · Go · Python · Rust · Swift，只读不改")),
    (BAR2, lambda t, d: window_scene("waiting", t, d, (1100, 560, 0.72), (900, 480, 0.98),
                                     "AI 答完了，一眼就知道", "「等你回复」汇总所有在等你下一句的项目",
                                     rings=[((22, 300, 412, 360), 0.5)])),
    (BAR2, lambda t, d: window_scene("detail", t, d, (1700, 700, 0.75), (2050, 620, 1.05),
                                     "一键续上 AI 会话", "在终端执行 claude --resume，上下文原样回来",
                                     rings=[((1660, 402, 2490, 494), 0.6)])),
    (BAR2, lambda t, d: launcher_scene(t, d)),
    (BAR2 + 1.5, lambda t, d: title_card(t, d, outro=True)),
]


def main():
    total = sum(d for d, _ in SCENES)
    out = OUT / "style-demo.mp4"
    ff = subprocess.Popen([
        "ffmpeg", "-v", "error", "-y",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
        "-ss", f"{MUSIC_OFFSET:.3f}", "-i", str(MUSIC),
        "-filter_complex", f"[1:a]afade=t=in:d=0.6,afade=t=out:st={total - 2:.2f}:d=2,volume=0.9[a]",
        "-map", "0:v", "-map", "[a]", "-shortest",
        "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
        "-movflags", "+faststart", str(out)], stdin=subprocess.PIPE)
    n = int(total * FPS)
    starts, acc = [], 0.0
    for d, _ in SCENES:
        starts.append(acc); acc += d
    cur = -1
    last = None
    for i in range(n):
        t = i / FPS
        k = max(j for j, s in enumerate(starts) if s <= t + 1e-6)
        if k != cur:
            prev_frame[0] = last
            cur = k
        d, fn = SCENES[k]
        frame = fn(t - starts[k], d).convert("RGB")
        last = frame.convert("RGBA")
        ff.stdin.write(frame.tobytes())
        if i % 90 == 0:
            print(f"  {t:5.1f}s / {total:.1f}s", flush=True)
    ff.stdin.close()
    ff.wait()
    print("→", out)


if __name__ == "__main__":
    main()
