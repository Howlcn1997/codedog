import { spawn } from "node:child_process";
import { watch } from "node:fs";
import path from "node:path";
import { createServer } from "vite";
import electron from "electron";

const server = await createServer();
await server.listen();
const env = { ...process.env, CODEDOG_DEV_URL: "http://127.0.0.1:5173" };
delete env.ELECTRON_RUN_AS_NODE;
let child;
let closing = false;
let restarting = false;
let pendingRestart = false;
let timer;

function launch() {
  child = spawn(electron, ["."], { stdio: "inherit", env });
  console.info(`[codedog] Desktop process started (PID ${child.pid})`);
  child.once("error", (error) => {
    console.error(error);
    shutdown(1);
  });
  child.once("exit", (code, signal) => {
    if (!closing && !restarting) shutdown(code ?? (signal ? 1 : 0));
  });
}
async function stopChild() {
  const current = child;
  if (!current || current.exitCode !== null || current.signalCode !== null)
    return;
  await new Promise((resolve) => {
    const timeout = setTimeout(() => current.kill("SIGKILL"), 5000);
    current.once("exit", () => {
      clearTimeout(timeout);
      resolve();
    });
    current.kill("SIGTERM");
  });
}
async function restart() {
  pendingRestart = true;
  if (restarting || closing) return;
  restarting = true;
  try {
    while (pendingRestart && !closing) {
      pendingRestart = false;
      console.info(
        "[codedog] Main/preload changed; restarting desktop process…",
      );
      await stopChild();
      if (!closing) launch();
    }
  } finally {
    restarting = false;
  }
}
const watcher = watch(
  path.resolve("electron"),
  { recursive: true },
  (_event, file) => {
    if (!file || !/\.(?:mjs|cjs|js)$/.test(file)) return;
    clearTimeout(timer);
    timer = setTimeout(
      () =>
        restart().catch((error) => {
          console.error(error);
          shutdown(1);
        }),
      350,
    );
  },
);
async function shutdown(code = 0) {
  if (closing) return;
  closing = true;
  clearTimeout(timer);
  watcher.close();
  await stopChild();
  await server.close();
  process.exit(code);
}
process.on("SIGINT", () => shutdown());
process.on("SIGTERM", () => shutdown());
launch();
