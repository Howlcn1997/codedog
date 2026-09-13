import { terminalLaunch } from "./terminal.mjs";
import { chooseEditor, projectMenuTemplate } from "./project-menu.mjs";
import { setupAutoUpdates } from "./updates.mjs";
import { applyWindowMode, sizeForMode } from "./window-mode.mjs";
import {
  app,
  autoUpdater,
  BrowserWindow,
  ipcMain,
  dialog,
  shell,
  clipboard,
  session,
  nativeImage,
  nativeTheme,
  Menu,
  globalShortcut,
} from "electron";
import fs from "node:fs/promises";
import { watch as watchFiles } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  ProjectStore,
  inspect,
  run,
  diskUsage,
  dependencyCleanupPlan,
  cleanProjectDependencies,
  installPlan,
  exists,
  isSearchSource,
} from "./core.mjs";
const here = path.dirname(fileURLToPath(import.meta.url));
if (process.env.CODEDOG_DATA_DIR)
  app.setPath("userData", process.env.CODEDOG_DATA_DIR);
app.setName("codedog");
let window;
let store;
let busy = false;
const IDE = ["Cursor", "Visual Studio Code", "WebStorm", "GoLand", "PyCharm"];
const cli = {
  Cursor: "cursor",
  "Visual Studio Code": "code",
  WebStorm: "webstorm",
  GoLand: "goland",
  PyCharm: "pycharm",
};
function log(text) {
  window?.webContents.send("codedog:log", text);
}
async function job(fn) {
  if (busy) throw Error("请等待当前操作完成");
  busy = true;
  try {
    return await fn();
  } finally {
    busy = false;
  }
}
function handle(name, fn) {
  ipcMain.handle("codedog:" + name, async (event, ...args) => {
    if (
      event.sender !== window?.webContents ||
      event.senderFrame !== window.webContents.mainFrame
    )
      throw Error("无效的调用来源");
    try {
      return { ok: true, data: await fn(...args) };
    } catch (e) {
      return { ok: false, error: e.message };
    }
  });
}
async function editorIcons() {
  if (process.platform !== "darwin") return {};
  const icons = {};
  await Promise.all(
    IDE.map(async (editor) => {
      for (const base of [
        "/Applications",
        path.join(app.getPath("home"), "Applications"),
      ]) {
        const folder = path.join(base, editor + ".app");
        if (!(await exists(folder))) continue;
        try {
          const icon = await app.getFileIcon(folder, { size: "small" });
          if (!icon.isEmpty())
            icons[editor] = icon.resize({ width: 16, height: 16 });
        } catch {}
        break;
      }
    }),
  );
  return icons;
}
async function pick() {
  const r = await dialog.showOpenDialog(window, {
    properties: ["openDirectory", "createDirectory"],
  });
  return r.canceled ? null : r.filePaths[0];
}
async function openProject(id, kind, editorOverride) {
  const p = await store.get(id);
  if (kind === "folder") {
    const error = await shell.openPath(p.path);
    if (error) throw Error(error);
  } else if (kind === "terminal") {
    const launch = terminalLaunch(store.state.terminal || "system", p.path);
    if (launch.url) {
      try {
        await shell.openExternal(launch.url);
      } catch {
        throw Error(
          "无法打开 Warp，请确认已安装 Warp，或在设置中改用系统终端。",
        );
      }
    } else await run(launch.command, launch.args);
  } else if (kind === "ide") {
    const ide = chooseEditor(editorOverride, p.ide, store.state.ide);
    if (process.platform === "darwin") await run("open", ["-a", ide, p.path]);
    else await run(cli[ide], [p.path]);
    await store.transaction(async () => {
      const item = store.state.projects.find((x) => x.id === id);
      item.lastOpened = Date.now();
      await store.save();
    });
  } else if (kind === "repository") {
    let remote = p.remote || (await inspect(p.path)).remote;
    if (/^git@[\w.-]+:[^\s]+$/i.test(remote)) {
      const match = remote.match(/^git@([\w.-]+):(.+)$/i);
      remote = `https://${match[1]}/${match[2]}`;
    } else if (/^ssh:\/\/(?:git@)?[\w.-]+\/[^\s]+$/i.test(remote)) {
      const match = remote.match(/^ssh:\/\/(?:git@)?([\w.-]+)\/(.+)$/i);
      remote = `https://${match[1]}/${match[2]}`;
    }
    remote = remote.replace(/\.git$/i, "");
    if (!/^https:\/\/[^\s]+$/i.test(remote))
      throw Error("这个项目没有可访问的 HTTPS 仓库地址");
    await shell.openExternal(remote);
  } else throw Error("无效的打开方式");
}
// Do not await ready at module scope: Electron waits for ESM evaluation before emitting ready.
app
  .whenReady()
  .then(async () => {
    // Finder-launched apps need the login shell's tool paths. Never evaluate project text in a shell.
    if (process.platform === "darwin" && !process.env.CODEDOG_SKIP_PATH) {
      try {
        const output = await run(
          process.env.SHELL || "/bin/zsh",
          ["-ilc", 'printf "\\nCODEDOG_PATH=%s\\n" "$PATH"'],
          undefined,
          () => {},
          5000,
        );
        const value = output.match(/CODEDOG_PATH=([^\n]+)/)?.[1];
        if (value) process.env.PATH = value;
      } catch {}
    }
    store = new ProjectStore(
      path.join(app.getPath("userData"), "projects.json"),
    );
    try {
      await store.init();
    } catch (e) {
      dialog.showErrorBox("无法启动 codedog", e.message);
      app.quit();
      return;
    }
    nativeTheme.themeSource = store.state.theme || "system";
    nativeTheme.on("updated", () => {
      if (window && !window.isDestroyed())
        window.setBackgroundColor(
          nativeTheme.shouldUseDarkColors ? "#191b23" : "#fafbfc",
        );
    });
    let currentMode = store.state.uiMode === "compact" ? "compact" : "standard";
    let indexWatchers = [];
    const indexTimers = new Map();
    function resetSearchWatchers() {
      for (const watcher of indexWatchers) watcher.close();
      indexWatchers = [];
      for (const project of store.state.projects) {
        try {
          const watcher = watchFiles(
            project.path,
            { persistent: false },
            (_event, filename) => {
              if (!filename || !isSearchSource(filename.toString())) return;
              clearTimeout(indexTimers.get(project.id));
              indexTimers.set(
                project.id,
                setTimeout(async () => {
                  indexTimers.delete(project.id);
                  try {
                    await store.refreshSearchIndex(project.id);
                    window?.webContents.send("codedog:searchIndexUpdated");
                  } catch {}
                }, 350),
              );
            },
          );
          watcher.on("error", () => watcher.close());
          indexWatchers.push(watcher);
        } catch {}
      }
    }
    function resizeMode(mode) {
      if (mode === currentMode || !window || window.isDestroyed()) return;
      currentMode = mode;
      applyWindowMode(window, mode);
    }
    function createWindow() {
      const [width, height] = sizeForMode(currentMode);
      window = new BrowserWindow({
        width,
        height,
        minWidth: width,
        minHeight: height,
        title: "codedog",
        backgroundColor: nativeTheme.shouldUseDarkColors
          ? "#191b23"
          : "#fafbfc",
        titleBarStyle: "hiddenInset",
        trafficLightPosition: { x: 20, y: 17 },
        icon: path.join(here, "../public/icon.png"),
        webPreferences: {
          preload: path.join(here, "preload.cjs"),
          contextIsolation: true,
          nodeIntegration: false,
          sandbox: true,
        },
      });
      window.center();
      window.webContents.on("did-finish-load", () => {
        console.info("[codedog] Window loaded:", window.webContents.getURL());
      });
      window.webContents.on("did-fail-load", (_event, code, description) => {
        console.error("[codedog] Window failed to load:", code, description);
      });
      window.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
      window.webContents.on("will-navigate", (e) => e.preventDefault());
      if (process.env.CODEDOG_DEV_URL === "http://127.0.0.1:5173")
        window.loadURL(process.env.CODEDOG_DEV_URL);
      else window.loadFile(path.join(here, "../dist/index.html"));
    }
    session.defaultSession.setPermissionRequestHandler((_w, _p, callback) =>
      callback(false),
    );
    if (app.dock)
      app.dock.setIcon(
        nativeImage.createFromPath(path.join(here, "../public/icon.png")),
      );
    handle("state", async () => ({
      uiMode: store.state.uiMode || "standard",
      root: store.state.root,
      ide: store.state.ide,
      groups: store.groups(),
      theme: store.state.theme || "system",
      terminal: store.state.terminal || "system",
      savedFilters: store.state.savedFilters || [],
      projects: await store.list(),
    }));
    handle("setMode", async (mode) => {
      await store.setMode(mode);
      resizeMode(mode);
    });
    handle("setSavedFilters", (filters) => store.setSavedFilters(filters));
    handle("hideLauncher", async () => {
      if (currentMode === "compact") window.hide();
    });
    handle("pickFolder", pick);
    handle("setRoot", (folder) => job(() => store.setRoot(folder)));
    handle("createGroup", (name) => store.createGroup(name));
    handle("setTheme", async (theme) => {
      await store.setTheme(theme);
      nativeTheme.themeSource = theme;
    });
    handle("setTerminal", (terminal) => store.setTerminal(terminal));
    handle("setIde", async (ide) => {
      if (!IDE.includes(ide)) throw Error("无效 IDE");
      return store.transaction(async () => {
        store.state.ide = ide;
        await store.save();
      });
    });
    handle("import", (input) =>
      job(async () => {
        const result = await store.importProject(input, log);
        resetSearchWatchers();
        return result;
      }),
    );
    handle("scan", (folder) => store.scan(folder));
    handle("refreshSearchIndex", (id) =>
      job(() => store.refreshSearchIndex(id)),
    );
    handle("update", (id, patch) => store.update(id, patch));
    handle("forget", (id) =>
      job(async () => {
        const result = await store.forget(id);
        resetSearchWatchers();
        return result;
      }),
    );
    handle("open", openProject);
    handle("projectMenu", async (id) => {
      const project = await store.get(id);
      const icons = await editorIcons();
      const selection = await new Promise((resolve) => {
        let selected = null;
        const menu = Menu.buildFromTemplate(
          projectMenuTemplate(
            chooseEditor(undefined, project.ide, store.state.ide),
            (action) => {
              selected = action;
            },
            icons,
          ),
        );
        menu.popup({ window, callback: () => resolve(selected) });
      });
      if (!selection) return { opened: false };
      await openProject(id, selection.kind, selection.editor);
      return { opened: true };
    });
    handle("copy", async (id) =>
      clipboard.writeText((await store.get(id)).path),
    );
    handle("storage", async (id) => diskUsage((await store.get(id)).path));
    handle("storageBatch", async (ids) => {
      if (!Array.isArray(ids) || ids.length > 500)
        throw Error("项目列表格式无效");
      const unique = [...new Set(ids)];
      const results = {};
      let index = 0;
      await Promise.all(
        Array.from({ length: Math.min(4, unique.length) }, async () => {
          while (index < unique.length) {
            const id = unique[index++];
            results[id] = await diskUsage((await store.get(id)).path);
          }
        }),
      );
      return results;
    });
    handle("cleanupDependencies", (ids) =>
      job(async () => {
        if (!Array.isArray(ids) || !ids.length || ids.length > 500)
          throw Error("请选择要清理的项目");
        const projects = await Promise.all(
          [...new Set(ids)].map((id) => store.get(id)),
        );
        const plans = await Promise.all(
          projects.map(async (project) => ({
            project,
            plan: await dependencyCleanupPlan(project.path),
          })),
        );
        const reclaimable = plans.reduce(
          (total, item) => total + item.plan.size,
          0,
        );
        const directories = plans.reduce(
          (total, item) => total + item.plan.directories.length,
          0,
        );
        if (!directories)
          return { canceled: false, reclaimed: 0, projects: [] };
        const format = (bytes) =>
          bytes >= 1073741824
            ? `${(bytes / 1073741824).toFixed(1)} GB`
            : `${(bytes / 1048576).toFixed(1)} MB`;
        const cleanablePlans = plans.filter(
          (item) => item.plan.directories.length,
        );
        const preview = cleanablePlans
          .slice(0, 12)
          .map(
            ({ project, plan }) =>
              `${project.name} · ${format(plan.size)} · ${plan.directories.map((item) => item.relativePath).join(", ")}`,
          );
        if (cleanablePlans.length > 12)
          preview.push(`以及其他 ${cleanablePlans.length - 12} 个项目`);
        const answer = await dialog.showMessageBox(window, {
          type: "warning",
          title: "清理项目依赖",
          message: `清理 ${directories} 个依赖目录？`,
          detail: `${preview.join("\n")}\n\n预计释放 ${format(reclaimable)}。源码与锁文件会保留，需要时可重新安装依赖。`,
          buttons: ["取消", "清理依赖"],
          defaultId: 0,
          cancelId: 0,
          noLink: true,
        });
        if (answer.response !== 1) return { canceled: true };
        const cleaned = [];
        for (const project of projects) {
          const result = await cleanProjectDependencies(project.path);
          if (result.removed) cleaned.push({ id: project.id, ...result });
        }
        const reclaimed = cleaned.reduce(
          (total, item) => total + item.reclaimed,
          0,
        );
        log(
          `已清理 ${cleaned.length} 个项目的依赖，释放约 ${format(reclaimed)}\n`,
        );
        return { canceled: false, reclaimed, projects: cleaned };
      }),
    );
    handle("environment", async (id) => {
      const p = await store.get(id);
      const info = await inspect(p.path);
      const output = [];
      for (const env of info.environments) {
        const command =
          env.stack === "Node.js"
            ? "node"
            : env.stack === "Go"
              ? "go"
              : process.platform === "win32"
                ? "python"
                : "python3";
        const version = await run(
          command,
          [env.stack === "Go" ? "version" : "--version"],
          p.path,
        ).catch((e) => e.message);
        const managerVersion = await run(
          env.manager === "pip" ? command : env.manager,
          env.manager === "pip"
            ? ["-m", "pip", "--version"]
            : env.manager === "go"
              ? ["version"]
              : ["--version"],
          p.path,
        ).catch((e) => e.message);
        const location =
          env.stack === "Go"
            ? await run("go", ["env", "GOMODCACHE"], p.path).catch(
                () => env.location,
              )
            : path.join(p.path, env.location);
        output.push({ ...env, version, managerVersion, location });
      }
      return output;
    });
    handle("install", async (id, stack) =>
      job(async () => {
        const p = await store.get(id);
        const env = (await inspect(p.path)).environments.find(
          (e) => e.stack === stack,
        );
        if (!env) throw Error("未找到对应开发环境");
        if (env.manifest === "go.work")
          throw Error("请导入具体 Go 模块后安装依赖");
        const steps = installPlan(env, p.path);
        const answer = await dialog.showMessageBox(window, {
          type: "question",
          title: "安装项目依赖",
          message: `为 ${p.name} 安装 ${stack} 依赖？`,
          detail:
            steps.map((s) => `${s.command} ${s.args.join(" ")}`).join("\n") +
            "\n\n会连接软件源、更新依赖文件，并可能执行项目或依赖包中的安装脚本。",
          buttons: ["取消", "安装依赖"],
          defaultId: 0,
          cancelId: 0,
        });
        if (answer.response !== 1) return { canceled: true };
        for (const step of steps) {
          log(`$ ${step.command} ${step.args.join(" ")}\n`);
          await run(step.command, step.args, p.path, log, 600000, step.env);
        }
        log("依赖操作完成\n");
        return { canceled: false };
      }),
    );
    handle("backup", async () => {
      const r = await dialog.showSaveDialog(window, {
        defaultPath: "codedog-backup.json",
        filters: [{ name: "JSON", extensions: ["json"] }],
      });
      if (!r.canceled && r.filePath) {
        await fs.writeFile(r.filePath, JSON.stringify(store.state, null, 2));
        return true;
      }
      return false;
    });
    handle("openRoot", async () => {
      if (!store.state.root) return;
      const error = await shell.openPath(store.state.root);
      if (error) throw Error(error);
    });
    createWindow();
    resetSearchWatchers();
    const launcherShortcut = "CommandOrControl+Shift+Space";
    if (
      !globalShortcut.register(launcherShortcut, async () => {
        if (
          window?.isVisible() &&
          window.isFocused() &&
          currentMode === "compact"
        ) {
          window.hide();
          return;
        }
        if (!window || window.isDestroyed()) createWindow();
        if (currentMode !== "compact") {
          await store.setMode("compact");
          resizeMode("compact");
          window.webContents.send("codedog:mode", "compact");
        }
        window.show();
        window.focus();
        if (process.platform === "darwin") app.focus({ steal: true });
      })
    )
      console.warn(`[codedog] 无法注册全局快捷键 ${launcherShortcut}`);
    app.on("will-quit", () => {
      for (const watcher of indexWatchers) watcher.close();
      for (const timer of indexTimers.values()) clearTimeout(timer);
      globalShortcut.unregisterAll();
    });
    setupAutoUpdates({ app, autoUpdater, dialog });
    app.on("activate", () => {
      if (BrowserWindow.getAllWindows().length === 0) createWindow();
      else if (window && !window.isVisible()) {
        window.show();
        window.focus();
      }
    });
    app.on("window-all-closed", () => {
      if (process.platform !== "darwin") app.quit();
    });
  })
  .catch((error) => {
    console.error("[codedog] Startup failed:", error);
    dialog.showErrorBox("codedog 启动失败", error.stack || error.message);
    app.exit(1);
  });
