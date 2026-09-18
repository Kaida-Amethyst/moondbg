// Real VS Code integration test. Run in an isolated Extension Development Host.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vscode = require("vscode");

exports.run = async function () {
  const received = [];
  const sent = [];
  const errors = [];
  const listeners = new Set();
  let passed = false;
  let session;
  const workspace = vscode.workspace.workspaceFolders[0];
  const source = path.join(workspace.uri.fsPath, "main/main.mbt");
  const runningProgram = process.env.MOONDBG_TEST_RUNNING_PROGRAM;
  const lines = fs.readFileSync(source, "utf8").split("\n");
  const line = lines.findIndex((text) => text.trim() === "let len = p.length()");
  assert.ok(line >= 0);
  const breakpoint = new vscode.SourceBreakpoint(
    new vscode.Location(vscode.Uri.file(source), new vscode.Position(line, 0)),
  );
  function waitFor(predicate) {
    const existing = received.find(predicate);
    if (existing) return Promise.resolve(existing);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        listeners.delete(listener);
        reject(new Error(`Timed out; received: ${JSON.stringify(received)}`));
      }, 25000);
      const listener = (message) => {
        if (predicate(message)) {
          clearTimeout(timer);
          listeners.delete(listener);
          resolve(message);
        }
      };
      listeners.add(listener);
    });
  }
  const tracker = vscode.debug.registerDebugAdapterTrackerFactory("moondbg", {
    createDebugAdapterTracker() {
      return {
        onWillReceiveMessage: (message) => sent.push(message),
        onDidSendMessage(message) {
          received.push(message);
          for (const listener of listeners) listener(message);
        },
        onError: (error) => errors.push({
          message: error.message,
          afterDisconnect: received.some((m) => m.type === "response" &&
            m.command === "disconnect" && m.success),
        }),
      };
    },
  });
  const ended = vscode.debug.onDidTerminateDebugSession((endedSession) => {
    if (endedSession.type !== "moondbg") return;
    const message = { hostSessionEnded: true };
    received.push(message);
    for (const listener of listeners) listener(message);
  });
  try {
    await vscode.window.showTextDocument(vscode.Uri.file(source));
    if (!runningProgram) vscode.debug.addBreakpoints([breakpoint]);
    assert.equal(await vscode.debug.startDebugging(workspace, {
      type: "moondbg", request: "launch", name: "moondbg live host acceptance",
      program: runningProgram || path.join(workspace.uri.fsPath, "_build/native/debug/build/main/main.exe"),
      cwd: workspace.uri.fsPath, internalConsoleOptions: "openOnSessionStart",
    }), true);
    if (runningProgram) {
      await waitFor((m) => m.event === "output" && m.body.output.includes("dap-running-ready"));
      session = vscode.debug.activeDebugSession;
      assert.ok(session);
      assert.ok(!received.some((m) => m.event === "stopped"));
      const launched = received.find((m) => m.event === "process");
      assert.ok(launched?.body.systemProcessId);
      // Same operation as the VS Code Stop button, while no breakpoint is hit.
      await vscode.debug.stopDebugging(session);
      await waitFor((m) => m.hostSessionEnded);
      assert.throws(() => process.kill(launched.body.systemProcessId, 0), { code: "ESRCH" });
    } else {
      const stopped = await waitFor((m) => m.event === "stopped");
      assert.equal(stopped.body.reason, "breakpoint");
      session = vscode.debug.activeDebugSession;
      assert.ok(session);
      // Await VS Code's own stack request, not just a manually issued request.
      const stack = await waitFor((m) => m.type === "response" &&
        m.command === "stackTrace" && m.success && m.body.stackFrames.length > 0);
      assert.equal(stack.body.stackFrames[0].line, line + 1);
      assert.equal(fs.realpathSync(stack.body.stackFrames[0].source.path), fs.realpathSync(source));
      const scopes = await session.customRequest("scopes", { frameId: stack.body.stackFrames[0].id });
      assert.equal(scopes.scopes[0].name, "Locals");
      const locals = await session.customRequest("variables", {
        variablesReference: scopes.scopes[0].variablesReference,
      });
      const point = locals.variables.find((variable) => variable.name === "p");
      assert.ok(point?.variablesReference > 0, JSON.stringify(locals));
      const fields = await session.customRequest("variables", {
        variablesReference: point.variablesReference,
      });
      assert.equal(fields.variables.find((field) => field.name === "x").value, "3");
      assert.equal(fields.variables.find((field) => field.name === "y").value, "4");
      vscode.debug.removeBreakpoints([breakpoint]);
      await session.customRequest("continue", { threadId: stopped.body.threadId });
      const exited = await waitFor((m) => m.event === "exited");
      assert.equal(exited.body.exitCode, 0);
      await waitFor((m) => m.hostSessionEnded);
      const output = received.filter((m) => m.event === "output").map((m) => m.body.output).join("");
      assert.match(output, /Length of point: 5/);
      assert.match(output, /Length of point q: 10/);
      assert.ok(received.some((m) => m.type === "response" && m.command === "setBreakpoints" &&
        m.success && m.body.breakpoints.some((b) => b.verified)));
    }
    assert.ok(received.some((m) => m.type === "response" && m.command === "disconnect" && m.success));
    assert.ok(errors.every((e) => e.message === "read error" && e.afterDisconnect), JSON.stringify(errors));
    passed = true;
    console.log("moondbg real VS Code launch/breakpoint/stack/continue acceptance passed");
  } finally {
    if (!passed && session) await vscode.debug.stopDebugging(session);
    vscode.debug.removeBreakpoints([breakpoint]);
    tracker.dispose();
    ended.dispose();
    if (process.env.MOONDBG_VSCODE_TEST_RESULT) {
      fs.writeFileSync(process.env.MOONDBG_VSCODE_TEST_RESULT,
        JSON.stringify({ passed, sent, received, errors }, null, 2));
    }
  }
};
