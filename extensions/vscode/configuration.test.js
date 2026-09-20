const assert = require("node:assert/strict");
const test = require("node:test");
const { createConfigurationProvider, entryUnknown } = require("./configuration");

function fixture(source = "/project/src/app/main.mbt") {
  const errors = [];
  const calls = [];
  const folder = { uri: { toString: () => "file:///project" } };
  const document = { uri: { scheme: "file", fsPath: source }, isDirty: false, save: async () => true };
  const vscode = {
    ProgressLocation: { Notification: 1 },
    window: {
      activeTextEditor: { document },
      showErrorMessage: message => errors.push(message),
      withProgress: async (_, run) => run({}, { onCancellationRequested: () => ({ dispose() {} }) }),
    },
    workspace: { getWorkspaceFolder: () => folder, getConfiguration: () => ({ get: () => "~/.moon" }) },
  };
  const provider = createConfigurationProvider(vscode, { append() {}, appendLine() {}, show() {} },
    async () => ({}), async (_, file) => {
      calls.push(file);
      if (file.includes("lib")) throw new Error(entryUnknown);
      return { package: "/project/src/app", name: "example/app" };
    });
  return { provider, vscode, errors, calls, folder, document };
}

test("empty F5 and automatic template resolve only the captured source", async () => {
  const f = fixture();
  for (const configuration of [{}, f.provider.provideDebugConfigurations()[0]]) {
    const result = await f.provider.resolveDebugConfiguration(f.folder, configuration);
    assert.equal(result.package, "/project/src/app");
    assert.equal(result.request, "launch");
  }
  assert.deepEqual(f.calls, [f.document.uri.fsPath, f.document.uri.fsPath]);
});

test("library no editor non-source and wrong workspace never choose another entry", async () => {
  const lib = fixture("/project/src/lib/lib.mbt");
  assert.equal(await lib.provider.resolveDebugConfiguration(lib.folder, {}), undefined);
  assert.deepEqual(lib.errors, [entryUnknown]);
  for (const kind of ["absent", "non-source", "untitled", "wrong-folder"]) {
    const f = fixture();
    if (kind === "absent") f.vscode.window.activeTextEditor = undefined;
    if (kind === "non-source") f.document.uri.fsPath = "/project/README.md";
    if (kind === "untitled") f.document.uri.scheme = "untitled";
    const folder = kind === "wrong-folder" ? { uri: { toString: () => "file:///other" } } : f.folder;
    assert.equal(await f.provider.resolveDebugConfiguration(folder, {}), undefined);
    assert.deepEqual(f.calls, []);
    assert.deepEqual(f.errors, [entryUnknown]);
  }
});

test("explicit targets never use source discovery and invalid configs never fall back", async () => {
  const f = fixture();
  f.vscode.window.activeTextEditor = undefined;
  for (const target of [{ package: "/pkg" }, { program: "/bin/exe" }, { connectionTest: true }]) {
    const configuration = { type: "moondbg", request: "launch", ...target };
    assert.equal(await f.provider.resolveDebugConfiguration(f.folder, configuration), configuration);
  }
  for (const bad of [{ package: "" }, { package: "/a", program: "/b" }, { request: "attach" }]) {
    assert.equal(await f.provider.resolveDebugConfiguration(f.folder, { request: "launch", ...bad }), undefined);
  }
  assert.deepEqual(f.calls, []);
});

test("cancelled or unsaved sources never start discovery", async () => {
  const f = fixture();
  assert.equal(await f.provider.resolveDebugConfiguration(f.folder, {}, { isCancellationRequested: true }), undefined);
  f.document.isDirty = true;
  f.document.save = async () => false;
  assert.equal(await f.provider.resolveDebugConfiguration(f.folder, {}), undefined);
  assert.deepEqual(f.calls, []);
});
