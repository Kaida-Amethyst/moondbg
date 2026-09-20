const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const manifest = require("./package.json");

test("preview manifest restricts execution and ships only runtime files", () => {
  assert.equal(manifest.preview, true);
  assert.equal(manifest.publisher, "moondbg-local");
  assert.equal(manifest.capabilities.untrustedWorkspaces.supported, false);
  assert.equal(manifest.capabilities.virtualWorkspaces.supported, false);
  assert.deepEqual(manifest.extensionKind, ["workspace"]);
  assert.equal(manifest.contributes.configuration.properties["moondbg.moonHome"].scope, "machine");
  assert.deepEqual(manifest.files, ["extension.js", "launcher.js", "configuration.js", "discovery.js", "README.md", "LICENSE", "CHANGELOG.md"]);
  for (const file of manifest.files) assert.ok(fs.statSync(path.join(__dirname, file)).isFile());
  assert.ok(fs.readFileSync(path.join(__dirname, "LICENSE")).equals(fs.readFileSync(path.join(__dirname, "../../LICENSE"))));
});
