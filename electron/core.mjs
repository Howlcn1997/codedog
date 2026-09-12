import fs from "node:fs/promises";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";
export const defaultGroups = {
  company: "公司项目",
  personal: "个人项目",
  temporary: "临时项目",
};
export const exists = async (p) => !!(await fs.stat(p).catch(() => null));
export const within = (root, target) => {
  const r = path.relative(root, target);
  return (
    r === "" ||
    (!r.startsWith(".." + path.sep) && r !== ".." && !path.isAbsolute(r))
  );
};
function groupFolderName(name) {
  if (
    typeof name !== "string" ||
    !name.trim() ||
    name !== name.trim() ||
    /[<>:"/\\|?*\x00-\x1f\x7f]/u.test(name) ||
    /[. ]$/.test(name) ||
    /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(name) ||
    Object.keys(defaultGroups).some((id) => id === name.toLowerCase()) ||
    /^group-[a-f0-9-]+$/i.test(name)
  )
    throw Error(
      "分组名称不能用作文件夹名称，请避免路径分隔符、特殊字符或系统保留名称",
    );
  return name;
}
export function safeName(name) {
  if (
    typeof name !== "string" ||
    !/^[\p{L}\p{N}][\p{L}\p{N}._ -]{0,99}$/u.test(name) ||
    name.endsWith(".")
  )
    throw Error("项目名称不能包含路径分隔符，且必须以字母或数字开头");
  return name.trim();
}
export function run(
  command,
  args,
  cwd,
  onLog = () => {},
  timeout = 30000,
  extraEnv = {},
) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd,
      shell: false,
      env: { ...process.env, GIT_TERMINAL_PROMPT: "0", ...extraEnv },
      windowsHide: true,
    });
    let output = "";
    let error = "";
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill("SIGTERM");
    }, timeout);
    const append = (chunk) => {
      const text = chunk.toString();
      output = (output + text).slice(-200000);
      onLog(text);
    };
    child.stdout.on("data", append);
    child.stderr.on("data", (c) => {
      error = (error + c).slice(-6000);
      append(c);
    });
    child.on("error", (e) => {
      clearTimeout(timer);
      reject(
        Error(
          e.code === "ENOENT"
            ? `未找到 ${command}，请安装后重新启动 codedog`
            : e.message,
        ),
      );
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      code === 0
        ? resolve(output.trim())
        : reject(
            Error(
              timedOut
                ? "操作超时，请检查网络或开发工具"
                : error.trim() || `${command} 退出码 ${code}`,
            ),
          );
    });
  });
}
async function read(p) {
  return fs.readFile(p, "utf8").catch(() => "");
}
async function json(p) {
  const content = await read(p);
  if (!content) return null;
  try {
    return JSON.parse(content);
  } catch {
    throw Error(`无法解析 ${path.basename(p)}，请检查文件格式`);
  }
}
export async function inspect(folder) {
  if (!(await exists(folder)))
    return {
      stacks: [],
      missing: true,
      dependencyState: "missing",
      environments: [],
      dependencies: [],
      branch: "",
      changes: 0,
      remote: "",
      description: "",
    };
  const environments = [];
  const dependencies = [];
  const stacks = [];
  const pkg = await json(path.join(folder, "package.json"));
  if (pkg) {
    stacks.push("Node.js");
    const manager = (await exists(path.join(folder, "pnpm-lock.yaml")))
      ? "pnpm"
      : (await exists(path.join(folder, "yarn.lock")))
        ? "yarn"
        : "npm";
    const installed = await exists(path.join(folder, "node_modules"));
    environments.push({
      stack: "Node.js",
      declared:
        pkg.engines?.node ||
        (await read(path.join(folder, ".nvmrc"))).trim() ||
        "未声明",
      manager,
      manifest: "package.json",
      location: "node_modules",
      installed,
    });
    for (const [kind, values] of Object.entries({
      生产: pkg.dependencies,
      开发: pkg.devDependencies,
    }))
      for (const [name, version] of Object.entries(values || {}))
        dependencies.push({
          name,
          version: String(version),
          kind,
          stack: "Node.js",
        });
  }
  const gomod = await read(path.join(folder, "go.mod"));
  if (gomod || (await exists(path.join(folder, "go.work")))) {
    stacks.push("Go");
    environments.push({
      stack: "Go",
      declared: gomod.match(/^go\s+(.+)$/m)?.[1] || "未声明",
      manager: "go",
      manifest: gomod ? "go.mod" : "go.work",
      location: "共享模块缓存（go env GOMODCACHE）",
      installed: null,
    });
    for (const m of gomod.matchAll(
      /^\s*(?:require\s+)?([\w.\-/]+)\s+(v[^\s]+)(?:\s*\/\/.*)?$/gm,
    ))
      dependencies.push({
        name: m[1],
        version: m[2],
        kind: "模块",
        stack: "Go",
      });
  }
  const pyproject = await read(path.join(folder, "pyproject.toml"));
  const requirements = await read(path.join(folder, "requirements.txt"));
  if (
    pyproject ||
    requirements ||
    (await exists(path.join(folder, "setup.py")))
  ) {
    stacks.push("Python");
    const manager = (await exists(path.join(folder, "uv.lock")))
      ? "uv"
      : (await exists(path.join(folder, "poetry.lock")))
        ? "poetry"
        : "pip";
    environments.push({
      stack: "Python",
      declared:
        pyproject.match(/requires-python\s*=\s*["']([^"']+)/)?.[1] || "未声明",
      manager,
      manifest: pyproject
        ? "pyproject.toml"
        : requirements
          ? "requirements.txt"
          : "setup.py",
      location: ".venv",
      installed: await exists(path.join(folder, ".venv")),
    });
    for (const line of requirements
      .split("\n")
      .filter((l) => l.trim() && !l.startsWith("#")))
      dependencies.push({
        name: line.trim(),
        version: "",
        kind: "声明",
        stack: "Python",
      });
    const list =
      pyproject.match(/(?:^|\n)dependencies\s*=\s*\[([\s\S]*?)\]/)?.[1] || "";
    for (const m of list.matchAll(/["']([^"']+)["']/g))
      dependencies.push({
        name: m[1],
        version: "",
        kind: "声明",
        stack: "Python",
      });
  }
  let branch = "",
    changes = 0,
    remote = "";
  // Do not attribute a parent repository to a non-repository child directory.
  if (await exists(path.join(folder, ".git"))) {
    branch = await run(
      "git",
      ["-C", folder, "branch", "--show-current"],
      folder,
    ).catch(() => "HEAD");
    const status = await run(
      "git",
      ["-C", folder, "status", "--porcelain"],
      folder,
    ).catch(() => "");
    changes = status ? status.split("\n").length : 0;
    remote = await run(
      "git",
      ["-C", folder, "remote", "get-url", "origin"],
      folder,
    ).catch(() => "");
  }
  return {
    stacks,
    environments,
    dependencies,
    branch,
    changes,
    remote,
    description: pkg?.description || "",
    missing: false,
    dependencyState: environments.some((e) => e.installed === false)
      ? "pending"
      : environments.some((e) => e.installed === null)
        ? "unknown"
        : environments.length
          ? "ready"
          : "none",
  };
}
export async function diskUsage(folder) {
  let source = 0,
    dependencies = 0,
    skipped = 0;
  async function walk(dir, isDependency = false) {
    for (const entry of await fs
      .readdir(dir, { withFileTypes: true })
      .catch(() => {
        skipped++;
        return [];
      })) {
      if (entry.isSymbolicLink()) continue;
      const p = path.join(dir, entry.name);
      const dep =
        isDependency || ["node_modules", ".venv", "venv"].includes(entry.name);
      if (entry.isDirectory()) await walk(p, dep);
      else {
        const size = (await fs.stat(p).catch(() => null))?.size || 0;
        if (dep) dependencies += size;
        else source += size;
      }
    }
  }
  await walk(folder);
  return { source, dependencies, skipped };
}
export class ProjectStore {
  constructor(file) {
    this.file = file;
    this.state = { version: 1, root: "", ide: "Cursor", projects: [] };
    this.queue = Promise.resolve();
  }
  async init() {
    try {
      this.state = JSON.parse(await fs.readFile(this.file, "utf8"));
      if (this.state.version !== 1 || !Array.isArray(this.state.projects))
        throw Error("不支持的数据格式");
    } catch (e) {
      if (e.code !== "ENOENT") throw Error(`无法读取管理数据：${e.message}`);
    }
    return this.state;
  }
  transaction(fn) {
    const operation = this.queue.then(fn);
    this.queue = operation.catch(() => {});
    return operation;
  }
  async save() {
    await fs.mkdir(path.dirname(this.file), { recursive: true });
    const temp = this.file + ".tmp";
    await fs.writeFile(temp, JSON.stringify(this.state, null, 2));
    await fs.rename(temp, this.file);
  }
  groups() {
    return {
      ...defaultGroups,
      ...Object.fromEntries(
        (this.state.groups || []).map((g) => [g.id, g.name]),
      ),
    };
  }
  groupDirectory(id) {
    if (Object.hasOwn(defaultGroups, id)) return id;
    const group = (this.state.groups || []).find((g) => g.id === id);
    if (!group) throw Error("无效的项目分组");
    return groupFolderName(group.name);
  }
  async createGroup(name) {
    if (typeof name !== "string" || !name.trim() || name.trim().length > 40)
      throw Error("分组名称须为 1–40 个字符");
    name = name.trim();
    groupFolderName(name);
    return this.transaction(async () => {
      if (
        Object.values(this.groups()).some(
          (n) =>
            n.normalize("NFKC").toLocaleLowerCase() ===
            name.normalize("NFKC").toLocaleLowerCase(),
        )
      )
        throw Error("已存在同名分组");
      const group = { id: "group-" + randomUUID(), name };
      const previous = this.state.groups;
      this.state.groups = [...(previous || []), group];
      try {
        await this.save();
      } catch (error) {
        this.state.groups = previous;
        throw error;
      }
      return group;
    });
  }
  async setTheme(theme) {
    if (!["system", "light", "dark"].includes(theme)) throw Error("无效的主题");
    return this.transaction(async () => {
      const previous = this.state.theme;
      this.state.theme = theme;
      try {
        await this.save();
      } catch (error) {
        this.state.theme = previous;
        throw error;
      }
    });
  }
  async setTerminal(terminal) {
    if (!["system", "warp"].includes(terminal)) throw Error("不支持的终端");
    return this.transaction(async () => {
      const previous = this.state.terminal;
      this.state.terminal = terminal;
      try {
        await this.save();
      } catch (error) {
        this.state.terminal = previous;
        throw error;
      }
    });
  }
  async setMode(mode) {
    if (!["standard", "compact"].includes(mode)) throw Error("无效的界面模式");
    return this.transaction(async () => {
      const previous = this.state.uiMode;
      this.state.uiMode = mode;
      try {
        await this.save();
      } catch (error) {
        this.state.uiMode = previous;
        throw error;
      }
    });
  }
  async setRoot(folder) {
    return this.transaction(async () => {
      const root = await fs.realpath(folder);
      if (this.state.root !== root && this.state.projects.length)
        throw Error(
          "已有项目时不能直接切换根目录。请先备份并移出管理，文件会保留。",
        );
      this.state.root = root;
      await this.save();
      return this.state;
    });
  }
  async get(id) {
    const item = this.state.projects.find((p) => p.id === id);
    if (!item) throw Error("项目不存在");
    const real = await fs.realpath(item.path);
    if (!within(await fs.realpath(this.state.root), real))
      throw Error("项目路径已移出根目录，请重新导入");
    return { ...item, path: real };
  }
  async list() {
    const records = [...this.state.projects];
    const result = new Array(records.length);
    let index = 0;
    await Promise.all(
      Array.from({ length: Math.min(6, records.length) }, async () => {
        while (index < records.length) {
          const position = index++;
          const p = records[position];
          try {
            if (await exists(p.path)) await this.get(p.id);
            result[position] = { ...p, ...(await inspect(p.path)) };
          } catch (e) {
            result[position] = {
              ...p,
              stacks: [],
              environments: [],
              dependencies: [],
              dependencyState: "unknown",
              error: e.message,
            };
          }
        }
      }),
    );
    return result;
  }
  async importProject(input, onLog = () => {}) {
    return this.transaction(async () => {
      if (!this.state.root) throw Error("请先选择项目根目录");
      const root = await fs.realpath(this.state.root);
      const name = safeName(input.name);
      const group = input.group;
      const rawTags = input.tags ?? [];
      if (
        !Array.isArray(rawTags) ||
        rawTags.some((tag) => typeof tag !== "string")
      )
        throw Error("标签必须是文本列表");
      const tags = [
        ...new Set(rawTags.map((tag) => tag.trim()).filter(Boolean)),
      ];
      if (tags.length > 20 || tags.some((tag) => tag.length > 40))
        throw Error("最多选择 20 个标签，每个标签最多 40 个字符");
      if (!Object.hasOwn(this.groups(), group)) throw Error("无效的项目分组");
      if (!["copy", "move", "register", "clone"].includes(input.mode))
        throw Error("无效的导入方式");
      let source = "";
      let target = "";
      let created = false;
      if (input.mode !== "clone") {
        source = await fs.realpath(input.source);
        if (!(await fs.stat(source)).isDirectory()) throw Error("请选择文件夹");
      }
      if (input.mode === "register") {
        if (!within(root, source) || root === source)
          throw Error("只能直接登记根目录内的项目子文件夹");
        target = source;
      } else {
        const parent = path.join(root, this.groupDirectory(group));
        await fs.mkdir(parent, { recursive: true });
        if (!within(root, await fs.realpath(parent)))
          throw Error("分类目录不能指向根目录之外");
        target = path.join(parent, name);
        if (await exists(target))
          throw Error("目标目录已存在，请修改名称或直接登记");
        if (source && (within(source, target) || within(source, root)))
          throw Error("不能将包含根目录的文件夹导入自身");
      }
      if (
        this.state.projects.some(
          (p) => p.path === target || (source && p.path === source),
        )
      )
        throw Error("这个项目已在管理中");
      if (input.mode === "clone") {
        if (
          typeof input.url !== "string" ||
          !/^(https:\/\/|ssh:\/\/|git@[\w.-]+:)/.test(input.url) ||
          /[\r\n\x00]/.test(input.url)
        )
          throw Error("请输入 HTTPS 或 SSH Git 仓库地址");
        if (this.state.projects.some((p) => p.cloneUrl === input.url))
          throw Error("这个仓库已经导入");
      }
      onLog("开始导入…\n");
      try {
        if (input.mode === "copy") {
          await fs.mkdir(target);
          created = true;
          // Reserve ownership of the destination, then copy its children.
          // Newer Node/Electron versions reject cp(source, existingDirectory)
          // with errorOnExist, even when that directory was just created here.
          for (const entry of await fs.readdir(source)) {
            await fs.cp(path.join(source, entry), path.join(target, entry), {
              recursive: true,
              force: false,
              errorOnExist: true,
              verbatimSymlinks: true,
            });
          }
        }
        if (input.mode === "move") {
          await fs.rename(source, target);
          onLog("文件夹已移动到 " + target + "\n");
        }
        if (input.mode === "clone") {
          await fs.mkdir(target);
          created = true;
          await run(
            "git",
            ["clone", "--progress", "--", input.url, target],
            root,
            onLog,
            600000,
          );
        }
        const record = {
          id: randomUUID(),
          name,
          path: target,
          group,
          tags,
          notes: "",
          favorite: false,
          archived: false,
          createdAt: Date.now(),
          lastOpened: 0,
          cloneUrl: input.url || "",
        };
        this.state.projects.push(record);
        try {
          await this.save();
        } catch (e) {
          this.state.projects.pop();
          if (input.mode === "move") await fs.rename(target, source);
          throw e;
        }
        onLog("导入完成\n");
        return record;
      } catch (e) {
        if (created) await fs.rm(target, { recursive: true, force: true });
        throw e;
      }
    });
  }
  async update(id, patch) {
    return this.transaction(async () => {
      const item = this.state.projects.find((p) => p.id === id);
      if (!item) throw Error("项目不存在");
      const allowed = {};
      if (patch.name !== undefined) allowed.name = safeName(patch.name);
      if (patch.group !== undefined) {
        if (!Object.hasOwn(this.groups(), patch.group)) throw Error("无效分组");
        allowed.group = patch.group;
      }
      for (const key of ["favorite", "archived"])
        if (patch[key] !== undefined) allowed[key] = !!patch[key];
      if (patch.notes !== undefined)
        allowed.notes = String(patch.notes).slice(0, 10000);
      if (patch.tags !== undefined) {
        if (!Array.isArray(patch.tags)) throw Error("标签格式无效");
        allowed.tags = patch.tags
          .map(String)
          .map((s) => s.trim())
          .filter(Boolean)
          .slice(0, 20);
      }
      if (patch.ide !== undefined) {
        if (
          ![
            "",
            "Cursor",
            "Visual Studio Code",
            "WebStorm",
            "GoLand",
            "PyCharm",
          ].includes(patch.ide)
        )
          throw Error("无效 IDE");
        allowed.ide = patch.ide;
      }
      Object.assign(item, allowed);
      await this.save();
      return item;
    });
  }
  async forget(id) {
    return this.transaction(async () => {
      this.state.projects = this.state.projects.filter((p) => p.id !== id);
      await this.save();
    });
  }
  async scan(folder) {
    const found = [];
    const skip = new Set([
      "node_modules",
      ".git",
      ".venv",
      "venv",
      "dist",
      "build",
      ".next",
    ]);
    const walk = async (dir, depth) => {
      if (found.length >= 300) return;
      const entries = await fs.readdir(dir, { withFileTypes: true });
      if (
        entries.some((e) =>
          [
            "package.json",
            "go.mod",
            "go.work",
            "pyproject.toml",
            "requirements.txt",
            ".git",
          ].includes(e.name),
        )
      ) {
        found.push(dir);
        return;
      }
      if (depth >= 4) return;
      for (const e of entries)
        if (e.isDirectory() && !skip.has(e.name))
          await walk(path.join(dir, e.name), depth + 1);
    };
    await walk(await fs.realpath(folder), 0);
    return found;
  }
}
export function installPlan(env, folder) {
  if (env.stack === "Node.js")
    return [
      {
        command: env.manager,
        args: env.manager === "npm" ? ["install"] : ["install"],
      },
    ];
  if (env.stack === "Go") return [{ command: "go", args: ["mod", "download"] }];
  if (env.manager === "uv") return [{ command: "uv", args: ["sync"] }];
  if (env.manager === "poetry")
    return [
      {
        command: "poetry",
        args: ["install"],
        env: { POETRY_VIRTUALENVS_IN_PROJECT: "true" },
      },
    ];
  const python = path.join(
    folder,
    ".venv",
    process.platform === "win32" ? "Scripts/python.exe" : "bin/python",
  );
  return [
    {
      command: process.platform === "win32" ? "python" : "python3",
      args: ["-m", "venv", ".venv"],
    },
    {
      command: python,
      args: [
        "-m",
        "pip",
        "install",
        ...(env.manifest === "requirements.txt"
          ? ["-r", "requirements.txt"]
          : ["-e", "."]),
      ],
    },
  ];
}
