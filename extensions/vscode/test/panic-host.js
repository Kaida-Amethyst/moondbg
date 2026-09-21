// Real Extension Development Host: verify VS Code's automatic frame selection,
// not just protocol hints. Uses an isolated user-data directory when invoked.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vscode = require("vscode");

exports.run = async function () {
  const sent = [];
  const received = [];
  let passed = false;
  let session;
  async function until(predicate) {
    const deadline = Date.now() + 30000;
    while (Date.now() < deadline) {
      const value = predicate();
      if (value) return value;
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    throw new Error(`Timed out: ${JSON.stringify({ sent, received })}`);
  }
  const tracker = vscode.debug.registerDebugAdapterTrackerFactory("moondbg", {
    createDebugAdapterTracker() {
      return {
        onWillReceiveMessage: message => sent.push(message),
        onDidSendMessage: message => received.push(message),
      };
    },
  });
  try {
    const workspace = vscode.workspace.workspaceFolders[0];
    const root = workspace.uri.fsPath;
    const source = path.join(root, "panic_context_lib", "fail.mbt");
    await vscode.window.showTextDocument(vscode.Uri.file(path.join(root, "panic_context", "main.mbt")));
    assert.equal(await vscode.debug.startDebugging(workspace, {
      type: "moondbg", request: "launch", name: "Panic acceptance",
      package: path.join(root, "panic_context"),
      internalConsoleOptions: "openOnSessionStart",
    }), true);
    const stop = await until(() => received.find(message => message.event === "stopped"));
    const target = received.find(message => message.event === "process");
    assert.ok(target && Number.isInteger(target.body.systemProcessId));
    assert.equal(stop.body.reason, "exception");
    assert.equal(stop.body.description, "MoonBit panic");
    assert.ok(sent.some(message => message.command === "setExceptionBreakpoints" &&
      message.arguments.filters.includes("moonbit-panic")), "VS Code should enable panic by default");
    session = vscode.debug.activeDebugSession;
    assert.ok(session);
    await until(() => vscode.window.activeTextEditor &&
      fs.realpathSync(vscode.window.activeTextEditor.document.uri.fsPath) === fs.realpathSync(source));
    const frame = await until(() => {
      const item = vscode.debug.activeStackItem;
      return item && typeof item.frameId === "number" && item;
    });
    const stack = await session.customRequest("stackTrace", { threadId: stop.body.threadId, levels: 20 });
    const selected = stack.stackFrames.find(value => value.id === frame.frameId);
    assert.ok(selected, JSON.stringify(stack));
    assert.equal(fs.realpathSync(selected.source.path), fs.realpathSync(source));
    assert.equal(selected.line, 4);
    assert.match(stack.stackFrames[0].name, /^moonbit_panic/);
    const value = await session.customRequest("evaluate", { frameId: frame.frameId, expression: "value", context: "watch" });
    assert.equal(value.result, "42");
    const scopes = await session.customRequest("scopes", { frameId: frame.frameId });
    const locals = await session.customRequest("variables", { variablesReference: scopes.scopes[0].variablesReference });
    assert.equal(locals.variables.find(value => value.name === "value").value, "42");
    await session.customRequest("setExceptionBreakpoints", { filters: [] });
    await vscode.debug.stopDebugging(session);
    await until(() => received.some(message => message.command === "disconnect" && message.success));
    await until(() => {
      try { process.kill(target.body.systemProcessId, 0); return false; }
      catch (error) { if (error.code === "ESRCH") return true; throw error; }
    });
    passed = true;
  } finally {
    if (session && vscode.debug.activeDebugSession) await vscode.debug.stopDebugging(session);
    tracker.dispose();
    if (process.env.MOONDBG_VSCODE_TEST_RESULT) {
      fs.writeFileSync(process.env.MOONDBG_VSCODE_TEST_RESULT, JSON.stringify({ passed, sent, received }, null, 2));
    }
  }
};
