#!/usr/bin/env python3
"""生成演示视频用的假数据：~/Developer 下的项目（含一年 git 历史）、Claude/Codex 会话、codedog 数据目录。

用法：python3 -I make_demo.py [--clean]
  - 项目：~/Developer/<name>
  - Claude 会话：~/.claude/projects/-Users-<you>-Developer-<name>/<uuid>.jsonl（供真实 `claude --resume` 使用）
  - Codex 会话：~/codedog-demo/codex/sessions/...（App 用 CODEX_HOME 指过来）
  - codedog 数据：~/codedog-demo/data/library.json
--clean 只删除上述演示内容。时间都相对"现在"，录制前重新生成即可。
"""
import json, os, random, shutil, subprocess, sys, uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

HOME = Path.home()
DEV = HOME / "Developer"
DEMO = HOME / "codedog-demo"
DATA = DEMO / "data"
CODEX = DEMO / "codex"
CLAUDE_PROJECTS = HOME / ".claude" / "projects"
EMAIL = "lin@codedog.dev"
NAME = "Lin"
NOW = datetime.now(timezone.utc).replace(microsecond=0)
CLAUDE_VERSION = "2.1.322"
rnd = random.Random(42)


def claude_key(path: Path) -> str:
    return "".join(c if c.isalnum() else "-" for c in str(path))


def clean():
    if DEV.exists():
        shutil.rmtree(DEV)
    if DEMO.exists():
        shutil.rmtree(DEMO)
    prefix = claude_key(DEV) + "-"
    for d in CLAUDE_PROJECTS.glob(prefix + "*"):
        shutil.rmtree(d)


# ---------------------------------------------------------------- 项目定义
# activity: 一年内提交的大致数量；recent: 最近一次提交距今（天）；dirty: 未提交文件数
P = []


def proj(name, files, desc_readme, **kw):
    d = dict(name=name, files=files, readme=desc_readme, activity=60, recent=3, dirty=0, tags=[], color=None,
             favorite=False, notes="", claude=[], codex=[], deps_mb=0, subjects=None, start=360)
    d.update(kw)
    P.append(d)


def pkg(name, desc, deps, dev=None, scripts=None):
    return json.dumps({"name": name, "version": "0.4.2", "private": True, "description": desc,
                       "scripts": scripts or {"dev": "vite", "build": "vite build"},
                       "dependencies": deps, "devDependencies": dev or {"typescript": "^5.6.3"}}, indent=2, ensure_ascii=False) + "\n"


WEB_SUBJECTS = ["feat: 商品详情页支持多规格选择", "fix: 修复购物车数量为 0 时仍可结算", "feat: 首页瀑布流懒加载", "refactor: 抽出 useCart hook",
                "style: 统一按钮圆角", "feat: 订单列表分页", "fix: Safari 下日期解析错误", "chore: 升级 next 到 15", "feat: 暗色模式",
                "perf: 图片改用 avif", "test: 补充结算流程 e2e", "feat: 优惠券叠加规则", "fix: 登录态过期后跳转循环", "docs: 更新 README"]
SVC_SUBJECTS = ["feat: 订单超时自动关闭", "fix: 并发扣库存的竞态", "feat: 新增 /v2/orders 接口", "refactor: 拆分 repository 层",
                "perf: 订单查询加复合索引", "chore: 升级依赖", "feat: 接入链路追踪", "fix: 时区导致的对账差异", "test: 补充退款单测",
                "feat: 幂等键中间件", "docs: 补充接口文档"]
PY_SUBJECTS = ["feat: 新增每日活跃用户报表", "fix: 处理空分区", "refactor: 用 polars 替换 pandas", "feat: 增量同步", "chore: 调整调度时间",
               "perf: 批量写入", "fix: 编码问题", "feat: 数据质量校验", "docs: 补充字段说明"]
GEN_SUBJECTS = ["feat: 初版", "fix: 小修", "refactor: 整理代码", "chore: 更新依赖", "feat: 新功能", "docs: 更新说明", "style: 格式化", "test: 补测试"]

