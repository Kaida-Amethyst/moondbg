const fs = require("node:fs/promises");
const { constants } = require("node:fs");
const path = require("node:path");
const os = require("node:os");

// Resolve only the explicitly selected toolchain. Never search
// PATH, invoke a shell, rewrite a symlink, or build the debugger automatically.
async function resolveDebugger(environment = process.env, options = {}) {
  const platform = options.platform ?? process.platform;
  const arch = options.arch ?? process.arch;
  if (platform !== "darwin" || arch !== "arm64") {
    throw new Error(`moondbg 预览版仅支持 macOS Apple Silicon（aarch64-apple-darwin）；当前为 ${platform}/${arch}。请使用原生 ARM64 版 VS Code，不支持 Rosetta、其他系统或架构。`);
  }
  const configured = options.moonHome ?? "";
  if (typeof configured !== "string") throw new Error("moondbg.moonHome 必须是目录字符串。");
  const selected = configured.trim() || environment.MOON_HOME;
  // Expand ~ only in the user setting, never by starting a shell. An explicit
  // invalid selection is an error, not permission to try another toolchain.
  const moonHome = configured.trim().startsWith("~/")
    ? path.join(options.homeDirectory ?? os.homedir(), configured.trim().slice(2))
    : selected;
  if (typeof moonHome !== "string" || !path.isAbsolute(moonHome)) {
    throw new Error(
      `moondbg: MOON_HOME 必须为工具链的绝对目录路径，实际为 ${moonHome || "未设置"}。` +
      "请在 VS Code 用户设置中将 moondbg.moonHome 设为 MoonBit 安装目录（例如 ~/.moon），或从已设置 MOON_HOME 的环境启动 VS Code。",
    );
  }
  const executable = path.join(moonHome, "bin", "moondbg");
  try {
    if (!(await fs.stat(executable)).isFile()) {
      throw new Error("路径目标不是普通文件");
    }
    await fs.access(executable, constants.X_OK);
  } catch (error) {
    throw new Error(`moondbg: 无法启动 ${executable}：${error.message}。请使用所选工具链执行 moon install Kaida-Amethyst/moondbg，并确认安装的 moondbg 支持 --dap。`);
  }
  return {
    executable,
    // Pass the same toolchain to the adapter's package builder. Never source a shell profile.
    env: { ...environment, MOON_HOME: moonHome,
      PATH: [path.join(moonHome, "bin"), environment.PATH].filter(Boolean).join(path.delimiter) },
  };
}

module.exports = { resolveDebugger };
