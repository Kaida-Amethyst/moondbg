const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const root = path.resolve(__dirname, "..");
const manifest = require("../package.json");
// Keep the shipped license byte-for-byte identical to the repository license.
if (!fs.readFileSync(path.join(root, "LICENSE")).equals(
  fs.readFileSync(path.join(root, "../../LICENSE")),
)) throw new Error("Extension LICENSE differs from the repository LICENSE");
const dist = path.join(root, "dist");
fs.mkdirSync(dist, { recursive: true });
const artifact = path.join(dist, `${manifest.name}-${manifest.version}-darwin-arm64.vsix`);
const vsce = path.join(root, "node_modules/@vscode/vsce/vsce");
const result = spawnSync(process.execPath, [vsce, "package", "--target", "darwin-arm64",
  "--pre-release", "--no-dependencies", "--out", artifact], { cwd: root, stdio: "inherit" });
if (result.error) throw result.error;
if (result.status !== 0) process.exit(result.status ?? 1);
console.log(`Local preview artifact: ${artifact}`);