TSX_PAGE = """import { useCart } from '@/hooks/useCart'
import { ProductCard } from '@/components/ProductCard'

export default async function Home() {
  const products = await fetch(`${process.env.API}/products?limit=24`).then(r => r.json())
  return (
    <main className="grid grid-cols-2 gap-4 p-4 md:grid-cols-4">
      {products.map((p: Product) => <ProductCard key={p.id} product={p} />)}
    </main>
  )
}
"""
GO_MAIN = """package main

import (
\t"log"
\t"net/http"

\t"github.com/go-chi/chi/v5"
)

func main() {
\tr := chi.NewRouter()
\tr.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte("ok")) })
\tr.Mount("/v2/orders", ordersRouter())
\tlog.Println("listening on :8080")
\tlog.Fatal(http.ListenAndServe(":8080", r))
}
"""

GAME_HTML = """<!doctype html>
<html lang="zh"><head><meta charset="utf-8"><title>Star Hopper</title>
<style>html,body{margin:0;height:100%;background:#0b1026;overflow:hidden}
.sky{position:absolute;inset:0;background:radial-gradient(circle at 30% 20%,#3b2f8f 0,#0b1026 60%)}
.star{position:absolute;width:3px;height:3px;border-radius:50%;background:#fff}
.planet{position:absolute;left:58%;top:42%;width:180px;height:180px;border-radius:50%;background:linear-gradient(135deg,#ffb86b,#ff5e7e)}
.ship{position:absolute;left:24%;top:58%;font:64px sans-serif}
h1{position:absolute;left:8%;top:10%;color:#fff;font:800 56px/1 -apple-system,sans-serif;letter-spacing:-1px}</style></head>
<body><div class="sky"></div><div class="planet"></div><div class="ship">🚀</div><h1>Star Hopper</h1>
<script>for(let i=0;i<80;i++){const s=document.createElement('div');s.className='star';s.style.left=Math.random()*100+'%';s.style.top=Math.random()*100+'%';document.body.appendChild(s)}</script>
</body></html>
"""
LANDING_HTML = """<!doctype html>
<html lang="zh"><head><meta charset="utf-8"><title>Lumen 智能台灯</title>
<style>body{margin:0;font-family:-apple-system,sans-serif;background:#f6f1ea;color:#222}
header{padding:64px 8%;}h1{font-size:64px;margin:0;letter-spacing:-2px}p{font-size:22px;color:#666}
.lamp{position:absolute;right:10%;top:12%;width:220px;height:220px;border-radius:50%;background:radial-gradient(circle,#ffe8a3,#f6f1ea 70%)}
a{display:inline-block;margin-top:24px;padding:14px 28px;background:#222;color:#fff;border-radius:999px;text-decoration:none}</style></head>
<body><div class="lamp"></div><header><h1>Lumen</h1><p>会随日落调节色温的智能台灯。</p><a href="#">预约首发</a></header></body></html>
"""

proj("shop-web", {
    "package.json": pkg("shop-web", "小鹿商城 Web 前端：Next.js + Tailwind", {"next": "^15.0.3", "react": "^19.0.0", "react-dom": "^19.0.0", "zustand": "^5.0.1", "swr": "^2.2.5"},
                        {"typescript": "^5.6.3", "tailwindcss": "^3.4.14", "@playwright/test": "^1.48.2"}, {"dev": "next dev", "build": "next build"}),
    "tsconfig.json": "{}\n", "app/page.tsx": TSX_PAGE, "app/cart/page.tsx": "export default function Cart() { return null }\n",
    "hooks/useCart.ts": "export function useCart() {}\n", "components/ProductCard.tsx": "export function ProductCard() { return null }\n",
}, "# 小鹿商城 Web\n\n小鹿商城的 Web 前端，基于 Next.js App Router 与 Tailwind CSS。\n\n## 开发\n\n```sh\npnpm install\npnpm dev\n```\n\n## 目录\n\n- `app/` 页面与路由\n- `components/` 通用组件\n- `hooks/` 购物车、登录态等状态\n",
     activity=260, recent=0, dirty=3, tags=["小鹿商城"], color="blue", favorite=True, deps_mb=640, subjects=WEB_SUBJECTS,
     notes="预发环境：staging.xiaolu.shop\n结算页改版 12 月上线",
     claude=[dict(title="优惠券叠加规则与结算页金额校验", age_h=1.5, waiting=True, model="claude-opus-5-5", turns=[
         ("结算页的优惠券现在不能叠加，产品要求满减券和品类券可以叠加，但同类不能叠加，帮我改一下 useCart 里的计算逻辑", "我看了 `hooks/useCart.ts`，现在 `applyCoupon` 只保留最后一张券。我改成按 `type` 分组：每组只取面额最大的一张，组间叠加，最后再和订单金额取较小值，避免出现负数。\n\n同时在 `app/cart/page.tsx` 增加了提示文案。"),
         ("跑一下测试", "e2e 全部通过（14/14）。新增了 3 个用例覆盖：同类券互斥、满减+品类叠加、优惠后金额不为负。\n\n要我顺便把结算页的金额明细也展示出来吗？"),
     ]), dict(title="首页瀑布流图片懒加载", age_h=50, model="claude-sonnet-5-5", turns=[
         ("首页图片太多，滚动卡顿，帮我做懒加载", "已改用 `next/image` 的 `loading=\"lazy\"`，并给瀑布流加了 IntersectionObserver 分批渲染，首屏请求从 96 个降到 18 个。")]),
         dict(title="Safari 日期解析报错排查", age_h=24 * 9, model="claude-sonnet-5-5", turns=[
             ("Safari 下订单列表时间显示 Invalid Date", "原因是后端返回 `2025-03-01 10:00:00`，Safari 不接受空格分隔。已统一用 `date-fns/parseISO` 并在接口层转成 ISO 8601。")])])

