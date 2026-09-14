const fs = require("node:fs/promises");
const { constants } = require("node:fs");
const path = require("node:path");

// Resolve only the explicitly selected toolchain. Never search
// PATH, invoke a shell, rewrite a symlink, or build the debugger automatically.
async function resolveDebugger(environment = process.env) {
  const moonHome = environment.MOON_HOME;
  if (typeof moonHome !== "string" || !path.isAbsolute(moonHome)) {
    throw new Error(
      `moondbg: MOON_HOME 必须为工具链的绝对目录路径，实际为 ${moonHome || "未设置"}。` +
        "请使用仓库的 stable 扩展开发启动配置，或先执行 source ~/.zshrc 和 set_moon_stable，再从该环境启动 VS Code。",
    );
  }
  const executable = path.join(moonHome, "bin", "moondbg");
  try {
    if (!(await fs.stat(executable)).isFile()) {
      throw new Error("路径目标不是普通文件");
    }
    await fs.access(executable, constants.X_OK);
  } catch (error) {
    throw new Error(`moondbg: 无法启动 ${executable}：${error.message}。请在所选 MOON_HOME/bin 下安装 moondbg 或配置有效软链接，并确认它可执行且支持 --dap。`);
  }
  return executable;
}

module.exports = { resolveDebugger };
