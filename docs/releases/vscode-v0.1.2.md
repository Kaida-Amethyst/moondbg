# moondbg for VS Code 0.1.2 — 技术预览

仅支持 macOS Apple Silicon（`aarch64-apple-darwin` / VSIX `darwin-arm64`）。
下载 Assets 中的 `moondbg-0.1.2-darwin-arm64.vsix`；尚未上架 Marketplace。
VSIX **不包含 CLI、MoonBit 工具链或 lldb-dap**，本次不发布 Mooncakes 包。

## 本轮更新

以下能力由本标签对应的 moondbg CLI 提供，扩展运行时代码未变：

- **MoonBit panic 停点**：默认开启，停止后优先定位最近的项目源码 frame；保留完整调用栈和变量观察。
  关闭开关不等于关闭 LLDB 自身的 SIGABRT 停止。runtime 尚未提供的错误类别和消息不作推测。
- **条件断点**：支持行、普通函数和泛型函数；可使用字段、数组路径、整数/Bool 比较、括号、
  `&&`、`||`、`!`，按真正的短路规则求值。不隐式转换数值类型，读取失败时停住报错。
- **变量探查**：String/Bytes 有界内容预览及范围访问；tuple/Result 等支持 `.0` 位置成员，
  例如 `result.0.x`，与 Variables 展开、Watch 和 REPL 共用访问规则。
- **嵌套摘要**：如 `Ok(Point { x: 3, y: 4 })`。默认 2 层、每层 4 个成员、合计 16 个值、
  160 个 Unicode 字符；不自动展开数组元素。截断不限制进一步手动探查。
- **错误状态**：区分内存读取失败、LLDB 报告变量不可用、当前 frame 未找到变量；
  证据不足时不将“找不到变量”直接判断为“超出作用域”。
- CLI 未设置 `MOON_HOME` 时默认使用 `$HOME/.moon`；VS Code 仍使用其独立工具链设置。

## 安装或升级

1. 准备原生 ARM64 VS Code、MoonBit 工具链和 MoonBit 语言扩展。
   执行 `xcrun --find lldb-dap` 确认可用。
2. **同步 CLI**。通常可用 `moon install Kaida-Amethyst/moondbg`，但 Mooncakes 包可能落后于本 release。
   要确保获得本轮全部能力，在新的目录执行：

   ```sh
   git clone --branch vscode-v0.1.2 --depth 1 https://github.com/Kaida-Amethyst/moondbg.git moondbg-preview
   cd moondbg-preview
   moon install --path .
   ```

   这会替换已安装的 moondbg CLI，不会更新 MoonBit 工具链；VSIX 不会替你执行此步骤。
3. VS Code 按 `Cmd+Shift+P` → **Extensions: Install from VSIX…** → 选择下载的 VSIX → 重新加载窗口。
   已安装 `moondbg-local.moondbg` 0.1.1 时可直接升级，无需先卸载；旧 `moondbg-dev` 请先卸载或禁用。
4. 用户设置 `moondbg.moonHome` 填 `~/.moon` 或实际工具链目录。
   扩展只启动该目录的 `bin/moondbg`，不搜索 PATH。

打开项目文件夹及可执行包源码，打断点，执行 **moondbg：调试当前包** 或 F5 选择 moondbg。
无需 launch.json。library、测试文件、非 native 可执行包或未打开源码时会拒绝，不搜索其他 main。

## 试用新能力

- 打开仓库 `testdata/dwarf_probe/value_summaries/main.mbt`，在 `SUMMARY_READY` 行打断点后 F5。
  查看 `item`、`nested`、`many`；`many` 摘要只显示 4 项，但展开仍有全部 6 项，Watch 的 `many.5.x` 为 `6`。
- 对 `conditional/main.mbt` 中循环里的行断点设置条件 `i == 7`；不要把 REPL 的 `b ... if ...` 输入 VS Code。
- 调试 `panic_context/main.mbt`，在断点面板保持 **MoonBit panic** 勾选，观察停止原因和用户现场。

## 限制与验收范围

- 仅支持受信任的本地 macOS ARM64 工作区；不支持 Intel、Rosetta、Windows、Linux 或远程调试。
- MoonBit 支持基线记录为 **v0.10.4**；实际验收使用 `moonc v0.10.12+2583f1173-nightly`，
  v0.10.4 独立兼容性验收尚未完成。
- **优化表示的 Option 仍等待编译器支持**，本版不宣称完整支持；不会用源码或数值猜测 Some/None。
- 不支持 attach、会话内 restart、程序参数、环境变量覆盖、交互式 stdin、命中次数或 logpoint。
- Watch 只支持只读变量路径，不支持算术、函数调用或赋值。条件比较暂不支持 Float/Double。
- tuple/enum 位置成员中的复合元素数组暂不能索引；命名变量的复合数组访问不受此限制。
- 项目需通过完整 `moon check`，以 `-g -O0` 构建。源码位置和变量可见性仍依赖 DWARF 与 LLDB。

已通过 `moon check`、425 项默认测试，以及真实工具链验收 57 项；另有 2 个 Option 联调用例因
编译器契约尚未合入而按开关跳过。完整验收后，新构建又通过摘要、位置成员与 String/Bytes 的 6 项专项验收。
另通过 14 项扩展测试及 VSIX 包内容检查；本轮未重新执行真实 VS Code 扩展宿主自动验收，
不将打包成功视为全部 VS Code 版本或旧 MoonBit 的兼容性保证。

更多说明：[README](https://github.com/Kaida-Amethyst/moondbg/blob/vscode-v0.1.2/README.md)、
[变量摘要](https://github.com/Kaida-Amethyst/moondbg/blob/vscode-v0.1.2/docs/value_summary.md)、
[Option 留痕](https://github.com/Kaida-Amethyst/moondbg/blob/vscode-v0.1.2/docs/option_view.md)。
反馈请提交到 [Issues](https://github.com/Kaida-Amethyst/moondbg/issues)，附版本信息和最小复现，勿包含敏感环境变量。
