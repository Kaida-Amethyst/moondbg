// Test driver runs separately; the debugger extension is installed from VSIX.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vscode = require("vscode");

exports.run = async function () {
  const extension = vscode.extensions.getExtension("KaidaAmethyst.moondbg");
  assert.equal(extension?.packageJSON.version, "0.1.1");
  assert.equal(path.dirname(extension.extensionPath), process.env.MOONDBG_INSTALLED_EXTENSIONS);
  await vscode.workspace.getConfiguration("moondbg").update("moonHome", process.env.MOONDBG_TEST_MOON_HOME, vscode.ConfigurationTarget.Global);
  await extension.activate();
  const folder = vscode.workspace.workspaceFolders[0];
  const root = folder.uri.fsPath;
  assert.ok(!fs.existsSync(path.join(root, ".vscode/launch.json")));
  const received = [];
  const listeners = new Set();
  const waitFor = (predicate, start) => {
    const previous = received.slice(start).find(predicate);
    if (previous) return Promise.resolve(previous);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { listeners.delete(listener); reject(new Error(JSON.stringify(received))); }, 30000);
      const listener = message => {
        if (predicate(message)) { clearTimeout(timer); listeners.delete(listener); resolve(message); }
      };
      listeners.add(listener);
    });
  };
  const track = vscode.debug.registerDebugAdapterTrackerFactory("moondbg", { createDebugAdapterTracker() {
    return { onDidSendMessage(message) { received.push(message); for (const listener of listeners) listener(message); } };
  } });
  const ended = vscode.debug.onDidTerminateDebugSession(() => {
    const message = { ended: true }; received.push(message); for (const listener of listeners) listener(message);
  });
  let passed = false;
  const points = [];
  try {
    for (const mode of ["empty", "command"]) {
      const source = path.join(root, "src/app/main.mbt");
      await vscode.window.showTextDocument(vscode.Uri.file(source));
      const point = new vscode.SourceBreakpoint(new vscode.Location(vscode.Uri.file(source), new vscode.Position(2, 0)));
      points.push(point);
      vscode.debug.addBreakpoints([point]);
      const start = received.length;
      const started = mode === "empty"
        ? await vscode.debug.startDebugging(folder, { type: "moondbg" })
        : await vscode.commands.executeCommand("moondbg.debugCurrentPackage");
      assert.equal(started, true);
      const stop = await waitFor(m => m.event === "stopped", start);
      const session = vscode.debug.activeDebugSession;
      const stack = await session.customRequest("stackTrace", { threadId: stop.body.threadId });
      assert.equal(fs.realpathSync(stack.stackFrames[0].source.path), fs.realpathSync(source));
      assert.equal(stack.stackFrames[0].line, 3);
      vscode.debug.removeBreakpoints([point]);
      await session.customRequest("continue", { threadId: stop.body.threadId });
      await waitFor(m => m.ended, start);
    }
    // The project has a runnable app, but the library must never select it.
    await vscode.window.showTextDocument(vscode.Uri.file(path.join(root, "src/lib/lib.mbt")));
    const before = received.length;
    assert.equal(await vscode.commands.executeCommand("moondbg.debugCurrentPackage"), false);
    assert.equal(received.length, before);
    await vscode.commands.executeCommand("workbench.action.closeAllEditors");
    assert.equal(vscode.window.activeTextEditor, undefined);
    assert.equal(await vscode.commands.executeCommand("moondbg.debugCurrentPackage"), false);
    assert.equal(received.length, before);
    assert.ok(!fs.existsSync(path.join(root, ".vscode/launch.json")));
    passed = true;
    console.log("Installed VSIX automatic current-package launch and library rejection passed");
  } finally {
    await vscode.debug.stopDebugging();
    vscode.debug.removeBreakpoints(points);
    track.dispose(); ended.dispose();
    if (process.env.MOONDBG_VSCODE_TEST_RESULT) fs.writeFileSync(process.env.MOONDBG_VSCODE_TEST_RESULT, JSON.stringify({ passed, received }, null, 2));
  }
};
