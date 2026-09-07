const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const { resolveDebugger } = require("./launcher");

test("missing, relative and stable MOON_HOME are rejected without a PATH fallback", async () => {
  for (const value of [undefined, "~/.moon_dev", ".moon_dev", "/test/.moon"]) {
    await assert.rejects(resolveDebugger({ MOON_HOME: value }, "/test"), /MOON_HOME 必须为/);
  }
});

test("only an executable development symlink is accepted", async (t) => {
  const home = await fs.mkdtemp(path.join(os.tmpdir(), "moondbg-launcher-"));
  t.after(() => fs.rm(home, { recursive: true, force: true }));
  const moonHome = path.join(home, ".moon_dev");
  const executable = path.join(moonHome, "bin", "moondbg");
  const environment = { MOON_HOME: moonHome };
  await fs.mkdir(path.dirname(executable), { recursive: true });
  await assert.rejects(resolveDebugger(environment, home), /无法启动/);
  await fs.writeFile(executable, "not a symlink");
  await assert.rejects(resolveDebugger(environment, home), /必须是.*软链接/);
  await fs.unlink(executable);
  const target = path.join(home, "adapter");
  await fs.symlink(target, executable);
  await assert.rejects(resolveDebugger(environment, home), /无法启动/);
  await fs.writeFile(target, "test fixture", { mode: 0o600 });
  await assert.rejects(resolveDebugger(environment, home), /无法启动/);
  await fs.chmod(target, 0o700);
  assert.equal(await resolveDebugger(environment, home), executable);
});
