import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

test("main module finishes evaluation before Electron emits ready", async (t) => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "codedog-startup-"));
  t.after(() => fs.rm(dir, { recursive: true, force: true }));
  // Electron emits ready only after its entry module finishes evaluating.
  // Keep ready pending: a top-level await would deadlock this import.
  await fs.writeFile(
    path.join(dir, "electron.mjs"),
    `
    export const app={setName(){},setPath(){},whenReady(){return new Promise(()=>{});}};
    export const BrowserWindow=class {},autoUpdater={},globalShortcut={};
    export const ipcMain={},dialog={},shell={},clipboard={},session={},nativeImage={},nativeTheme={},Menu={};
  `,
  );
  const source = (
    await fs.readFile(new URL("../electron/main.mjs", import.meta.url), "utf8")
  )
    .replace('from "electron"', 'from "./electron.mjs"')
    .replace(
      'from "./core.mjs"',
      `from ${JSON.stringify(new URL("../electron/core.mjs", import.meta.url).href)}`,
    );
  await fs.writeFile(
    path.join(dir, "main.mjs"),
    source
      .replace(
        'from "./terminal.mjs"',
        `from ${JSON.stringify(new URL("../electron/terminal.mjs", import.meta.url).href)}`,
      )
      .replace(
        'from "./project-menu.mjs"',
        `from ${JSON.stringify(new URL("../electron/project-menu.mjs", import.meta.url).href)}`,
      )
      .replace(
        'from "./updates.mjs"',
        `from ${JSON.stringify(new URL("../electron/updates.mjs", import.meta.url).href)}`,
      )
      .replace(
        'from "./window-mode.mjs"',
        `from ${JSON.stringify(new URL("../electron/window-mode.mjs", import.meta.url).href)}`,
      ),
  );
  let timer;
  try {
    const result = await Promise.race([
      import(pathToFileURL(path.join(dir, "main.mjs")).href).then(
        () => "evaluated",
      ),
      new Promise((resolve) => {
        timer = setTimeout(() => resolve("deadlocked"), 1500);
      }),
    ]);
    assert.equal(
      result,
      "evaluated",
      "Entry module must not await app.whenReady() at top level",
    );
  } finally {
    clearTimeout(timer);
  }
});
