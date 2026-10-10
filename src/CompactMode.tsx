import { useEffect, useMemo, useRef, useState } from "react";
import {
  Search,
  PanelsTopLeft,
  CornerDownLeft,
  Star,
  X,
  Loader2,
  Terminal,
  GitBranch,
  Code2,
  FolderOpen,
  RefreshCw,
  MoreHorizontal,
} from "lucide-react";
import type { CSSProperties, KeyboardEvent as ReactKeyboardEvent } from "react";
import type { SearchItem, CompactAppearance } from "./types";
import TechStackIcon from "./TechStackIcon";
import { searchProjects } from "./projectSearch";

export default function CompactMode({
  projects,
  appearance,
  groups,
  root,
  busy,
  demo,
  onStandard,
  onOpen,
  onProjectMenu,
  onHide,
  onRefreshIndex,
  error,
  onDismissError,
}: {
  projects: SearchItem[];
  appearance: CompactAppearance;
  groups: Record<string, string>;
  root: string;
  busy: boolean;
  demo: boolean;
  onStandard: () => void;
  onOpen: (
    p: SearchItem,
    kind: "ide" | "terminal" | "repository" | "folder",
  ) => void;
  onProjectMenu: (p: SearchItem) => void;
  onHide: () => void;
  onRefreshIndex: () => void;
  error: string;
  onDismissError: () => void;
}) {
  const [search, setSearch] = useState("");
  const [sort, setSort] = useState("recent");
  const [selected, setSelected] = useState("");
  const [actionIndex, setActionIndex] = useState(0);
  const input = useRef<HTMLInputElement>(null);
  const selectedRow = useRef<HTMLButtonElement>(null);
  const menu = useRef<HTMLDetailsElement>(null);
  const recent = useMemo(
    () =>
      projects
        .filter(
          (p) =>
            p.kind !== "workspace" &&
            !p.archived &&
            !p.missing &&
            p.lastOpened > 0,
        )
        .sort(
          (a, b) => b.lastOpened - a.lastOpened || a.name.localeCompare(b.name),
        )
        .slice(0, 5),
    [projects],
  );
  const results = useMemo(
    () =>
      searchProjects(
        projects.filter(
          (p) => !p.archived && (p.kind !== "workspace" || search.trim()),
        ),
        search,
        (a, b) =>
          sort === "name"
            ? a.name.localeCompare(b.name)
            : b.lastOpened - a.lastOpened,
      ),
    [projects, search, sort],
  );
  const current = results.find((p) => p.id === selected) || results[0];
  const actions = [
    {
      kind: "ide" as const,
      label: "IDE",
      title: "打开 IDE",
      icon: Code2,
      disabled: false,
    },
    {
      kind: "terminal" as const,
      label: "终端",
      title: "打开终端",
      icon: Terminal,
      disabled: false,
    },
    {
      kind: "repository" as const,
      label: "仓库",
      title: "访问仓库",
      icon: GitBranch,
      disabled: !current?.remote,
    },
    {
      kind: "folder" as const,
      label: "访达",
      title: "在文件管理器中打开",
      icon: FolderOpen,
      disabled: false,
    },
  ];
  useEffect(() => {
    document.documentElement.dataset.uiMode = "compact";
    input.current?.focus();
    const focus = () => input.current?.focus();
    const outside = (e: PointerEvent) => {
      if (menu.current && !menu.current.contains(e.target as Node))
        menu.current.open = false;
    };
    const shortcut = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        input.current?.focus();
      }
      if (e.key === "Escape" && menu.current?.open) {
        e.preventDefault();
        e.stopPropagation();
        menu.current.open = false;
        input.current?.focus();
      }
    };
    window.addEventListener("focus", focus);
    window.addEventListener("pointerdown", outside);
    window.addEventListener("keydown", shortcut, true);
    return () => {
      delete document.documentElement.dataset.uiMode;
      window.removeEventListener("focus", focus);
      window.removeEventListener("pointerdown", outside);
      window.removeEventListener("keydown", shortcut, true);
    };
  }, []);
  useEffect(() => {
    selectedRow.current?.scrollIntoView({ block: "nearest" });
  }, [current?.id]);
  useEffect(() => {
    if (actionIndex === 2 && !current?.remote) setActionIndex(0);
  }, [current?.remote, actionIndex]);

  function open(
    p: SearchItem,
    kind: "ide" | "terminal" | "repository" | "folder" = "ide",
  ) {
    if (!busy && !p.missing) onOpen(p, kind);
  }
  function handleProjectKeyDown(e: ReactKeyboardEvent<HTMLElement>) {
    if (e.nativeEvent.isComposing || e.keyCode === 229) return;
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      e.stopPropagation();
      if (!results.length) return;
      const index = results.findIndex((p) => p.id === current?.id);
      setSelected(
        results[
          (index + (e.key === "ArrowDown" ? 1 : -1) + results.length) %
            results.length
        ].id,
      );
      input.current?.focus();
    } else if (e.key === "ArrowLeft" || e.key === "ArrowRight") {
      e.preventDefault();
      e.stopPropagation();
      const direction = e.key === "ArrowRight" ? 1 : -1;
      let next = actionIndex;
      do {
        next = (next + direction + actions.length) % actions.length;
      } while (actions[next].disabled && next !== actionIndex);
      setActionIndex(next);
      input.current?.focus();
    } else if (e.key === "Enter") {
      e.preventDefault();
      e.stopPropagation();
      const action = actions[actionIndex];
      if (current && action && !action.disabled && !e.repeat)
        open(current, action.kind);
    } else if (e.key === "Escape") {
      e.preventDefault();
      e.stopPropagation();
      if (search) {
        setSearch("");
        setSelected("");
        input.current?.focus();
      } else onHide();
    }
  }
  return (
    <main
      style={
        {
          "--compact-opacity": appearance.opacity / 100,
        } as CSSProperties
      }
      data-glass-contrast={appearance.opacity < 55 ? "high" : undefined}
      className="compact-shell"
      aria-label="精简模式"
      onKeyDown={(e) => {
        if (e.key === "Escape") handleProjectKeyDown(e);
      }}
    >
      <header className="compact-search-row">
        <div className="compact-search">
          <Search size={21} />
          <input
            ref={input}
            autoFocus
            aria-label="搜索项目"
            placeholder="搜索项目…"
            value={search}
            onChange={(e) => {
              setSearch(e.target.value);
              setSelected("");
            }}
            title="搜索项目、项目组、README 或依赖"
            onKeyDown={handleProjectKeyDown}
          />
          {search ? (
            <button
              aria-label="清空搜索"
              className="icon-button"
              onClick={() => {
                setSearch("");
                setSelected("");
                input.current?.focus();
              }}
            >
              <X size={15} />
            </button>
          ) : (
            <kbd>⌘ K</kbd>
          )}
        </div>
        <details className="compact-menu" ref={menu}>
          <summary aria-label="更多选项">
            <MoreHorizontal size={21} />
          </summary>
          <div className="compact-menu-panel">
            <button
              disabled={busy}
              onClick={() => {
                if (menu.current) menu.current.open = false;
                onStandard();
              }}
            >
              <PanelsTopLeft size={15} />
              标准模式
            </button>
            <button
              disabled={busy}
              onClick={() => {
                if (menu.current) menu.current.open = false;
                onRefreshIndex();
              }}
            >
              <RefreshCw size={15} className={busy ? "spin" : ""} />
              刷新搜索索引
            </button>
          </div>
        </details>
      </header>
      {!search.trim() && recent.length > 0 && (
        <section className="compact-recent" aria-label="最近打开">
          <div className="compact-section-label">最近打开</div>
          <div className="compact-recent-grid">
            {recent.map((p) => (
              <button
                className="compact-recent-project"
                key={p.id}
                disabled={busy}
                aria-label={`打开最近项目 ${p.name}`}
                title={`${p.name}\n${p.path}`}
                onClick={() => open(p)}
                onContextMenu={(e) => {
                  e.preventDefault();
                  onProjectMenu(p);
                }}
                onKeyDown={(e) => {
                  if (
                    e.key === "ContextMenu" ||
                    (e.shiftKey && e.key === "F10")
                  ) {
                    e.preventDefault();
                    onProjectMenu(p);
                  }
                }}
              >
                <span
                  className={`compact-recent-icon ${p.stacks[0] === "Go" ? "go" : p.stacks[0] === "Python" ? "python" : ""}`}
                >
                  {p.name.toLowerCase() === "codedog" ? (
                    <img src="./icon.png" alt="" />
                  ) : (
                    <TechStackIcon stack={p.stacks[0]} size={24} />
                  )}
                </span>
                <span className="compact-recent-name">{p.name}</span>
              </button>
            ))}
          </div>
        </section>
      )}
      <div className="compact-list-heading">
        <span aria-live="polite">
          {demo ? "演示 · " : ""}
          {search.trim() ? "搜索结果" : "全部项目"} · {results.length}
        </span>
        <select
          aria-label="排序"
          value={sort}
          onChange={(e) => setSort(e.target.value)}
        >
          <option value="recent">最近打开 ↓</option>
          <option value="name">名称 A–Z</option>
        </select>
      </div>
      <ul className="compact-projects" aria-label="项目列表">
        {results.map((p) => (
          <li key={p.id}>
            <button
              ref={p.id === current?.id ? selectedRow : undefined}
              className={`compact-project ${p.id === current?.id ? "selected" : ""}`}
              aria-label={`打开${p.kind === "workspace" ? "项目组" : "项目"} ${p.name}`}
              title={`${p.name}\n${p.path}\n↑ / ↓：选择项目 · ← / →：选择打开方式 · Enter：执行`}
              aria-current={p.id === current?.id ? "true" : undefined}
              disabled={busy || p.missing}
              onFocus={() => setSelected(p.id)}
              onClick={() => open(p)}
              onContextMenu={(e) => {
                e.preventDefault();
                e.stopPropagation();
                setSelected(p.id);
                onProjectMenu(p);
              }}
              onKeyDown={(e) => {
                if (
                  e.key === "ContextMenu" ||
                  (e.shiftKey && e.key === "F10")
                ) {
                  e.preventDefault();
                  e.stopPropagation();
                  onProjectMenu(p);
                  return;
                }
                handleProjectKeyDown(e);
              }}
            >
              <span className="project-mark">
                {p.kind === "workspace" ? (
                  <FolderOpen size={17} />
                ) : (
                  <TechStackIcon stack={p.stacks[0]} size={17} />
                )}
              </span>
              <span className="compact-project-info">
                <span className="compact-project-name">
                  <span className="compact-name-text">{p.name}</span>
                  {search.trim() && (
                    <span
                      className={`result-kind ${p.kind === "workspace" ? "is-workspace" : ""}`}
                    >
                      {p.kind === "workspace" ? "项目组" : "项目"}
                    </span>
                  )}
                  {p.favorite && (
                    <Star size={12} fill="currentColor" className="starred" />
                  )}
                </span>
                <span
                  className={`compact-path ${p.searchMatch ? "search-match" : ""}`}
                >
                  {p.searchMatch
                    ? p.searchMatch.reasons.join(" · ")
                    : `${p.missing ? "路径缺失 · " : ""}${p.path.startsWith(root + "/") ? p.path.slice(root.length + 1) : p.path}`}
                </span>
              </span>
              <span className="compact-group">
                {p.kind === "workspace"
                  ? `${p.memberCount} 个成员`
                  : groups[p.group] || p.group}
              </span>
              <span className="compact-open">
                {busy && p.id === current?.id ? (
                  <Loader2 size={15} className="spin" />
                ) : p.id === current?.id ? (
                  <CornerDownLeft size={14} />
                ) : null}
              </span>
            </button>
          </li>
        ))}
        {!results.length && (
          <li className="compact-empty">
            <Search size={25} />
            <p>
              {projects.some((p) => !p.archived)
                ? "没有匹配的项目"
                : "还没有项目"}
            </p>
            <span>
              {projects.some((p) => !p.archived)
                ? "试试其他关键词。"
                : "从右上角切换到标准模式，导入第一个项目。"}
            </span>
          </li>
        )}
      </ul>
      <footer className="compact-command-bar" aria-label="打开方式">
        <span className="compact-command-hint">↑ ↓ 选择 · ← → 切换</span>
        {actions.map((action, index) => {
          const ActionIcon = action.icon;
          return (
            <button
              key={action.kind}
              className={actionIndex === index ? "active" : ""}
              aria-label={action.title}
              title={
                current ? `${action.title} · ${current.name}` : action.title
              }
              aria-pressed={actionIndex === index}
              disabled={!current || busy || current.missing || action.disabled}
              onFocus={() => setActionIndex(index)}
              onClick={() => current && open(current, action.kind)}
            >
              <ActionIcon size={13} />
              {action.label}
              {actionIndex === index && <kbd>↵</kbd>}
            </button>
          );
        })}
      </footer>
      {error && (
        <div className="error-toast" role="alert">
          <span>{error}</span>
          <button
            className="icon-button"
            aria-label="关闭错误提示"
            onClick={onDismissError}
          >
            <X size={16} />
          </button>
        </div>
      )}
    </main>
  );
}
