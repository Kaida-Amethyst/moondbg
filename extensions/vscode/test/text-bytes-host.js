// Run in an isolated real Extension Development Host against the current CLI.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vscode = require("vscode");

exports.run = async function () {
  const received = [];
  let passed = false;
  let session;
  const tracker = vscode.debug.registerDebugAdapterTrackerFactory("moondbg", {
    createDebugAdapterTracker() {
      return { onDidSendMessage: message => received.push(message) };
    },
  });
  async function until(predicate) {
    const deadline = Date.now() + 30000;
    while (Date.now() < deadline) {
      const value = predicate();
      if (value) return value;
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    throw new Error(`Timed out: ${JSON.stringify(received)}`);
  }
  const workspace = vscode.workspace.workspaceFolders[0];
  const source = vscode.Uri.file(path.join(workspace.uri.fsPath, "text_bytes/main.mbt"));
  const line = fs.readFileSync(source.fsPath, "utf8").split("\n")
    .findIndex(text => text.includes("let marker = values.text"));
  assert.ok(line >= 0);
  const breakpoint = new vscode.SourceBreakpoint(new vscode.Location(source, new vscode.Position(line, 0)));
  try {
    await vscode.window.showTextDocument(source);
    vscode.debug.addBreakpoints([breakpoint]);
    assert.equal(await vscode.debug.startDebugging(workspace, {
      type: "moondbg", request: "launch", name: "String and Bytes acceptance",
      package: path.join(workspace.uri.fsPath, "text_bytes"),
    }), true);
    await until(() => received.some(message => message.event === "stopped"));
    session = vscode.debug.activeDebugSession;
    const frame = await until(() => {
      const item = vscode.debug.activeStackItem;
      return item && typeof item.frameId === "number" && item;
    });
    const evaluate = expression => session.customRequest("evaluate", {
      frameId: frame.frameId, expression, context: "watch",
    });
    const text = await evaluate("values.text");
    assert.equal(text.type, "String");
    assert.equal(text.result, '"你好🙂\\nA\\u0000B" (length = 8 UTF-16 units)');
    const bytes = await evaluate("values.bytes");
    assert.equal(bytes.result, 'b"\\x41\\x00\\xff" (length = 3 bytes)');
    const long = await evaluate("values.long_text");
    assert.match(long.result, /showing \[0:127\], truncated/);
    const chunks = await session.customRequest("variables", {
      variablesReference: long.variablesReference, start: 0, count: 3,
    });
    assert.deepEqual(chunks.variables.map(value => value.name), ["[0:127]", "[127:256]", "[256:280]"]);
    assert.match(chunks.variables[1].value, /^"🙂/);
    const sliced = await evaluate("values.text[2:4]");
    assert.match(sliced.result, /^"🙂"/);
    assert.equal(sliced.variablesReference, 0);
    await assert.rejects(evaluate("values.text[0:9]"), /outside length 8/);
    assert.equal((await evaluate("values.result")).type, "Result[Point, String]");
    await vscode.debug.stopDebugging(session);
    await until(() => !vscode.debug.activeDebugSession);
    passed = true;
  } finally {
    if (session && vscode.debug.activeDebugSession) await vscode.debug.stopDebugging(session);
    vscode.debug.removeBreakpoints([breakpoint]);
    tracker.dispose();
    if (process.env.MOONDBG_VSCODE_TEST_RESULT) {
      fs.writeFileSync(process.env.MOONDBG_VSCODE_TEST_RESULT, JSON.stringify({ passed, received }, null, 2));
    }
  }
};
