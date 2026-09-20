const vscode = require("vscode");
const { resolveDebugger } = require("./launcher");

function activate(context) {
  context.subscriptions.push(
    vscode.commands.registerCommand("moondbg.showStatus", () =>
      vscode.window.showInformationMessage(
        "moondbg 扩展已加载。支持按包自动构建、断点、单步、暂停和变量查看。",
      ),
    ),
  );
  context.subscriptions.push(
    vscode.debug.registerDebugConfigurationProvider("moondbg", {
      resolveDebugConfiguration(_folder, configuration) {
        const hasPackage = Object.hasOwn(configuration, "package");
        const hasProgram = Object.hasOwn(configuration, "program");
        const validTarget = hasPackage !== hasProgram &&
          typeof configuration[hasPackage ? "package" : "program"] === "string" &&
          configuration[hasPackage ? "package" : "program"].trim().length > 0;
        if (configuration.request !== "launch" ||
            (configuration.connectionTest === true ? hasPackage || hasProgram : !validTarget)) {
          vscode.window.showErrorMessage(
            "请为 launch 配置 package（包目录，自动构建）或 program（预编译可执行文件），两者只能选一个。连接验证不接受目标；当前不支持 attach。",
          );
          return undefined;
        }
        return configuration;
      },
    }),
    vscode.debug.registerDebugAdapterDescriptorFactory("moondbg", {
      async createDebugAdapterDescriptor() {
        const executable = await resolveDebugger();
        return new vscode.DebugAdapterExecutable(executable, ["--dap"]);
      },
    }),
  );
}

module.exports = { activate };
