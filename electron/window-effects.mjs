import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
let bridge;
let blurError;
export function getWindowBlurError() {
  return blurError;
}

export function setWindowBlurRadius(window, radius, compact = radius > 0) {
  return applyEffect("setBlurRadius", window, radius, compact);
}

export function refreshWindowBlur(window, radius) {
  return applyEffect("refreshBlur", window, radius, radius > 0);
}

function applyEffect(method, window, radius, compact) {
  try {
    bridge ||= require("./native/window-effects.node");
    bridge[method](window.getNativeWindowHandle(), radius, compact);
    blurError = undefined;
    return true;
  } catch (error) {
    blurError = `窗口模糊暂不可用：${error.message}`;
    console.warn(blurError);
    return false;
  }
}
