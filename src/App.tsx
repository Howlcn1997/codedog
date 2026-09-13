import GroupCreator from "./GroupCreator";
import CompactMode from "./CompactMode";
import ImportTags from "./ImportTags";
import TechStackIcon from "./TechStackIcon";
import StorageWorkspace from "./StorageWorkspace";
import { useEffect, useRef, useState, useMemo } from "react";
import type { ReactNode } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import {
  Search,
  Plus,
  ChevronDown,
  ChevronUp,
  ChevronRight,
  Folder,
  FolderOpen,
  Clock,
  Star,
  Archive,
  HardDrive,
  Settings,
  Terminal,
  Copy,
  GitBranch,
  RefreshCw,
  X,
  ArrowUpRight,
  Check,
  Loader2,
  Box,
  Code2,
  SlidersHorizontal,
  ArrowDownWideNarrow,
  LayoutGrid,
  List,
  Download,
  ExternalLink,
  AlertCircle,
  CheckCircle2,
  Trash2,
  Keyboard,
  PanelRightClose,
  PanelRightOpen,
} from "lucide-react";
import type {
  State,
  Project,
  Group,
  ImportInput,
  Environment,
  Theme,
  SavedFilter,
} from "./types";
import { demo } from "./demo";
import { searchProjects } from "./projectSearch";
const defaultGroups: Record<Group, string> = {
  company: "公司项目",
  personal: "个人项目",
  temporary: "临时项目",
};
const api = window.codedog;
const empty: State = { root: "", ide: "Cursor", projects: [] };
const defaultLauncherShortcut = "CommandOrControl+Shift+Space";
type DependencyCleanupPreview = {
  ids: string[];
  size: number;
  directories: {
    projectId: string;
    projectName: string;
    path: string;
    size: number;
  }[];
};
function launcherShortcutParts(shortcut: string) {
  const isMac = navigator.platform.toLowerCase().includes("mac");
  const labels: Record<string, string> = {
    CommandOrControl: isMac ? "⌘" : "Ctrl",
    Command: "⌘",
    Control: "Ctrl",
    Alt: isMac ? "⌥" : "Alt",
    Shift: "⇧",
    Super: "Super",
    Space: "Space",
    Enter: "Enter",
    Up: "↑",
    Down: "↓",
    Left: "←",
    Right: "→",
  };
  return shortcut.split("+").map((part) => labels[part] || part);
}
function shortcutFromEvent(event: React.KeyboardEvent) {
  if (["Meta", "Control", "Alt", "Shift"].includes(event.key)) return "";
  const key =
    event.key === " "
      ? "Space"
      : event.key.startsWith("Arrow")
        ? event.key.slice(5)
        : /^(?:[a-z0-9]|F(?:[1-9]|1[0-2]))$/i.test(event.key)
          ? event.key.toUpperCase()
          : ["Enter", "Tab"].includes(event.key)
            ? event.key
            : "";
  if (!key) throw Error("暂不支持这个按键，请使用字母、数字、方向键或功能键");
  const modifiers = [
    event.metaKey || event.ctrlKey ? "CommandOrControl" : "",
    event.altKey ? "Alt" : "",
    event.shiftKey ? "Shift" : "",
  ].filter(Boolean);
  if (!modifiers.some((modifier) => modifier !== "Shift"))
    throw Error("快捷键至少需要包含 Command/Ctrl 或 Option/Alt");
  return [...modifiers, key].join("+");
}
const formatSize = (n: number) =>
  n > 1073741824
    ? `${(n / 1073741824).toFixed(1)} GB`
    : n > 1048576
      ? `${(n / 1048576).toFixed(1)} MB`
      : `${Math.round(n / 1024)} KB`;
const ago = (n: number) =>
  !n
    ? "尚未打开"
    : Date.now() - n < 60000
      ? "刚刚"
      : Date.now() - n < 3600000
        ? `${Math.floor((Date.now() - n) / 60000)} 分钟前`
        : Date.now() - n < 86400000
          ? `${Math.floor((Date.now() - n) / 3600000)} 小时前`
          : `${Math.floor((Date.now() - n) / 86400000)} 天前`;
