import test from "node:test";
import assert from "node:assert/strict";
import { applyWindowMode, sizeForMode } from "../electron/window-mode.mjs";

function fakeWindow({ fullscreen = false, maximized = false } = {}) {
  const calls = [];
  let leaveFullscreen;
  return {
    calls,
    isFullScreen: () => fullscreen,
    isMaximized: () => maximized,
    once: (event, callback) => {
      calls.push(["once", event]);
      leaveFullscreen = callback;
    },
    setFullScreen: (value) => calls.push(["setFullScreen", value]),
    unmaximize: () => calls.push(["unmaximize"]),
    setMinimumSize: (...size) => calls.push(["setMinimumSize", ...size]),
    setSize: (...size) => calls.push(["setSize", ...size]),
    center: () => calls.push(["center"]),
    leaveFullscreen: () => leaveFullscreen?.(),
  };
}

test("each UI mode uses its minimum size and centers the window", () => {
  assert.deepEqual(sizeForMode("compact"), [640, 420]);
  assert.deepEqual(sizeForMode("standard"), [1050, 700]);
  assert.throws(() => sizeForMode("unknown"), /无效/);

  const compact = fakeWindow();
  applyWindowMode(compact, "compact");
  assert.deepEqual(compact.calls, [
    ["setMinimumSize", 640, 420],
    ["setSize", 640, 420],
    ["center"],
  ]);
});

test("mode switching exits maximized or fullscreen state before centering", () => {
  const maximized = fakeWindow({ maximized: true });
  applyWindowMode(maximized, "standard");
  assert.deepEqual(maximized.calls, [
    ["unmaximize"],
    ["setMinimumSize", 1050, 700],
    ["setSize", 1050, 700],
    ["center"],
  ]);

  const fullscreen = fakeWindow({ fullscreen: true });
  applyWindowMode(fullscreen, "compact");
  assert.deepEqual(fullscreen.calls, [
    ["once", "leave-full-screen"],
    ["setFullScreen", false],
  ]);
  fullscreen.leaveFullscreen();
  assert.deepEqual(fullscreen.calls.slice(2), [
    ["setMinimumSize", 640, 420],
    ["setSize", 640, 420],
    ["center"],
  ]);
});
