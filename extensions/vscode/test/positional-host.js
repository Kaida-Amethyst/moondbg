// Run in an isolated Extension Development Host with the current CLI.
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
  const source = vscode.Uri.file(path.join(workspace.uri.fsPath, "positional_values/main.mbt"));
  const lines = fs.readFileSync(source.fsPath, "utf8").split("\n");
  const breakpoints = ["POSITIONAL_READY", "POSITIONAL_CHANGED"].map(marker => {
    const line = lines.findIndex(text => text.includes(marker));
    assert.ok(line >= 0);
    return new vscode.SourceBreakpoint(new vscode.Location(source, new vscode.Position(line, 0)));
  });
  try {
    await vscode.window.showTextDocument(source);
    vscode.debug.addBreakpoints(breakpoints);
    assert.equal(await vscode.debug.startDebugging(workspace, {
      type: "moondbg", request: "launch", name: "Positional values acceptance",
      package: path.join(workspace.uri.fsPath, "positional_values"),
    }), true);
    const stop = await until(() => received.find(message => message.event === "stopped"));
    session = vscode.debug.activeDebugSession;
    const stack = await session.customRequest("stackTrace", { threadId: stop.body.threadId });
    let frameId = stack.stackFrames[0].id;
    const evaluate = expression => session.customRequest("evaluate", { frameId, expression, context: "watch" });
    const children = async value => (await session.customRequest("variables", {
      variablesReference: value.variablesReference,
    })).variables;
    const pair = await evaluate("pair");
    assert.equal(pair.type, "(Int, String)");
    const members = await children(pair);
    assert.deepEqual(members.map(value => value.name), [".0", ".1"]);
    for (const member of members) {
      assert.equal((await evaluate(member.evaluateName)).result, member.value);
    }
    assert.equal((await evaluate("pair.0")).result, "42");
    const result = await evaluate("result");
    assert.equal(result.result, "Ok");
    const payload = (await children(result))[0];
    assert.equal(payload.evaluateName, "result.0");
    const x = (await children(payload)).find(value => value.name === "x");
    assert.equal(x.evaluateName, "result.0.x");
    assert.equal((await evaluate(x.evaluateName)).result, "3");
    assert.equal((await evaluate("items[0].0")).result, "11");
    assert.equal((await evaluate("values.numbers.1[1]")).result, "22");
    await assert.rejects(evaluate("pair.2"), /out of bounds/);
    await assert.rejects(evaluate("values.empty.0"), /Empty has 0/);
    await session.customRequest("continue", { threadId: stop.body.threadId });
    await until(() => received.filter(message => message.event === "stopped").length === 2);
    frameId = (await session.customRequest("stackTrace", { threadId: stop.body.threadId })).stackFrames[0].id;
    const changed = await evaluate("values.changing");
    assert.equal(changed.result, "Err");
    assert.match((await evaluate("values.changing.0")).result, /changed🙂/);
    await assert.rejects(evaluate("values.changing.0.x"), /not a struct/);
    await vscode.debug.stopDebugging(session);
    await until(() => !vscode.debug.activeDebugSession);
    passed = true;
  } finally {
    if (session && vscode.debug.activeDebugSession) await vscode.debug.stopDebugging(session);
    vscode.debug.removeBreakpoints(breakpoints);
    tracker.dispose();
    if (process.env.MOONDBG_VSCODE_TEST_RESULT) {
      fs.writeFileSync(process.env.MOONDBG_VSCODE_TEST_RESULT, JSON.stringify({ passed, received }, null, 2));
    }
  }
};
