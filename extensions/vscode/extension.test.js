const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const manifest = require("./package.json");

test("launch configuration loads this extension and opens the existing fixture", () => {
  const repository = path.resolve(__dirname, "../..");
  const launch = JSON.parse(
    fs.readFileSync(path.join(repository, ".vscode/launch.json"), "utf8"),
  );
  const configuration = launch.configurations.find(
    (entry) => entry.type === "extensionHost",
  );
  assert.ok(configuration);
  assert.equal(configuration.request, "launch");
  assert.equal(configuration.runtimeExecutable, "${execPath}");
  const args = configuration.args.map((arg) =>
    arg.replaceAll("${workspaceFolder}", repository),
  );
  assert.equal(args[0], `--extensionDevelopmentPath=${__dirname}`);
  assert.ok(fs.statSync(args[1]).isDirectory());
  assert.ok(fs.statSync(path.join(__dirname, manifest.main)).isFile());
});

test("activation registers the declared status command and disposes with the host", async () => {
  const commands = new Map();
  const messages = [];
  const vscode = {
    commands: {
      registerCommand(id, handler) {
        assert.ok(!commands.has(id));
        commands.set(id, handler);
        return { dispose: () => commands.delete(id) };
      },
    },
    window: {
      showInformationMessage(message) {
        messages.push(message);
        return Promise.resolve(undefined);
      },
    },
  };
  const sandbox = {
    module: { exports: {} },
    require(id) {
      assert.equal(id, "vscode");
      return vscode;
    },
  };
  vm.runInNewContext(
    fs.readFileSync(path.join(__dirname, manifest.main), "utf8"),
    sandbox,
    { filename: manifest.main },
  );
  const context = { subscriptions: [] };
  sandbox.module.exports.activate(context);
  assert.deepEqual(
    [...commands.keys()],
    manifest.contributes.commands.map((command) => command.command),
  );
  assert.deepEqual(messages, []);
  for (const [id, handler] of commands) {
    assert.ok(manifest.activationEvents.includes(`onCommand:${id}`));
    await handler();
  }
  assert.deepEqual(messages, [
    "moondbg 扩展已加载。当前仅验证扩展加载，尚未接入 DAP 调试。",
  ]);
  for (const disposable of context.subscriptions) {
    disposable.dispose();
  }
  assert.equal(commands.size, 0);
});
