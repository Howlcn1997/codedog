// Keep the macOS launcher alive independently of its window and Dock entry.
export function setupBackground({
  app,
  autoUpdater,
  powerMonitor,
  Tray,
  Menu,
  nativeImage,
  getWindow,
  showWindow,
  openLauncher,
}) {
  let quitting = false;
  let lastDockHide = 0;
  let dockHideTimer;
  const cancelHide = () => clearTimeout(dockHideTimer);
  const hideDock = () => {
    cancelHide();
    // Electron/macOS ignores dock.hide calls less than a second apart.
    const delay = 1100 - (Date.now() - lastDockHide);
    if (delay > 0) {
      dockHideTimer = setTimeout(hideDock, delay);
      dockHideTimer.unref?.();
      return;
    }
    lastDockHide = Date.now();
    app.dock?.hide();
  };
  const hide = () => {
    const window = getWindow();
    if (window && !window.isDestroyed()) {
      if (window.isFullScreen()) {
        window.once("leave-full-screen", hide);
        window.setFullScreen(false);
        return;
      }
      window.hide();
    }
    hideDock();
  };
  const prepareToQuit = () => {
    cancelHide();
    quitting = true;
  };
  const quit = () => {
    prepareToQuit();
    app.quit();
  };

  // A monochrome paw at 2x resolution; template rendering adapts to the menu bar.
  const size = 36;
  const pixels = Buffer.alloc(size * size * 4);
  const ellipses = [
    [18, 24, 9, 7],
    [6, 15, 4, 5],
    [14, 8, 4, 5],
    [23, 8, 4, 5],
    [30, 15, 4, 5],
  ];
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      let coverage = 0;
      for (const dx of [0.25, 0.75])
        for (const dy of [0.25, 0.75]) {
          if (
            ellipses.some(
              ([cx, cy, rx, ry]) =>
                ((x + dx - cx) / rx) ** 2 + ((y + dy - cy) / ry) ** 2 <= 1,
            )
          )
            coverage++;
        }
      pixels[(y * size + x) * 4 + 3] = Math.round((255 * coverage) / 4);
    }
  }
  const icon = nativeImage.createFromBitmap(pixels, {
    width: size,
    height: size,
    scaleFactor: 2,
  });
  icon.setTemplateImage(true);
  const tray = new Tray(icon);
  tray.setToolTip("codedog · 项目启动器");
  tray.setContextMenu(
    Menu.buildFromTemplate([
      { label: "显示 codedog", click: showWindow },
      { label: "打开项目启动器", click: openLauncher },
      { label: "后台运行（隐藏 Dock 图标）", click: hide },
      { type: "separator" },
      { label: "彻底退出 codedog", click: quit },
    ]),
  );
  app.on("before-quit", (event) => {
    if (quitting) return;
    event.preventDefault();
    hide();
  });
  autoUpdater.on("before-quit-for-update", prepareToQuit);
  powerMonitor.on("shutdown", prepareToQuit);
  app.on("will-quit", () => tray.destroy());
  return {
    hide,
    cancelHide,
    prepareToQuit,
    attach(window) {
      window.on("close", (event) => {
        if (quitting) return;
        event.preventDefault();
        hide();
      });
    },
  };
}
