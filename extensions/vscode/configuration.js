const { resolveDebugger } = require("./launcher");
const { discoverSource } = require("./discovery");

const entryUnknown = "未确定 main 函数位置：请打开可执行包中的 MoonBit 源码文件；不会自动选择其他入口。";
const automaticConfiguration = () => ({
  type: "moondbg", request: "launch", name: "moondbg：调试当前包",
  internalConsoleOptions: "openOnSessionStart",
});

function createConfigurationProvider(vscode, output, resolve = resolveDebugger, discover = discoverSource) {
  return {
    provideDebugConfigurations() { return [automaticConfiguration()]; },
    async resolveDebugConfiguration(folder, configuration, outerToken) {
      const hasPackage = Object.hasOwn(configuration, "package");
      const hasProgram = Object.hasOwn(configuration, "program");
      const hasTarget = hasPackage || hasProgram || configuration.connectionTest === true;
      if (hasTarget) {
        const validTarget = hasPackage !== hasProgram &&
          typeof configuration[hasPackage ? "package" : "program"] === "string" &&
          configuration[hasPackage ? "package" : "program"].trim().length > 0;
        if (configuration.request === "launch" &&
            (configuration.connectionTest === true ? !hasPackage && !hasProgram : validTarget)) return configuration;
        vscode.window.showErrorMessage("请为 launch 配置 package（包目录，自动构建）或 program（预编译可执行文件），两者只能选一个。连接验证不接受目标；当前不支持 attach。");
        return undefined;
      }
      if (configuration.request && configuration.request !== "launch") {
        vscode.window.showErrorMessage("moondbg 当前仅支持 launch，不支持 attach。");
        return undefined;
      }
      // Capture the document before awaiting anything; changing editors while
      // discovery runs must not silently change the selected target.
      const document = vscode.window.activeTextEditor?.document;
      const workspace = document && vscode.workspace.getWorkspaceFolder(document.uri);
      if (!document || document.uri.scheme !== "file" || !document.uri.fsPath.endsWith(".mbt") ||
          !workspace || (folder && folder.uri.toString() !== workspace.uri.toString())) {
        vscode.window.showErrorMessage(entryUnknown);
        return undefined;
      }
      if (configuration.noDebug === true) {
        vscode.window.showErrorMessage("moondbg 当前不支持不调试运行。");
        return undefined;
      }
      try {
        if (outerToken?.isCancellationRequested) return undefined;
        if (document.isDirty && !await document.save()) return undefined;
        const moonHome = vscode.workspace.getConfiguration("moondbg").get("moonHome", "");
        const launch = await resolve(process.env, { moonHome });
        const target = await vscode.window.withProgress({
          location: vscode.ProgressLocation.Notification, title: "moondbg：定位当前包入口", cancellable: true,
        }, async (_, token) => {
          const controller = new AbortController();
          const cancel = () => controller.abort();
          const subscriptions = [token, outerToken].filter(Boolean).map(t => t.onCancellationRequested(cancel));
          if (token.isCancellationRequested || outerToken?.isCancellationRequested) cancel();
          output.appendLine(`定位源码：${document.uri.fsPath}`);
          try {
            return await discover(launch, document.uri.fsPath, {
              signal: controller.signal, onDiagnostic: text => output.append(text),
            });
          } finally { for (const subscription of subscriptions) subscription.dispose(); }
        });
        // No on-disk launch.json and no guessed /main convention.
        return { ...automaticConfiguration(), ...configuration, type: "moondbg", request: "launch",
          package: target.package, name: `moondbg：${target.name}` };
      } catch (error) {
        if (error.name !== "AbortError") {
          output.appendLine(error.message);
          output.show(true);
          vscode.window.showErrorMessage(error.message);
        }
        return undefined;
      }
    },
  };
}

module.exports = { createConfigurationProvider, automaticConfiguration, entryUnknown };
