// Real Extension Development Host: VS Code sends its native breakpoint
// condition, moondbg filters internally, and only i == 7 becomes a visible stop.
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
  const workspace = vscode.workspace.workspaceFolders[0];
  const paths = process.env.MOONDBG_TEST_CONDITION_PATHS === "1";
  const packageName = paths ? "conditional_paths" : "conditional";
  const expression = paths ? "scene.points[0].x == limit" : "i == 7";
  const watched = paths ? "scene.point.x" : "i";
  const source = vscode.Uri.file(path.join(workspace.uri.fsPath, packageName, "main.mbt"));
  const line = paths ? fs.readFileSync(source.fsPath, "utf8").split("\n").findIndex(text => text.includes("let marker = scene.point.x")) : 3;
  assert.ok(line >= 0);
  const breakpoint = new vscode.SourceBreakpoint(
    new vscode.Location(source, new vscode.Position(line, 0)), true, expression,
  );
  try {
    await vscode.window.showTextDocument(source);
    vscode.debug.addBreakpoints([breakpoint]);
    assert.equal(await vscode.debug.startDebugging(workspace, {
      type: "moondbg", request: "launch", name: "Conditional breakpoint acceptance",
      package: path.join(workspace.uri.fsPath, packageName),
    }), true);
    const stop = await until(() => received.find(message => message.event === "stopped"));
    assert.equal(stop.body.reason, "breakpoint");
    assert.ok(received.some(message => message.command === "initialize" &&
      message.body.supportsConditionalBreakpoints === true));
    assert.ok(sent.some(message => message.command === "setBreakpoints" &&
      message.arguments.breakpoints.some(point => point.condition === expression)));
    session = vscode.debug.activeDebugSession;
    const frame = await until(() => {
      const item = vscode.debug.activeStackItem;
      return item && typeof item.frameId === "number" && item;
    });
    const value = await session.customRequest("evaluate", {
      frameId: frame.frameId, expression: watched, context: "watch",
    });
    assert.equal(value.result, "7");
    const stack = await session.customRequest("stackTrace", { threadId: stop.body.threadId });
    assert.equal(stack.stackFrames[0].line, line + 1);
    assert.equal(fs.realpathSync(stack.stackFrames[0].source.path), fs.realpathSync(source.fsPath));
    await session.customRequest("continue", { threadId: stop.body.threadId });
    const exit = await until(() => received.find(message => message.event === "exited"));
    assert.equal(exit.body.exitCode, 0);
    await until(() => received.some(message => message.event === "terminated"));
    assert.equal(received.filter(message => message.event === "stopped").length, 1);
    passed = true;
  } finally {
    if (session && vscode.debug.activeDebugSession) await vscode.debug.stopDebugging(session);
    vscode.debug.removeBreakpoints([breakpoint]);
    tracker.dispose();
    if (process.env.MOONDBG_VSCODE_TEST_RESULT) {
      fs.writeFileSync(process.env.MOONDBG_VSCODE_TEST_RESULT, JSON.stringify({ passed, sent, received }, null, 2));
    }
  }
};