proj("order-service", {
    "go.mod": "module github.com/xiaolu/order-service\n\ngo 1.23\n\nrequire github.com/go-chi/chi/v5 v5.1.0\n",
    "cmd/server/main.go": GO_MAIN, "internal/orders/handler.go": "package orders\n", "internal/orders/repo.go": "package orders\n",
}, "# order-service\n\n小鹿商城订单服务：下单、支付回调、超时关单与退款。Go + PostgreSQL。\n\n```sh\nmake run\n```\n",
     activity=200, recent=0, dirty=1, tags=["小鹿商城"], color="teal", favorite=True, subjects=SVC_SUBJECTS,
     claude=[dict(title="订单超时自动关闭的定时任务", age_h=0.3, model="claude-opus-5-5", turns=[
         ("加一个订单超时自动关闭：30 分钟未支付就关闭并回滚库存", "我会在 `internal/orders` 下加一个 `Closer`，用 `SELECT … FOR UPDATE SKIP LOCKED` 分批取超时订单，避免多实例重复处理。先写测试…")], running=True),
         dict(title="并发扣库存竞态", age_h=24 * 3, model="claude-opus-5-5", turns=[
             ("压测时库存会扣成负数", "问题在先查后扣。改成单条 `UPDATE stock SET n = n - $1 WHERE id = $2 AND n >= $1`，按影响行数判断是否成功。")])])

proj("pay-gateway", {
    "pom.xml": "<project><modelVersion>4.0.0</modelVersion><groupId>shop.xiaolu</groupId><artifactId>pay-gateway</artifactId><description>聚合支付网关：微信、支付宝、Apple Pay</description></project>\n",
    "src/main/java/shop/xiaolu/pay/PayApplication.java": "package shop.xiaolu.pay;\n\npublic class PayApplication {}\n",
}, "# pay-gateway\n\n聚合支付网关：统一封装微信支付、支付宝与 Apple Pay，负责签名、回调验签与对账。\n",
     activity=90, recent=12, tags=["小鹿商城"], color="green", subjects=SVC_SUBJECTS,
     codex=[dict(title="对账文件解析", age_h=24 * 12, model="gpt-5.5-codex", prompt="支付宝对账文件解析，金额单位统一成分")])

proj("admin-console", {
    "package.json": pkg("admin-console", "小鹿商城运营后台：Vue 3 + Element Plus", {"vue": "^3.5.12", "element-plus": "^2.8.7", "pinia": "^2.2.6", "vite": "^5.4.10"}),
    "tsconfig.json": "{}\n", "src/App.vue": "<template><router-view /></template>\n", "src/views/Orders.vue": "<template><div /></template>\n",
}, "# admin-console\n\n小鹿商城运营后台，商品、订单、活动配置。\n",
     activity=120, recent=1, dirty=6, tags=["小鹿商城"], color="purple", deps_mb=520, subjects=WEB_SUBJECTS,
     codex=[dict(title="订单导出 Excel", age_h=26, model="gpt-5.5-codex", prompt="订单列表加导出 Excel，支持按时间筛选", waiting=True)])

