const vscode = require("vscode");

function activate(context) {
  context.subscriptions.push(
    vscode.commands.registerCommand("moondbg.showStatus", () =>
      vscode.window.showInformationMessage(
        "moondbg 扩展已加载。当前仅验证扩展加载，尚未接入 DAP 调试。",
      ),
    ),
  );
}

module.exports = { activate };
