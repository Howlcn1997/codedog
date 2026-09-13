import { HardDrive, Loader2, RefreshCw, Trash2 } from "lucide-react";
import TechStackIcon from "./TechStackIcon";
import type { Project } from "./types";

export type ProjectUsage = {
  source: number;
  dependencies: number;
  skipped: number;
};

const formatSize = (bytes: number) =>
  bytes >= 1073741824
    ? `${(bytes / 1073741824).toFixed(1)} GB`
    : bytes >= 1048576
      ? `${(bytes / 1048576).toFixed(1)} MB`
      : `${Math.max(0, Math.round(bytes / 1024))} KB`;

export default function StorageWorkspace({
  projects,
  groups,
  root,
  usage,
  selected,
  loading,
  busy,
  demo,
  onScan,
  onToggle,
  onToggleAll,
  onClean,
}: {
  projects: Project[];
  groups: Record<string, string>;
  root: string;
  usage: Record<string, ProjectUsage>;
  selected: string[];
  loading: boolean;
  busy: boolean;
  demo: boolean;
  onScan: () => void;
  onToggle: (id: string) => void;
  onToggleAll: (ids: string[], checked: boolean) => void;
  onClean: () => void;
}) {
  const selectable = projects.filter((project) => !project.missing);
  const allSelected =
    selectable.length > 0 &&
    selectable.every((project) => selected.includes(project.id));
  const measured = projects.filter((project) => usage[project.id]);
  const total = measured.reduce(
    (sum, project) =>
      sum + usage[project.id].source + usage[project.id].dependencies,
    0,
  );
  const dependencies = measured.reduce(
    (sum, project) => sum + usage[project.id].dependencies,
    0,
  );
  const selectedDependencies = selected.reduce(
    (sum, id) => sum + (usage[id]?.dependencies || 0),
    0,
  );

  return (
    <section className="storage-workspace" aria-label="项目存储空间">
      <div className="storage-summary">
        <div className="storage-metric primary-metric">
          <span>项目总占用</span>
          <strong>{measured.length ? formatSize(total) : "—"}</strong>
          <small>{measured.length} 个项目已扫描</small>
        </div>
        <div className="storage-metric">
          <span>依赖占用</span>
          <strong>{measured.length ? formatSize(dependencies) : "—"}</strong>
          <small>可通过重新安装恢复</small>
        </div>
        <div className="storage-metric">
          <span>源码与其他文件</span>
          <strong>
            {measured.length ? formatSize(total - dependencies) : "—"}
          </strong>
          <small>清理时不会删除</small>
        </div>
        <button
          className="button storage-scan"
          disabled={loading || busy || demo}
          onClick={onScan}
        >
          <RefreshCw size={14} className={loading ? "spin" : ""} />
          {loading ? "扫描中" : "重新扫描"}
        </button>
      </div>

      <div className="storage-toolbar">
        <label className="storage-select-all">
          <input
            type="checkbox"
            checked={allSelected}
            disabled={!selectable.length || busy || demo}
            onChange={(event) =>
              onToggleAll(
                selectable.map((project) => project.id),
                event.target.checked,
              )
            }
          />
          全选项目
        </label>
        <span>
          已选 {selected.length} 个
          {selectedDependencies > 0 &&
            ` · 可释放约 ${formatSize(selectedDependencies)}`}
        </span>
        <button
          className="button danger storage-clean"
          disabled={
            busy || loading || demo || !selected.length || !selectedDependencies
          }
          onClick={onClean}
        >
          <Trash2 size={14} />
          清理所选项目依赖
        </button>
      </div>

      <div className="storage-table-wrap">
        <table className="storage-table">
          <thead>
            <tr>
              <th aria-label="选择" />
              <th>项目</th>
              <th>技术栈</th>
              <th>源码与其他</th>
              <th>依赖</th>
              <th>总占用</th>
            </tr>
          </thead>
          <tbody>
            {projects.map((project) => {
              const item = usage[project.id];
              const itemTotal = item ? item.source + item.dependencies : 0;
              const dependencyRatio = itemTotal
                ? Math.round((item.dependencies / itemTotal) * 100)
                : 0;
              return (
                <tr
                  key={project.id}
                  className={selected.includes(project.id) ? "selected" : ""}
                >
                  <td>
                    <input
                      type="checkbox"
                      aria-label={`选择 ${project.name}`}
                      checked={selected.includes(project.id)}
                      disabled={project.missing || busy || demo}
                      onChange={() => onToggle(project.id)}
                    />
                  </td>
                  <td>
                    <div className="storage-project-name">
                      <TechStackIcon stack={project.stacks[0]} size={17} />
                      <span>
                        <strong>{project.name}</strong>
                        <small title={project.path}>
                          {project.path.startsWith(root + "/")
                            ? project.path.slice(root.length + 1)
                            : project.path}
                        </small>
                      </span>
                      <em>{groups[project.group] || project.group}</em>
                    </div>
                  </td>
                  <td>{project.stacks.join(" / ") || "其他"}</td>
                  <td>
                    {item ? (
                      formatSize(item.source)
                    ) : loading ? (
                      <Loader2 size={13} className="spin" />
                    ) : (
                      "—"
                    )}
                  </td>
                  <td>
                    {item ? (
                      <div className="dependency-usage">
                        <span>{formatSize(item.dependencies)}</span>
                        <i>
                          <b style={{ width: `${dependencyRatio}%` }} />
                        </i>
                      </div>
                    ) : loading ? (
                      <Loader2 size={13} className="spin" />
                    ) : (
                      "—"
                    )}
                  </td>
                  <td>
                    <strong>
                      {item
                        ? formatSize(itemTotal)
                        : project.missing
                          ? "路径缺失"
                          : "—"}
                    </strong>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
        {!projects.length && (
          <div className="storage-empty">
            <HardDrive size={28} />
            <p>还没有可分析的项目</p>
          </div>
        )}
      </div>
      {demo && (
        <p className="storage-demo-note">
          返回本地项目后即可扫描和清理实际存储空间。
        </p>
      )}
    </section>
  );
}