proj("data-pipeline", {
    "pyproject.toml": '[project]\nname = "data-pipeline"\ndescription = "每日经营数据 ETL：从业务库同步到数仓并产出报表"\ndependencies = ["polars", "duckdb", "prefect"]\n',
    "pipeline/flows/daily.py": "from prefect import flow\n\n@flow\ndef daily():\n    ...\n", "pipeline/__init__.py": "",
}, "# data-pipeline\n\n每日经营数据 ETL。\n", activity=150, recent=2, tags=["数据"], color="orange", subjects=PY_SUBJECTS, deps_mb=210,
     claude=[dict(title="用 polars 重写日报聚合", age_h=40, model="claude-sonnet-5-5", turns=[
         ("日报 flow 跑要 20 分钟，看看能不能快一点", "瓶颈在 pandas 的 groupby + apply。改成 polars 的 lazy 查询后，本地样本从 92s 降到 7s。")])],
     codex=[dict(title="数据质量校验", age_h=24 * 5, model="gpt-5.5-codex", prompt="给 orders 表加数据质量校验：主键唯一、金额非负")])

proj("ml-playground", {
    "requirements.txt": "torch\nnumpy\njupyterlab\nmatplotlib\n", "notebooks/mnist.ipynb": "{}\n", "train.py": "import torch\n",
}, "# ml-playground\n\n随手做的机器学习实验：MNIST、文本分类、推荐召回。\n", activity=40, recent=45, tags=["数据"], color="yellow",
     subjects=PY_SUBJECTS, deps_mb=1800,
     claude=[dict(title="推荐召回的负采样", age_h=24 * 45, model="claude-opus-5-5", turns=[("双塔模型负采样怎么做比较好", "建议用批内负采样 + 少量全局随机负样本，并对热门物品做 logQ 修正。")])])

proj("noteflow", {
    "NoteFlow.xcodeproj/project.pbxproj": "// !$*UTF8*$!\n", "NoteFlow/NoteFlowApp.swift": "import SwiftUI\n\n@main\nstruct NoteFlowApp: App {\n    var body: some Scene { WindowGroup { ContentView() } }\n}\n",
    "NoteFlow/ContentView.swift": "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View { Text(\"NoteFlow\") }\n}\n",
}, "# NoteFlow\n\n一个极简的 macOS Markdown 笔记应用，支持双向链接和 iCloud 同步。\n", activity=180, recent=1, tags=["个人"], color="pink", favorite=True,
     subjects=["feat: 双向链接", "fix: iCloud 冲突合并", "feat: 快速搜索", "refactor: 迁移到 SwiftData", "feat: 菜单栏快速记录", "fix: 深色模式下代码块配色", "perf: 大文件打开速度"],
     claude=[dict(title="iCloud 同步冲突合并", age_h=20, waiting=True, model="claude-opus-5-5", turns=[
         ("两台 Mac 同时改一篇笔记会丢内容", "我用 `NSFileVersion` 拿到冲突版本，按段落做三方合并；无法自动合并的段落保留两份并标注。已在两台模拟器上验证。\n\n需要我把冲突提示做成 UI 吗？")])])

proj("weather-cli", {
    "Cargo.toml": '[package]\nname = "weather-cli"\nversion = "0.3.0"\nedition = "2021"\ndescription = "终端里看天气：彩色图表、逐小时预报"\n\n[dependencies]\nclap = "4"\nreqwest = "0.12"\n',
    "src/main.rs": "fn main() {\n    println!(\"☀️  23°C\");\n}\n",
}, "# weather-cli\n\n终端里看天气。\n", activity=50, recent=20, tags=["个人", "工具"], color="red", deps_mb=380,
     subjects=["feat: 逐小时预报", "feat: 彩色温度曲线", "fix: 城市名含空格", "chore: 发布 0.3.0"],
     codex=[dict(title="加上空气质量", age_h=24 * 20, model="gpt-5.5-codex", prompt="加一个 --aqi 参数显示空气质量")])

proj("star-hopper", {"index.html": GAME_HTML, "game.js": "// TODO\n"},
     "# Star Hopper\n\n周末做的 HTML5 小游戏：在星球之间跳跃收集星星。\n", activity=30, recent=6, tags=["个人"], color="purple",
     subjects=["feat: 星球引力", "feat: 计分", "fix: 移动端触控", "style: 背景星空"],
     claude=[dict(title="加一个关卡选择界面", age_h=24 * 6, model="claude-sonnet-5-5", turns=[("加一个关卡选择界面", "已加入 5 个关卡和关卡选择界面，进度存在 localStorage。")])])

