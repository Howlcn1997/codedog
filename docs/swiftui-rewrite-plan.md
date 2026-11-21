# codedog SwiftUI 重写计划

> 目标：抛弃 Electron + React，用 SwiftUI（必要处桥接 AppKit）彻底重写 codedog。
> 视觉参考本地 Dozoo（原生 SwiftUI + AppKit + Sparkle），只借鉴风格，不搬运其素材。
> 原则：**不受现有交互、UI、数据格式约束**，只保留第 3 节列出的值得保留的设计。

---

## 1. 产品重新定位

| | 旧 codedog（v0.3.x） | 新 codedog |
|---|---|---|
| 定位 | 项目托管器：项目放进指定根目录，负责导入、搬家、装依赖 | 项目发现器 + 启动器：自动扫描已有代码目录，最快找到并打开项目 |
| 项目来源 | 手动导入 / 新建 | 扫描目录自动发现，文件变化时增量更新 |
| 是否改动用户文件 | 会（复制、移动、clone、安装依赖） | 不会（唯一例外：用户明确确认的"清理依赖目录"与"新建项目"） |

一句话：**看见所有项目，最快打开它。**

---

## 2. 功能取舍

### 2.1 删除

| 功能 | 理由 |
|---|---|
| 项目根目录 + `root/<分组>/<名称>` 结构 | 复杂度根源，改为扫描目录 |
| 导入的复制 / 移动 / Git Clone 模式及回滚 | 访达、终端做得更好，且有破坏风险 |
| Claude 聊天记录迁移 | 只服务于"移动导入" |
| 依赖安装、环境检测、依赖声明列表、依赖状态 | IDE / 终端的职责 |
| 操作日志抽屉 | 无内容可显示 |
| 保存的筛选（从未有 UI） | 由智能文件夹替代 |
| 导出备份 | 数据在 Application Support，时间机器覆盖 |
| 演示模式 | 自动扫描，首次启动即有真实数据 |
| 主题设置 | 跟随系统 |
| 精简模式外观编辑器（模糊/不透明度）、CGS 私有 API | 使用系统材质 |
| 项目组（符号链接目录、README、mermaid、修复） | 太重、场景窄；需求由"分类一起打开"满足 |
| 别名 | 模糊搜索 + 常用度排序替代，有需要再加回 |
| Windows / Linux | 原生 macOS |
| `projects.json` 格式与跨进程锁协议 | 新数据层重做，首次启动一次性迁移 |

### 2.2 合并

| 旧概念 | 新概念 |
|---|---|
| 分组（公司/个人/临时/自定义）+ 标签 | **分类**：多选的标签式集合；分类可"一起打开"（生成 `.code-workspace` 给 VS Code 系编辑器） |
| 收藏、最近打开、已归档、有改动、保存的筛选 | **智能文件夹**：规则过滤 |
| 已归档 | **隐藏** |
| 存储空间页 + 依赖清理 | 卡片显示大小、按大小排序、"占空间最大"智能文件夹、多选批量"清理依赖目录" |
| 标准 / 精简模式切换 + 全局快捷键 | **启动器面板**（独立的 Spotlight 式浮动面板） |
| 后台模式 + 菜单栏 + 隐藏 Dock | 一个设置项：**常驻菜单栏** |
| 写死 5 款 IDE + 系统终端 / Warp | **任意编辑器 / 任意终端**（选任意 App，自动识别常见工具） |
| 单个导入 + 批量扫描 + 新建 | **扫描目录** + 轻量"新建项目"（位置、名称、可选 git init） |
| 备注 + README | 详情里的"说明"区：README 只读渲染 + 个人备注 |

### 2.3 新增（借鉴 Dozoo）

| 功能 | 说明 |
|---|---|
| 活跃度时间轴 | 按天聚合活跃度（git 提交时间、文件修改时间、AI 会话时间），驱动页头柱状图与时间范围筛选 |
| AI 工具识别 | 读取 Claude Code（`~/.claude/projects/*.jsonl`）、Codex 等会话记录：卡片显示用过的工具，侧栏按工具分组 |
| "在等你"状态 | 最近会话最后一条是助手消息 → 等待用户回复 |
| 一键续上 | 在终端中执行 `claude --resume <id>` 等，接着上次会话继续 |
| 项目类型推断 | 网页 / Mac App / 工具脚本 / 后端服务 / 其他，基于文件特征 |
| 口语化时间 | "今天在做""昨天在做""2 天前" |

