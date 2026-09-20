const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const { discoverSource } = require("./discovery");

async function fakeCli(t, script) {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "moondbg-discovery-"));
  t.after(() => fs.rm(dir, { recursive: true, force: true }));
  const executable = path.join(dir, "moondbg");
  await fs.writeFile(executable, `#!${process.execPath}\n${script}`, { mode: 0o700 });
  return { executable, env: process.env };
}

test("discovery parses JSON separately from diagnostics and reports CLI upgrades", async (t) => {
  const cli = await fakeCli(t, 'console.error("checking"); console.log(JSON.stringify({protocolVersion:1,package:"/a b/pkg",name:"a/pkg"}));');
  const diagnostics = [];
  assert.equal((await discoverSource(cli, "/a b/main.mbt", { onDiagnostic: text => diagnostics.push(text) })).package, "/a b/pkg");
  assert.match(diagnostics.join(""), /checking/);
  const old = await fakeCli(t, 'console.log("Usage: moondbg"); process.exit(2);');
  await assert.rejects(discoverSource(old, "/src/main.mbt"), /更新 CLI/);
  const lib = await fakeCli(t, 'console.log(JSON.stringify({protocolVersion:1,error:"未确定 main 函数位置"})); process.exit(1);');
  await assert.rejects(discoverSource(lib, "/src/lib.mbt"), /未确定 main 函数位置/);
});

test("cancel and timeout kill the owned discovery group", async (t) => {
  const cli = await fakeCli(t, 'console.error("ready"); setInterval(()=>{},1000);');
  const controller = new AbortController();
  await assert.rejects(discoverSource(cli, "/main.mbt", { signal: controller.signal,
    onDiagnostic: () => controller.abort() }), { name: "AbortError" });
  await assert.rejects(discoverSource(cli, "/main.mbt", { timeout: 100 }), /超时/);
});
