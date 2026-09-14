import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import { randomUUID } from "node:crypto";

const marker = ".codedog-workspace.json";
const key = (value) => value.normalize("NFKC").toLowerCase();
const inside = (parent, child) => {
  const relative = path.relative(parent, child);
  return (
    !relative ||
    (!path.isAbsolute(relative) &&
      relative !== ".." &&
      !relative.startsWith(`..${path.sep}`))
  );
};
async function stat(file) {
  try {
    return await fs.lstat(file);
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
}
function name(value) {
  if (
    typeof value !== "string" ||
    !value.trim() ||
    value.length > 100 ||
    /[<>:"/\\|?*\x00-\x1f\x7f]/u.test(value) ||
    /[. ]$/.test(value) ||
    value !== value.trim() ||
    value.startsWith(".") ||
    /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(value)
  )
    throw Error("名称须为 1–100 个字符，不能包含路径分隔符或系统保留名称");
  return value;
}
function find(store, id) {
  const workspace = (store.state.workspaces || []).find(
    (item) => item.id === id,
  );
  if (!workspace) throw Error("项目组不存在");
  return workspace;
}
async function checkRoot(workspace) {
  const info = await stat(workspace.path);
  if (
    !info?.isDirectory() ||
    info.isSymbolicLink() ||
    (await fs.realpath(workspace.path)) !== workspace.path
  )
    throw Error("项目组目录不存在或已被替换，请恢复原目录");
  const file = path.join(workspace.path, marker);
  if (!(await stat(file))?.isFile()) throw Error("项目组标记文件已失效");
  const value = JSON.parse(await fs.readFile(file, "utf8"));
  if (value.id !== workspace.id) throw Error("项目组目录标记不匹配");
}
async function readDescription(workspace) {
  const file = path.join(workspace.path, "README.md");
  const info = await stat(file);
  if (!info) return "";
  if (!info.isFile() || info.size > 1024 * 1024)
    throw Error("README.md 必须是小于 1 MB 的普通文件");
  return fs.readFile(file, "utf8");
}
async function members(store, input, workspacePath) {
  if (!Array.isArray(input) || input.length > 100)
    throw Error("项目组最多包含 100 个项目");
  const aliases = new Set([key("README.md"), key(marker)]),
    ids = new Set();
  const result = [];
  for (const member of input) {
    const alias = name(member.alias);
    if (aliases.has(key(alias)) || ids.has(member.projectId))
      throw Error("成员或组内目录名重复，或使用了保留文件名");
    aliases.add(key(alias));
    ids.add(member.projectId);
    const project = store.state.projects.find(
      (item) => item.id === member.projectId,
    );
    if (!project) throw Error("成员项目已移出管理，请移除该成员");
    const target = await fs.realpath(project.path).catch(() => {
      throw Error(`项目路径失效：${project.name}`);
    });
    if (!(await fs.stat(target)).isDirectory())
      throw Error("成员项目必须是目录");
    if (inside(target, workspacePath) || inside(workspacePath, target))
      throw Error("项目组与成员目录不能互相包含");
    if (result.some((item) => item.target === target))
      throw Error("不能重复关联同一个真实目录");
    result.push({ projectId: project.id, alias, target });
  }
  return result;
}
async function ownedLink(workspace, member) {
  const file = path.join(workspace.path, member.alias);
  const info = await stat(file);
  if (!info) return false;
  if (
    !info.isSymbolicLink() ||
    path.resolve(workspace.path, await fs.readlink(file)) !== member.target
  )
    throw Error(`目录项已被替换，保留原样：${member.alias}`);
  return true;
}
const link = (target, file) =>
  fs.symlink(target, file, process.platform === "win32" ? "junction" : "dir");

export async function listWorkspaces(store) {
  return Promise.all(
    (store.state.workspaces || []).map(async (workspace) => {
      let error;
      try {
        await checkRoot(workspace);
      } catch (e) {
        error = e.message;
      }
      const statuses = await Promise.all(
        workspace.members.map(async (member) => {
          let status = "ready";
          try {
            if (error) throw Error(error);
            const project = store.state.projects.find(
              (p) => p.id === member.projectId,
            );
            if (!project) throw Error("项目已移出管理");
            if (!(await ownedLink(workspace, member))) throw Error("链接缺失");
            const real = await fs.realpath(project.path);
            if (real !== member.target || !(await fs.stat(real)).isDirectory())
              throw Error("项目路径已变化");
          } catch (e) {
            status = e.code === "ENOENT" ? "项目路径失效" : e.message;
          }
          return { ...member, status };
        }),
      );
      return { ...workspace, members: statuses, error };
    }),
  );
}

export async function workspaceLocation(store, id) {
  await store.refresh();
  const workspace = find(store, id);
  await checkRoot(workspace);
  return workspace;
}

export async function getWorkspace(store, id) {
  const workspace = await workspaceLocation(store, id);
  return { ...workspace, description: await readDescription(workspace) };
}

export async function createWorkspace(store, input, home = os.homedir()) {
  return store.transaction(async () => {
    const title = name(input.name);
    if (
      (store.state.workspaces || []).some(
        (item) => key(item.name) === key(title),
      )
    )
      throw Error("已存在同名项目组");
    if (
      typeof input.description !== "string" ||
      Buffer.byteLength(input.description) > 1024 * 1024
    )
      throw Error("关系说明不能超过 1 MB");
    const base = path.join(home, "codespace", "workspaces");
    await fs.mkdir(base, { recursive: true });
    const parent = await fs.realpath(base);
    const id = randomUUID();
    const folder = path.join(parent, `${title}-${id.slice(0, 8)}`);
    const items = await members(store, input.members, folder);
    const workspace = {
      id,
      name: title,
      path: folder,
      members: items,
      createdAt: Date.now(),
      lastOpened: 0,
    };
    await fs.mkdir(folder);
    const created = [];
    const previous = store.state.workspaces;
    try {
      for (const item of items) {
        const file = path.join(folder, item.alias);
        await link(item.target, file);
        created.push(file);
      }
      for (const [filename, content] of [
        [marker, JSON.stringify({ id, version: 1 })],
        ["README.md", input.description],
      ]) {
        const file = path.join(folder, filename);
        await fs.writeFile(file, content, { flag: "wx" });
        created.push(file);
      }
      store.state.workspaces = [...(previous || []), workspace];
      await store.save();
      return workspace;
    } catch (error) {
      store.state.workspaces = previous;
      for (const file of created.reverse())
        await fs.unlink(file).catch(() => {});
      await fs.rmdir(folder).catch(() => {});
      throw error;
    }
  });
}

// Preflight all entries, then journal each filesystem mutation so a failed save
// restores the previous links and README. Never recursively delete a directory.
export async function updateWorkspace(store, id, input, repair = false) {
  return store.transaction(async () => {
    const workspace = find(store, id);
    await checkRoot(workspace);
    if (repair) input = { name: workspace.name, members: workspace.members };
    const title = name(input.name);
    if (
      (store.state.workspaces || []).some(
        (item) => item.id !== id && key(item.name) === key(title),
      )
    )
      throw Error("已存在同名项目组");
    const items = await members(store, input.members, workspace.path);
    const existing = new Map();
    for (const member of workspace.members)
      existing.set(member.alias, await ownedLink(workspace, member));
    for (const member of items) {
      if (
        !existing.has(member.alias) &&
        (await stat(path.join(workspace.path, member.alias)))
      )
        throw Error(`目录项已存在：${member.alias}`);
    }
    const oldDescription =
      input.description !== undefined
        ? await readDescription(workspace)
        : undefined;
    if (
      input.description !== undefined &&
      (typeof input.description !== "string" ||
        Buffer.byteLength(input.description) > 1024 * 1024)
    )
      throw Error("关系说明不能超过 1 MB");
    if (
      input.description !== undefined &&
      input.expectedDescription !== oldDescription
    )
      throw Error("README.md 已被外部修改，请重新加载后编辑");
    const undo = [];
    const previous = store.state.workspaces;
    try {
      for (const member of workspace.members) {
        if (
          existing.get(member.alias) &&
          !items.some(
            (item) =>
              item.alias === member.alias && item.target === member.target,
          )
        ) {
          const file = path.join(workspace.path, member.alias);
          await fs.unlink(file);
          undo.push(() => link(member.target, file));
        }
      }
      for (const member of items) {
        if (
          !existing.get(member.alias) ||
          !workspace.members.some(
            (item) =>
              item.alias === member.alias && item.target === member.target,
          )
        ) {
          const file = path.join(workspace.path, member.alias);
          await link(member.target, file);
          undo.push(() => fs.unlink(file));
        }
      }
      if (
        input.description !== undefined &&
        input.description !== oldDescription
      ) {
        const file = path.join(workspace.path, "README.md");
        const existed = !!(await stat(file));
        const write = async (content) => {
          const temp = path.join(workspace.path, `.readme-${randomUUID()}.tmp`);
          try {
            await fs.writeFile(temp, content, { flag: "wx" });
            await fs.rename(temp, file);
          } finally {
            await fs.unlink(temp).catch(() => {});
          }
        };
        await write(input.description);
        undo.push(() => (existed ? write(oldDescription) : fs.unlink(file)));
      }
      const next = { ...workspace, name: title, members: items };
      store.state.workspaces = previous.map((item) =>
        item.id === id ? next : item,
      );
      await store.save();
      return next;
    } catch (error) {
      store.state.workspaces = previous;
      const failures = [];
      for (const revert of undo.reverse()) {
        try {
          await revert();
        } catch (e) {
          failures.push(e.message);
        }
      }
      if (failures.length)
        throw Error(`${error.message}；部分恢复失败：${failures.join("；")}`);
      throw error;
    }
  });
}

export async function repairWorkspace(store, id) {
  return updateWorkspace(store, id, undefined, true);
}

export async function forgetWorkspace(store, id) {
  return store.transaction(async () => {
    find(store, id);
    const previous = store.state.workspaces;
    store.state.workspaces = previous.filter((item) => item.id !== id);
    try {
      await store.save();
    } catch (error) {
      store.state.workspaces = previous;
      throw error;
    }
  });
}