proj("lumen-landing", {"index.html": LANDING_HTML, "style.css": "/* */\n"},
     "# Lumen 落地页\n\n智能台灯 Lumen 的预约落地页。\n", activity=25, recent=15, tags=["外包"], color="yellow",
     subjects=["feat: 首屏", "feat: 预约表单", "fix: 移动端排版"])

proj("design-tokens", {
    "package.json": pkg("@xiaolu/design-tokens", "小鹿设计系统的颜色、字号与间距 token", {}, {"typescript": "^5.6.3", "style-dictionary": "^4.2.0"}, {"build": "style-dictionary build"}),
    "tsconfig.json": "{}\n", "tokens/color.json": "{}\n",
}, "# design-tokens\n", activity=35, recent=30, tags=["小鹿商城"], color="pink", subjects=GEN_SUBJECTS, deps_mb=120)

proj("chat-bot", {
    "package.json": pkg("chat-bot", "飞书群机器人：值班提醒、发版通知", {"express": "^4.21.1", "node-cron": "^3.0.3"}, scripts={"start": "node index.js"}),
    "index.js": "const express = require('express')\n",
}, "# chat-bot\n", activity=45, recent=4, tags=["工具"], color="green", deps_mb=90, subjects=GEN_SUBJECTS,
     claude=[dict(title="发版通知卡片", age_h=24 * 4, model="claude-haiku-5-5", turns=[("发版通知改成卡片消息", "已改为交互卡片，包含版本号、变更列表和回滚按钮。")])])

proj("dotfiles", {"install.sh": "#!/bin/sh\nln -sf \"$PWD/zshrc\" ~/.zshrc\n", "zshrc": "export EDITOR=nvim\n"},
     "# dotfiles\n\n我的 zsh、git、nvim 配置。\n", activity=40, recent=8, tags=["工具"], subjects=["chore: 更新别名", "feat: nvim lsp", "fix: path 顺序"])

proj("leetcode", {"pyproject.toml": '[project]\nname = "leetcode"\ndescription = "刷题记录"\n', "solutions/0001_two_sum.py": "def two_sum(nums, target):\n    ...\n"},
     "# leetcode\n", activity=110, recent=60, tags=["个人"], subjects=["solve: 1. 两数之和", "solve: 146. LRU 缓存", "solve: 300. 最长递增子序列", "solve: 42. 接雨水"])

proj("blog", {
    "package.json": pkg("blog", "个人博客：Astro + MDX", {"astro": "^4.16.10", "@astrojs/mdx": "^3.1.9"}, scripts={"dev": "astro dev"}),
    "src/pages/index.astro": "---\n---\n<h1>Lin's blog</h1>\n", "src/content/posts/swiftui-tips.mdx": "# SwiftUI 小技巧\n",
}, "# blog\n", activity=30, recent=10, tags=["个人"], color="brown", deps_mb=260,
     subjects=["post: SwiftUI 小技巧", "post: Go 并发模式", "feat: RSS", "style: 代码高亮"])

proj("rss-reader", {"go.mod": "module github.com/lin/rss-reader\n\ngo 1.23\n", "main.go": "package main\n\nfunc main() {}\n"},
     "# rss-reader\n\n自托管的 RSS 阅读器后端。\n", activity=20, recent=120, color="orange", subjects=SVC_SUBJECTS)

proj("pixel-editor", {
    "package.json": pkg("pixel-editor", "在浏览器里画像素画，导出 GIF", {"react": "^19.0.0", "react-dom": "^19.0.0", "vite": "^5.4.10"}),
    "tsconfig.json": "{}\n", "src/App.tsx": "export default function App() { return null }\n",
}, "# pixel-editor\n", activity=15, recent=200, tags=["个人"], deps_mb=310, subjects=WEB_SUBJECTS[:6])

proj("infra", {"main.tf": 'terraform {\n  required_version = ">= 1.9"\n}\n', "Makefile": "plan:\n\tterraform plan\n"},
     "# infra\n\n小鹿商城的云资源（Terraform）。\n", activity=30, recent=25, tags=["小鹿商城"], subjects=["infra: 新增 redis 集群", "infra: 调整 RDS 规格", "chore: provider 升级"])


