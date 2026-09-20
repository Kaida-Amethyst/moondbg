const { spawn } = require("node:child_process");
const path = require("node:path");

function cancelled() {
  const error = new Error("已取消入口定位。");
  error.name = "AbortError";
  return error;
}

// The new CLI discovery entry keeps moon/compiler descendants in this owned
// process group. Cancelling the group cannot affect another debug session.
function discoverSource(launch, source, { signal, onDiagnostic = () => {}, timeout = 120000 } = {}) {
  if (signal?.aborted) return Promise.reject(cancelled());
  return new Promise((resolve, reject) => {
    const child = spawn(launch.executable, ["--resolve-source", source], {
      env: launch.env, detached: true, stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let failure;
    let bytes = 0;
    const stop = (error) => {
      failure ??= error;
      if (child.pid) {
        try { process.kill(-child.pid, "SIGKILL"); } catch (error) {
          if (error.code !== "ESRCH") child.kill("SIGKILL");
        }
      }
    };
    const abort = () => stop(cancelled());
    const timer = setTimeout(() => stop(new Error("定位入口超时，请检查 MoonBit 工具链或项目检查输出。")), timeout);
    signal?.addEventListener("abort", abort, { once: true });
    const cleanup = () => { clearTimeout(timer); signal?.removeEventListener("abort", abort); };
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    const bounded = (text) => {
      bytes += Buffer.byteLength(text);
      if (bytes > 1024 * 1024) { stop(new Error("入口定位输出超过 1 MiB。")); return false; }
      return !failure;
    };
    child.stdout.on("data", (text) => { if (bounded(text)) stdout += text; });
    child.stderr.on("data", (text) => { if (bounded(text)) onDiagnostic(text); });
    child.on("error", (error) => { cleanup(); reject(error); });
    child.on("close", (code) => {
      cleanup();
      if (failure) return reject(failure);
      let result;
      try { result = JSON.parse(stdout); } catch { /* older CLI prints human help */ }
      if (result?.protocolVersion !== 1) {
        return reject(new Error("已安装的 moondbg 不支持当前文件入口定位，请先更新 CLI（需要 --resolve-source），再启动调试。"));
      }
      if (typeof result.error === "string") return reject(new Error(result.error));
      if (code !== 0 || typeof result.package !== "string" || !path.isAbsolute(result.package) ||
          typeof result.name !== "string") return reject(new Error("moondbg 返回了无效的入口定位结果。"));
      resolve(result);
    });
  });
}

module.exports = { discoverSource };