function IconButton({
  children,
  label,
  onClick,
  disabled = false,
}: {
  children: ReactNode;
  label: string;
  onClick: () => void;
  disabled?: boolean;
}) {
  return (
    <button
      className="icon-button"
      title={label}
      aria-label={label}
      onClick={onClick}
      disabled={disabled}
    >
      {children}
    </button>
  );
}
function Modal({
  title,
  description,
  open,
  onClose,
  children,
  wide = false,
  className = "",
}: {
  title: string;
  description: string;
  open: boolean;
  onClose: () => void;
  children: ReactNode;
  wide?: boolean;
  className?: string;
}) {
  return (
    <Dialog.Root open={open} onOpenChange={(v) => !v && onClose()}>
      <Dialog.Portal>
        <Dialog.Overlay className="overlay" />
        <Dialog.Content
          className={`modal ${wide ? "wide" : ""} ${className}`.trim()}
        >
          <div className="modal-heading">
            <div>
              <Dialog.Title>{title}</Dialog.Title>
              <Dialog.Description>{description}</Dialog.Description>
            </div>
            <Dialog.Close asChild>
              <button className="icon-button" aria-label="关闭">
                <X size={18} />
              </button>
            </Dialog.Close>
          </div>
          {children}
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
function StackIcon({ stack }: { stack?: string }) {
  return (
    <span
      className={`stack-icon ${stack === "Go" ? "go" : stack === "Python" ? "python" : "node"}`}
    >
      <TechStackIcon stack={stack} size={14} />
    </span>
  );
}
function Status({ value }: { value: string }) {
  return (
    <span className={`status ${value}`}>
      <i />
      {(
        {
          ready: "依赖就绪",
          pending: "待安装",
          unknown: "待检查",
          none: "未识别",
          missing: "路径缺失",
        } as Record<string, string>
      )[value] || "待检查"}
    </span>
  );
}
export default function App() {
  const [uiMode, setUiMode] = useState<"standard" | "compact">(() => {
    if (api) return api.initialMode;
    return localStorage.getItem("codedog-ui-mode") === "compact"
      ? "compact"
      : "standard";
  });
  const modeChangeSequence = useRef(0);
  async function switchMode(mode: "standard" | "compact") {
    const sequence = ++modeChangeSequence.current;
    const previousMode = uiMode;
    setUiMode(mode);
    try {
      if (api) await api.setMode(mode);
      else localStorage.setItem("codedog-ui-mode", mode);
    } catch (e) {
      if (sequence === modeChangeSequence.current) {
        setUiMode(previousMode);
        setError((e as Error).message);
      }
    }
  }
  const [state, setState] = useState<State>(empty),
    [demoMode, setDemoMode] = useState(!api),
    [nav, setNav] = useState("all"),
    [search, setSearch] = useState(""),
    [stack, setStack] = useState("all"),
    [status, setStatus] = useState("all"),
    [groupFilter, setGroupFilter] = useState("all"),
    [sort, setSort] = useState("recent"),
    [selected, setSelected] = useState(""),
    [tab, setTab] = useState("overview"),
    [grid, setGrid] = useState(false),
    [inspector, setInspector] = useState(true),
    [busy, setBusy] = useState(false),
    [toast, setToast] = useState(""),
    [error, setError] = useState(""),
    [modal, setModal] = useState(""),
    [recordingShortcut, setRecordingShortcut] = useState(false),
    [settingsSection, setSettingsSection] = useState<
      "general" | "appearance" | "open" | "data"
    >("general"),
    [cliInfo, setCliInfo] = useState<{
      installed: boolean;
      path: string;
    } | null>(null),
    [logs, setLogs] = useState(""),
    [showLogs, setShowLogs] = useState(false),
    [usage, setUsage] = useState<
      Record<string, { source: number; dependencies: number; skipped: number }>
    >({}),
    [storageSelected, setStorageSelected] = useState<string[]>([]),
    [storageLoading, setStorageLoading] = useState(false),
    [cleanupPreview, setCleanupPreview] =
      useState<DependencyCleanupPreview | null>(null),
    [cleanupExpanded, setCleanupExpanded] = useState(false),
    [envs, setEnvs] = useState<Record<string, Environment[]>>({});
  const [importForm, setImportForm] = useState<ImportInput>({
      copyClaudeChats: false,
      mode: "copy",
      source: "",
      url: "",
      name: "",
      group: "personal",
      tags: [],
    }),
    [importTab, setImportTab] = useState("folder"),
    [scanResults, setScanResults] = useState<string[]>([]),
    [checked, setChecked] = useState<string[]>([]),
    [edit, setEdit] = useState({
      name: "",
      group: "personal" as Group,
      tags: "",
      notes: "",
      ide: "",
      aliases: "",
    });
  const searchRef = useRef<HTMLInputElement>(null);
  const data = demoMode ? demo : state;
  const groups = useMemo(
    () => ({ ...defaultGroups, ...(data.groups || {}) }),
    [data.groups],
  );
  async function createGroup(name: string) {
    if (!api || demoMode) throw Error("请先切换到本地项目后新增分组");
    const group = await api.createGroup(name);
    await refresh();
    return group.id;
  }
  const theme = state.theme || "system";
  useEffect(() => {
    document.documentElement.dataset.theme = theme;
  }, [theme]);
  const projects = data.projects;
  const selectedProject = projects.find((p) => p.id === selected);
  async function refresh() {
    if (api) {
      const value = await api.state();
      setState(value);
      setSelected(
        (s) => s || value.projects.find((p) => !p.archived)?.id || "",
      );
    }
  }
  useEffect(() => {
    refresh().catch((e) => setError(e.message));
    const removeLog = api?.onLog((text) =>
      setLogs((s) => (s + text).slice(-100000)),
    );
    const removeMode = api?.onModeChange((mode) => setUiMode(mode));
    const removeIndexUpdate = api?.onSearchIndexUpdated(() => {
      refresh().catch((e) => setError(e.message));
    });
    return () => {
      removeLog?.();
      removeMode?.();
      removeIndexUpdate?.();
    };
  }, []);
  useEffect(() => {
    if (demoMode) setSelected(demo.projects[0].id);
  }, [demoMode]);
  useEffect(() => {
    if (modal === "settings" && api)
      api
        .cliStatus()
        .then(setCliInfo)
        .catch(() => setCliInfo(null));
  }, [modal]);
  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(""), 3500);
    return () => clearTimeout(t);
  }, [toast]);
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault();
        searchRef.current?.focus();
      }
      if (e.key === "Escape") setSearch("");
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, []);
  const active = projects.filter((p) => !p.archived);
  const storageProjects = [...active].sort((a, b) => {
    const aUsage = usage[a.id];
    const bUsage = usage[b.id];
    return (
      (bUsage ? bUsage.source + bUsage.dependencies : -1) -
      (aUsage ? aUsage.source + aUsage.dependencies : -1)
    );
  });
  const list = useMemo(() => {
    const filtered = projects.filter((p) => {
      if (nav === "archived" ? !p.archived : p.archived) return false;
      if (nav === "favorites" && !p.favorite) return false;
      if (nav === "recent" && !p.lastOpened) return false;
      if (Object.hasOwn(groups, nav) && p.group !== nav) return false;
      if (groupFilter !== "all" && p.group !== groupFilter) return false;
      if (stack !== "all" && !p.stacks.includes(stack)) return false;
      if (status !== "all" && p.dependencyState !== status) return false;
      return true;
    });
    return searchProjects(filtered, search, (a, b) =>
      sort === "name"
        ? a.name.localeCompare(b.name)
        : sort === "created"
          ? b.createdAt - a.createdAt
          : b.lastOpened - a.lastOpened,
    );
  }, [projects, nav, groupFilter, stack, status, search, sort, groups]);
  useEffect(() => {
    if (!list.some((p) => p.id === selected)) setSelected(list[0]?.id || "");
  }, [list, selected]);
  const title = (
    {
      all: "全部项目",
      recent: "最近打开",
      favorites: "收藏项目",
      archived: "已归档",
      storage: "存储空间",
      ...groups,
    } as Record<string, string>
  )[nav];
  async function perform(fn: () => Promise<unknown>, message?: string) {
    if (busy) return;
    setBusy(true);
    setError("");
    try {
      await fn();
      if (message) setToast(message);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  function requireNative() {
    if (!api || demoMode) {
      setToast("这是演示数据。请返回本地项目后操作。");
      return false;
    }
    return true;
  }
  async function chooseRoot() {
    if (!api) {
      setToast("请在桌面应用中选择项目目录");
      return;
    }
    await perform(async () => {
      const folder = await api.pickFolder();
      if (folder) {
        await api.setRoot(folder);
        await refresh();
        setToast("项目根目录已设置");
      }
    });
  }
  async function patch(p: Project, value: Partial<Project>) {
    if (!requireNative()) return;
    await perform(async () => {
      await api!.update(p.id, value);
      await refresh();
    });
  }
  async function scanStorage() {
    if (!api || demoMode || storageLoading) return;
    setStorageLoading(true);
    setError("");
    try {
      const ids = projects
        .filter((project) => !project.archived && !project.missing)
        .map((project) => project.id);
      const result = await api.storageBatch(ids);
      setUsage(result);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setStorageLoading(false);
    }
  }
  async function cleanSelectedDependencies() {
    if (!api || demoMode || !storageSelected.length) return;
    const ids = [...storageSelected];
    setStorageLoading(true);
    setError("");
    try {
      const preview = await api.cleanupDependenciesPreview(ids);
      if (!preview.directories.length) {
        setToast("所选项目没有可清理的依赖");
        return;
      }
      setCleanupPreview({ ...preview, ids });
      setCleanupExpanded(false);
      setModal("cleanup");
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setStorageLoading(false);
    }
  }
  async function confirmDependencyCleanup() {
    if (!api || !cleanupPreview) return;
    const ids = cleanupPreview.ids;
    await perform(async () => {
      const result = await api.cleanupDependencies(ids);
      const updated = await api.storageBatch(ids);
      setUsage((current) => ({ ...current, ...updated }));
      setStorageSelected([]);
      setCleanupPreview(null);
      setCleanupExpanded(false);
      setModal("");
      await refresh();
      setToast(
        result.reclaimed
          ? `已释放约 ${formatSize(result.reclaimed)}`
          : "所选项目没有可清理的依赖",
      );
    });
  }
  function closeDependencyCleanup() {
    if (busy) return;
    setCleanupPreview(null);
    setCleanupExpanded(false);
    setModal("");
  }
  function navigate(value: string) {
    setNav(value);
    setSearch("");
    setGroupFilter("all");
    setStack("all");
    setStatus("all");
  }
  useEffect(() => {
    if (nav !== "storage") return;
    setStorageSelected([]);
    void scanStorage();
  }, [nav, demoMode]);
  function select(p: Project) {
    setSelected(p.id);
    setTab("overview");
    setInspector(true);
  }
  function beginImport() {
    if (!requireNative()) return;
    if (!state.root) {
      chooseRoot();
      return;
    }
    setImportForm({
      copyClaudeChats: false,
      mode: "copy",
      source: "",
      url: "",
      name: "",
      group: "personal",
      tags: [],
    });
    setScanResults([]);
    setChecked([]);
    setModal("import");
  }
  async function pickSource() {
    if (!api) return;
    const folder = await api.pickFolder();
    if (folder) {
      setImportForm((f) => ({
        ...f,
        source: folder,
        name: folder.split(/[\\/]/).pop() || "",
        mode: "register",
      }));
      setScanResults([]);
      setChecked([]);
    }
  }
  async function doImport() {
    await perform(async () => {
      setLogs("");
      setShowLogs(true);
      if (importTab === "scan") {
        for (const folder of checked) {
          await api!.import({
            ...importForm,
            source: folder,
            name: folder.split(/[\\/]/).pop()!,
            mode: folder.startsWith(state.root + "/")
              ? "register"
              : importForm.mode,
          });
          // Keep completed projects out of retries if a later import fails.
          setChecked((remaining) =>
            remaining.filter((item) => item !== folder),
          );
          setScanResults((remaining) =>
            remaining.filter((item) => item !== folder),
          );
          await refresh();
        }
      } else
        await api!.import({
          ...importForm,
          mode: importTab === "git" ? "clone" : importForm.mode,
        });
      await refresh();
      setModal("");
      setToast("项目已导入");
    });
  }
  function beginEdit(p: Project) {
    setEdit({
      name: p.name,
      group: p.group,
      tags: p.tags.join(", "),
      notes: p.notes,
      ide: p.ide || "",
      aliases: (p.aliases || []).join(", "),
    });
    setModal("edit");
  }
  const navButton = (
    key: string,
    label: string,
    icon: ReactNode,
    count?: number,
  ) => (
    <button
      className={`nav-item ${nav === key ? "active" : ""}`}
      onClick={() => navigate(key)}
    >
      {icon}
      <span>{label}</span>
      {count !== undefined && <small>{count}</small>}
    </button>
  );
  const actionOpen = (p: Project, kind: string) => {
    if (requireNative())
      perform(async () => {
        await api!.open(p.id, kind);
        if (kind === "ide") await refresh();
      }, "已打开");
  };
  const showProjectMenu = (p: Project) => {
    if (demoMode) {
      setError("演示项目不能在本地打开，请先切换到本地项目。");
      return;
    }
    if (!api || busy) return;
    setSelected(p.id);
    perform(async () => {
      const result = await api.projectMenu(p.id);
      if (result.opened) {
        await refresh();
        setToast("已打开");
      }
    });
  };
  const contextMenu = (p: Project, e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    showProjectMenu(p);
  };
  const menuKey = (p: Project, e: React.KeyboardEvent) => {
    if (e.key === "ContextMenu" || (e.shiftKey && e.key === "F10")) {
      e.preventDefault();
      e.stopPropagation();
      showProjectMenu(p);
    }
  };
  const noProjects = !demoMode && !state.projects.length;
  if (uiMode === "compact")
    return (
      <CompactMode
        projects={projects}
        groups={groups}
        root={data.root}
        busy={busy}
        demo={demoMode}
        onStandard={() => switchMode("standard")}
        onProjectMenu={showProjectMenu}
        savedFilters={data.savedFilters || []}
        onSaveFilters={(filters: SavedFilter[]) => {
          if (!api || demoMode) {
            setError("演示模式不能保存筛选。");
            return;
          }
          void perform(async () => {
            await api.setSavedFilters(filters);
            await refresh();
          }, "筛选已保存");
        }}
        onHide={() => void api?.hideLauncher()}
        onRefreshIndex={() => {
          if (!api || demoMode) {
            setToast("演示模式无需刷新搜索索引");
            return;
          }
          void perform(async () => {
            await api.refreshSearchIndex();
            await refresh();
          }, "搜索索引已刷新");
        }}
        onOpen={(p, kind) => {
          if (demoMode)
            setError("当前为演示模式，请在标准模式中切换到本地项目后打开。");
          else actionOpen(p, kind);
        }}
        error={error}
        onDismissError={() => setError("")}
      />
    );
  return (
    <div className="app-shell">
      <header className="titlebar">
        <span className="traffic-placeholder" />
        <span>codedog</span>
        <span className="titlebar-right">
          <button
            className="button standard-mode-switch"
            disabled={busy}
            onClick={() => switchMode("compact")}
          >
            <List size={14} />
            精简模式
          </button>
          {demoMode && <span className="preview-label">演示模式</span>}
          <IconButton
            label={inspector ? "收起详情" : "展开详情"}
            onClick={() => setInspector(!inspector)}
          >
            {inspector ? (
              <PanelRightClose size={16} />
            ) : (
              <PanelRightOpen size={16} />
            )}
          </IconButton>
        </span>
      </header>
      <div className="app-body">
        <aside className="sidebar">
          <div className="brand">
            <img src="./icon.png" alt="codedog 小狗图标" />
            <div>
              <strong>
                codedog<span>.</span>
              </strong>
              <small>给每个项目一个家</small>
            </div>
          </div>
          <nav>
            {navButton("all", "全部项目", <Box size={18} />, active.length)}
            {navButton("recent", "最近打开", <Clock size={18} />)}
            {navButton(
              "favorites",
              "收藏",
              <Star size={18} />,
              active.filter((p) => p.favorite).length,
            )}
          </nav>
          <div className="nav-label group-heading">
            <span>项目分组</span>
            <IconButton
              label="新增项目分组"
              disabled={busy || demoMode}
              onClick={() => setModal("groups")}
            >
              <Plus size={14} />
            </IconButton>
          </div>
          <nav>
            {(Object.entries(groups) as [Group, string][]).map(
              ([key, label]) => (
                <div key={key}>
                  {navButton(
                    key,
                    label,
                    <Folder size={18} />,
                    active.filter((p) => p.group === key).length,
                  )}
                </div>
              ),
            )}
          </nav>
          <div className="nav-label">工作台</div>
          <nav>
            {navButton("storage", "存储空间", <HardDrive size={18} />)}
            {navButton("archived", "已归档", <Archive size={18} />)}
          </nav>
          <div className="sidebar-bottom">
            <div className="root-card">
              <div className="root-eyebrow">
                <span className="dot" />
                本地工作空间
              </div>
              <button
                onClick={() =>
                  data.root
                    ? requireNative() && perform(() => api!.openRoot())
                    : chooseRoot()
                }
                title={data.root}
              >
                <FolderOpen size={16} />
                <span>
                  {data.root
                    ? data.root.replace(/^\/Users\/[^/]+/, "~")
                    : "选择项目根目录"}
                </span>
                <ChevronRight size={14} />
              </button>
            </div>
            <button className="nav-item" onClick={() => setModal("settings")}>
              <Settings size={18} />
              <span>设置</span>
              <span className="local-label">本地优先</span>
            </button>
          </div>
        </aside>
        <main className="workspace">
          <div className="page-header">
            <div>
              <div className="page-title">
                <h1>{title}</h1>
                <span className="count">{list.length}</span>
              </div>
              <p>
                {nav === "storage"
                  ? "查看项目占用，按需回收依赖空间。"
                  : "所有项目，井然有序。"}
              </p>
            </div>
            {nav !== "storage" && (
              <button className="button primary" onClick={beginImport}>
                <Plus size={17} />
                导入项目
                <ChevronDown size={14} />
              </button>
            )}
          </div>
          {demoMode && (
            <div className="demo-banner">
              <span>
                <span className="dot" />
                示例项目 · 操作不会影响本地文件
              </span>
              {api ? (
                <button
                  onClick={() => {
                    setDemoMode(false);
                    setSelected(state.projects[0]?.id || "");
                  }}
                >
                  返回本地项目
                  <ArrowUpRight size={14} />
                </button>
              ) : (
                <span>在桌面应用中管理真实项目</span>
              )}
            </div>
          )}
          {nav === "storage" ? (
            <StorageWorkspace
              projects={storageProjects}
              groups={groups}
              root={data.root}
              usage={usage}
              selected={storageSelected}
              loading={storageLoading}
              busy={busy}
              demo={demoMode}
              onScan={() => void scanStorage()}
              onToggle={(id) =>
                setStorageSelected((current) =>
                  current.includes(id)
                    ? current.filter((item) => item !== id)
                    : [...current, id],
                )
              }
              onToggleAll={(ids, checked) =>
                setStorageSelected(checked ? ids : [])
              }
              onClean={() => void cleanSelectedDependencies()}
            />
          ) : (
            <>
              <div className="search-box">
                <Search size={18} />
                <input
                  ref={searchRef}
                  aria-label="搜索项目"
                  placeholder="搜索名称、用途、README 或依赖…"
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                />
                <IconButton
                  label="刷新搜索索引"
                  disabled={busy}
                  onClick={() => {
                    if (!api || demoMode) {
                      setToast("演示模式无需刷新搜索索引");
                      return;
                    }
                    void perform(async () => {
                      await api.refreshSearchIndex();
                      await refresh();
                    }, "搜索索引已刷新");
                  }}
                >
                  <RefreshCw size={15} className={busy ? "spin" : ""} />
                </IconButton>
                {search ? (
                  <IconButton label="清空搜索" onClick={() => setSearch("")}>
                    <X size={15} />
                  </IconButton>
                ) : (
                  <kbd>⌘ K</kbd>
                )}
              </div>
              <div className="filters">
                <div className="filter-left">
                  <select
                    aria-label="项目分组"
                    value={groupFilter}
                    onChange={(e) => setGroupFilter(e.target.value)}
                  >
                    <option value="all">所有分组</option>
                    {Object.entries(groups).map(([k, v]) => (
                      <option key={k} value={k}>
                        {v}
                      </option>
                    ))}
                  </select>
                  <select
                    aria-label="技术栈"
                    value={stack}
                    onChange={(e) => setStack(e.target.value)}
                  >
                    <option value="all">技术栈</option>
                    {["Node.js", "Go", "Python"].map((s) => (
                      <option key={s}>{s}</option>
                    ))}
                  </select>
                  <select
                    aria-label="依赖状态"
                    value={status}
                    onChange={(e) => setStatus(e.target.value)}
                  >
                    <option value="all">依赖状态</option>
                    <option value="ready">依赖就绪</option>
                    <option value="pending">待安装</option>
                    <option value="unknown">待检查</option>
                    <option value="missing">路径缺失</option>
                  </select>
                </div>
                <div className="filter-right">
                  <select
                    aria-label="排序"
                    value={sort}
                    onChange={(e) => setSort(e.target.value)}
                  >
                    <option value="recent">最近打开 ↓</option>
                    <option value="name">名称 A–Z</option>
                    <option value="created">最近导入 ↓</option>
                  </select>
                  <div className="view-toggle">
                    <button
                      aria-label="列表视图"
                      className={!grid ? "selected" : ""}
                      onClick={() => setGrid(false)}
                    >
                      <List size={16} />
                    </button>
                    <button
                      aria-label="卡片视图"
                      className={grid ? "selected" : ""}
                      onClick={() => setGrid(true)}
                    >
                      <LayoutGrid size={15} />
                    </button>
                  </div>
                </div>
              </div>
              <div className="project-scroll">
                {noProjects ? (
                  <div className="empty-state welcome">
                    <img src="./icon.png" alt="" />
                    <span className="eyebrow">HELLO, DEVELOPER</span>
                    <h2>让项目各就各位。</h2>
                    <p>
                      公司项目、个人作品，或是一个临时灵感。
                      <br />
                      从一个统一的目录开始，把它们交给 codedog。
                    </p>
                    <button
                      className="button primary"
                      onClick={state.root ? beginImport : chooseRoot}
                    >
                      <FolderOpen size={17} />
                      {state.root ? "导入第一个项目" : "选择项目根目录"}
                    </button>
                    <button
                      className="text-button"
                      onClick={() => setDemoMode(true)}
                    >
                      先看看演示项目
                      <ArrowUpRight size={14} />
                    </button>
                    <div className="welcome-stacks">
                      <span>
                        <StackIcon stack="Node.js" />
                        Node.js
                      </span>
                      <span>
                        <StackIcon stack="Go" />
                        Go
                      </span>
                      <span>
                        <StackIcon stack="Python" />
                        Python
                      </span>
                    </div>
                  </div>
                ) : !list.length ? (
                  <div className="empty-state">
                    <Search size={32} />
                    <h2>没有找到匹配的项目</h2>
                    <p>试试其他关键词，或清除筛选条件。</p>
                    <button
                      className="button"
                      onClick={() => {
                        setSearch("");
                        setStack("all");
                        setStatus("all");
                        setGroupFilter("all");
                      }}
                    >
                      清除筛选
                    </button>
                  </div>
                ) : grid ? (
                  <div className="project-grid">
                    {list.map((p) => (
                      <button
                        key={p.id}
                        className={`project-card ${selected === p.id ? "selected" : ""}`}
                        onContextMenu={(e) => contextMenu(p, e)}
                        onKeyDown={(e) => menuKey(p, e)}
                        onClick={() => select(p)}
                      >
                        <div>
                          <ProjectMark p={p} />
                          <Star
                            size={15}
                            className={p.favorite ? "starred" : ""}
                          />
                        </div>
                        <h3>{p.name}</h3>
                        <p className={p.searchMatch ? "search-match" : ""}>
                          {p.searchMatch?.reasons[0] ||
                            p.description ||
                            p.path.split("/").slice(-2).join("/")}
                        </p>
                        <div>
                          <span className="tag">{groups[p.group]}</span>
                          <Status value={p.dependencyState} />
                        </div>
                      </button>
                    ))}
                  </div>
                ) : (
                  <table className="project-table">
                    <thead>
                      <tr>
                        <th>项目</th>
                        <th>分组</th>
                        <th>技术栈</th>
                        <th>状态</th>
                        <th className="last-column">最近打开 ↓</th>
                      </tr>
                    </thead>
                    <tbody>
                      {list.map((p) => (
                        <tr
                          key={p.id}
                          className={selected === p.id ? "selected" : ""}
                          onContextMenu={(e) => contextMenu(p, e)}
                          onClick={() => select(p)}
                          tabIndex={0}
                          onKeyDown={(e) => {
                            menuKey(p, e);
                            if (e.key === "Enter") select(p);
                          }}
                          aria-selected={selected === p.id}
                        >
                          <td>
                            <div className="project-name-cell">
                              <ProjectMark p={p} />
                              <div>
                                <div className="name-line">
                                  <strong>{p.name}</strong>
                                  <button
                                    className={`favorite-button ${p.favorite ? "starred" : ""}`}
                                    aria-label={
                                      p.favorite
                                        ? "取消收藏 " + p.name
                                        : "收藏 " + p.name
                                    }
                                    onClick={(e) => {
                                      e.stopPropagation();
                                      patch(p, { favorite: !p.favorite });
                                    }}
                                  >
                                    <Star
                                      size={13}
                                      fill={
                                        p.favorite ? "currentColor" : "none"
                                      }
                                    />
                                  </button>
                                </div>
                                <small>
                                  {p.path.replace(data.root + "/", "")}
                                </small>
                                {p.searchMatch && (
                                  <small className="search-match">
                                    {p.searchMatch.reasons.join(" · ")}
                                  </small>
                                )}
                              </div>
                            </div>
                          </td>
                          <td>
                            <span className="tag">
                              {(groups[p.group] || p.group).replace(
                                /项目$/,
                                "",
                              )}
                            </span>
                          </td>
                          <td>
                            <span className="stack-label">
                              <StackIcon stack={p.stacks[0]} />
                              {p.stacks.join(" / ") || "其他"}
                            </span>
                          </td>
                          <td>
                            <Status value={p.dependencyState} />
                          </td>
                          <td className="last-column">{ago(p.lastOpened)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}
              </div>
              <div className="list-footer">
                <span>
                  显示 {noProjects ? 0 : list.length} / {projects.length} 个项目
                </span>
                <span>
                  <Keyboard size={13} />⌘ K 快速查找
                </span>
              </div>
            </>
          )}
        </main>
        {inspector && nav !== "storage" && (
          <aside className="inspector">
            {selectedProject ? (
              <>
                <div className="inspector-top">
                  <span>项目详情</span>
                  <IconButton
                    label="编辑项目信息"
                    onClick={() => beginEdit(selectedProject)}
                  >
                    <SlidersHorizontal size={15} />
                  </IconButton>
                </div>
                <div className="detail-identity">
                  <ProjectMark p={selectedProject} large />
                  <div>
                    <h2>{selectedProject.name}</h2>
                    <p>
                      {selectedProject.description ||
                        "一个值得好好安放的项目。"}
                    </p>
                  </div>
                </div>
                <div className="detail-tags">
                  <span className="tag accent">
                    {groups[selectedProject.group]}
                  </span>
                  {selectedProject.tags.map((tag) => (
                    <span className="tag" key={tag}>
                      {tag}
                    </span>
                  ))}
                </div>
                <button
                  className="button primary open-ide"
                  disabled={busy || selectedProject.missing}
                  onClick={() => actionOpen(selectedProject, "ide")}
                >
                  <Code2 size={17} />在 {selectedProject.ide || data.ide} 中打开
                  <ArrowUpRight size={16} />
                </button>
                <div className="quick-actions">
                  <button
                    className="button"
                    onClick={() => actionOpen(selectedProject, "terminal")}
                  >
                    <Terminal size={16} />
                    终端
                  </button>
                  <button
                    className="button"
                    onClick={() => actionOpen(selectedProject, "folder")}
                  >
                    <Folder size={16} />
                    文件夹
                  </button>
                </div>
                <div className="tabs">
                  {[
                    ["overview", "概览"],
                    ["deps", "依赖"],
                    ["notes", "备注"],
                  ].map(([key, label]) => (
                    <button
                      className={tab === key ? "active" : ""}
                      key={key}
                      onClick={() => setTab(key)}
                    >
                      {label}
                    </button>
                  ))}
                </div>
                <div className="inspector-scroll">
                  {selectedProject.error && (
                    <div className="inline-error">{selectedProject.error}</div>
                  )}
                  {tab === "overview" ? (
                    <>
                      <DetailSection title="项目位置">
                        <button
                          className="path-box"
                          onClick={() =>
                            requireNative() &&
                            perform(
                              () => api!.copy(selectedProject.id),
                              "路径已复制",
                            )
                          }
                        >
                          <code>
                            {selectedProject.path.replace(
                              /^\/Users\/[^/]+/,
                              "~",
                            )}
                          </code>
                          <Copy size={14} />
                        </button>
                      </DetailSection>
                      <DetailSection title="Git">
                        <KeyValue label="分支">
                          <GitBranch size={13} />
                          {selectedProject.branch || "未初始化"}
                        </KeyValue>
                        <KeyValue label="工作区">
                          <span
                            className={
                              selectedProject.changes ? "accent-text" : ""
                            }
                          >
                            {selectedProject.branch
                              ? selectedProject.changes
                                ? `${selectedProject.changes} 项改动`
                                : "没有未提交改动"
                              : "—"}
                          </span>
                        </KeyValue>
                        {selectedProject.remote && (
                          <p
                            className="remote-path"
                            title={selectedProject.remote}
                          >
                            {selectedProject.remote}
                          </p>
                        )}
                      </DetailSection>
                      <DetailSection
                        title="开发环境"
                        action={
                          <button
                            className="text-button"
                            disabled={busy}
                            onClick={() => {
                              if (requireNative())
                                perform(async () => {
                                  const e = await api!.environment(
                                    selectedProject.id,
                                  );
                                  setEnvs((s) => ({
                                    ...s,
                                    [selectedProject.id]: e,
                                  }));
                                });
                            }}
                          >
                            检查
                            <RefreshCw size={12} />
                          </button>
                        }
                      >
                        {(
                          envs[selectedProject.id] ||
                          selectedProject.environments
                        ).map((env) => (
                          <div className="environment" key={env.stack}>
                            <KeyValue label={env.stack}>
                              {env.version || env.declared}
                            </KeyValue>
                            <KeyValue label="包管理器">{env.manager}</KeyValue>
                            {env.version && (
                              <small>项目要求 {env.declared}</small>
                            )}
                          </div>
                        ))}
                        {!selectedProject.environments.length && (
                          <p className="muted">未识别到依赖声明文件</p>
                        )}
                      </DetailSection>
                      <DetailSection
                        title="依赖"
                        action={
                          <Status value={selectedProject.dependencyState} />
                        }
                      >
                        {selectedProject.environments.map((env) => (
                          <div key={env.stack}>
                            <KeyValue label="声明文件">
                              <code>{env.manifest}</code>
                            </KeyValue>
                            <KeyValue label="安装位置">
                              <code>{env.location}</code>
                            </KeyValue>
                          </div>
                        ))}
                        <KeyValue label="已解析声明">
                          {selectedProject.dependencies.length} 项
                        </KeyValue>
                        <button
                          className="text-button"
                          onClick={() => setTab("deps")}
                        >
                          查看依赖
                          <ArrowUpRight size={14} />
                        </button>
                      </DetailSection>
                      <DetailSection
                        title="磁盘占用"
                        action={
                          <button
                            className="text-button"
                            disabled={busy}
                            onClick={() => {
                              if (requireNative())
                                perform(async () => {
                                  const u = await api!.storage(
                                    selectedProject.id,
                                  );
                                  setUsage((s) => ({
                                    ...s,
                                    [selectedProject.id]: u,
                                  }));
                                });
                            }}
                          >
                            计算
                          </button>
                        }
                      >
                        {usage[selectedProject.id] ? (
                          <>
                            <div className="storage-bar">
                              <span
                                style={{
                                  width: `${(100 * usage[selectedProject.id].source) / Math.max(usage[selectedProject.id].source + usage[selectedProject.id].dependencies, 1)}%`,
                                }}
                              />
                            </div>
                            <div className="storage-labels">
                              <span>
                                项目
                                <strong>
                                  {formatSize(usage[selectedProject.id].source)}
                                </strong>
                              </span>
                              <span>
                                依赖
                                <strong>
                                  {formatSize(
                                    usage[selectedProject.id].dependencies,
                                  )}
                                </strong>
                              </span>
                            </div>
                            <small className="muted">
                              不跟随符号链接，不计共享缓存。
                              {usage[selectedProject.id].skipped > 0 &&
                                "部分目录无法读取。"}
                            </small>
                          </>
                        ) : (
                          <p className="muted">按需计算，浏览项目更轻快。</p>
                        )}
                      </DetailSection>
                    </>
                  ) : tab === "deps" ? (
                    <>
                      <DetailSection title="环境与安装">
                        {selectedProject.environments.map((env) => (
                          <div className="install-card" key={env.stack}>
                            <div>
                              <StackIcon stack={env.stack} />
                              <strong>{env.stack}</strong>
                              <span>{env.manager}</span>
                            </div>
                            <p>{env.manifest}</p>
                            <button
                              className="button"
                              disabled={busy}
                              onClick={() => {
                                if (requireNative())
                                  perform(async () => {
                                    setLogs("");
                                    setShowLogs(true);
                                    const result = await api!.install(
                                      selectedProject.id,
                                      env.stack,
                                    );
                                    await refresh();
                                    if (!result.canceled)
                                      setToast("依赖安装完成");
                                  });
                              }}
                            >
                              <Download size={14} />
                              {env.installed ? "同步依赖" : "安装依赖"}
                            </button>
                          </div>
                        ))}
                      </DetailSection>
                      <DetailSection
                        title={`依赖声明 · ${selectedProject.dependencies.length}`}
                      >
                        <p className="muted">
                          展示声明版本，实际安装版本以锁文件和包管理器为准。
                        </p>
                        {selectedProject.dependencies.map((d, i) => (
                          <div className="dependency" key={i}>
                            <div>
                              <code>{d.name}</code>
                              <small>
                                {d.kind} · {d.stack}
                              </small>
                            </div>
                            <code>{d.version}</code>
                          </div>
                        ))}
                      </DetailSection>
                    </>
                  ) : (
                    <DetailSection title="项目备注">
                      <p className="notes">
                        {selectedProject.notes ||
                          "还没有备注。记录启动方式、注意事项，或下次想继续的灵感。"}
                      </p>
                      <button
                        className="button"
                        onClick={() => beginEdit(selectedProject)}
                      >
                        编辑信息
                      </button>
                    </DetailSection>
                  )}
                </div>
                <div className="inspector-footer">
                  <button
                    className="text-button muted"
                    onClick={() =>
                      patch(selectedProject, {
                        archived: !selectedProject.archived,
                      })
                    }
                  >
                    <Archive size={14} />
                    {selectedProject.archived ? "恢复项目" : "归档项目"}
                  </button>
                  <IconButton
                    label="移出管理"
                    onClick={() => setModal("forget")}
                  >
                    <Trash2 size={14} />
                  </IconButton>
                </div>
              </>
            ) : (
              <div className="detail-empty">
                <FolderOpen size={30} />
                <h3>项目的细节，就在这里。</h3>
                <p>
                  选择一个项目，查看它的环境、
                  <br />
                  依赖与最近状态。
                </p>
              </div>
            )}
          </aside>
        )}
      </div>
      <footer className="statusbar">
        <span>
          <span className="dot" />
          {data.root
            ? `项目根目录  ${data.root.replace(/^\/Users\/[^/]+/, "~")}`
            : "尚未设置项目根目录"}
        </span>
        <div>
          <button onClick={() => setShowLogs(!showLogs)}>
            <Terminal size={12} />
            操作日志
          </button>
          <button
            disabled={busy}
            onClick={() => perform(refresh, "项目状态已刷新")}
          >
            <RefreshCw size={12} className={busy ? "spin" : ""} />
            {busy ? "操作进行中" : "刷新项目"}
          </button>
          <span>仅保存在本机</span>
        </div>
      </footer>
      {toast && (
        <div className="toast" role="status">
          <CheckCircle2 size={16} />
          {toast}
        </div>
      )}
      {error && (
        <div className="error-toast" role="alert">
          <AlertCircle size={18} />
          <span>{error}</span>
          <IconButton label="关闭错误提示" onClick={() => setError("")}>
            <X size={16} />
          </IconButton>
        </div>
      )}
      {showLogs && (
        <section className="log-panel">
          <div>
            <strong>
              <Terminal size={15} />
              操作日志{busy && <Loader2 size={14} className="spin" />}
            </strong>
            <IconButton label="关闭日志" onClick={() => setShowLogs(false)}>
              <X size={16} />
            </IconButton>
          </div>
          <pre>
            {logs || "暂无操作日志。导入和依赖安装的输出会显示在这里。"}
          </pre>
        </section>
      )}
      <Modal
        title="导入项目"
        description="把已有代码或远程仓库，安放到你的项目空间。"
        open={modal === "import"}
        onClose={() => !busy && setModal("")}
      >
        <div className="segmented">
          {[
            ["folder", "已有文件夹"],
            ["git", "Git Clone"],
            ["scan", "批量扫描"],
          ].map(([key, label]) => (
            <button
              key={key}
              className={importTab === key ? "active" : ""}
              disabled={busy}
              onClick={() => {
                setImportTab(key);
                if (key !== "scan")
                  setImportForm((form) => ({
                    ...form,
                    copyClaudeChats: false,
                  }));
              }}
            >
              {label}
            </button>
          ))}
        </div>
        <div className="form">
          {importTab === "git" ? (
            <label>
              仓库地址
              <input
                placeholder="https://github.com/owner/repo.git"
                value={importForm.url}
                onChange={(e) => {
                  const url = e.target.value;
                  setImportForm((f) => ({
                    ...f,
                    url,
                    name:
                      url
                        .split(/[/:]/)
                        .pop()
                        ?.replace(/\.git$/, "") || "",
                  }));
                }}
              />
            </label>
          ) : (
            <label>
              {importTab === "scan" ? "扫描目录" : "项目文件夹"}
              <div className="input-action">
                <input
                  readOnly
                  value={importForm.source}
                  placeholder="选择本地文件夹"
                />
                <button className="button" onClick={() => perform(pickSource)}>
                  <FolderOpen size={16} />
                  选择
                </button>
              </div>
            </label>
          )}
          {importTab !== "scan" && (
            <label>
              项目名称
              <input
                value={importForm.name}
                onChange={(e) =>
                  setImportForm((f) => ({ ...f, name: e.target.value }))
                }
                placeholder="my-awesome-project"
              />
            </label>
          )}
          <div className="form-row">
            <label>
              项目分组
              <select
                value={importForm.group}
                onChange={(e) =>
                  setImportForm((f) => ({
                    ...f,
                    group: e.target.value as Group,
                  }))
                }
              >
                {Object.entries(groups).map(([k, v]) => (
                  <option value={k} key={k}>
                    {v}
                  </option>
                ))}
              </select>
              <GroupCreator
                disabled={busy || demoMode}
                onCreate={createGroup}
                onCreated={(id) => setImportForm((f) => ({ ...f, group: id }))}
              />
            </label>
            {importTab !== "git" && (
              <label>
                导入方式
                <select
                  value={importForm.mode}
                  onChange={(e) =>
                    setImportForm((f) => ({ ...f, mode: e.target.value }))
                  }
                >
                  <option value="copy">复制到根目录</option>
                  <option value="move">移动到根目录</option>
                  <option value="register">登记项目（保留原路径）</option>
                </select>
              </label>
            )}
          </div>
          <ImportTags
            key={modal === "import" ? "open" : "closed"}
            available={[...new Set(projects.flatMap((p) => p.tags))]}
            value={importForm.tags}
            onChange={(tags) => setImportForm((f) => ({ ...f, tags }))}
            disabled={busy}
            batch={importTab === "scan"}
          />
          {importTab === "scan" && importForm.mode === "move" && (
            <label className="check-row">
              <input
                type="checkbox"
                checked={importForm.copyClaudeChats}
                onChange={(e) =>
                  setImportForm((form) => ({
                    ...form,
                    copyClaudeChats: e.target.checked,
                  }))
                }
                disabled={busy}
              />
              <span>
                复制 Claude Code 聊天记录到新路径
                <small>旧路径下的聊天记录会保留，已有会话不会被覆盖。</small>
              </span>
            </label>
          )}
          {importTab === "scan" ? (
            <>
              <button
                className="button"
                disabled={!importForm.source || busy}
                onClick={() =>
                  perform(async () => {
                    const folders = await api!.scan(importForm.source);
                    setScanResults(folders);
                    setChecked(folders);
                    if (!folders.length)
                      setToast("未发现项目，扫描最多深入 4 层目录");
                  })
                }
              >
                <Search size={15} />
                扫描项目
              </button>
              <div className="scan-results">
                {scanResults.map((folder) => (
                  <label key={folder}>
                    <input
                      type="checkbox"
                      checked={checked.includes(folder)}
                      onChange={(e) =>
                        setChecked((s) =>
                          e.target.checked
                            ? [...s, folder]
                            : s.filter((p) => p !== folder),
                        )
                      }
                    />
                    <span>{folder}</span>
                  </label>
                ))}
              </div>
            </>
          ) : (
            <div className="destination">
              <span>目标位置</span>
              <code>
                {importTab !== "git" && importForm.mode === "register"
                  ? importForm.source
                  : `${state.root}/${importForm.group}/${importForm.name || "项目名称"}`}
              </code>
            </div>
          )}
          {importForm.mode === "move" && importTab !== "git" && (
            <p className="move-note">
              移动后原路径将不再存在，已有终端和 IDE
              路径可能需要重新打开。跨磁盘移动请使用复制方式。
            </p>
          )}
        </div>
        <div className="modal-footer">
          <button
            className="button"
            disabled={busy}
            onClick={() => setModal("")}
          >
            取消
          </button>
          <button
            className="button primary"
            disabled={
              busy ||
              (importTab === "scan"
                ? !checked.length
                : !importForm.name ||
                  !(importTab === "git" ? importForm.url : importForm.source))
            }
            onClick={doImport}
          >
            {busy ? <Loader2 size={15} className="spin" /> : <Plus size={15} />}{" "}
            {busy
              ? "正在导入…"
              : importTab === "scan"
                ? `导入 ${checked.length} 个项目`
                : "导入项目"}
          </button>
        </div>
      </Modal>
      <Modal
        title="项目分组"
        description="新增分组后，可在导入、编辑和筛选项目时使用。"
        open={modal === "groups"}
        onClose={() => setModal("")}
      >
        <div className="form">
          <div className="group-chips">
            {Object.entries(groups).map(([id, name]) => (
              <span className="tag" key={id}>
                {name}
              </span>
            ))}
          </div>
          <GroupCreator
            expanded
            disabled={busy || demoMode}
            onCreate={createGroup}
          />
        </div>
      </Modal>
      <Modal
        title="设置"
        description=""
        open={modal === "settings"}
        onClose={() => setModal("")}
        wide
        className="settings-modal"
      >
        <div className="settings-layout">
          <nav className="settings-nav" aria-label="设置导航">
            <span>设置模块</span>
            {[
              ["general", "通用", <SlidersHorizontal size={15} />],
              ["appearance", "外观", <LayoutGrid size={15} />],
              ["open", "打开方式", <ExternalLink size={15} />],
              ["data", "数据", <Download size={15} />],
            ].map(([id, label, icon]) => (
              <button
                key={id as string}
                className={settingsSection === id ? "active" : ""}
                aria-current={settingsSection === id ? "page" : undefined}
                onClick={() =>
                  setSettingsSection(
                    id as "general" | "appearance" | "open" | "data",
                  )
                }
              >
                {icon}
                {label}
              </button>
            ))}
            <small>codedog 0.1.0</small>
          </nav>
          <div className="settings-content">
            {settingsSection === "general" && (
              <section className="settings-pane">
                <div className="settings-section-heading">
                  <h3>通用</h3>
                  <p>设置项目的统一存放位置和应用数据来源。</p>
                </div>
                <div className="form settings-form">
                  <label>
                    项目根目录
                    <div className="input-action">
                      <input readOnly value={data.root || "尚未选择"} />
                      <button
                        className="button"
                        disabled={busy || demoMode}
                        onClick={chooseRoot}
                      >
                        选择
                      </button>
                    </div>
                    <small>
                      复制、移动和克隆的项目存放在这里；登记项目可保留原路径。
                    </small>
                  </label>
                  <div className="settings-line">
                    <div>
                      <strong>全局项目启动器</strong>
                      <p>在任何应用中呼出精简模式，再按一次即可收起。</p>
                    </div>
                    <div className="shortcut-editor">
                      <button
                        className={`shortcut-display ${recordingShortcut ? "recording" : ""}`}
                        disabled={busy || demoMode}
                        aria-label="更改全局项目启动器快捷键"
                        onClick={() => setRecordingShortcut(true)}
                        onBlur={() => setRecordingShortcut(false)}
                        onKeyDown={(event) => {
                          if (!recordingShortcut) return;
                          event.preventDefault();
                          event.stopPropagation();
                          if (event.key === "Escape") {
                            setRecordingShortcut(false);
                            return;
                          }
                          try {
                            const shortcut = shortcutFromEvent(event);
                            if (!shortcut) return;
                            setRecordingShortcut(false);
                            if (!api) return;
                            void perform(async () => {
                              await api.setLauncherShortcut(shortcut);
                              await refresh();
                            }, "全局快捷键已更新");
                          } catch (e) {
                            setError((e as Error).message);
                          }
                        }}
                      >
                        <Keyboard size={14} />
                        {recordingShortcut ? (
                          <span>请按下新的组合键…</span>
                        ) : (
                          launcherShortcutParts(
                            state.launcherShortcut || defaultLauncherShortcut,
                          ).map((part, index) => (
                            <span
                              className="shortcut-part"
                              key={`${part}-${index}`}
                            >
                              {index > 0 && <i>+</i>}
                              <kbd>{part}</kbd>
                            </span>
                          ))
                        )}
                      </button>
                      {(state.launcherShortcut || defaultLauncherShortcut) !==
                        defaultLauncherShortcut && (
                        <button
                          className="icon-button shortcut-reset"
                          title="恢复默认快捷键"
                          aria-label="恢复默认快捷键"
                          disabled={busy || demoMode}
                          onClick={() => {
                            if (!api) return;
                            void perform(async () => {
                              await api.setLauncherShortcut(
                                defaultLauncherShortcut,
                              );
                              await refresh();
                            }, "已恢复默认快捷键");
                          }}
                        >
                          <RefreshCw size={13} />
                        </button>
                      )}
                    </div>
                  </div>
                  <div className="settings-line">
                    <div>
                      <strong>命令行工具</strong>
                      <p>
                        在终端中使用 codedog add、list、open 和 path。
                        {cliInfo?.path ? ` 安装位置：${cliInfo.path}` : ""}
                        若终端提示找不到命令，请将 ~/.local/bin 加入 PATH。
                      </p>
                    </div>
                    <button
                      className="button"
                      disabled={busy || demoMode}
                      onClick={() => {
                        if (!api) return;
                        perform(async () => {
                          const result = await api.installCli();
                          setCliInfo({ installed: true, path: result.path });
                        }, "命令行工具已安装");
                      }}
                    >
                      <Terminal size={14} />
                      {cliInfo?.installed ? "重新安装" : "安装"}
                    </button>
                  </div>
                  <div className="settings-line">
                    <div>
                      <strong>
                        {demoMode ? "当前正在查看演示数据" : "演示项目"}
                      </strong>
                      <p>使用内置项目体验界面，不会修改本地文件。</p>
                    </div>
                    <button
                      className="button"
                      onClick={() => {
                        setDemoMode(!demoMode);
                        setModal("");
                        setSelected(state.projects[0]?.id || "");
                      }}
                    >
                      {demoMode ? "返回本地" : "查看演示"}
                      <ArrowUpRight size={14} />
                    </button>
                  </div>
                </div>
              </section>
            )}
            {settingsSection === "appearance" && (
              <section className="settings-pane">
                <div className="settings-section-heading">
                  <h3>外观</h3>
                  <p>调整主题和应用启动后的工作界面。</p>
                </div>
                <div className="form settings-form">
                  <label>
                    外观主题
                    <select
                      aria-label="外观主题"
                      value={theme}
                      disabled={busy}
                      onChange={(e) => {
                        const next = e.target.value as Theme;
                        if (!api) {
                          setState((s) => ({ ...s, theme: next }));
                          return;
                        }
                        perform(async () => {
                          await api.setTheme(next);
                          await refresh();
                        }, "主题已更新");
                      }}
                    >
                      <option value="system">跟随系统</option>
                      <option value="light">亮色模式</option>
                      <option value="dark">暗黑模式</option>
                    </select>
                    <small>标准模式和精简模式会使用同一主题。</small>
                  </label>
                  <div className="settings-choice">
                    <span>界面模式</span>
                    <div className="settings-choice-grid">
                      <button className="active" disabled>
                        <LayoutGrid size={17} />
                        <strong>标准模式</strong>
                        <small>完整的项目管理工作台</small>
                      </button>
                      <button
                        disabled={busy}
                        onClick={() => {
                          setModal("");
                          void switchMode("compact");
                        }}
                      >
                        <List size={17} />
                        <strong>精简模式</strong>
                        <small>紧凑搜索与快速打开</small>
                      </button>
                    </div>
                  </div>
                </div>
              </section>
            )}
            {settingsSection === "open" && (
              <section className="settings-pane">
                <div className="settings-section-heading">
                  <h3>打开方式</h3>
                  <p>选择项目默认使用的编辑器和终端应用。</p>
                </div>
                <div className="form settings-form">
                  <label>
                    默认 IDE
                    <select
                      aria-label="默认 IDE"
                      value={data.ide}
                      disabled={demoMode || busy}
                      onChange={(e) =>
                        perform(async () => {
                          await api!.setIde(e.target.value);
                          await refresh();
                        }, "默认 IDE 已更新")
                      }
                    >
                      {[
                        "Cursor",
                        "Visual Studio Code",
                        "WebStorm",
                        "GoLand",
                        "PyCharm",
                      ].map((ide) => (
                        <option key={ide}>{ide}</option>
                      ))}
                    </select>
                    <small>每个项目仍可单独覆盖这个默认选择。</small>
                  </label>
                  <label>
                    默认终端
                    <select
                      aria-label="默认终端"
                      value={data.terminal || "system"}
                      disabled={demoMode || busy}
                      onChange={(e) => {
                        const terminal = e.target.value as "system" | "warp";
                        perform(async () => {
                          await api!.setTerminal(terminal);
                          await refresh();
                        }, "默认终端已更新");
                      }}
                    >
                      <option value="system">系统终端（默认）</option>
                      <option value="warp">Warp</option>
                    </select>
                    <small>项目详情、右键菜单和快捷键都使用这个终端。</small>
                  </label>
                </div>
              </section>
            )}
            {settingsSection === "data" && (
              <section className="settings-pane">
                <div className="settings-section-heading">
                  <h3>数据</h3>
                  <p>备份 codedog 保存的项目管理信息。</p>
                </div>
                <div className="settings-line settings-data-line">
                  <div>
                    <strong>导出管理数据</strong>
                    <p>包含项目路径、分组、标签与备注，不包含项目源码。</p>
                  </div>
                  <button
                    className="button"
                    disabled={demoMode || busy}
                    onClick={() =>
                      perform(async () => {
                        if (await api!.backup()) setToast("备份已导出");
                      })
                    }
                  >
                    <Download size={15} />
                    导出备份
                  </button>
                </div>
                <p className="settings-privacy">
                  codedog 的管理数据仅保存在本机，不会上传项目内容。
                </p>
              </section>
            )}
          </div>
        </div>
      </Modal>
      <Modal
        title="编辑项目信息"
        description="分类与名称只更新管理信息，不会移动或重命名磁盘文件夹。"
        open={modal === "edit"}
        onClose={() => setModal("")}
      >
        <div className="form">
          <label>
            显示名称
            <input
              value={edit.name}
              onChange={(e) => setEdit((s) => ({ ...s, name: e.target.value }))}
            />
          </label>
          <div className="form-row">
            <label>
              分组
              <select
                value={edit.group}
                onChange={(e) =>
                  setEdit((s) => ({ ...s, group: e.target.value as Group }))
                }
              >
                {Object.entries(groups).map(([k, v]) => (
                  <option value={k} key={k}>
                    {v}
                  </option>
                ))}
              </select>
              <GroupCreator
                disabled={busy || demoMode}
                onCreate={createGroup}
                onCreated={(id) => setEdit((f) => ({ ...f, group: id }))}
              />
            </label>
            <label>
              IDE
              <select
                value={edit.ide}
                onChange={(e) =>
                  setEdit((s) => ({ ...s, ide: e.target.value }))
                }
              >
                <option value="">跟随默认设置</option>
                {[
                  "Cursor",
                  "Visual Studio Code",
                  "WebStorm",
                  "GoLand",
                  "PyCharm",
                ].map((i) => (
                  <option key={i}>{i}</option>
                ))}
              </select>
            </label>
          </div>
          <label>
            标签
            <input
              value={edit.tags}
              placeholder="前端, React, 工作"
              onChange={(e) => setEdit((s) => ({ ...s, tags: e.target.value }))}
            />
            <small>用逗号分隔多个标签</small>
          </label>
          <label>
            项目别名
            <input
              value={edit.aliases}
              placeholder="网关, gateway, 鉴权"
              onChange={(e) =>
                setEdit((s) => ({ ...s, aliases: e.target.value }))
              }
            />
            <small>用逗号分隔；每个别名全局唯一，可直接用于 CLI 打开项目</small>
          </label>
          <label>
            备注
            <textarea
              rows={4}
              value={edit.notes}
              onChange={(e) =>
                setEdit((s) => ({ ...s, notes: e.target.value }))
              }
            />
          </label>
        </div>
        <div className="modal-footer">
          <button className="button" onClick={() => setModal("")}>
            取消
          </button>
          <button
            className="button primary"
            disabled={busy}
            onClick={() => {
              if (selectedProject && requireNative())
                perform(async () => {
                  await api!.update(selectedProject.id, {
                    ...edit,
                    tags: edit.tags
                      .split(/[,，]/)
                      .map((t) => t.trim())
                      .filter(Boolean),
                    aliases: edit.aliases
                      .split(/[,，]/)
                      .map((alias) => alias.trim())
                      .filter(Boolean),
                  });
                  await refresh();
                  setModal("");
                }, "项目信息已更新");
            }}
          >
            保存信息
          </button>
        </div>
      </Modal>
      <Modal
        title={`清理 ${cleanupPreview?.directories.length || 0} 个依赖目录`}
        description="这些目录会被永久删除；项目源码和锁文件会保留。"
        open={modal === "cleanup" && !!cleanupPreview}
        onClose={closeDependencyCleanup}
        className="cleanup-modal"
      >
        {cleanupPreview && (
          <>
            <div className="cleanup-summary">
              <div>
                <span>预计释放</span>
                <strong>{formatSize(cleanupPreview.size)}</strong>
              </div>
              <div>
                <span>影响项目</span>
                <strong>
                  {
                    new Set(
                      cleanupPreview.directories.map((item) => item.projectId),
                    ).size
                  }{" "}
                  个
                </strong>
              </div>
            </div>
            <div className="cleanup-list-heading">
              <span>即将删除</span>
              <span>{cleanupPreview.directories.length} 项</span>
            </div>
            <ul className={`cleanup-list ${cleanupExpanded ? "expanded" : ""}`}>
              {cleanupPreview.directories
                .slice(0, cleanupExpanded ? undefined : 5)
                .map((item) => (
                  <li key={`${item.projectId}:${item.path}`}>
                    <span className="cleanup-project">{item.projectName}</span>
                    <code>{item.path}</code>
                    <span className="cleanup-size">
                      {formatSize(item.size)}
                    </span>
                  </li>
                ))}
            </ul>
            {cleanupPreview.directories.length > 5 && (
              <button
                className="cleanup-expand"
                aria-expanded={cleanupExpanded}
                onClick={() => setCleanupExpanded((value) => !value)}
              >
                {cleanupExpanded ? (
                  <>
                    <ChevronUp size={14} /> 收起列表
                  </>
                ) : (
                  <>
                    <ChevronDown size={14} /> 展开其余{" "}
                    {cleanupPreview.directories.length - 5} 项
                  </>
                )}
              </button>
            )}
            <div className="modal-footer">
              <button
                className="button"
                disabled={busy}
                onClick={closeDependencyCleanup}
              >
                取消
              </button>
              <button
                className="button danger"
                disabled={busy}
                onClick={() => void confirmDependencyCleanup()}
              >
                {busy ? (
                  <Loader2 size={14} className="spin" />
                ) : (
                  <Trash2 size={14} />
                )}
                清理依赖
              </button>
            </div>
          </>
        )}
      </Modal>
      <Modal
        title="移出管理"
        description="项目源码与依赖会完整保留在原目录，只移除 codedog 中的记录。"
        open={modal === "forget"}
        onClose={() => setModal("")}
      >
        <p className="forget-name">{selectedProject?.name}</p>
        <div className="modal-footer">
          <button className="button" onClick={() => setModal("")}>
            取消
          </button>
          <button
            className="button danger"
            disabled={busy}
            onClick={() => {
              if (selectedProject && requireNative())
                perform(async () => {
                  await api!.forget(selectedProject.id);
                  setSelected("");
                  await refresh();
                  setModal("");
                }, "已移出管理，文件仍在原位置");
            }}
          >
            移出管理
          </button>
        </div>
      </Modal>
    </div>
  );
}
function ProjectMark({ p, large = false }: { p: Project; large?: boolean }) {
  return (
    <span
      className={`project-mark ${large ? "large" : ""} ${p.stacks[0] === "Python" ? "python" : p.stacks[0] === "Go" ? "go" : ""}`}
    >
      <TechStackIcon stack={p.stacks[0]} size={large ? 27 : 20} />
    </span>
  );
}
function DetailSection({
  title,
  action,
  children,
}: {
  title: string;
  action?: ReactNode;
  children: ReactNode;
}) {
  return (
    <section className="detail-section">
      <div className="section-heading">
        <h3>{title}</h3>
        {action}
      </div>
      {children}
    </section>
  );
}
function KeyValue({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="key-value">
      <span>{label}</span>
      <div>{children}</div>
    </div>
  );
}
