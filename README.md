# moondbg

MoonBit native 程序的调试器，提供 REPL 和 VS Code 调试，通过 `lldb-dap` 调试，不依赖 Python formatter。

## VS Code 技术预览版

下载 [GitHub Release：vscode-v0.1.1](https://github.com/Kaida-Amethyst/moondbg/releases/tag/vscode-v0.1.1)
中的 `moondbg-0.1.1-darwin-arm64.vsix`。这是预发布版本，尚未上架 VS Code Marketplace。
VSIX **只包含扩展，不包含 moondbg CLI、MoonBit 工具链或 lldb-dap**。

### 安装与启动

1. 安装 CLI。通常通过 `moon install Kaida-Amethyst/moondbg` 安装到 `~/.moon/bin/moondbg`。
   本版自动定位需要 CLI 的 `--resolve-source` 接口；旧版 Mooncakes 包可能尚未包含它。
   要确保 CLI 与此预览版匹配，可在一个新的目录中安装本 release 的源码：

   ```sh
   git clone --branch vscode-v0.1.1 --depth 1 https://github.com/Kaida-Amethyst/moondbg.git moondbg-preview
   cd moondbg-preview
   moon install --path .
   ```

   安装会替换原来的 moondbg CLI，但不会更新你的 MoonBit 工具链。
2. 在 VS Code 按 `Cmd+Shift+P`，执行 **Extensions: Install from VSIX… / 扩展：从 VSIX 安装…**，
   选择下载的 VSIX，随后重新加载窗口。若装过旧 `moondbg-dev`，先卸载，避免调试类型冲突。
3. 在用户设置中将 `moondbg.moonHome` 设为 `~/.moon`（自定义安装则填实际工具链目录）。
   扩展只启动该目录的 `bin/moondbg`，不会搜索 PATH 或自动安装 CLI。
4. 打开要调试的 MoonBit 项目文件夹，打开可执行包中的 `.mbt` 文件并设置断点。
   在命令面板执行 **moondbg：调试当前包**；也可以按 F5 并选择 moondbg。
   不需要编写 `launch.json`。项目已有其他调试配置时，使用当前包命令可避免启动旧配置。

当前文件属于 library、测试文件或非 native 可执行包，或没有打开已保存的源码时，
提示“未确定 main 函数位置”，**不会自动寻找其他可执行包**。
已有明确 `package` / `program` 的启动配置仍按其指定目标运行。
后续更新请从对应 release 下载新 VSIX，按其说明同步 CLI；扩展不自动更新 CLI。

### 支持范围与限制

- 仅支持 macOS Apple Silicon（`aarch64-apple-darwin`）及原生 ARM64 VS Code；
  不支持 Intel Mac、Rosetta、Windows、Linux 或远程调试环境。仅支持受信任的本地文件工作区。
- MoonBit 支持基线记录为 **v0.10.4**；实际验收使用 `moonc v0.10.12+2583f1173-nightly`，
  尚未完成 v0.10.4 的独立兼容性验收。
- 需要 MoonBit 语言扩展，以及可用的 `lldb-dap`（可用 `xcrun --find lldb-dap` 检查）。
  包调试要求整个项目检查通过，以 `-g -O0` 构建；其他包或测试的检查错误也可能阻止启动。
- 支持行/函数断点、单步、暂停、调用栈、变量按需展开、Watch、悬停和程序输出。
  求值仅支持 `point.x`、`arr[0].x` 等只读变量路径，不支持算术、函数调用或赋值。
- 暂不支持 attach、会话内 restart、条件断点、程序参数、环境变量覆盖及交互式 stdin。
  修改代码后重新启动调试；行号与变量可见性仍受编译器 DWARF 和 LLDB 限制。

以上为已发布版本范围；当前源码新增的简单行条件断点见下方“条件断点（开发版本，第一轮）”。

VS Code 安装及使用说明见 [扩展 README](extensions/vscode/README.md)，本地 VSIX 打包见
[打包说明](extensions/vscode/PACKAGING.md)。安装后可在普通 VS Code 窗口调试，不需要扩展开发窗口。
仓库内开发与验收步骤见 [开发说明](extensions/vscode/DEVELOPMENT.md)。
支持 native 程序的行断点、函数断点、调用栈、单步、继续、暂停、局部变量树、悬停、Watch、调试控制台只读访问路径求值、输出和停止。
支持按包 F5 自动构建，也保留直接调试预编译程序。求值支持 `point.x`、`arr[0].x` 等变量路径；暂不支持算术、函数调用或赋值。
函数断点面板支持 `main`、启动包的 `foo` 和 `@alias.foo`，泛型函数匹配所有已生成实例。
普通函数名需要 `package` 启动上下文；预编译 `program` 模式仅支持 `main`。
`connectionTest: true` 配置仅验证 DAP 连接，不启动用户程序或 lldb-dap。

### 条件断点（开发版本，第一轮）

当前源码支持 **行断点** 的简单条件，两种前端使用同一套 MoonBit Int 比较逻辑。
这不是任意 MoonBit 表达式求值，也不会将条件交给 LLDB 的 C/C++ 表达式求值器。

在仓库根目录构建后体验：

```sh
moon build --target native -g .
cd testdata/dwarf_probe
moondbg conditional
```

以上 `moondbg` 须指向本次构建；也可直接使用仓库内 `_build/native/debug/build/moondbg.exe` 的绝对路径。

```text
(moondbg) b conditional/main.mbt:4 if i == 7
(moondbg) run
(moondbg) p i
```

预期只在 `i = 7` 的那轮停住。`b` 和 `break` 均支持 `if` 后缀，暂停后也可用
`b 4 if i == 7` 在当前选中 frame 的源码设置条件断点；函数断点暂不支持条件。
条件会在创建时一起安装，语法错误不会创建断点。`condition 1 i >= 8` 修改条件，`condition 1` 清除条件；
`breakpoints` 显示条件。无效修改不会覆盖原条件；条件随 disable/enable 和再次 run 保留。

VS Code 打开 `testdata/dwarf_probe/conditional/main.mbt`，在第 4 行 `println(i)` 左侧
右键选择 **添加条件断点 / Add Conditional Breakpoint**，选择表达式并填写 `i == 7`，按 F5。
已有红点可以右键编辑条件。停住后变量面板、悬停或 Watch 可查看 `i = 7`。
只需更新 CLI，无需重新安装 VSIX；下一次启动调试时会重新读取条件断点能力。

第一轮边界：

- 左侧仅支持当前命中 frame 的简单局部变量名（ASCII 字母、数字、下划线），类型必须为 `Int`。
- 右侧为十进制 Int 常量（可带负号，范围 -2147483648 到 2147483647）。支持 `>`、`>=`、`<`、`<=`、`==`、`!=`。
- 暂不支持函数断点条件、成员/下标访问、变量间比较、Double、算术、逻辑组合、命中次数或 logpoint。
- 条件读取失败（变量不存在、不可用或类型不符）会停住并报告错误，不当成 false。
- run/continue 在条件为假时自动继续；单步保留 LLDB 的真实停止，不为跳过条件断点而额外继续。
- panic、信号、主动暂停及同时命中的无条件断点不会被条件过滤隐藏。无法可靠识别命中 ID 时也保留停止。
- 每次命中都需要停下并读取变量，频繁命中的循环会比无断点慢；程序输出仍正常保留。

## 命令行使用

安装根目录的可执行包即可：

```sh
moon install Kaida-Amethyst/moondbg
```

在 MoonBit 项目目录中运行 `moondbg <包目录>`，例如 `moondbg main`。
CLI 未设置 `MOON_HOME` 时默认使用 `$HOME/.moon`；显式设置则严格使用该目录，
即使无效也不会回退。解析后的 `MOON_HOME` 会传给构建子进程，不修改 shell 环境。
VS Code 扩展仍按 `moondbg.moonHome` 设置或其进程的 `MOON_HOME` 选择工具链。
也支持包的项目内相对名称和完整包名。目标必须是支持 native 的可执行包；library 包会被拒绝。
启动时调用 `$MOON_HOME/bin/moon check` 获取包信息，再调用
`moon run --build-only --target native -g` 构建目标，自动传入包名和 import alias。
调试构建及元数据保存在项目 `_build/moondbg` 下。
当前元数据获取需要完整项目检查，其他包或测试的检查错误也会阻止启动。

进入提示符后可执行：

```text
b main
run
next
locals
bt
continue
quit
```

`help` 显示完整命令。REPL 内 `run` 会重新运行已构建的程序；修改源码后重新启动 moondbg
以重新构建。

已有可执行文件仍可通过 `moondbg ./program.exe` 调试；需要函数断点时，传入
`--current-package <完整包名>` 及可重复的 `--package-alias alias=package`。
显式指定 `--current-package` 时，整套显式包名和 alias 会替代自动上下文，不会合并。

## 开发与验证

### panic 停点（开发版本）

当前源码中的 REPL 会在 `moonbit_panic` 入口自动停止，显示 `MoonBit panic`。
这是内部停点，不占用用户断点编号，也不受 `delete` / `disable` 影响。
VS Code 也支持此停点，需要本仓库的新 CLI；上面的 release 所对应的旧 CLI 尚不包含此功能。

在构建本仓库 CLI 后可试用：

```sh
cd testdata/dwarf_probe
moondbg panic_stop
```

无需设置断点，直接输入 `run`。停止后用 `bt` 查看 MoonBit 调用栈，
`bt --all` 显示包括 runtime 在内的完整栈，`quit` 退出。
`breakpoints` 仍显示 `No breakpoints.`。
panic 时自动选择最近的项目源码 frame，跳过 core 与第三方依赖；项目自己的 library 包也属于项目源码。
显示的位置、`locals` 和 `p` 使用同一个 frame，`bt --all` 保留完整栈及物理编号。
没有匹配的项目源码 frame 时明确提示，不自动选择依赖代码；可用 `frame <id>` 手动选择。
直接调试预编译可执行文件时没有项目源码元数据，也会提示手动选择，不根据当前目录猜测。
变量可能因编译器调试信息限制而不可用；只报告 panic，不推断越界等具体原因。
继续执行将完成原来的终止流程，可能随后因 SIGABRT 再次停止，并不恢复正常运行。

要验证跳过 core 的 `abort` frame，在同一示例项目运行 `moondbg panic_context`，输入
`run`、`locals`、`p value`、`bt --all`。预期停在项目的 `panic_context_lib/fail.mbt:4`，
当前测试工具链下可看到 `value = 42`，而不是停在 core 的 `abort.mbt`。

VS Code 中打开 `testdata/dwarf_probe`，再打开 `panic_context/main.mbt`，按 F5。
**运行和调试 → 断点** 面板会出现默认勾选的 **MoonBit panic**。无需源码断点，程序会以
`MoonBit panic` 原因停止，自动定位 `panic_context_lib/fail.mbt:4`；变量面板可看到 `value = 42`，
Watch 或调试控制台可直接输入 `value`（不带 REPL 的 `p`）。完整调用栈仍可手动展开、选择。
非项目 frame 只作弱化显示，不删除、重排或伪造位置。缺少项目源码上下文时会明确提示手动选择 frame。

取消勾选只删除 moondbg 的内部 panic 断点，不影响源码/函数断点，也不关闭 LLDB 自身的
SIGABRT 停止行为。再次勾选可重新启用；VS Code 会记住你的选择，因此“默认开启”不覆盖手动选择。
想重新 F5 调试当前包时，先切回 `panic_context/main.mbt`，不要停留在 library 包的源码标签页。
此开关由 CLI 的 DAP capabilities 提供，已有 moondbg 扩展无需重装；结束旧会话后启动新会话即可。

#### 继续、重跑和退出验收

`testdata/dwarf_probe` 提供四个独立可执行包：

| 包目录 | 行为 |
| --- | --- |
| `panic_stop` | 直接调用 `panic()` |
| `panic_bounds` | `Array[Int]` 越界访问 |
| `panic_context` | core `abort` 打印 `panic context example` 后终止 |
| `panic_normal` | 打印一行并正常退出，不能误报 panic |

REPL 运行 `moondbg panic_bounds`，依次输入 `run`、`c`、`run`、`quit`。
第一次停在越界访问处；`c` 执行原有终止逻辑，不恢复正常运行；再次 `run` 创建新进程并再次停止。
当前工具链通常以 code 1 退出，使用 `abort()` 的 runtime 可能随后再停于 `signal SIGABRT`；
此时可直接 `run` 重跑或 `quit` 清理，不会把该信号标成又一次 MoonBit panic。
panic 停止时会显示这一区别的提示；正常结束仍显示 code 0。

VS Code 打开对应包的 `main.mbt` 后 F5，保持 **MoonBit panic** 勾选。
可同时添加 `main` 函数断点和源码行断点；移除普通断点不会移除内部 panic 停点。
panic 后 F5 继续终止；若遇到 SIGABRT，再次停止时显示真实原因。按红色 Stop 可在两种停点清理程序。
结束后先切回可执行包的 `main.mbt` 再 F5，启动的是新会话，不是恢复已终止的进程。

自动验收还使用 `testdata/panic_signal/main.c` 强制覆盖 `panic → abort() → SIGABRT`。
它只是测试替身，不替换 MoonBit runtime；验收会检查重跑/退出前记录的目标、adapter 等子进程已清理。

### 构建和验收

开发工具链要求见 [AGENTS.md](AGENTS.md)。先选择工具链并构建 moondbg：

```sh
source ~/.zshrc
set_moon_stable
moon info && moon fmt
moon check
moon test
moon build --target native -g .
alias moondbg="$PWD/_build/native/debug/build/moondbg.exe"
```

这个 alias 只供当前终端使用。VS Code 固定启动 `$MOON_HOME/bin/moondbg --dap`，
开发用安装或链接方法见 [开发说明](extensions/vscode/DEVELOPMENT.md#更新到本阶段)。

默认测试不启动真实工具链验收。显式开启后，通过真实 PTY 执行 `moondbg`：

```sh
MOONDBG_TOOLCHAIN_ACCEPTANCE=1 moon test acceptance/breakpoint_management_wbtest.mbt --no-parallelize
MOONDBG_TOOLCHAIN_ACCEPTANCE=1 moon test acceptance --no-parallelize
```

第二条包含包启动、断点管理、调用栈、变量及 DAP 验收。2026-09-14 本机 stable
完整验收 20/20 通过，环境和复现说明见[测试文档](docs/testing.md)。
[T-07](docs/discussion/T-07-breakpoint-management.md) 保留此前开发工具链的历史记录。

## 手动体验断点管理

```sh
cd testdata/dwarf_probe
moondbg breakpoint_management
```

停止后可使用 `b 18` 或 `break 18`，在**当前选中 frame 的源码文件**设置第 18 行断点。
数字是从 1 开始的绝对行号，不支持 `+3`、`-3` 或不带参数的 `b`。源码选择与 `list`
一致，`frame`、`up`、`down` 会影响此后新建的裸行号断点；已创建的断点固定在原路径上。
尚未停止或选中 frame 没有源码时，会提示使用 `b <file>:<line>`，不会猜测文件。
原来的 `b <function>`、`b @alias.function` 和 `b <file>:<line>` 仍可使用。

`breakpoints` 列出稳定逻辑 ID、启用状态、当前/历史安装结果及已知落点。`delete <id>`、
`disable <id>`、`enable <id>` 只接受一个十进制正整数，不接受范围或 `all`。禁用保留逻辑
断点，删除不复用 ID；设置跨 `run` 保持，底层句柄每次运行重新建立。

以下从新会话开始。第 18 行是 `MOONDBG_BREAKPOINT_CHECKPOINT` 标记的第一处 println；
若修改了示例，请先核对标记所在行。自动测试从标记读取行号。

```text
b main
b identity
b breakpoint_management/main.mbt:18
run
breakpoints
disable 2
continue
```

此时跳过第一轮两个 `identity` 调用，停在 main 的第一处 println。重新启用并移除该行断点：

```text
enable 2
delete 3
continue
p value
continue
p value
```

两次分别停在第二轮的 `identity[Int]` 和 `identity[Double]`，`value` 为 21 和 2.5。
一个 family 逻辑 ID 管理所有落点，`locations` 是 LLDB 落点数，不是泛型实例统计。

```text
delete 2
continue
breakpoints
run
delete 1
continue
breakpoints
quit
```

删除 family 后第三轮不再命中；第一次结束后的 `breakpoints` 将 main 的旧安装标为
`previous`。重新 `run` 仍由逻辑 ID 1 停在 main，删除后再次运行至结束，列表为空。

源码与精确函数的重复目标、零落点 family、非零 frame 选择和变量观察保持由上述两个
门控测试覆盖。当前工具链下该示例此观察点的调用者 frame 局部变量显示不可用；切回 frame 0 可用
`p value` 观察，不代表管理命令改变了变量状态。

本轮真实验收只针对本机的 LLDB/lldb-dap；未承诺其他 adapter 版本的 CLI 文本兼容性。
短期不提供交互式 stdin，readline 编辑中的异步输出/重绘仍沿用已有边界。