---

## 3. 保留的设计（逻辑层，照搬思路）

1. **搜索算法**（`shared/project-search.mjs`）：NFKC 规范化、多个关键词都必须命中、按字段分优先级（名称/分类 > 路径/描述/备注/技术栈 > README）、名称子序列模糊匹配、命中原因与 README 片段。新增：最近打开与打开频率参与排序。
2. **启动器键盘模型**：↑↓ 选项目、←→ 选动作、回车执行（忽略按键重复）、Esc 依次关菜单 → 清空搜索 → 隐藏、输入法组字时不响应。
3. **安全原则**：不修改用户源文件；原子写入；清理依赖前重新确认目录位于项目内、不是符号链接、确实是目录。
4. **按项目指定编辑器**：本次临时指定 > 项目设置 > 全局默认；新增从 AI 会话 / 使用记录自动推断。
5. **登录 shell PATH 修正**：从访达启动时执行 `$SHELL -ilc` 读取 PATH，保证能找到 git 等工具。
6. **右键菜单显示编辑器的应用图标**。
7. **命令行工具** `codedog open|path|list|add`，与 App 共用核心库。
8. **Git 只读检测**：只在项目自身有 `.git` 时执行，不 fetch，`GIT_TERMINAL_PROMPT=0`，带超时。
9. **扫描规则**：遇到项目标记（`.git`、`package.json`、`go.mod`、`pyproject.toml`、`Cargo.toml`、`*.xcodeproj` 等）即视为项目，不再往下钻；跳过 `node_modules`、`.venv`、`dist`、`build` 等目录。

---

## 4. 产品形态与视觉

### 4.1 四个入口

| 入口 | 职责 |
|---|---|
| **主窗口** | 浏览、筛选、整理全部项目 |
| **启动器面板** | 快捷键（默认 ⌘⇧Space）呼出，搜索后回车打开 |
| **菜单栏** | 最近项目、"在等你"的项目、打开启动器、偏好设置 |
| **命令行** | `codedog` |

### 4.2 主窗口布局（Dozoo 风格）

```
┌──────────────┬──────────────────────────────────────────────────────────┐
│ ● ● ●     ▢  │ (🔍 搜索项目)  (＋)  (▦ ☰)  (⇅ ▾)              (↻ 重新扫描) │
│              │                                                          │
│ ▦ 全部项目 98 │  Claude Code                    (近一周)(近1月)(近3月)(全部) │
│              │  48 个项目                                                │
│ 智能文件夹    │   ▁ ▁ ▂ ▁ ▁ ▂ ▁ ▃ ▁ ▃ ▃ ▁ ▃ ▄ ▃ █ ▅                         │
│ ☆ 收藏        │  更早    2025年     3月     5月     7月     9月    本周      │
│ ⏳ 在等你   1  │                                                          │
│ ✎ 有改动没提交 │   ┌────────┐   ┌────────┐   ┌────────┐                    │
│ ▣ 占空间最大  │   │  ◎     │   │  ▭     │   │  ◎     │   文件夹造型卡片     │
│ 分类          │   │名称…    │   │名称     │   │名称…    │   名称 / 状态·大小   │
│ ＋ 新建分类   │   │今天·9GB │   │●在等你  │   │昨天·1GB │   工具图标 / 类型徽标 │
│ 项目类型      │   │✳◎▸ HTML│   │✳◎▸ App │   │✳◎▸ HTML│                    │
│ AI 工具       │   └────────┘   └────────┘   └────────┘                    │
│ ⚙            │                                                          │
└──────────────┴──────────────────────────────────────────────────────────┘
```

