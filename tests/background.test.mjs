import test from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { setupBackground } from "../electron/background.mjs";

function fixture() {
  const app = new EventEmitter();
  const autoUpdater = new EventEmitter();
  const powerMonitor = new EventEmitter();
  const window = new EventEmitter();
  let dockHidden = false;
  let hidden = false;
  let exited = false;
  let destroyed = false;
  let menu;
  const event = () => ({
    prevented: false,
    preventDefault() {
      this.prevented = true;
    },
  });
  Object.assign(window, {
    isDestroyed: () => false,
    isFullScreen: () => false,
    hide() {
      hidden = true;
    },
  });
  app.dock = {
    hide() {
      dockHidden = true;
    },
  };
  app.quit = () => {
    const before = event();
    app.emit("before-quit", before);
    if (before.prevented) return;
    const close = event();
    window.emit("close", close);
    if (close.prevented) return;
    exited = true;
    app.emit("will-quit");
  };
  const background = setupBackground({
    app,
    autoUpdater,
    powerMonitor,
    getWindow: () => window,
    showWindow: () => {
      hidden = false;
      dockHidden = false;
    },
    openLauncher: () => {
      hidden = false;
    },
    Menu: { buildFromTemplate: (value) => value },
    nativeImage: { createFromBitmap: () => ({ setTemplateImage() {} }) },
    Tray: class {
      setToolTip() {}
      setContextMenu(value) {
        menu = value;
      }
      destroy() {
        destroyed = true;
      }
    },
  });
  background.attach(window);
  return {
    app,
    autoUpdater,
    window,
    background,
    event,
    menu,
    state: () => ({ dockHidden, hidden, exited, destroyed }),
  };
}

test("closing the window keeps the app alive and hides its Dock entry", () => {
  const f = fixture();
  const close = f.event();
  f.window.emit("close", close);
  assert.equal(close.prevented, true);
  assert.deepEqual(f.state(), {
    hidden: true,
    dockHidden: true,
    exited: false,
    destroyed: false,
  });
  f.menu[0].click();
  assert.equal(f.state().hidden, false);
});

test("Dock quit backgrounds the app; explicit tray quit closes it and destroys the tray", () => {
  const f = fixture();
  f.app.quit();
  assert.equal(f.state().exited, false);
  assert.equal(f.state().dockHidden, true);
  f.menu.at(-1).click();
  assert.equal(f.state().exited, true);
  assert.equal(f.state().destroyed, true);
});

test("update install may close windows before Electron emits before-quit", () => {
  const f = fixture();
  f.background.prepareToQuit();
  const close = f.event();
  f.window.emit("close", close);
  assert.equal(close.prevented, false);
  f.app.quit();
  assert.equal(f.state().exited, true);
});

test("native updater event also allows a real exit", () => {
  const f = fixture();
  f.autoUpdater.emit("before-quit-for-update");
  f.app.quit();
  assert.equal(f.state().exited, true);
});

test("fullscreen windows leave fullscreen before backgrounding", () => {
  const f = fixture();
  f.window.isFullScreen = () => true;
  f.window.setFullScreen = (value) => {
    assert.equal(value, false);
  };
  f.background.hide();
  assert.equal(f.state().hidden, false);
  f.window.isFullScreen = () => false;
  f.window.emit("leave-full-screen");
  assert.equal(f.state().hidden, true);
  assert.equal(f.state().dockHidden, true);
});

test("rapid hide/show cycles defer Dock hiding and reopening cancels the pending hide", (t) => {
  t.mock.timers.enable({ apis: ["Date", "setTimeout"], now: 2000 });
  const f = fixture();
  f.background.hide();
  f.menu[0].click();
  f.background.hide();
  assert.equal(f.state().dockHidden, false);
  t.mock.timers.tick(1100);
  assert.equal(f.state().dockHidden, true);
  f.menu[0].click();
  f.background.hide();
  f.background.cancelHide();
  f.menu[0].click();
  t.mock.timers.tick(1100);
  assert.equal(f.state().dockHidden, false);
});
