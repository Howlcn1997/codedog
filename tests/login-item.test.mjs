import test from "node:test";
import assert from "node:assert/strict";
import { createLoginItemSettings } from "../electron/login-item.mjs";

function fixture(platform = "darwin") {
  let settings = { openAtLogin: false, executableWillLaunchAtLogin: false };
  const writes = [];
  const app = {
    isPackaged: true,
    getLoginItemSettings: () => settings,
    setLoginItemSettings(value) {
      writes.push(value);
      settings = {
        openAtLogin: value.openAtLogin,
        executableWillLaunchAtLogin: value.openAtLogin,
      };
    },
  };
  return {
    app,
    writes,
    api: createLoginItemSettings(app, platform),
    systemChange: (value) => {
      settings = value;
    },
  };
}

for (const platform of ["darwin", "win32"]) {
  test(`${platform}: enable, disable and read external system changes`, () => {
    const { api, writes, systemChange } = fixture(platform);
    assert.equal(api.get().enabled, false);
    assert.equal(api.set(true).enabled, true);
    assert.equal(api.set(false).enabled, false);
    assert.deepEqual(writes, [{ openAtLogin: true }, { openAtLogin: false }]);
    systemChange({ openAtLogin: true, executableWillLaunchAtLogin: true });
    assert.equal(api.get().enabled, true);
  });
}

test("development builds and unsupported platforms never write login items", () => {
  for (const platform of ["darwin", "win32", "linux"]) {
    const { app, api, writes } = fixture(platform);
    if (platform !== "linux") app.isPackaged = false;
    assert.equal(api.get().supported, false);
    assert.throws(() => api.set(true));
    assert.deepEqual(writes, []);
  }
});

test("reject invalid IPC input before changing system settings", () => {
  const { api, writes } = fixture();
  for (const value of [null, 1, "true", {}])
    assert.throws(() => api.set(value), /无效/);
  assert.deepEqual(writes, []);
});

test("report silent system failure and propagate native errors", () => {
  const { app, api } = fixture();
  app.setLoginItemSettings = () => {};
  assert.throws(() => api.set(true), /未生效/);
  app.setLoginItemSettings = () => {
    throw Error("permission denied");
  };
  assert.throws(() => api.set(true), /permission denied/);
});

test("show macOS approval requirement and Windows disabled startup item", () => {
  const mac = fixture();
  mac.systemChange({ openAtLogin: false, status: "requires-approval" });
  assert.match(mac.api.get().reason, /登录项/);
  const win = fixture("win32");
  win.systemChange({ openAtLogin: true, executableWillLaunchAtLogin: false });
  assert.equal(win.api.get().enabled, false);
  assert.match(win.api.get().reason, /系统禁用/);
});