| 元素 | 实现 |
|---|---|
| 窗口 | `NavigationSplitView`，隐藏标题栏，红绿灯嵌入侧栏顶部，右侧可收起的检查器（`.inspector`） |
| 侧栏 | 深色半透明 + 渐变底；分区小标题；SF Symbol + 名称 + 等宽数字计数 |
| 工具栏 | 胶囊形玻璃控件（`glassEffect` / `GlassEffectContainer`） |
| 页头 | 大号粗体标题 + "N 个项目" + 时间范围胶囊 |
| 活跃度图 | Swift Charts `BarMark`，圆角单色，点击柱子 = 时间筛选 |
| 卡片 | 自绘 `FolderShape`（后层纸张 + 中心类型图标，前层毛玻璃文件夹面），悬停抬升、弹性动画 |
| 列表视图 | `Table`：名称、分类、类型、最近活跃、大小、Git 状态 |
| 检查器 | Git（分支、改动、远程）、大小与清理、说明（README + 备注）、最近 AI 会话、打开方式 |
| 颜色 | 资产目录语义色，亮/暗两套；强调色待定（第 8 节） |

### 4.3 设置（仅五项）

扫描目录、默认编辑器与终端、启动器快捷键、常驻菜单栏与开机启动、安装命令行工具。

---

## 5. 技术架构

```
codedog/
├─ Project.yml / codedog.xcodeproj        工程定义（生成方式待定）
├─ Packages/CodedogCore                   纯逻辑 Swift Package，无 UI
│   ├─ Model/        Project（发现结果）、ProjectMeta（用户元数据）、Category、SmartFolder
│   ├─ Store/        LibraryStore(actor)：元数据持久化 + 派生数据缓存
│   ├─ Discovery/    FolderScanner、FSEventsWatcher、ProjectClassifier（类型/技术栈）
│   ├─ Inspect/      GitInspector、SizeCalculator、ReadmeLoader
│   ├─ Activity/     ActivityAggregator（git log、mtime、AI 会话 → 按天聚合）
│   ├─ AITools/      ClaudeCodeReader、CodexReader …（协议 AIToolReader，便于扩展）
│   ├─ Search/       ProjectSearch
│   ├─ Actions/      Opener（编辑器/终端/访达/仓库）、DependencyCleaner、ProjectCreator、
│   │                WorkspaceFileWriter（.code-workspace）
│   ├─ Migration/    LegacyImporter（读取旧 projects.json）
│   └─ System/       ShellRunner（Process + 超时 + 登录 shell PATH）
├─ App/                                   SwiftUI App target
│   ├─ CodedogApp.swift   Window + Settings + MenuBarExtra
│   ├─ State/             @Observable LibraryModel、FilterModel、SelectionModel
│   ├─ Views/             Sidebar、Toolbar、Header、ActivityChart、FolderCard、
│   │                     ProjectTable、Inspector、Onboarding、Settings
│   ├─ Launcher/          LauncherPanel（NSPanel）+ LauncherView
│   ├─ Platform/          HotKey（Carbon）、LoginItem（SMAppService）、DockPolicy
│   └─ Resources/         Assets、自制工具/技术栈图标、Localizable（zh-Hans 优先，en）
└─ CLI/                                   codedog 命令行目标（swift-argument-parser）
```

**数据层**
- 存储位置：`~/Library/Application Support/codedog/`
- `library.json`：用户元数据（扫描目录、分类、项目的收藏/隐藏/分类/备注/编辑器设置），以项目路径 + 文件系统 ID 作为键，原子写入。
- `cache.json`（或 SQLite）：派生数据（Git、大小、活跃度、AI 会话摘要），可随时重建。
- CLI 只读缓存；写操作（`add`）通过 `NSFileCoordinator` 协调，不再自制锁协议。
- 首次启动：检测旧 `projects.json`，迁移收藏、标签和分组（转为分类）、备注、单项目编辑器设置，并把旧项目所在的父目录建议为扫描目录。

**技术选型**
- Swift 6 严格并发、SwiftUI、Observation、Swift Charts、Swift Testing
- 第三方依赖：Sparkle 2、swift-argument-parser，不引入其他依赖
- 后台扫描用 `TaskGroup` 限并发；大小计算增量缓存，按目录修改时间判断是否需要重算

---

## 6. 实施阶段

