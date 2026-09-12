import { useEffect, useMemo, useRef, useState } from "react";
import {
  Search,
  PanelsTopLeft,
  CornerDownLeft,
  Star,
  Code2,
  Box,
  FileCode2,
  X,
  Loader2,
} from "lucide-react";
import type { KeyboardEvent as ReactKeyboardEvent } from "react";
import type { Project } from "./types";
function fuzzy(name: string, query: string) {
  let i = 0;
  for (const c of name.toLocaleLowerCase()) if (c === query[i]) i++;
  return i === query.length;
}
export default function CompactMode({
  projects,
  groups,
  root,
  busy,
  demo,
  onStandard,
  onOpen,
  onProjectMenu,
  error,
  onDismissError,
}: {
  projects: Project[];
  groups: Record<string, string>;
  root: string;
  busy: boolean;
  demo: boolean;
  onStandard: () => void;
  onOpen: (p: Project, kind: "ide" | "terminal") => void;
  onProjectMenu: (p: Project) => void;
  error: string;
  onDismissError: () => void;
}) {
  const [search, setSearch] = useState(""),
    [group, setGroup] = useState("all"),
    [stack, setStack] = useState("all"),
    [tag, setTag] = useState("all"),
    [sort, setSort] = useState("recent"),
    [selected, setSelected] = useState("");
  const input = useRef<HTMLInputElement>(null);
  const selectedRow = useRef<HTMLButtonElement>(null);
  const tags = useMemo(
    () =>
      [
        ...new Set(projects.filter((p) => !p.archived).flatMap((p) => p.tags)),
      ].sort((a, b) => a.localeCompare(b, "zh-CN")),
    [projects],
  );
  const results = useMemo(
    () =>
      projects
        .filter((p) => {
          if (
            p.archived ||
            (group !== "all" && p.group !== group) ||
            (stack !== "all" && !p.stacks.includes(stack)) ||
            (tag !== "all" && !p.tags.includes(tag))
          )
            return false;
          const hay = [
            p.name,
            p.path,
            p.notes,
            p.remote,
            ...p.tags,
            ...p.stacks,
          ]
            .join(" ")
            .toLocaleLowerCase();
          return search
            .trim()
            .toLocaleLowerCase()
            .split(/\s+/)
            .every((q) => hay.includes(q) || fuzzy(p.name, q));
        })
        .sort((a, b) =>
          sort === "name"
            ? a.name.localeCompare(b.name)
            : sort === "created"
              ? b.createdAt - a.createdAt
              : b.lastOpened - a.lastOpened,
        ),
    [projects, search, group, stack, tag, sort],
  );
  const current = results.find((p) => p.id === selected) || results[0];
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
    const shortcut = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        input.current?.focus();
      }
    };
    window.addEventListener("keydown", shortcut);
    return () => window.removeEventListener("keydown", shortcut);
  }, []);
  function open(p: Project, kind: "ide" | "terminal" = "ide") {
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
    } else if (e.key === "Enter") {
      e.preventDefault();
      e.stopPropagation();
      if (current && !e.repeat) open(current, e.metaKey ? "terminal" : "ide");
    } else if (e.key === "Escape") {
      setSearch("");
      setSelected("");
      input.current?.focus();
    }
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
            placeholder="搜索项目名称、路径或标签…"
            value={search}
            onChange={(e) => {
              setSearch(e.target.value);
              setSelected("");
            }}
            title="↑ / ↓ 选择项目 · Enter 使用 IDE 打开 · ⌘ Enter 使用终端打开"
            onKeyDown={handleProjectKeyDown}
          />
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
      <div className="compact-filters">
        <div>
          <select
            aria-label="项目分组"
            value={group}
            onChange={(e) => {
              setGroup(e.target.value);
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
            onChange={(e) => setSort(e.target.value)}
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
              aria-label={`打开项目 ${p.name}`}
              title={`${p.name}\n${p.path}\nEnter：IDE 打开 · ⌘ Enter：终端打开`}
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
                {p.stacks[0] === "Go" ? (
                  <Box />
                ) : p.stacks[0] === "Python" ? (
                  <FileCode2 />
                ) : (
                  <Code2 />
                )}
              </span>
              <span className="compact-project-info">
                <span className="compact-project-name">
                  <span className="compact-name-text">{p.name}</span>
                  {p.favorite && (
                    <Star size={13} fill="currentColor" className="starred" />
                  )}
                </span>
                <span className="compact-path">
                  {p.missing ? "路径缺失 · " : ""}
                  {p.path.startsWith(root + "/")
                    ? p.path.slice(root.length + 1)
                    : p.path}
                </span>
              </span>
              <span className="compact-group">
                {groups[p.group] || p.group}
              </span>
              <span className="compact-stack">
                {p.stacks.join(" / ") || "其他"}
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
