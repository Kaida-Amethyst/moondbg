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
    const launch = await resolveDebugger(environment);
    assert.equal(launch.executable, executable);
    assert.equal(launch.env.MOON_HOME, moonHome);
    assert.equal(launch.env.PATH, `${path.join(moonHome, "bin")}${path.delimiter}${environment.PATH}`);
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
  assert.equal((await resolveDebugger(environment)).executable, executable);
});

test("explicit setting works without MOON_HOME and propagates the same toolchain", async (t) => {
  const home = await fs.mkdtemp(path.join(os.tmpdir(), "moondbg-setting-"));
  t.after(() => fs.rm(home, { recursive: true, force: true }));
  const moonHome = path.join(home, "tool chain");
  await fs.mkdir(path.join(moonHome, "bin"), { recursive: true });
  await fs.writeFile(path.join(moonHome, "bin/moondbg"), "test", { mode: 0o700 });
  for (const environment of [{}, { MOON_HOME: "/wrong/toolchain", PATH: "/old/bin", KEEP: "yes" }]) {
    const before = { ...environment };
    const result = await resolveDebugger(environment, { moonHome: "~/tool chain", homeDirectory: home });
    assert.equal(result.executable, path.join(moonHome, "bin/moondbg"));
    assert.equal(result.env.MOON_HOME, moonHome);
    assert.equal(result.env.KEEP, environment.KEEP);
    assert.ok(result.env.PATH.startsWith(path.join(moonHome, "bin")));
    assert.deepEqual(environment, before);
  }
  await assert.rejects(resolveDebugger({ MOON_HOME: moonHome }, { moonHome: "/missing/toolchain" }), /无法启动/);
  for (const moonHome of ["relative", "~someone/.moon", "$HOME/.moon", "${env:HOME}/.moon"]) {
    await assert.rejects(resolveDebugger({ MOON_HOME: "/valid" }, { moonHome }), /MOON_HOME 必须为/);
  }
});

test("unsupported hosts fail before attempting to launch a debugger", async () => {
  for (const [platform, arch] of [["darwin", "x64"], ["linux", "arm64"], ["win32", "arm64"]]) {
    await assert.rejects(resolveDebugger({}, { platform, arch }), /aarch64-apple-darwin/);
  }
});
