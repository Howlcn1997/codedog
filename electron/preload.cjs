const { contextBridge, ipcRenderer } = require("electron");
const methods = [
  "state",
  "setMode",
  "setSavedFilters",
  "setLauncherShortcut",
  "cliStatus",
  "installCli",
  "hideLauncher",
  "pickFolder",
  "setRoot",
  "setIde",
  "setTerminal",
  "setTheme",
  "createGroup",
  "import",
  "scan",
  "refreshSearchIndex",
  "update",
  "forget",
  "open",
  "projectMenu",
  "copy",
  "storage",
  "storageBatch",
  "cleanupDependencies",
  "environment",
  "install",
  "backup",
  "openRoot",
];
const api = {};
for (const method of methods)
  api[method] = async (...args) => {
    const response = await ipcRenderer.invoke("codedog:" + method, ...args);
    if (!response.ok) throw new Error(response.error);
    return response.data;
  };
api.onLog = (callback) => {
  const listener = (_event, text) => callback(text);
  ipcRenderer.on("codedog:log", listener);
  return () => ipcRenderer.removeListener("codedog:log", listener);
};
api.onModeChange = (callback) => {
  const listener = (_event, mode) => callback(mode);
  ipcRenderer.on("codedog:mode", listener);
  return () => ipcRenderer.removeListener("codedog:mode", listener);
};
api.onSearchIndexUpdated = (callback) => {
  const listener = () => callback();
  ipcRenderer.on("codedog:searchIndexUpdated", listener);
  return () =>
    ipcRenderer.removeListener("codedog:searchIndexUpdated", listener);
};
contextBridge.exposeInMainWorld("codedog", api);
