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
  Save,
  Trash2,
  Code2,
  FolderOpen,
  RefreshCw,
} from "lucide-react";
import type { KeyboardEvent as ReactKeyboardEvent } from "react";
import type { SearchItem, SavedFilter } from "./types";
import TechStackIcon from "./TechStackIcon";
import { searchProjects } from "./projectSearch";
export default function CompactMode({
  projects,
  groups,
  root,
  busy,
  demo,
  onStandard,
  onOpen,
  onProjectMenu,
  savedFilters,
  onSaveFilters,
  onHide,
  onRefreshIndex,
  error,
  onDismissError,
}: {
  projects: SearchItem[];
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
  savedFilters: SavedFilter[];
  onSaveFilters: (filters: SavedFilter[]) => void;
  onHide: () => void;
  onRefreshIndex: () => void;
  error: string;
  onDismissError: () => void;
}) {
  const [search, setSearch] = useState(""),
    [group, setGroup] = useState("all"),
    [stack, setStack] = useState("all"),
    [tag, setTag] = useState("all"),
    [sort, setSort] = useState("recent"),
    [selected, setSelected] = useState(""),
    [preset, setPreset] = useState(""),
    [namingFilter, setNamingFilter] = useState(false),
    [filterName, setFilterName] = useState(""),
    [actionIndex, setActionIndex] = useState(0);
  const input = useRef<HTMLInputElement>(null);
  const selectedRow = useRef<HTMLButtonElement>(null);
  const tags = useMemo(
    () =>
      [
        ...new Set(projects.filter((p) => !p.archived).flatMap((p) => p.tags)),
      ].sort((a, b) => a.localeCompare(b, "zh-CN")),
    [projects],
  );
  const results = useMemo(() => {
    const filtered = projects.filter((p) => {
      if (p.kind === "workspace" && !search.trim()) return false;
      if (
        p.archived ||
        (group !== "all" && p.group !== group) ||
        (stack !== "all" && !p.stacks.includes(stack)) ||
        (tag !== "all" && !p.tags.includes(tag))
      )
        return false;
      if (preset === "week")
        return Math.max(p.lastOpened, p.createdAt) >= Date.now() - 7 * 86400000;
      if (preset === "dirty") return (p.changes || 0) > 0;
      if (preset === "backend")
        return p.group === "company" && p.tags.includes("后端");
      return true;
    });
    return searchProjects(filtered, search, (a, b) =>
      sort === "name"
        ? a.name.localeCompare(b.name)
        : sort === "created"
          ? b.createdAt - a.createdAt
          : b.lastOpened - a.lastOpened,
    );
  }, [projects, search, group, stack, tag, sort, preset]);
  const current = results.find((p) => p.id === selected) || results[0];
  const actions = [
    { kind: "ide" as const, label: "打开 IDE", icon: Code2, disabled: false },
    {
      kind: "terminal" as const,
      label: "打开终端",
      icon: Terminal,
      disabled: false,
    },
    {
      kind: "repository" as const,
      label: "访问仓库",
      icon: GitBranch,
      disabled: !current?.remote,
    },
    {
      kind: "folder" as const,
      label: "在访达中打开",
      icon: FolderOpen,
      disabled: false,
    },
  ];
  useEffect(() => {
    input.current?.focus();
    const focus = () => input.current?.focus();
    window.addEventListener("focus", focus);
    return () => window.removeEventListener("focus", focus);
  }, []);
  useEffect(() => {
    selectedRow.current?.scrollIntoView({ block: "nearest" });
  }, [current?.id]);
  useEffect(() => {
    if (actions[actionIndex]?.disabled) setActionIndex(0);
  }, [current?.id, current?.remote, actionIndex]);
  useEffect(() => {
    const shortcut = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        input.current?.focus();
      }
    };
    window.addEventListener("keydown", shortcut);
    return () => window.removeEventListener("keydown", shortcut);
  }, []);
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
      if (
        search ||
        preset ||
        group !== "all" ||
        stack !== "all" ||
        tag !== "all" ||
        sort !== "recent"
      ) {
        setSearch("");
        clearStructuredFilters();
        input.current?.focus();
      } else onHide();
    }
  }
  function clearStructuredFilters() {
    setGroup("all");
    setStack("all");
    setTag("all");
    setSort("recent");
    setPreset("");
    setSelected("");
  }
  function applyBuiltIn(id: string) {
    clearStructuredFilters();
    setSearch("");
    setPreset(id);
    input.current?.focus();
  }
  function applySaved(filter: SavedFilter) {
    setSearch(filter.query);
    setGroup(filter.group);
    setStack(filter.stack);
    setTag(filter.tag);
    setSort(filter.sort);
    setPreset(filter.id);
    setSelected("");
    input.current?.focus();
  }
  function saveFilter() {
    const name = filterName.trim();
    if (!name) return;
    onSaveFilters([
      ...savedFilters,
      {
        id: `filter-${Date.now()}`,
        name,
        query: search,
        group,
        stack,
        tag,
        sort,
      },
    ]);
    setNamingFilter(false);
    setFilterName("");
  }
  return (
    <main className="compact-shell" aria-label="精简模式">
      <div className="compact-search-row">
        <div className="compact-search">
          <Search size={16} />
          <input
            ref={input}
            autoFocus
            aria-label="搜索项目"
            placeholder="搜索项目、项目组、README 或依赖…"
            value={search}
            onChange={(e) => {
              setSearch(e.target.value);
              setPreset("");
              setSelected("");
            }}
            title="↑ / ↓ 选择项目 · ← / → 选择打开方式 · Enter 执行"
            onKeyDown={handleProjectKeyDown}
          />
          <button
            aria-label="刷新搜索索引"
            className="icon-button"
            disabled={busy}
            onClick={onRefreshIndex}
          >
            <RefreshCw size={15} className={busy ? "spin" : ""} />
          </button>
          {search ? (
            <button
              aria-label="清空搜索"
              className="icon-button"
              onClick={() => {
                setSearch("");
                input.current?.focus();
              }}
            >
              <X size={15} />
            </button>
          ) : (
            <kbd>⌘ K</kbd>
          )}
        </div>
        <button
          className="button compact-switch"
          disabled={busy}
          onClick={onStandard}
        >
          <PanelsTopLeft size={17} />
          标准模式
        </button>
      </div>
      <div className="compact-presets" aria-label="快捷筛选">
        <span className="compact-presets-label">快捷筛选</span>
        {[
          ["week", "本周项目"],
          ["dirty", "有未提交修改"],
          ["backend", "公司后端"],
        ].map(([id, label]) => (
          <button
            key={id}
            className={preset === id ? "active" : ""}
            aria-pressed={preset === id}
            onClick={() => applyBuiltIn(id)}
          >
            {label}
          </button>
        ))}
        {savedFilters.map((filter) => (
          <span className="saved-filter" key={filter.id}>
            <button
              className={preset === filter.id ? "active" : ""}
              aria-pressed={preset === filter.id}
              onClick={() => applySaved(filter)}
            >
              {filter.name}
            </button>
            <button
              className="saved-filter-remove"
              aria-label={`删除筛选 ${filter.name}`}
              title={`删除筛选 ${filter.name}`}
              onClick={() =>
                onSaveFilters(
                  savedFilters.filter((item) => item.id !== filter.id),
                )
              }
            >
              <Trash2 size={11} />
            </button>
          </span>
        ))}
        {namingFilter ? (
          <form
            className="save-filter-form"
            onSubmit={(event) => {
              event.preventDefault();
              saveFilter();
            }}
          >
            <input
              autoFocus
              aria-label="筛选名称"
              placeholder="筛选名称"
              maxLength={30}
              value={filterName}
              onChange={(event) => setFilterName(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === "Escape") {
                  event.stopPropagation();
                  setNamingFilter(false);
                }
              }}
            />
            <button type="submit" disabled={!filterName.trim()}>
              保存
            </button>
          </form>
        ) : (
          <button
            className="save-filter"
            disabled={
              savedFilters.length >= 20 ||
              ["week", "dirty", "backend"].includes(preset)
            }
            title={
              ["week", "dirty", "backend"].includes(preset)
                ? "内置快捷筛选无需重复保存"
                : "保存当前搜索与筛选条件"
            }
            onClick={() => setNamingFilter(true)}
          >
            <Save size={12} />
            保存当前
          </button>
        )}
      </div>
      <div className="compact-filters">
        <div>
          <select
            aria-label="项目分组"
            value={group}
            onChange={(e) => {
              setGroup(e.target.value);
              setPreset("");
              setSelected("");
            }}
          >
            <option value="all">所有分组</option>
            {Object.entries(groups).map(([key, label]) => (
              <option key={key} value={key}>
                {label}
              </option>
            ))}
          </select>
          <select
            aria-label="技术栈"
            value={stack}
            onChange={(e) => {
              setStack(e.target.value);
              setPreset("");
              setSelected("");
            }}
          >
            <option value="all">技术栈</option>
            {["Node.js", "Go", "Python"].map((s) => (
              <option key={s}>{s}</option>
            ))}
          </select>
          <select
            aria-label="标签"
            value={tag}
            onChange={(e) => {
              setTag(e.target.value);
              setPreset("");
              setSelected("");
            }}
          >
            <option value="all">标签</option>
            {tags.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </select>
        </div>
        <div>
          <span className="compact-count">
            {demo ? "演示 · " : ""}
            {results.length} 个项目
          </span>
          <select
            aria-label="排序"
            value={sort}
            onChange={(e) => {
              setSort(e.target.value);
              setPreset("");
            }}
          >
            <option value="recent">最近打开 ↓</option>
            <option value="name">名称 A–Z</option>
            <option value="created">最近导入 ↓</option>
          </select>
        </div>
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
              <span
                className={`project-mark ${p.stacks[0] === "Go" ? "go" : p.stacks[0] === "Python" ? "python" : ""}`}
              >
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
                    <Star size={13} fill="currentColor" className="starred" />
                  )}
                </span>
                <span
                  className={`compact-path ${p.searchMatch ? "search-match" : ""}`}
                >
                  {p.searchMatch
                    ? p.searchMatch.reasons.join(" · ")
                    : `${p.missing ? "路径缺失 · " : ""}${
                        p.path.startsWith(root + "/")
                          ? p.path.slice(root.length + 1)
                          : p.path
                      }`}
                </span>
              </span>
              <span className="compact-group">
                {p.kind === "workspace"
                  ? `${p.memberCount} 个成员`
                  : groups[p.group] || p.group}
              </span>
              <span className="compact-stack">
                {p.kind === "workspace" ? "" : p.stacks.join(" / ") || "其他"}
              </span>
              <span
                className={`compact-open ${p.id === current?.id ? "active" : ""}`}
              >
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
                ? "试试其他关键词，或调整筛选条件。"
                : "切换到标准模式，导入你的第一个项目。"}
            </span>
          </li>
        )}
      </ul>
      <footer className="compact-command-bar" aria-label="打开方式">
        <span className="compact-command-project">
          {current ? current.name : "选择一个项目"}
        </span>
        {actions.map((action, index) => {
          const ActionIcon = action.icon;
          return (
            <button
              key={action.kind}
              className={actionIndex === index ? "active" : ""}
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
