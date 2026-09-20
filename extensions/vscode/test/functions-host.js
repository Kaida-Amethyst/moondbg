// Run through a real isolated Extension Development Host, not a mocked client.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vscode = require("vscode");

exports.run = async function () {
  const received = [];
  const sent = [];
  const errors = [];
  const listeners = new Set();
  const owned = [];
  let passed = false;
  let session;
  const workspace = vscode.workspace.workspaceFolders[0];
  function waitFor(predicate, start = 0) {
    const previous = received.slice(start).find(predicate);
    if (previous) return Promise.resolve(previous);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        listeners.delete(listener);
        reject(new Error(`Timed out: ${JSON.stringify(received)}`));
      }, 30000);
      const listener = (message) => {
        if (!predicate(message)) return;
        clearTimeout(timer);
        listeners.delete(listener);
        resolve(message);
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
        onError: (error) => errors.push({ message: error.message,
          afterDisconnect: received.some((m) => m.command === "disconnect" && m.success) }),
      };
    },
  });
  const ended = vscode.debug.onDidTerminateDebugSession((value) => {
    if (value.type !== "moondbg") return;
    const message = { hostSessionEnded: true };
    received.push(message);
    for (const listener of listeners) listener(message);
  });
  const main = new vscode.FunctionBreakpoint("main");
  const foo = new vscode.FunctionBreakpoint("foo");
  const imported = new vscode.FunctionBreakpoint("@util.foo");
  const generic = new vscode.FunctionBreakpoint("identity");
  owned.push(main, foo, imported, generic);
  async function update(change, count) {
    const start = received.length;
    change();
    return waitFor((m) => m.type === "response" && m.command === "setFunctionBreakpoints" &&
      m.success && m.body.breakpoints.length === count, start);
  }
  async function resume(thread, expectedName) {
    const start = received.length;
    await session.customRequest("continue", { threadId: thread });
    const stop = await waitFor((m) => m.event === "stopped", start);
    assert.equal(stop.body.reason, "function breakpoint");
    assert.ok(stop.body.hitBreakpointIds.length > 0);
    const stack = await session.customRequest("stackTrace", { threadId: stop.body.threadId });
    assert.ok(stack.stackFrames[0].name.includes(expectedName), JSON.stringify(stack));
    return stop;
  }
  try {
    vscode.debug.addBreakpoints(owned);
    assert.equal(await vscode.debug.startDebugging(workspace, {
      type: "moondbg", request: "launch", name: "Function breakpoint acceptance",
      package: path.join(workspace.uri.fsPath, "dap_functions"),
      internalConsoleOptions: "openOnSessionStart",
    }), true);
    const stop = await waitFor((m) => m.event === "stopped");
    assert.equal(stop.body.reason, "function breakpoint");
    session = vscode.debug.activeDebugSession;
    assert.ok(session);
    const initial = received.find((m) => m.type === "response" && m.command === "setFunctionBreakpoints" && m.success);
    assert.equal(initial.body.breakpoints.length, 4);
    assert.ok(initial.body.breakpoints.every((b) => b.verified));
    assert.match(initial.body.breakpoints[3].message, /2 function/);
    await update(() => vscode.debug.removeBreakpoints([main]), 3);
    await resume(stop.body.threadId, ".foo");
    const disabled = new vscode.FunctionBreakpoint("foo", false);
    owned.push(disabled);
    await update(() => {
      vscode.debug.removeBreakpoints([foo]);
      vscode.debug.addBreakpoints([disabled]);
    }, 2);
    await resume(stop.body.threadId, "dap_function_util.foo");
    const first = await resume(stop.body.threadId, ".identity");
    const second = await resume(stop.body.threadId, ".identity");
    assert.deepEqual(first.body.hitBreakpointIds, second.body.hitBreakpointIds);
    const enabled = new vscode.FunctionBreakpoint("foo", true);
    owned.push(enabled);
    await update(() => {
      vscode.debug.removeBreakpoints([disabled]);
      vscode.debug.addBreakpoints([enabled]);
    }, 3);
    await resume(stop.body.threadId, "dap_functions.foo");
    await update(() => vscode.debug.removeBreakpoints(owned), 0);
    await session.customRequest("continue", { threadId: stop.body.threadId });
    const exit = await waitFor((m) => m.event === "exited");
    assert.equal(exit.body.exitCode, 0);
    await waitFor((m) => m.hostSessionEnded);
    assert.ok(errors.every((e) => e.message === "read error" && e.afterDisconnect), JSON.stringify(errors));
    passed = true;
    console.log("VS Code function breakpoints: add, remove, disable, reenable, generic instances passed");
  } finally {
    if (!passed && session) await vscode.debug.stopDebugging(session);
    vscode.debug.removeBreakpoints(owned);
    tracker.dispose();
    ended.dispose();
    if (process.env.MOONDBG_VSCODE_TEST_RESULT) {
      fs.writeFileSync(process.env.MOONDBG_VSCODE_TEST_RESULT,
        JSON.stringify({ passed, sent, received, errors }, null, 2));
    }
  }
};
