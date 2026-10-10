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

test("compact blur is independent from opacity and resets in standard mode", async () => {
  const { applyWindowAppearance } = await import("../electron/window-mode.mjs");
  const calls = [];
  const window = {
    setVibrancy: (v) => calls.push(["vibrancy", v]),
    setWindowButtonVisibility: (v) => calls.push(["buttons", v]),
    setBackgroundColor: (v) => calls.push(["background", v]),
  };
  const blur = (_window, radius, compact) =>
    calls.push(["blur", radius, compact]);
  for (const dark of [false, true]) {
    for (const opacity of [0, 50, 100]) {
      applyWindowAppearance(
        window,
        "compact",
        dark,
        "darwin",
        { opacity, blurRadius: 40 },
        blur,
      );
      assert.deepEqual(calls.splice(0), [
        ["vibrancy", null],
        ["buttons", false],
        ["background", "#00000000"],
        ["blur", 40, true],
      ]);
    }
  }
  applyWindowAppearance(window, "standard", true, "darwin", undefined, blur);
  assert.deepEqual(calls.splice(0), [
    ["vibrancy", null],
    ["buttons", true],
    ["background", "#191b23"],
    ["blur", 0, false],
  ]);
  applyWindowAppearance(window, "compact", false, "win32", undefined, blur);
  assert.deepEqual(calls.splice(0), [["background", "#fafbfc"]]);
  applyWindowAppearance(
    window,
    "compact",
    false,
    "darwin",
    { opacity: 20, blurRadius: 0 },
    blur,
  );
  assert.ok(
    calls.some(
      ([type, value, compact]) =>
        type === "blur" && value === 0 && compact === true,
    ),
  );
});

test("older appearance settings migrate without persisting guessed material radii", async () => {
  const { normalizeCompactAppearance: normalize } =
    await import("../electron/compact-appearance.mjs");
  assert.deepEqual(normalize(), { opacity: 70, blurRadius: 20 });
  assert.deepEqual(normalize({ transparency: 80, material: "off" }), {
    opacity: 20,
    blurRadius: 0,
  });
  assert.deepEqual(normalize({ transparency: 30, material: "menu" }), {
    opacity: 70,
    blurRadius: 20,
  });
  assert.deepEqual(normalize({ opacity: 0, blurRadius: 80 }), {
    opacity: 0,
    blurRadius: 80,
  });
  assert.deepEqual(normalize({ opacity: NaN, blurRadius: -1 }), {
    opacity: 70,
    blurRadius: 20,
  });
});
