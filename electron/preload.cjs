const { contextBridge, ipcRenderer } = require("electron");
const methods = [
  "state",
  "setMode",
  "pickFolder",
  "setRoot",
  "setIde",
  "setTerminal",
  "setTheme",
  "createGroup",
  "import",
  "scan",
  "update",
  "forget",
  "open",
  "projectMenu",
  "copy",
  "storage",
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
contextBridge.exposeInMainWorld("codedog", api);
