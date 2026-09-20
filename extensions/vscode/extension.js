const vscode = require("vscode");
const { resolveDebugger } = require("./launcher");
const { createConfigurationProvider, automaticConfiguration } = require("./configuration");

function activate(context) {
  const output = vscode.window.createOutputChannel("moondbg");
  context.subscriptions.push(output);
  context.subscriptions.push(
    vscode.commands.registerCommand("moondbg.showStatus", () =>
      vscode.window.showInformationMessage(
        "moondbg 扩展已加载。支持按包自动构建、断点、单步、暂停和变量查看。",
      ),
    ),
  );
  context.subscriptions.push(
    vscode.commands.registerCommand("moondbg.debugCurrentPackage", () => {
      const document = vscode.window.activeTextEditor?.document;
      const folder = document && vscode.workspace.getWorkspaceFolder(document.uri);
      return vscode.debug.startDebugging(folder, automaticConfiguration());
    }),
    vscode.debug.registerDebugConfigurationProvider("moondbg", createConfigurationProvider(vscode, output)),
    vscode.debug.registerDebugAdapterDescriptorFactory("moondbg", {
      async createDebugAdapterDescriptor() {
        const moonHome = vscode.workspace.getConfiguration("moondbg").get("moonHome", "");
        const launch = await resolveDebugger(process.env, { moonHome });
        return new vscode.DebugAdapterExecutable(launch.executable, ["--dap"], { env: launch.env });
      },
    }),
  );
}

module.exports = { activate };
