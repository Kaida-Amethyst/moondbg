const vscode = require("vscode");
const { resolveDebugger } = require("./launcher");

function activate(context) {
  context.subscriptions.push(
    vscode.commands.registerCommand("moondbg.showStatus", () =>
      vscode.window.showInformationMessage(
        "moondbg 扩展已加载。支持已编译程序的行断点、调用栈、单步、继续和暂停。",
      ),
    ),
  );
  context.subscriptions.push(
    vscode.debug.registerDebugConfigurationProvider("moondbg", {
      resolveDebugConfiguration(_folder, configuration) {
        if (configuration.request !== "launch" ||
            (configuration.connectionTest !== true &&
             (typeof configuration.program !== "string" || !configuration.program.trim()))) {
          vscode.window.showErrorMessage(
            "请选择连接验证配置，或为 launch 配置 program（已使用 -g -O0 编译的可执行文件路径）。当前不支持 attach。",
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
