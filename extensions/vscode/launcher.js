const fs = require("node:fs/promises");
const { constants } = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// Resolve only the explicitly configured development toolchain. Never search
// PATH, invoke a shell, rewrite a symlink, or build the debugger automatically.
async function resolveDebugger(environment = process.env, home = os.homedir()) {
  const moonHome = environment.MOON_HOME;
  const expected = path.join(home, ".moon_dev");
  if (!moonHome || !path.isAbsolute(moonHome) || path.normalize(moonHome) !== expected) {
    throw new Error(
      `moondbg: MOON_HOME 必须为 ${expected}，实际为 ${moonHome || "未设置"}。` +
        "请使用仓库的扩展开发启动配置，或先执行 source ~/.zshrc 和 set_moon_dev，再从该环境启动 VS Code。",
    );
  }
  const executable = path.join(moonHome, "bin", "moondbg");
  try {
    if (!(await fs.lstat(executable)).isSymbolicLink()) {
      throw new Error("必须是开发版 moondbg 的软链接");
    }
    if (!(await fs.stat(executable)).isFile()) {
      throw new Error("链接目标不是文件");
    }
    await fs.access(executable, constants.X_OK);
  } catch (error) {
    throw new Error(`moondbg: 无法启动 ${executable}：${error.message}。请检查开发环境和构建产物。`);
  }
  return executable;
}

module.exports = { resolveDebugger };