# ---------------------------------------------------------------- 生成
def sh(*args, cwd=None, env=None, input=None):
    return subprocess.run(args, cwd=cwd, env=env, input=input, check=True, capture_output=True)


def iso(dt):
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def commit_dates(p):
    """一年内的提交时间：按工作日加权、成簇分布，最后一次在 recent 天前。"""
    n = p["activity"]
    last = NOW - timedelta(days=p["recent"], hours=rnd.uniform(1, 5))
    start = NOW - timedelta(days=min(p["start"], 364))
    span = (last - start).total_seconds()
    dates = []
    # 若干个"冲刺期"，提交集中在里面
    bursts = [rnd.uniform(0, 1) for _ in range(max(2, n // 25))] + [1.0]
    while len(dates) < n - 1:
        c = rnd.choice(bursts)
        x = min(1.0, max(0.0, rnd.gauss(c, 0.04)))
        d = start + timedelta(seconds=span * x)
        if d.weekday() >= 5 and rnd.random() < 0.7:
            continue
        d = d.replace(hour=rnd.choice([10, 11, 14, 15, 16, 17, 20, 21, 22]), minute=rnd.randrange(60))
        if d < last:
            dates.append(d)
    dates.append(last)
    return sorted(dates)


def build_repo(p, root: Path):
    git = ["git", "-C", str(root)]
    sh(*git, "init", "-q", "-b", "main")
    sh(*git, "config", "user.email", EMAIL)
    sh(*git, "config", "user.name", NAME)
    sh(*git, "config", "commit.gpgsign", "false")
    files = sorted(p["files"].items())
    dates = commit_dates(p)
    subjects = p["subjects"] or GEN_SUBJECTS
    # fast-import：首个提交带全部文件，其余提交改一个"活动"文件（.changes），最后几次提交改真实文件
    stream = []
    def blob(text):
        data = text.encode()
        return f"data {len(data)}\n".encode() + data + b"\n"
    log = ""
    for i, d in enumerate(dates):
        ts = int(d.timestamp())
        msg = "chore: 初始化项目" if i == 0 else rnd.choice(subjects)
        m = msg.encode()
        stream.append(f"commit refs/heads/main\nauthor {NAME} <{EMAIL}> {ts} +0800\ncommitter {NAME} <{EMAIL}> {ts} +0800\n".encode())
        stream.append(f"data {len(m)}\n".encode() + m + b"\n")
        if i == 0:
            for path, text in files:
                stream.append(f"M 100644 inline {path}\n".encode() + blob(text))
            stream.append(b"M 100644 inline README.md\n" + blob(p["readme"]))
        else:
            # 让 "最近改动的文件" 落到真实源码上
            path, text = files[i % len(files)]
            stream.append(f"M 100644 inline {path}\n".encode() + blob(text + ("" if i == len(dates) - 1 else f"{'#' if path.endswith(('.py', '.toml', '.sh')) or path in ('zshrc', 'Makefile', 'requirements.txt') else '//'} rev {i}\n" if not path.endswith(('.json', '.html', '.md', '.xml', '.ipynb', '.pbxproj', '.css', '.vue', '.mdx', '.astro', '.tf', '.mod')) else "")))
        stream.append(b"\n")
    subprocess.run(git + ["fast-import", "--quiet"], input=b"".join(stream), check=True)
    sh(*git, "checkout", "-q", "-f", "main")
    last = dates[-1].timestamp()
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d != ".git"]
        for f in filenames + dirnames:
            os.utime(os.path.join(dirpath, f), (last, last))
    os.utime(root, (last, last))
    # 未提交改动
    tracked = [f for f, _ in files if not f.startswith(".")]
    for k in range(p["dirty"]):
        if k < len(tracked):
            with open(root / tracked[k], "a") as f:
                f.write("\n")
            t = (NOW - timedelta(hours=p["recent"] * 24 + 0.5 + k)).timestamp()
            os.utime(root / tracked[k], (t, t))
        else:
            (root / f"draft-{k}.md").write_text("草稿\n")


def make_deps(p, root: Path, blob_path: Path):
    mb = p["deps_mb"]
    if not mb:
        return
    if p["files"].get("package.json"):
        d = root / "node_modules"
    elif "Cargo.toml" in p["files"]:
        d = root / "target"
    else:
        d = root / ".venv"
    d.mkdir(parents=True, exist_ok=True)
    # APFS 克隆：每份都按完整大小统计，实际几乎不占盘
    remaining = mb
    i = 0
    while remaining > 0:
        chunk = min(100, remaining)
        dst = d / f"pkg-{i}.bin"
        src = blob_path.parent / f"blob-{chunk}.bin"
        if not src.exists():
            sh("mkfile", f"{chunk}m", str(src))
        sh("cp", "-c", str(src), str(dst))
        remaining -= chunk
        i += 1


def claude_session(p, root: Path, s):
    sid = str(uuid.uuid4())
    end = NOW - timedelta(hours=s["age_h"])
    lines = []
    parent = None
    t = end - timedelta(minutes=6 * len(s["turns"]))
    common = dict(isSidechain=False, userType="external", entrypoint="cli", cwd=str(root), sessionId=sid, version=CLAUDE_VERSION, gitBranch="main")
    for k, (q, a) in enumerate(s["turns"]):
        u = str(uuid.uuid4())
        lines.append(dict(parentUuid=parent, type="user", message=dict(role="user", content=q), uuid=u, timestamp=iso(t),
                          permissionMode="default", turnOrigin="human", promptId=str(uuid.uuid4()), **common))
        parent = u
        t += timedelta(minutes=rnd.randint(2, 5))
        last = k == len(s["turns"]) - 1
        stop = "end_turn"
        if last and s.get("running"):
            t = end
        a_id = str(uuid.uuid4())
        lines.append(dict(parentUuid=parent, type="assistant", uuid=a_id, timestamp=iso(end if last else t), requestId="req_" + uuid.uuid4().hex[:24],
                          message=dict(id="msg_" + uuid.uuid4().hex[:24], type="message", role="assistant", model=s["model"],
                                       content=[dict(type="text", text=a)], stop_reason=stop, stop_sequence=None,
                                       usage=dict(input_tokens=rnd.randint(800, 4000), cache_creation_input_tokens=rnd.randint(2000, 20000),
                                                  cache_read_input_tokens=rnd.randint(80_000, 900_000), output_tokens=rnd.randint(2000, 18000))), **common))
        parent = a_id
        t += timedelta(minutes=rnd.randint(1, 4))
    if not s.get("waiting") and not s.get("running"):
        # 你已经回复过：最后补一条人类消息让它不处于"等你回复"
        lines.append(dict(parentUuid=parent, type="user", message=dict(role="user", content="好的，谢谢"), uuid=str(uuid.uuid4()),
                          timestamp=iso(end + timedelta(minutes=2)), turnOrigin="human", promptId=str(uuid.uuid4()), **common))
    lines.append(dict(type="ai-title", aiTitle=s["title"], sessionId=sid))
    lines.append(dict(type="last-prompt", lastPrompt=s["turns"][-1][0], sessionId=sid))
    d = CLAUDE_PROJECTS / claude_key(root)
    d.mkdir(parents=True, exist_ok=True)
    f = d / f"{sid}.jsonl"
    f.write_text("".join(json.dumps(l, ensure_ascii=False, separators=(",", ":")) + "\n" for l in lines))
    mt = (end + timedelta(minutes=2)).timestamp()
    os.utime(f, (mt, mt))
    return sid


def claude_history(p, root: Path):
    """额外的历史会话，让一年的 AI 圆点图有内容。"""
    n = p["activity"] // 6
    for _ in range(n):
        age = rnd.uniform(p["recent"] * 24 + 30, 24 * 330)
        claude_session(p, root, dict(title=rnd.choice(["重构", "修 bug", "写测试", "加功能", "排查问题", "代码评审"]), age_h=age,
                                     model=rnd.choice(["claude-opus-5-5", "claude-sonnet-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]),
                                     turns=[(rnd.choice(["看下这个报错", "帮我写个单测", "这段能不能简化", "加个参数"]), "已完成。")] * rnd.randint(1, 4)))


def codex_session(p, root: Path, s):
    end = NOW - timedelta(hours=s["age_h"])
    start = end - timedelta(minutes=8)
    sid = str(uuid.uuid4())
    d = CODEX / "sessions" / start.strftime("%Y/%m/%d")
    d.mkdir(parents=True, exist_ok=True)
    f = d / f"rollout-{start.strftime('%Y-%m-%dT%H-%M-%S')}-{sid}.jsonl"
    ev = [
        dict(timestamp=iso(start), type="session_meta", payload=dict(id=sid, timestamp=iso(start), cwd=str(root), originator="codex_cli_rs", cli_version="0.98.0")),
        dict(timestamp=iso(start), type="turn_context", payload=dict(cwd=str(root), model=s["model"])),
        dict(timestamp=iso(start), type="event_msg", payload=dict(type="user_message", message=s["prompt"])),
        dict(timestamp=iso(start), type="response_item", payload=dict(type="message", role="user", content=[dict(type="input_text", text=s["prompt"])])),
        dict(timestamp=iso(end), type="response_item", payload=dict(type="message", role="assistant", content=[dict(type="output_text", text="已完成，改动见 diff。")])),
        dict(timestamp=iso(end), type="event_msg", payload=dict(type="agent_message", message="已完成，改动见 diff。")),
        dict(timestamp=iso(end), type="event_msg", payload=dict(type="token_count", info=dict(total_token_usage=dict(input_tokens=52000, cached_input_tokens=40000, output_tokens=6100, total_tokens=58100)))),
        dict(timestamp=iso(end), type="event_msg", payload=dict(type="task_complete", last_agent_message="已完成，改动见 diff。")),
    ]
    if not s.get("waiting"):
        ev.append(dict(timestamp=iso(end + timedelta(minutes=3)), type="event_msg", payload=dict(type="user_message", message="好")))
    f.write_text("".join(json.dumps(e, ensure_ascii=False, separators=(",", ":")) + "\n" for e in ev))
    mt = (end + timedelta(minutes=3)).timestamp()
    os.utime(f, (mt, mt))


def main():
    clean()
    if "--clean" in sys.argv:
        print("cleaned")
        return
    DEV.mkdir()
    blobs = DEMO / "blobs"
    blobs.mkdir(parents=True)
    tags = {}
    tag_colors = {"小鹿商城": "blue", "个人": "pink", "数据": "orange", "工具": "green", "外包": "yellow"}
    meta = {}
    running = []
    for i, p in enumerate(P):
        root = DEV / p["name"]
        root.mkdir()
        if p["deps_mb"]:
            p["files"][".gitignore"] = "node_modules\ntarget\n.venv\n"
        make_deps(p, root, blobs / "x")
        build_repo(p, root)
        for s in p["claude"]:
            sid = claude_session(p, root, s)
            if s.get("running"):
                running.append(str(root))
            s["id"] = sid
        claude_history(p, root)
        for s in p["codex"]:
            codex_session(p, root, s)
        cat_ids = []
        for t in p["tags"]:
            if t not in tags:
                tags[t] = dict(id=str(uuid.uuid4()).upper(), name=t, color=tag_colors.get(t))
            cat_ids.append(tags[t]["id"])
        m = dict(favorite=False, hidden=False, categories=[], notes="", openCount=0, pinned=False)
        if p["favorite"]: m["favorite"] = True
        if cat_ids: m["categories"] = cat_ids
        if p["notes"]: m["notes"] = p["notes"]
        if p["color"]: m["color"] = p["color"]
        # 打开次数：让"最常打开"排序和启动器有意义
        opens = max(0, p["activity"] // 10 - p["recent"] // 10)
        if opens:
            m["openCount"] = opens
            m["lastOpened"] = (NOW - timedelta(days=p["recent"], hours=1)).strftime("%Y-%m-%dT%H:%M:%SZ")
        meta[str(root)] = m
        print(f"  {p['name']:<16} commits={p['activity']:<4} claude={len(p['claude'])} codex={len(p['codex'])} deps={p['deps_mb']}MB")
    DATA.mkdir(parents=True)
    lib = dict(version=2, scanRoots=[str(DEV)], categories=list(tags.values()), meta=meta, migratedLegacy=True,
               preferences=dict(launcherShortcut="cmd+shift+space", menuBarResident=True, checkForUpdates=False, appearance="light",
                                folderTransparency=0, appIcon="light",
                                terminal=dict(bundleID="com.apple.Terminal", name="Terminal")))
    (DATA / "library.json").write_text(json.dumps(lib, ensure_ascii=False, indent=2))
    (DEMO / "running.json").write_text(json.dumps(running))
    print("done:", DEV, DATA)


if __name__ == "__main__":
    main()
