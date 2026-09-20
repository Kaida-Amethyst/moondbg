# moondbg for VS Code 0.1.1 — 技术预览

首个 GitHub VSIX 预览版本，仅支持 macOS Apple Silicon（`aarch64-apple-darwin`）。
下载本页 Assets 中的 `moondbg-0.1.1-darwin-arm64.vsix`；不要把 Source code 压缩包当成 VSIX 安装。
尚未上架 Marketplace；VSIX 不包含 CLI、MoonBit 工具链或 lldb-dap。

## 安装

1. 准备原生 ARM64 VS Code、MoonBit 工具链及 MoonBit 语言扩展。
   用 `xcrun --find lldb-dap` 确认系统提供 lldb-dap。
2. CLI 通常使用 `moon install Kaida-Amethyst/moondbg` 安装。
   自动定位需要 `--resolve-source` 接口；旧 Mooncakes 包可能尚未包含本次改动。
   要确保版本一致，可在新目录中从本 release 安装 CLI：

   ```sh
   git clone --branch vscode-v0.1.1 --depth 1 https://github.com/Kaida-Amethyst/moondbg.git moondbg-preview
   cd moondbg-preview
   moon install --path .
   ```

   这会替换已安装的 moondbg CLI，不会更新 MoonBit 工具链。
3. VS Code 按 `Cmd+Shift+P` → **Extensions: Install from VSIX…** → 选择下载的 VSIX → 重新加载窗口。
   若安装过 `moondbg-dev`，先卸载它。
4. 用户设置 `moondbg.moonHome` 填 `~/.moon`，或实际 MoonBit 安装目录。
   扩展只启动该目录中的 `bin/moondbg`，不搜索 PATH，也不自动安装 CLI。

## 开始调试

打开 MoonBit 项目文件夹和可执行包的 `.mbt` 源码，打断点，执行命令 **moondbg：调试当前包**，
或者按 F5 选择 moondbg。不需要 launch.json；已有其他调试器配置时优先使用当前包命令。
支持自动构建、行/函数断点、继续、单步、暂停、调用栈、变量树、Watch、悬停及程序输出。

当前文件属于 library、测试文件或非 native 可执行包，或没有打开已保存的源码，
会提示“未确定 main 函数位置”，不会搜索其他可执行包。显式 package/program 配置保持原有行为。

## 限制

- 仅受信任的本地 macOS ARM64 工作区；不支持 Intel、Rosetta、Windows、Linux 或远程调试环境。
- MoonBit 支持基线记录为 **v0.10.4**；实际验收使用 `moonc v0.10.12+2583f1173-nightly`，
  v0.10.4 独立兼容性验收尚未完成。
- 按包启动要求整个项目检查通过，包括其他包和测试；以 `-g -O0` 构建。
- 求值支持只读变量路径，如 `point.x`、`arr[0].x`；不支持算术、函数调用、赋值。
- 暂不支持条件断点、attach、会话内 restart、程序参数、环境变量覆盖、交互式 stdin。
- 源码行号和变量可见性依赖编译器 DWARF 与 LLDB；不可用的值不代表零或空数组。
- 扩展和 CLI 分别安装；后续下载新版 VSIX 时需按该版说明同步 CLI。

已通过 `moon check`、默认测试 329 项、扩展测试 14 项，以及源文件定位/构建相关集成测试 6 项；
实际安装 VSIX 后验证了无配置启动、library/无源码拒绝、源码和函数断点、调用栈、变量与求值。

详细说明见 [README](https://github.com/Kaida-Amethyst/moondbg/blob/vscode-v0.1.1/README.md)。
反馈请附上系统、VS Code、MoonBit 与 LLDB 版本及最小复现，提交到
[Issues](https://github.com/Kaida-Amethyst/moondbg/issues)，勿包含敏感环境变量。
