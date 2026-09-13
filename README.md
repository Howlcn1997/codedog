# codedog

一个本地优先的桌面项目管理中心。Node.js、Go、Python，公司项目、个人作品与临时实验，都有自己的位置。

[Download for macOS](https://github.com/Howlcn1997/codedog/releases/latest)

> [!IMPORTANT]
> 当前发布包尚未经过 Apple 签名与公证。首次打开时，macOS 可能提示
> “codedog 已损坏，无法打开”。从本仓库的 GitHub Releases 下载并将
> `codedog.app` 移入“应用程序”后，可在终端运行以下命令移除 macOS 添加的
> 下载隔离标识，再重新打开应用：
>
> ```sh
> xattr -dr com.apple.quarantine /Applications/codedog.app
> ```
>
> 仅应对你确认来自本仓库官方 Release 的应用执行此命令。

第一次使用？请阅读 [Code Dog 用户指南](docs/user-guide.md)。

## 特色功能

当前能力按使用场景可归纳为 **8 类**：

1. **本地优先的项目中心**：源码留在本机，管理数据以 JSON 原子写入；统一浏览公司、个人、临时及自定义分组中的项目。
2. **灵活导入现有代码**：支持复制、移动、原地登记、Git HTTPS/SSH 克隆和批量扫描；移动项目时还能迁移 Claude Code 聊天记录副本。
3. **面向代码库的智能搜索**：名称支持子序列模糊匹配，也可检索别名、路径、标签、描述、备注、远程仓库、根目录 README 与依赖名称，并展示命中原因。索引支持手动刷新，也会跟随相关源文件变化自动更新。
4. **随时呼出的项目启动器**：按 `⌘/Ctrl + Shift + Space` 可在任何应用中打开或收起精简模式；全键盘完成搜索、选择项目、切换动作和打开。
5. **IDE、终端与 CLI 联动**：可使用全局或项目独立 IDE 打开，在系统终端或 Warp 中启动，也可通过 `codedog add/list/open/path` 从命令行访问同一份项目数据。
6. **多技术栈环境洞察**：识别 Node.js、Go、Python 的项目声明、运行时、包管理器和依赖状态，查看依赖清单并在原生确认后安装或同步依赖。
7. **存储空间治理**：按需区分源码与本地依赖占用，批量选择项目并安全清理项目内的 `node_modules`、`.venv` 和 `venv`，展示预计及实际释放空间。
8. **日常项目管理**：查看 Git 分支、未提交修改与远程地址，使用收藏、最近打开、归档、标签、备注、保存筛选、列表/卡片视图和亮色/暗色主题整理工作区。

## 运行

需要 Node.js 22.12+、npm，以及相应项目使用的 Git、语言运行时与包管理器。

```sh
npm ci
npm run dev
```

```sh
npm run build
npm start
```

`npm run dev:web` 只提供界面演示；本地文件和 IDE 操作需要桌面应用。

## 命令行工具（macOS）

在「设置 → 通用 → 命令行工具」中点击安装，命令会写入
`~/.local/bin/codedog`。如果终端找不到 `codedog`，请将下面一行加入
`~/.zshrc` 后重新打开终端：

```sh
export PATH="$HOME/.local/bin:$PATH"
```

```sh
codedog add .                 # 登记当前目录，源码保留在原位置
codedog list [关键词]          # 列出或筛选项目
codedog open <名称或别名>     # 使用项目默认 IDE 打开
codedog path <名称或别名>     # 只输出绝对路径
```

命令与桌面端共用项目数据；桌面端未运行时也可使用。

## 打包

```sh
npm run pack  # 当前系统可运行的应用目录，输出至 release/
npm run dist  # macOS DMG / Windows NSIS / Linux AppImage
```

此版本未配置应用签名与公证，适合本机开发使用。macOS 是本轮主要验证平台；Windows/Linux 的打包配置已保留，尚未实机验证。

## 功能明细

- 首次选择统一项目根目录，真实数据初始为空。可切换显式标注的演示模式。
- 从已有文件夹复制、移动或直接登记根目录内项目；Git HTTPS/SSH 克隆；批量扫描最多 4 层、300 个项目。批量移动时可选择把 Claude Code 聊天记录复制到新项目路径，旧记录会保留。
- 根目录下默认使用 company、personal、temporary 分组目录，也可新增自定义分组。编辑项目的名称或分组只改变管理信息，不移动磁盘文件。
- 项目名称子序列模糊搜索；别名、路径、标签、描述、备注、远程仓库、根目录 README 和依赖名称关键词搜索；结果展示匹配原因，并支持手动或随源文件变化刷新本地索引。
- 支持技术栈、分组、标签和依赖状态筛选，内置常用快捷筛选，并可保存最多 20 组搜索与筛选条件。
- 最近打开、收藏、归档、名称或导入时间排序、列表/卡片切换；主题可跟随系统或固定为亮色/暗色。
- `⌘/Ctrl + Shift + Space` 从任意应用呼出全局项目启动器；精简模式支持纯键盘搜索、筛选和选择打开动作。
- 使用默认或项目独立 IDE 打开；打开终端、文件夹、复制路径。
- 可选系统终端或 Warp；macOS 可安装与桌面端共用数据的 `codedog` 命令行工具。
- 识别 package.json、Go 模块、Python 项目声明；检查当前运行时和包管理器。
- 查看依赖声明，执行 npm/pnpm/Yarn 安装、go mod download、uv sync、Poetry install，或在项目 .venv 中使用 pip。原生确认框展示执行命令。
- 项目 Git 分支、未提交状态与远程地址（本地读取，不自动 fetch）。
- 按需计算项目与本地依赖体积，不遍历符号链接和共享缓存；确认后可批量清理项目内的 Node.js/Python 依赖目录。
- 管理信息原子写入本地 JSON，支持导出备份；移出管理保留全部磁盘文件。

## 数据与边界

管理元数据保存在 Electron userData 下的 projects.json（macOS 通常为 ~/Library/Application Support/codedog）。项目源码位于用户在应用内选择的根目录，和 codedog 自身源码目录相互独立。

已有项目时禁止直接切换根目录，以免索引失效。跨磁盘移动请使用复制模式；不会自动删除原目录。批量导入逐项完成，失败前已完成项目会保留并展示在列表中。

Node.js 的“依赖就绪”表示 node_modules 存在，Python 表示 .venv 存在，不代表锁文件一致或运行时版本兼容。Go 共享缓存不据此推断为已安装。依赖页面展示已解析的声明版本；复杂 TOML/requirements 引用、Poetry 外部虚拟环境和 monorepo 子包还未完整展开。安装动作可能更新锁文件并执行安装脚本，用户必须在原生对话框中确认。

尚未实现：自动依赖升级、共享依赖缓存清理、整体根目录迁移、备份恢复和批量编辑。不会把这些操作作为可用按钮展示。

## 测试

```sh
npm test
npm run build
node scripts/smoke.mjs
```

核心测试在临时目录验证真实文件操作。桌面测试使用 work/smoke 下的隔离资料与示例项目，不触碰现有项目。桌面测试需图形环境。

## 结构

- electron/core.mjs：项目存储、导入、语言检测、命令与空间统计
- electron/main.mjs：原生窗口、目录对话框、IPC、IDE 与依赖操作
- electron/preload.cjs：隔离的白名单桥接
- src/：React + TypeScript 界面，Radix Dialog 与自定义视觉组件
- public/icon.png：codedog 应用图标
- tests/：文件系统与核心回归测试
- scripts/：开发启动与 Electron 交互测试

不启用 Node renderer 集成；preload 使用上下文隔离与 sandbox；IPC 校验主窗口来源；命令用参数数组调用，不拼接项目文本到 shell；外部导航与新窗口默认拒绝。

## 精简模式

标题栏「精简模式」按钮切换到独立的紧凑界面，仅保留搜索框、筛选栏和项目列表。右上角「标准模式」返回完整工作台。选择会保存，下一次启动恢复所选模式。

精简模式启动时搜索框自动聚焦；⌘/Ctrl K 聚焦搜索，↑/↓ 选择结果，Enter 使用项目默认 IDE 打开，Escape 清空搜索。支持分组、技术栈与标签筛选。项目导入、编辑与依赖管理仍在标准模式中操作。

项目右键菜单：精简列表、标准列表与卡片均支持选择 VS Code、Cursor、WebStorm、GoLand、PyCharm 或项目默认 IDE 打开，以及在终端中打开。单次选择不修改默认 IDE。聚焦项目项后也可以按 Shift+F10 打开菜单。IDE 需要已安装在电脑上。

默认终端可在「设置 → 默认终端」中选择系统终端或 Warp；默认使用系统终端，选择会持久保存，并统一应用于项目详情和右键菜单。Warp 通过官方目录 URI 打开项目：已有窗口时在当前窗口新建标签页，否则启动 Warp 窗口。路径会进行 URL 编码，需预先安装 Warp。参考：https://docs.warp.dev/terminal/more-features/uri-scheme 。

## 发布与更新

推送与 `package.json` 版本一致的 Git 标签（例如 `v0.2.0`）后，GitHub Actions 会构建 Intel 和 Apple Silicon 两种 macOS DMG/ZIP，并自动创建 GitHub Release。已安装的发布版会在启动时和每 10 分钟检查一次新版本，下载完成后提示重启安装。

要让 macOS Gatekeeper 和应用内自动更新正常工作，需在仓库 Actions secrets 配置 `CSC_LINK`、`CSC_KEY_PASSWORD`、`APPLE_ID`、`APPLE_APP_SPECIFIC_PASSWORD` 和 `APPLE_TEAM_ID`。未配置时仍会发布未签名 DMG，但用户需手动允许安装，且无法完成应用内自动替换。
