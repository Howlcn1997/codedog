import { useEffect, useRef, useState } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import {
  FolderOpen,
  Plus,
  Terminal,
  Code2,
  RefreshCw,
  X,
  Pencil,
  Unlink,
} from "lucide-react";
import type { Api, Project, Workspace, WorkspaceMember } from "./types";
import MarkdownPreview from "./MarkdownPreview";

const template =
  "# 系统说明\n\n## 系统背景\n\n描述这个系统或流程的目标。\n\n## 项目职责\n\n说明各成员项目负责的功能。\n\n## 项目关系\n\n记录调用关系、接口约定和共同注意事项。\n";

export default function ProjectWorkspaces({
  api,
  projects,
  workspaces,
  refresh,
  initialSelectedId = "",
}: {
  api?: Api;
  projects: Project[];
  workspaces: Workspace[];
  refresh: () => Promise<void>;
  initialSelectedId?: string;
}) {
  const [selected, setSelected] = useState(initialSelectedId);
  const [description, setDescription] = useState("");
  const [readError, setReadError] = useState("");
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [busy, setBusy] = useState(false);
  const [editing, setEditing] = useState<"create" | "edit" | null>(null);
  const [removing, setRemoving] = useState(false);
  const [name, setName] = useState("");
  const [members, setMembers] = useState<WorkspaceMember[]>([]);
  const [draft, setDraft] = useState("");
  const [expected, setExpected] = useState("");
  const [query, setQuery] = useState("");
  const lock = useRef(false);
  const current =
    workspaces.find((item) => item.id === selected) || workspaces[0];
  useEffect(() => {
    let active = true;
    setDescription("");
    setReadError("");
    if (current && api)
      api
        .getWorkspace(current.id)
        .then((value) => {
          if (active) setDescription(value.description);
        })
        .catch((e) => {
          if (active) setReadError(e.message);
        });
    return () => {
      active = false;
    };
  }, [current, api]);

  async function run(action: () => Promise<void>, disableControls = true) {
    if (lock.current) return;
    lock.current = true;
    if (disableControls) setBusy(true);
    setError("");
    setNotice("");
    try {
      await action();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      lock.current = false;
      if (disableControls) setBusy(false);
    }
  }
  function showMemberMenu(projectId: string) {
    if (!api || busy) return;
    // A native menu owns interaction while open; keep its trigger enabled.
    void run(async () => {
      const result = await api.projectMenu(projectId);
      if (result.opened) await refresh();
      if (result.copied) setNotice("路径已复制");
    }, false);
  }
  function create() {
    setName("");
    setMembers([]);
    setDraft(template);
    setExpected("");
    setQuery("");
    setError("");
    setEditing("create");
  }
  async function edit() {
    if (!api || !current) return;
    await run(async () => {
      const value = await api.getWorkspace(current.id);
      setName(value.name);
      setMembers(value.members);
      setDraft(value.description);
      setExpected(value.description);
      setQuery("");
      setEditing("edit");
    });
  }
  async function save() {
    if (!api) return;
    await run(async () => {
      const input = {
        name,
        members,
        description: draft,
        expectedDescription: expected,
      };
      const result =
        editing === "create"
          ? await api.createWorkspace(input)
          : await api.updateWorkspace(current!.id, input);
      setSelected(result.id);
      setEditing(null);
      await refresh();
      setNotice("项目组已保存");
    });
  }
  function toggle(project: Project) {
    if (members.some((item) => item.projectId === project.id))
      setMembers(members.filter((item) => item.projectId !== project.id));
    else {
      const base =
        project.name
          .replace(/[<>:"/\\|?*\x00-\x1f]/g, "-")
          .replace(/^\.+|[. ]+$/g, "") || "project";
      let alias = base,
        suffix = 2;
      while (
        members.some(
          (item) => item.alias.toLowerCase() === alias.toLowerCase(),
        ) ||
        alias.toLowerCase() === "readme.md"
      )
        alias = `${base}-${suffix++}`;
      setMembers([...members, { projectId: project.id, alias }]);
    }
  }

  return (
    <>
      <div className="page-header">
        <div>
          <div className="page-title">
            <h1>项目组</h1>
            <span className="count">{workspaces.length}</span>
          </div>
          <p>将关联项目放在一个目录中，保留各自的源码位置。</p>
        </div>
        <button
          className="button primary"
          disabled={!api || busy}
          onClick={create}
        >
          <Plus size={16} />
          新建项目组
        </button>
      </div>
      {!api && (
        <p className="workspace-message">
          请在桌面应用中切换到本地项目后管理项目组。
        </p>
      )}
      {error && !editing && (
        <p className="workspace-message" role="alert">
          {error}
        </p>
      )}
      {notice && (
        <p className="workspace-message" role="status">
          {notice}
        </p>
      )}
      {current ? (
        <div className="project-workspaces">
          <nav className="workspace-picker" aria-label="项目组列表">
            {workspaces.map((item) => (
              <button
                key={item.id}
                className={`workspace-choice ${current.id === item.id ? "active" : ""}`}
                title={`${item.name} · ${item.members.length} 个项目${item.error || item.members.some((m) => m.status !== "ready") ? " · 需要检查" : ""}`}
                disabled={busy}
                onClick={() => setSelected(item.id)}
              >
                <FolderOpen size={18} />
                <span>
                  <strong>{item.name}</strong>
                  <small>
                    {item.members.length} 个项目
                    {item.error ||
                    item.members.some((m) => m.status !== "ready")
                      ? " · 需要检查"
                      : ""}
                  </small>
                </span>
              </button>
            ))}
          </nav>
          <section className="workspace-detail" aria-label="项目组详情">
            <h2>{current.name}</h2>
            <p className="workspace-path">{current.path}</p>
            <div className="workspace-actions">
              {(
                [
                  ["ide", "用 IDE 打开", Code2],
                  ["terminal", "打开终端", Terminal],
                  ["folder", "打开文件夹", FolderOpen],
                ] as const
              ).map(([kind, label, Icon]) => (
                <button
                  key={kind}
                  className="button"
                  disabled={busy || !api || !!current.error}
                  onClick={() =>
                    void run(async () => {
                      await api!.openWorkspace(current.id, kind);
                      await refresh();
                    })
                  }
                >
                  <Icon size={14} />
                  {label}
                </button>
              ))}
              <button
                className="button"
                disabled={busy || !api || !!current.error}
                onClick={() => void edit()}
              >
                <Pencil size={14} />
                编辑项目组
              </button>
              <button
                className="button"
                disabled={busy || !api}
                onClick={() => void run(refresh)}
              >
                <RefreshCw size={14} />
                刷新
              </button>
            </div>
            {current.error && <p role="alert">{current.error}</p>}
            <div className="workspace-section-title">
              <h3>成员项目</h3>
              <button
                className="text-button"
                disabled={busy || !api || !!current.error}
                onClick={() =>
                  void run(async () => {
                    await api!.repairWorkspace(current.id);
                    await refresh();
                    setNotice("链接已检查并修复");
                  })
                }
              >
                检查并修复链接
              </button>
            </div>
            {current.members.length ? (
              current.members.map((member) => {
                const project = projects.find(
                  (item) => item.id === member.projectId,
                );
                return (
                  <button
                    type="button"
                    className="workspace-member"
                    key={member.projectId}
                    disabled={!api || busy || !project}
                    aria-haspopup="menu"
                    onContextMenu={(event) => {
                      event.preventDefault();
                      showMemberMenu(member.projectId);
                    }}
                    onKeyDown={(event) => {
                      if (
                        event.key === "ContextMenu" ||
                        (event.shiftKey && event.key === "F10")
                      ) {
                        event.preventDefault();
                        showMemberMenu(member.projectId);
                      }
                    }}
                    onClick={() => showMemberMenu(member.projectId)}
                  >
                    {member.alias}
                  </button>
                );
              })
            ) : (
              <p className="workspace-message">
                尚无成员，编辑项目组以添加项目。
              </p>
            )}
            <h3>关系说明 · README.md</h3>
            {readError ? (
              <p role="alert">{readError}</p>
            ) : (
              <MarkdownPreview source={description} />
            )}
            <button
              className="text-button muted"
              disabled={busy || !api}
              onClick={() => setRemoving(true)}
            >
              <Unlink size={14} />
              移出管理
            </button>
          </section>
        </div>
      ) : (
        <div className="workspace-empty">
          <FolderOpen size={38} />
          <h2>把相关项目放在一起</h2>
          <p>
            例如将 App、Web 后台和服务端加入同一个项目组。
            <br />
            通过软链关联源码，在 README 中记录它们的关系。
          </p>
          <button className="button" disabled={!api || busy} onClick={create}>
            创建第一个项目组
          </button>
        </div>
      )}

      <Dialog.Root
        open={!!editing}
        onOpenChange={(open) => {
          if (!open && !busy) setEditing(null);
        }}
      >
        <Dialog.Portal>
          <Dialog.Overlay className="overlay" />
          <Dialog.Content className="modal wide workspace-editor">
            <div className="modal-heading">
              <div>
                <Dialog.Title>
                  {editing === "create" ? "新建项目组" : "编辑项目组"}
                </Dialog.Title>
                <Dialog.Description>
                  成员通过软链关联，源码保留在原位置。移除成员只解除链接。
                </Dialog.Description>
              </div>
              <Dialog.Close asChild>
                <button
                  className="icon-button"
                  disabled={busy}
                  aria-label="关闭"
                >
                  <X size={18} />
                </button>
              </Dialog.Close>
            </div>
            <form
              className="form"
              onSubmit={(event) => {
                event.preventDefault();
                void save();
              }}
            >
              <div className="workspace-form-scroll">
                <fieldset disabled={busy} className="workspace-fields">
                  <label>
                    项目组名称
                    <input
                      aria-label="项目组名称"
                      required
                      maxLength={100}
                      value={name}
                      onChange={(e) => setName(e.target.value)}
                    />
                  </label>
                  {editing === "edit" && (
                    <p className="workspace-path">
                      {current?.path}（重命名不改变目录）
                    </p>
                  )}
                  <label>
                    选择成员
                    <input
                      aria-label="搜索成员项目"
                      placeholder="按名称或路径搜索"
                      value={query}
                      onChange={(e) => setQuery(e.target.value)}
                    />
                  </label>
                  <div className="workspace-project-options">
                    {projects
                      .filter((p) =>
                        `${p.name} ${p.path}`
                          .toLowerCase()
                          .includes(query.toLowerCase()),
                      )
                      .map((project) => (
                        <label
                          key={project.id}
                          title={`${project.name}\n${project.path}${project.archived ? " · 已归档" : ""}`}
                        >
                          <input
                            type="checkbox"
                            checked={members.some(
                              (m) => m.projectId === project.id,
                            )}
                            onChange={() => toggle(project)}
                          />
                          <span>
                            <span className="workspace-option-name">
                              {project.name}
                            </span>
                            <small>
                              {project.path}
                              {project.archived ? " · 已归档" : ""}
                            </small>
                          </span>
                        </label>
                      ))}
                    {!projects.length && (
                      <p>暂无可选项目，请先导入项目。也可以先创建空项目组。</p>
                    )}
                  </div>
                  {members.length > 0 && (
                    <div className="workspace-aliases">
                      <span>组内目录名</span>
                      {members.map((member) => (
                        <div className="input-action" key={member.projectId}>
                          <span>
                            {projects.find((p) => p.id === member.projectId)
                              ?.name || "已失效成员"}
                          </span>
                          <input
                            aria-label={`目录名 ${member.projectId}`}
                            required
                            value={member.alias}
                            onChange={(e) =>
                              setMembers(
                                members.map((m) =>
                                  m.projectId === member.projectId
                                    ? { ...m, alias: e.target.value }
                                    : m,
                                ),
                              )
                            }
                          />
                          <button
                            type="button"
                            className="icon-button"
                            aria-label={`移除 ${member.alias}`}
                            onClick={() =>
                              setMembers(
                                members.filter(
                                  (m) => m.projectId !== member.projectId,
                                ),
                              )
                            }
                          >
                            <X size={14} />
                          </button>
                        </div>
                      ))}
                    </div>
                  )}
                  <label>
                    关系说明（Markdown）
                    <textarea
                      aria-label="关系说明"
                      rows={9}
                      value={draft}
                      onChange={(e) => setDraft(e.target.value)}
                    />
                  </label>
                  <small>
                    保存到组目录的 README.md，可使用外部编辑器修改。
                  </small>
                </fieldset>
              </div>
              {error && (
                <p role="alert" className="workspace-message">
                  {error}
                </p>
              )}
              <div className="workspace-actions">
                <button
                  type="submit"
                  className="button primary"
                  disabled={busy || !name.trim()}
                >
                  {busy ? "正在处理…" : "保存项目组"}
                </button>
                <button
                  type="button"
                  className="button"
                  disabled={busy}
                  onClick={() => setEditing(null)}
                >
                  取消
                </button>
              </div>
            </form>
          </Dialog.Content>
        </Dialog.Portal>
      </Dialog.Root>
      <Dialog.Root
        open={removing}
        onOpenChange={(open) => {
          if (!busy) setRemoving(open);
        }}
      >
        <Dialog.Portal>
          <Dialog.Overlay className="overlay" />
          <Dialog.Content className="modal">
            <div className="modal-heading">
              <div>
                <Dialog.Title>移出项目组管理</Dialog.Title>
                <Dialog.Description>
                  「{current?.name}」的目录、软链、README 和所有源码都会保留。
                </Dialog.Description>
              </div>
            </div>
            <div className="workspace-actions">
              <button
                className="button"
                disabled={busy}
                onClick={() => setRemoving(false)}
              >
                取消
              </button>
              <button
                className="button primary"
                disabled={busy}
                onClick={() =>
                  void run(async () => {
                    await api!.forgetWorkspace(current!.id);
                    setRemoving(false);
                    await refresh();
                    setNotice("已移出管理，磁盘文件已保留");
                  })
                }
              >
                移出管理
              </button>
            </div>
            {error && <p role="alert">{error}</p>}
          </Dialog.Content>
        </Dialog.Portal>
      </Dialog.Root>
    </>
  );
}
