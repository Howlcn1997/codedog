import { setWindowBlurRadius } from "./window-effects.mjs";
import { normalizeCompactAppearance } from "./compact-appearance.mjs";

export const windowSizes = {
  compact: [640, 420],
  standard: [1050, 700],
};

export function sizeForMode(mode) {
  const size = windowSizes[mode];
  if (!size) throw Error("无效的界面模式");
  return size;
}

export function applyWindowAppearance(
  window,
  mode,
  dark,
  platform = process.platform,
  appearance,
  applyBlur = setWindowBlurRadius,
) {
  const glass = mode === "compact" && platform === "darwin";
  if (platform === "darwin") {
    window.setVibrancy(null);
    window.setWindowButtonVisibility(mode !== "compact");
  }
  window.setBackgroundColor(glass ? "#00000000" : dark ? "#191b23" : "#fafbfc");
  if (platform === "darwin") {
    applyBlur(
      window,
      glass ? normalizeCompactAppearance(appearance).blurRadius : 0,
      glass,
    );
  }
}

export function applyWindowMode(window, mode) {
  const [width, height] = sizeForMode(mode);
  const resizeAndCenter = () => {
    window.setMinimumSize(width, height);
    window.setSize(width, height);
    window.center();
  };

  if (window.isFullScreen()) {
    window.once("leave-full-screen", resizeAndCenter);
    window.setFullScreen(false);
    return;
  }
  if (window.isMaximized()) window.unmaximize();
  resizeAndCenter();
}
