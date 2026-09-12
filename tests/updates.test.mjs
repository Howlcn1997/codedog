import test from "node:test";
import assert from "node:assert/strict";
import { setupAutoUpdates, updateFeed } from "../electron/updates.mjs";

test("update feed includes the release repository, platform, architecture and version", () => {
  assert.equal(
    updateFeed("1.2.3", "darwin", "arm64"),
    "https://update.electronjs.org/Howlcn1997/codedog/darwin-arm64/1.2.3",
  );
});

test("packaged macOS builds check now and install a downloaded update on confirmation", async () => {
  const listeners = new Map();
  let checked = 0;
  let installed = 0;
  const autoUpdater = {
    setFeedURL(value) {
      assert.deepEqual(value, {
        url: "https://update.electronjs.org/Howlcn1997/codedog/darwin-x64/0.1.0",
      });
    },
    on(name, callback) {
      listeners.set(name, callback);
    },
    checkForUpdates() {
      checked += 1;
      return Promise.resolve();
    },
    quitAndInstall() {
      installed += 1;
    },
  };
  const timer = setupAutoUpdates({
    app: { isPackaged: true, getVersion: () => "0.1.0" },
    autoUpdater,
    dialog: { showMessageBox: async () => ({ response: 1 }) },
    platform: "darwin",
    arch: "x64",
    interval: 60_000,
  });
  timer.unref();
  assert.equal(checked, 1);
  await listeners.get("update-downloaded")({}, "", "v0.2.0");
  assert.equal(installed, 1);
  clearInterval(timer);
});

test("development and unsupported platform builds do not configure updates", () => {
  const autoUpdater = {
    setFeedURL() {
      assert.fail("must not configure an update feed");
    },
  };
  assert.equal(
    setupAutoUpdates({
      app: { isPackaged: false },
      autoUpdater,
      dialog: {},
      platform: "darwin",
    }),
    null,
  );
  assert.equal(
    setupAutoUpdates({
      app: { isPackaged: true },
      autoUpdater,
      dialog: {},
      platform: "linux",
    }),
    null,
  );
});
