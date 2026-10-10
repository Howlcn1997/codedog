import { renameSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import path from "node:path";

if (process.platform === "darwin") {
  const require = createRequire(import.meta.url);
  const headers = path.join(
    path.dirname(require.resolve("node-api-headers/package.json")),
    "include",
  );
  const source = fileURLToPath(
    new URL("../electron/native/window-effects.mm", import.meta.url),
  );
  const output = fileURLToPath(
    new URL("../electron/native/window-effects.node", import.meta.url),
  );
  const temporaryOutput = `${output}.${process.pid}.build`;
  const sdk = spawnSync("xcrun", ["--sdk", "macosx", "--show-sdk-path"], {
    encoding: "utf8",
  });
  if (sdk.status !== 0) throw new Error(sdk.stderr || "macOS SDK not found");
  const result = spawnSync(
    "xcrun",
    [
      "clang++",
      "-isysroot",
      sdk.stdout.trim(),
      "-std=c++17",
      "-fobjc-arc",
      "-DNAPI_VERSION=8",
      "-arch",
      "arm64",
      "-arch",
      "x86_64",
      "-mmacosx-version-min=11.0",
      "-bundle",
      "-undefined",
      "dynamic_lookup",
      "-framework",
      "AppKit",
      "-framework",
      "QuartzCore",
      "-I",
      headers,
      source,
      "-o",
      temporaryOutput,
    ],
    { stdio: "inherit" },
  );
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status || 1);
  renameSync(temporaryOutput, output);
  console.log("Built universal macOS window effects bridge");
}
