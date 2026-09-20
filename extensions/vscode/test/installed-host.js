// A separate test-driver extension hosts this test. moondbg itself MUST be
// loaded from an installed VSIX, not --extensionDevelopmentPath.
const assert = require("node:assert/strict");
const path = require("node:path");
const vscode = require("vscode");

exports.run = async function () {
  const extension = vscode.extensions.getExtension("moondbg-local.moondbg");
  assert.ok(extension, "Installed VSIX extension is missing");
  assert.equal(path.dirname(extension.extensionPath), process.env.MOONDBG_INSTALLED_EXTENSIONS);
  assert.equal(extension.packageJSON.version, "0.1.1");
  // Test the GUI-launch path: no inherited MOON_HOME; machine-scoped user
  // configuration supplies it and the installed CLI gets the resolved value.
  assert.ok(!process.env.MOON_HOME);
  const moonHome = process.env.MOONDBG_TEST_MOON_HOME || "~/.moon";
  await vscode.workspace.getConfiguration("moondbg").update("moonHome", moonHome, vscode.ConfigurationTarget.Global);
  assert.equal(vscode.workspace.getConfiguration("moondbg").get("moonHome"), moonHome);
  await require("./functions-host").run();
  // Also exercise editor source breakpoints, variable trees and read-only
  // evaluation through the installed adapter, using an automatic package build.
  process.env.MOONDBG_TEST_BUILD_PACKAGE = "1";
  await require("./live-host").run();
  console.log(`Installed VSIX verified: ${extension.extensionPath}`);
};