| 阶段 | 内容 | 验收 |
|---|---|---|
| **P0 骨架** | 新工程、CodedogCore 包、CI 编译与测试 | 空窗口可运行，`swift test` 通过 |
| **P1 发现与数据** | 扫描目录、FSEvents 增量、分类器、Git、LibraryStore、旧数据迁移 | 扫描本机代码目录，结果正确且二次启动秒开 |
| **P2 搜索与打开** | ProjectSearch（移植旧测试为 Swift Testing）、Opener、ShellRunner | 搜索结果与旧版一致或更优；编辑器/终端/访达/仓库可打开 |
| **P3 主窗口** | 侧栏、玻璃工具栏、页头、卡片网格、列表、检查器、智能文件夹、分类、右键菜单 | 视觉对齐 Dozoo 风格，日常使用流畅 |
| **P4 活跃度与 AI 工具** | ActivityAggregator、柱状图与时间筛选、Claude Code / Codex 读取、"在等你"、一键续上 | 数据与真实会话吻合 |
| **P5 启动器与系统集成** | 启动器面板 + 快捷键、菜单栏、开机启动、CLI、设置、首次引导 | 键盘全流程可用 |
| **P6 大小与清理、新建项目** | SizeCalculator、占空间排序、批量清理依赖、新建项目、分类一起打开 | 清理前确认、清理后大小刷新 |
| **P7 发布** | 签名公证、Sparkle appcast、GitHub Actions 改为 `xcodebuild archive` → dmg/zip → Release；最后发一个 Electron 版提示用户下载新版；删除 Electron 代码与 node 依赖；更新 README/docs | v1.0.0 |

每阶段结束：`xcodebuild test` 通过，并手动运行 App 截图验收。

---

## 7. 风险

| 风险 | 应对 |
|---|---|
| 扫描大目录慢、FSEvents 事件风暴 | 限深度、跳过依赖目录、去抖、增量缓存 |
| AI 工具会话格式变化 | 每个工具独立 Reader，解析失败只降级显示，不影响主流程 |
| 老 Electron 用户无法自动升级 | 最后一个 Electron 版弹窗引导下载 |
| 自动更新、开机启动依赖签名 | 需要 Developer ID；没有则改为手动更新 |
| 访问桌面/文稿/下载目录需要授权 | 首次引导中说明，Info.plist 写好用途说明 |

---

## 8. 已定决策（2026-11-21）

1. 最低 macOS 26，直接使用 Liquid Glass。
2. 在 `swiftui` 分支并行开发，P7 合并时删除 Electron 代码。
3. 强调色沿用 codedog 紫 `#6563da`。
4. 工程由 XcodeGen 生成（`project.yml`），`.xcodeproj` 不入库；`make build` / `make test`。
5. 签名：暂按 ad-hoc 签名开发，P7 再定 Developer ID 与 Sparkle。
6. AI 工具首版支持 Claude Code + Codex。

## 9. 进度

- [x] P0 骨架：XcodeGen 工程、CodedogCore 包、App、内嵌 `codedog-cli`、Swift CI
- [x] P1 发现与数据：FolderScanner、ProjectClassifier、GitInspector、ShellRunner（登录 shell PATH）、LibraryStore（文件协调）、ProjectCache、FSEventsWatcher、LegacyImporter；23 个单元测试。真实数据：`~/codespace` 冷扫描 64 个项目约 4.4 秒，旧数据 58 条元数据迁移 57 条（剩 1 条是空目录）
- [x] P2 搜索与打开：ProjectSearch（移植旧算法 + 旧测试，修正 README 片段定位）、常用度排序、Opener（任意编辑器/终端、访达、仓库、`.code-workspace` 一起打开）、CLI `open|path|list|add`；38 个单元测试
- [x] P3 主窗口：侧栏（智能文件夹、分类、AI 与编辑器、项目类型）、玻璃工具栏、时间范围、活跃度柱状图、文件夹卡片、列表视图、全屏详情页（取代检查器）
- [x] P4 活跃度与 AI 工具：Claude Code / Codex 会话读取（按文件缓存，613MB 日志首次索引约 1.3 秒）、VS Code 系编辑器记录、运行中智能体检测、"在等你"、一键续上（AppleScript 驱动终端）、近一年提交 + AI 热力图、按模型 token 与 API 价估算、最近提交
- [ ] P5 启动器与系统集成
- [ ] P6 大小与清理、新建项目
- [ ] P7 发布
