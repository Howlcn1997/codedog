export function terminalLaunch(terminal, folder, platform = process.platform) {
  if (terminal === "warp")
    return {
      url: `warp://action/new_tab?path=${encodeURIComponent(folder)}`,
    };
  if (terminal !== "system") throw Error("不支持的终端");
  if (platform === "darwin")
    return { command: "open", args: ["-a", "Terminal", folder] };
  if (platform === "win32") return { command: "wt.exe", args: ["-d", folder] };
  return {
    command: "x-terminal-emulator",
    args: ["--working-directory", folder],
  };
}
