const vscode = require("vscode");
const { resolveDebugger } = require("./launcher");

function activate(context) {
  context.subscriptions.push(
    vscode.commands.registerCommand("moondbg.showStatus", () =>
      vscode.window.showInformationMessage(
        "moondbg 扩展已加载。可运行 DAP 连接验证；尚不支持调试用户程序。",
      ),
    ),
  );
  context.subscriptions.push(
    vscode.debug.registerDebugConfigurationProvider("moondbg", {
      resolveDebugConfiguration(_folder, configuration) {
        if (configuration.request !== "launch" || configuration.connectionTest !== true) {
          vscode.window.showErrorMessage(
            "当前仅支持 moondbg 的 DAP 连接验证。请选择连接验证配置（connectionTest: true）；不会运行用户程序。",
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
