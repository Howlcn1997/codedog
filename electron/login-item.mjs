export function createLoginItemSettings(app, platform = process.platform) {
  function get() {
    if (!["darwin", "win32"].includes(platform))
      return {
        supported: false,
        enabled: false,
        reason: "当前系统暂不支持开机自启。",
      };
    if (!app.isPackaged)
      return {
        supported: false,
        enabled: false,
        reason: "请在安装后的应用中设置开机自启。",
      };
    const settings = app.getLoginItemSettings();
    const needsApproval =
      platform === "darwin" && settings.status === "requires-approval";
    const enabled =
      settings.openAtLogin &&
      (platform !== "win32" || settings.executableWillLaunchAtLogin);
    return {
      supported: true,
      enabled: Boolean(enabled),
      reason: needsApproval
        ? "请在系统设置 → 通用 → 登录项中允许 codedog 自启。"
        : platform === "win32" && settings.openAtLogin && !enabled
          ? "启动项已被系统禁用，请在系统启动应用设置中启用 codedog。"
          : "登录电脑后自动启动 codedog。",
    };
  }
  function set(enabled) {
    if (typeof enabled !== "boolean") throw Error("无效的开机自启设置");
    const current = get();
    if (!current.supported) throw Error(current.reason);
    app.setLoginItemSettings({ openAtLogin: enabled });
    const result = get();
    if (result.enabled !== enabled)
      throw Error(
        result.reason === "登录电脑后自动启动 codedog。"
          ? "开机自启设置未生效，请检查系统登录项设置。"
          : result.reason,
      );
    return result;
  }
  return { get, set };
}
