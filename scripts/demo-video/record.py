#!/usr/bin/env python3
"""逐场景录制真实界面：启动演示 App，用 driver 模拟操作，ffmpeg 录外接屏。

依赖：build/driver（driver.swift 编译产物）、build/demo-video/audio/*.json（tts.py 产出，用来按旁白卡点）。
用法：python3 -I record.py [scene_id…]    不带参数则录全部
产出：build/demo-video/rec/<id>.mp4 与 <id>.events.json（录制起点、各动作时间）
"""
import json, os, shutil, signal, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
BUILD = ROOT / "build"
DRIVER = str(BUILD / "driver")
APP = BUILD / "DerivedData/Build/Products/Debug/codedog.app/Contents/MacOS/codedog"
AUDIO = BUILD / "demo-video/audio"
REC = BUILD / "demo-video/rec"
DEMO = Path.home() / "codedog-demo"
DEV = Path.home() / "Developer"
SCREEN_DEVICE = os.environ.get("DEMO_SCREEN", "2")       # ffmpeg avfoundation 屏幕序号（外接 4K）
# 外接屏在全局坐标中的位置（左上原点）
SX, SY, SW, SH = -184, -1080, 1920, 1080
WIN = (SX + (SW - 1280) // 2, SY + (SH - 800) // 2 + 10, 1280, 800)

app_proc = None
fake_claude = None


def drv(*args, check=True):
    r = subprocess.run([DRIVER, *map(str, args)], capture_output=True, text=True)
    if check and r.returncode != 0:
        print("  driver failed:", args, r.stdout.strip(), r.stderr.strip())
    return r.stdout.strip()


def osa(script):
    return subprocess.run(["osascript", "-e", script], capture_output=True, text=True).stdout.strip()


def launch_app(data_dir: Path):
    global app_proc
    quit_app()
    env = dict(os.environ, CODEDOG_DATA_DIR=str(data_dir), CODEX_HOME=str(DEMO / "codex"))
    app_proc = subprocess.Popen([str(APP)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(60):
        time.sleep(0.25)
        if drv("window", app_proc.pid, check=False):
            break
    place_window()


def place_window():
    drv("setwindow", app_proc.pid, *WIN)


def quit_app():
    global app_proc
    if app_proc and app_proc.poll() is None:
        app_proc.terminate()
        try:
            app_proc.wait(5)
        except subprocess.TimeoutExpired:
            app_proc.kill()
    app_proc = None


def activate_app():
    # 用 pid 激活，避免误激活用户自己的 codedog
    osa(f'tell application "System Events" to set frontmost of (first process whose unix id is {app_proc.pid}) to true')


def start_fake_claude():
    """一个名为 claude 的常驻进程，cwd 在 order-service，让卡片显示"运行中"。"""
    global fake_claude
    bin_dir = DEMO / "bin"
    bin_dir.mkdir(exist_ok=True)
    exe = bin_dir / "claude"
    if not exe.exists():
        shutil.copy("/bin/sleep", exe)
    if fake_claude is None or fake_claude.poll() is not None:
        fake_claude = subprocess.Popen([str(exe), "86400"], cwd=DEV / "order-service")


def stop_fake_claude():
    if fake_claude and fake_claude.poll() is None:
        fake_claude.kill()


def kill_demo_claude_sessions():
    """结束录制时由 codedog 在终端里拉起的 claude --resume（只杀 cwd 在 ~/Developer 下的）。"""
    out = subprocess.run(["pgrep", "-x", "claude"], capture_output=True, text=True).stdout.split()
    for pid in out:
        cwd = subprocess.run(["lsof", "-a", "-p", pid, "-d", "cwd", "-Fn"], capture_output=True, text=True).stdout
        if f"n{DEV}/" in cwd and (not fake_claude or int(pid) != fake_claude.pid):
            os.kill(int(pid), signal.SIGTERM)


def close_terminal():
    kill_demo_claude_sessions()
    time.sleep(0.8)
    osa('if application "Terminal" is running then tell application "Terminal" to quit')
    time.sleep(1.0)


def hide_others():
    osa('tell application "System Events" to set visible of (every process whose background only is false and unix id is not '
        f'{app_proc.pid if app_proc else 0}) to false')


class Clock:
    """场景时钟：t=0 为旁白开始。cue(词) 返回旁白念到该词的时间。"""

    def __init__(self, sid, lead):
        self.lead = lead
        f = AUDIO / f"{sid}.json"
        self.a = json.loads(f.read_text()) if f.exists() else None
        self.duration = self.a["end"][-1] if self.a else 8.0
        self.t0 = None
        self.events = []

    def start(self):
        self.t0 = time.time() + self.lead

    def now(self):
        return time.time() - self.t0

    def cue(self, word, nth=0):
        text = "".join(self.a["chars"]) if self.a else ""
        i = -1
        for _ in range(nth + 1):
            i = text.find(word, i + 1)
        if i < 0:
            print("  cue not found:", word)
            return self.now() + 0.5
        return self.a["start"][i]

    def at(self, t, label=""):
        d = t - self.now()
        if d > 0:
            time.sleep(d)
        self.events.append((round(self.now(), 2), label))

    def before(self, word, lead=0.4, nth=0):
        self.at(self.cue(word, nth) - lead, word)


def record(sid, body, lead=1.2, tail=1.5):
    """录一个场景：先预备 lead 秒，旁白时长 + tail 秒后停止。"""
    REC.mkdir(parents=True, exist_ok=True)
    out = REC / f"{sid}.mp4"
    ff = subprocess.Popen(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "avfoundation", "-capture_cursor", "1",
                           "-framerate", "30", "-pixel_format", "nv12", "-i", f"{SCREEN_DEVICE}:none",
                           "-c:v", "h264_videotoolbox", "-b:v", "40M", "-pix_fmt", "yuv420p", str(out)], stdin=subprocess.PIPE)
    time.sleep(1.5)  # 等 ffmpeg 真正开始出帧
    rec_start = time.time()
    c = Clock(sid, lead)
    c.start()
    body(c)
    c.at(c.duration + tail, "end")
    ff.stdin.write(b"q"); ff.stdin.flush()
    ff.wait(30)
    (REC / f"{sid}.events.json").write_text(json.dumps(dict(
        vo_start=round(c.t0 - rec_start, 3), duration=c.duration, events=c.events), ensure_ascii=False, indent=1))
    print("recorded", sid, round(c.duration, 1), "s", c.events)


# ---------------------------------------------------------------- 场景
P = lambda: app_proc.pid


def card(name):
    return f"{name} | ~/Developer/{name}"


def s02_scan(c):
    # 全新数据目录：只有 library.json，没有缓存 → 能看到扫描过程
    fresh = DEMO / "data-fresh"
    shutil.rmtree(fresh, ignore_errors=True)
    fresh.mkdir()
    shutil.copy(DEMO / "data/library.json", fresh / "library.json")
    drv("warp", SX + SW // 2, SY + SH - 160)
    c.at(0.3, "launch")
    launch_app(fresh)
    activate_app()
    c.before("Git", 0.6)
    drv("goto", P(), card("shop-web"), "-", 0, 1.2, 0, 40)
    c.before("Rust", 0.3)
    drv("goto", P(), card("weather-cli"), "-", 0, 1.2, 0, 40)
    c.before("全程只读", 0.2)
    drv("goto", P(), card("noteflow"), "-", 0, 1.4, 0, 60)


def s03_cards(c):
    c.at(0.2)
    drv("goto", P(), card("shop-web"), "-", 0, 1.0, 0, 20)
    c.before("项目类型", 0.6)
    drv("goto", P(), card("data-pipeline"), "-", 0, 1.0, 40, 70)
    c.before("右下角", 0.3)
    drv("goto", P(), card("order-service"), "-", 0, 0.9, -40, 77)
    c.before("等你回复", 0.6)
    drv("goto", P(), card("shop-web"), "-", 0, 0.8, -40, 77)


def s04_filter(c):
    c.before("等你回复", 0.9)
    drv("tap", P(), "等你回复", "AXStaticText", 0, 0.9)
    c.before("标签", 0.5)
    drv("tap", P(), "小鹿商城", "AXStaticText", 0, 0.8)
    c.before("AI 工具", 0.5)
    drv("scroll", -500, 40)
    time.sleep(0.3)
    drv("tap", P(), "Codex", "AXStaticText", 0, 0.6)
    c.before("项目类型", 0.2)
    drv("tap", P(), "网页", "AXStaticText", 0, 0.6)
    c.before("颜色", 0.2)
    drv("scroll", 300, 30)
    time.sleep(0.2)
    drv("tap", P(), "粉色", "AXStaticText", 0, 0.6)
    c.at(c.duration + 0.3)
    drv("scroll", 800, 30)
    time.sleep(0.2)
    drv("tap", P(), "全部项目", "AXStaticText", 0, 0.8)


def s05_search(c):
    c.at(0.0)
    drv("tap", P(), "搜索项目", "-", 0, 0.9)
    c.before("依赖", 0.9)
    drv("type", "polars", 6)
    c.before("备注", 0.2)
    for _ in range(6):
        drv("key", "delete"); time.sleep(0.06)
    drv("type", "staging", 7)
    c.before("Command", 0.8)
    drv("key", "esc"); time.sleep(0.15); drv("key", "esc")
    c.before("切换", 0.4)
    drv("key", "cmd+shift+l")
    c.at(c.duration + 0.6)
    drv("key", "cmd+shift+l")


def s06_detail(c):
    c.at(0.0)
    drv("tap", P(), card("shop-web"), "-", 0, 0.9)
    c.before("提交和", 0.8)
    drv("goto", P(), "活动", "-", 0, 0.8, 120, 50)
    c.before("花费", 0.6)
    drv("goto", P(), "花费", "-", 0, 0.7)
    c.before("当前分支", 0.4)
    drv("goto", P(), "活动", "-", 0, 0.6, 120, 140)
    drv("scroll", -260, 40)
    c.before("README", 0.6)
    drv("scroll", -420, 50)
    c.before("备注", 0.3)
    drv("scroll", -300, 40)


def s07_resume(c):
    c.at(0.0)
    drv("scroll", 1200, 50)
    c.before("续上", 0.8)
    drv("tap", P(), "续上", "AXButton", 0, 0.9)
    c.before("原样回来", 1.5)
    # 把终端窗口摆到中间
    for _ in range(20):
        if drv("window", "com.apple.Terminal", check=False):
            break
        time.sleep(0.2)
    drv("setwindow", "com.apple.Terminal", WIN[0] + 60, WIN[1] + 40, 1160, 720)
    c.before("直接接着聊", 0.2)
    drv("move", WIN[0] + 700, WIN[1] + 690, 0.6)
    drv("type", "好，把结算页的金额明细也展示出来", 7)


def s08_launcher(c):
    c.at(0.2)
    drv("key", "cmd+shift+space")
    c.before("输入几个字母", 0.2)
    drv("type", "note", 5)
    c.before("回车用编辑器", 0.3)
    drv("key", "right"); time.sleep(0.5); drv("key", "right"); time.sleep(0.5); drv("key", "left"); time.sleep(0.4); drv("key", "left")
    c.before("Command 回车", -0.2, nth=1)
    drv("key", "cmd+return")
    time.sleep(1.2)
    for _ in range(20):
        if drv("window", "com.apple.Terminal", check=False):
            break
        time.sleep(0.2)
    drv("setwindow", "com.apple.Terminal", WIN[0] + 60, WIN[1] + 40, 1160, 720)


def s09_cleanup(c):
    c.at(0.0)
    drv("tap", P(), "占空间", "AXStaticText", 0, 0.9)
    c.before("一键", 0.5)
    drv("tap", P(), "清理…", "AXButton", 0, 0.8)
    c.at(c.duration + 0.4)
    drv("key", "esc")


SCENES = [
    ("s02_scan", s02_scan, dict(prep="desktop")),
    ("s03_cards", s03_cards, dict(prep="main")),
    ("s04_filter", s04_filter, dict(prep="main")),
    ("s05_search", s05_search, dict(prep="main")),
    ("s06_detail", s06_detail, dict(prep="main")),
    ("s07_resume", s07_resume, dict(prep="detail")),
    ("s08_launcher", s08_launcher, dict(prep="launcher")),
    ("s09_cleanup", s09_cleanup, dict(prep="main")),
]


def prep(kind):
    close_terminal()
    if kind == "desktop":
        quit_app()
        hide_others()
        return
    if not app_proc or app_proc.poll() is not None:
        launch_app(DEMO / "data")
        time.sleep(8)  # 首次启动：扫描、Git、AI 索引都完成
    activate_app()
    place_window()
    hide_others()
    drv("key", "esc"); time.sleep(0.2); drv("key", "esc")
    drv("tap", P(), "全部项目", "AXStaticText", 0, 0.3)
    if kind == "detail":
        drv("tap", P(), card("shop-web"), "-", 0, 0.3)
        time.sleep(1.0)
    if kind == "launcher":
        # 隐藏 codedog 主窗口，只留桌面
        drv("key", "cmd+h")
    drv("move", WIN[0] + 900, WIN[1] + 500, 0.3)
    time.sleep(1.0)


def main():
    only = sys.argv[1:]
    start_fake_claude()
    if not (DEMO / "data/cache.json").exists():
        print("warming caches…")
        launch_app(DEMO / "data"); time.sleep(25); quit_app()
    try:
        for sid, body, opt in SCENES:
            if only and sid not in only:
                continue
            prep(opt["prep"])
            record(sid, body)
    finally:
        close_terminal()
        quit_app()
        stop_fake_claude()


if __name__ == "__main__":
    main()
