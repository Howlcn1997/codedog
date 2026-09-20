const UPDATE_SERVER = "https://update.electronjs.org";
const REPOSITORY = "Howlcn1997/codedog";
const TEN_MINUTES = 10 * 60 * 1000;

export function updateFeed(version, platform, arch) {
  return `${UPDATE_SERVER}/${REPOSITORY}/${platform}-${arch}/${version}`;
}

export function setupAutoUpdates({
  app,
  autoUpdater,
  dialog,
  platform = process.platform,
  arch = process.arch,
  interval = TEN_MINUTES,
  logger = console,
  beforeInstall = () => {},
}) {
  if (!app.isPackaged || !["darwin", "win32"].includes(platform)) return null;

  autoUpdater.setFeedURL({ url: updateFeed(app.getVersion(), platform, arch) });
  autoUpdater.on("error", (error) =>
    logger.error("[codedog] Update check failed:", error),
  );
  autoUpdater.on("update-downloaded", async (_event, _notes, releaseName) => {
    const answer = await dialog.showMessageBox({
      type: "info",
      title: "codedog 更新已就绪",
      message: `新版本 ${releaseName || ""} 已下载完成。`,
      detail: "重启 codedog 即可完成安装。",
      buttons: ["稍后", "立即重启"],
      defaultId: 1,
      cancelId: 0,
    });
    if (answer.response === 1) {
      beforeInstall();
      autoUpdater.quitAndInstall();
    }
  });

  const check = () => {
    try {
      const result = autoUpdater.checkForUpdates();
      if (result?.catch)
        result.catch((error) =>
          logger.error("[codedog] Update check failed:", error),
        );
    } catch (error) {
      logger.error("[codedog] Update check failed:", error);
    }
  };
  check();
  const timer = setInterval(check, interval);
  timer.unref?.();
  return timer;
}
