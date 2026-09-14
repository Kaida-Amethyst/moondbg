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
  assert.equal(configuration.env.MOON_HOME, "${env:HOME}/.moon");
  assert.equal(configuration.env.PATH, "${env:HOME}/.moon/bin:${env:PATH}");
  const args = configuration.args.map((arg) =>
    arg.replaceAll("${workspaceFolder}", repository),
  );
  assert.equal(args[0], `--extensionDevelopmentPath=${__dirname}`);
  assert.ok(fs.statSync(args[1]).isDirectory());
  assert.ok(fs.statSync(path.join(__dirname, manifest.main)).isFile());
  const fixtureLaunch = JSON.parse(fs.readFileSync(path.join(args[1], ".vscode/launch.json"), "utf8"));
  assert.equal(fixtureLaunch.configurations[0].type, "moondbg");
  assert.equal(fixtureLaunch.configurations[0].connectionTest, true);
  assert.equal(manifest.contributes.debuggers[0].type, "moondbg");
  assert.ok(manifest.activationEvents.includes("onDebugResolve:moondbg"));
});

test("activation registers the declared status command and disposes with the host", async () => {
  const commands = new Map();
  const messages = [];
  const registrations = new Map();
  const vscode = {
    DebugAdapterExecutable: class {
      constructor(command, args) { this.command = command; this.args = args; }
    },
    debug: {
      registerDebugConfigurationProvider(type, provider) {
        assert.equal(type, "moondbg");
        registrations.set("provider", provider);
        return { dispose: () => registrations.delete("provider") };
      },
      registerDebugAdapterDescriptorFactory(type, factory) {
        assert.equal(type, "moondbg");
        registrations.set("factory", factory);
        return { dispose: () => registrations.delete("factory") };
      },
    },
    commands: {
      registerCommand(id, handler) {
        assert.ok(!commands.has(id));
        commands.set(id, handler);
        return { dispose: () => commands.delete(id) };
      },
    },
    window: {
      showErrorMessage(message) { messages.push(message); },
      showInformationMessage(message) {
        messages.push(message);
        return Promise.resolve(undefined);
      },
    },
  };
  const sandbox = {
    module: { exports: {} },
    require(id) {
      if (id === "./launcher") {
        return { resolveDebugger: async () => "/test/.moon/bin/moondbg" };
      }
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
    "moondbg 扩展已加载。支持已编译程序的行断点、调用栈、单步、继续和暂停。",
  ]);
  const provider = registrations.get("provider");
  assert.equal(provider.resolveDebugConfiguration(undefined, { request: "launch" }), undefined);
  const configuration = { request: "launch", connectionTest: true };
  assert.equal(provider.resolveDebugConfiguration(undefined, configuration), configuration);
  const live = { request: "launch", program: "${workspaceFolder}/main.exe" };
  assert.equal(provider.resolveDebugConfiguration(undefined, live), live);
  assert.equal(provider.resolveDebugConfiguration(undefined, { request: "attach", program: "/tmp/a.exe" }), undefined);
  const descriptor = await registrations.get("factory").createDebugAdapterDescriptor();
  assert.equal(descriptor.command, "/test/.moon/bin/moondbg");
  assert.equal(descriptor.args.join(" "), "--dap");
  for (const disposable of context.subscriptions) {
    disposable.dispose();
  }
  assert.equal(commands.size, 0);
  assert.equal(registrations.size, 0);
});
