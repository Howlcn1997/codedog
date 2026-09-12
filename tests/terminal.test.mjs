import test from "node:test";
import assert from "node:assert/strict";
import { terminalLaunch } from "../electron/terminal.mjs";
test("system terminal opens project directory as a separate argument", () => {
  const folder = "/Users/developer/My Projects/a;test";
  assert.deepEqual(terminalLaunch("system", folder, "darwin"), {
    command: "open",
    args: ["-a", "Terminal", folder],
  });
});
test("Warp receives the exact directory through its documented URI without query injection", () => {
  const folder = "/Users/developer/项目 #1 & test?x=2";
  const launch = terminalLaunch("warp", folder);
  const url = new URL(launch.url);
  assert.equal(url.protocol, "warp:");
  assert.equal(url.hostname, "action");
  assert.equal(url.pathname, "/new_window");
  assert.equal(url.searchParams.get("path"), folder);
  assert.equal([...url.searchParams].length, 1);
  assert.throws(() => terminalLaunch("arbitrary", folder), /不支持/);
});
