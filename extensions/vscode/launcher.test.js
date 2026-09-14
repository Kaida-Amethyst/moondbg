const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const { resolveDebugger } = require("./launcher");

test("missing and relative MOON_HOME are rejected without a PATH fallback", async () => {
  for (const value of [undefined, "", "~/.moon", ".moon"]) {
    await assert.rejects(resolveDebugger({ MOON_HOME: value }), /MOON_HOME 必须为/);
  }
});

test("stable and custom toolchains accept regular executables without searching PATH", async (t) => {
  const home = await fs.mkdtemp(path.join(os.tmpdir(), "moondbg-launcher-"));
  t.after(() => fs.rm(home, { recursive: true, force: true }));
  for (const directory of [".moon", "custom toolchain"]) {
    const moonHome = path.join(home, directory);
    const executable = path.join(moonHome, "bin", "moondbg");
    const environment = { MOON_HOME: moonHome, PATH: process.env.PATH };
    await fs.mkdir(path.dirname(executable), { recursive: true });
    await assert.rejects(resolveDebugger(environment), /无法启动/);
    await fs.mkdir(executable);
    await assert.rejects(resolveDebugger(environment), /不是普通文件/);
    await fs.rmdir(executable);
    await fs.writeFile(executable, "test fixture", { mode: 0o600 });
    await assert.rejects(resolveDebugger(environment), /无法启动/);
    await fs.chmod(executable, 0o700);
    assert.equal(await resolveDebugger(environment), executable);
  }
});

test("valid executable symlinks are accepted, broken and non-executable targets are rejected", async (t) => {
  const home = await fs.mkdtemp(path.join(os.tmpdir(), "moondbg-launcher-"));
  t.after(() => fs.rm(home, { recursive: true, force: true }));
  const moonHome = path.join(home, ".moon");
  const executable = path.join(moonHome, "bin", "moondbg");
  const environment = { MOON_HOME: moonHome };
  await fs.mkdir(path.dirname(executable), { recursive: true });
  const target = path.join(home, "adapter");
  await fs.symlink(target, executable);
  await assert.rejects(resolveDebugger(environment), /无法启动/);
  await fs.writeFile(target, "test fixture", { mode: 0o600 });
  await assert.rejects(resolveDebugger(environment), /无法启动/);
  await fs.chmod(target, 0o700);
  assert.equal(await resolveDebugger(environment), executable);
});
