import fs from "node:fs/promises";
import path from "node:path";
import { spawn } from "node:child_process";
const root = process.cwd();
const cache = path.join(root, "work", "builder-cache");
await fs.mkdir(cache, { recursive: true });
await fs.writeFile(path.join(cache, "package.json"), '{"type":"commonjs"}\n');
process.env.electron_config_cache = path.join(root, "work", "electron-cache");
const { default: electron } = await import("electron");
const env = {
  ...process.env,
  ELECTRON_BUILDER_CACHE: cache,
  CSC_IDENTITY_AUTO_DISCOVERY: "false",
};
const electronDist = path.join(root, "node_modules", "electron", "dist");
const child = spawn(
  process.execPath,
  [
    "node_modules/electron-builder/cli.js",
    ...(process.argv.includes("--dir") ? ["--dir"] : []),
    "--config.electronDist=" + electronDist,
  ],
  { stdio: "inherit", env },
);
child.on("exit", (code) => process.exit(code || 0));
