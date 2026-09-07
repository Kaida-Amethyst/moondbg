// Run with VS Code's --extensionTestsPath; no npm dependencies required.
const assert = require("node:assert/strict");
const vscode = require("vscode");
const fs = require("node:fs");

exports.run = async function () {
  const received = [];
  const sent = [];
  const errors = [];
  let finish;
  let timer;
  let passed = false;
  const terminated = new Promise((resolve, reject) => {
    finish = resolve;
    timer = setTimeout(() => reject(new Error("DAP connection test timed out")), 20000);
  });
  const tracker = vscode.debug.registerDebugAdapterTrackerFactory("moondbg", {
    createDebugAdapterTracker() {
      return {
        onWillReceiveMessage: (message) => sent.push(message),
        onDidSendMessage: (message) => received.push(message),
        // VS Code emits "read error" unconditionally on adapter stdout close,
        // even after a successful disconnect. Permit only that notification
        // after the full protocol has completed; all other errors fail.
        onError: (error) => errors.push({
          message: error.message,
          afterDisconnect: received.some((item) => item.type === "response" &&
            item.command === "disconnect" && item.success),
        }),
      };
    },
  });
  const listener = vscode.debug.onDidTerminateDebugSession((session) => {
    if (session.type === "moondbg") finish();
  });
  try {
    const started = await vscode.debug.startDebugging(
      vscode.workspace.workspaceFolders?.[0],
      { type: "moondbg", request: "launch", name: "DAP host acceptance", connectionTest: true },
    );
    assert.equal(started, true);
    await terminated;
    assert.ok(errors.every((error) => error.message === "read error" && error.afterDisconnect),
      JSON.stringify(errors));
    for (const command of ["initialize", "launch", "configurationDone", "disconnect"]) {
      const request = sent.find((message) => message.command === command);
      assert.ok(request, `missing ${command} request`);
      assert.ok(received.some((message) => message.type === "response" &&
        message.request_seq === request.seq && message.command === command && message.success),
      `missing successful ${command} response`);
    }
    assert.ok(received.some((message) => message.event === "initialized"));
    assert.ok(received.some((message) => message.event === "terminated"));
    assert.ok(received.some((message) => message.event === "output" &&
      message.body.output.includes("DAP 连接验证成功")));
    assert.ok(!received.some((message) => ["process", "stopped", "exited"].includes(message.event)));
    console.log("moondbg real VS Code DAP acceptance passed");
    passed = true;
  } finally {
    if (process.env.MOONDBG_VSCODE_TEST_RESULT) {
      fs.writeFileSync(process.env.MOONDBG_VSCODE_TEST_RESULT,
        JSON.stringify({ passed, sent, received, errors }, null, 2));
    }
    clearTimeout(timer);
    listener.dispose();
    tracker.dispose();
  }
};
