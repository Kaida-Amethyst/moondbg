# moondbg

MoonBit native 程序的 REPL 调试器，通过 `lldb-dap` 调试，不依赖 Python formatter。

VS Code 调试及逐步操作说明见 [扩展 README](extensions/vscode/README.md)。
从本仓库根目录选择“运行 moondbg 扩展（开发窗口）”，再在新窗口选择“moondbg：调试 main（预编译）”。
支持预编译 native 程序的行断点、调用栈、单步、继续、暂停、输出和停止；暂不支持自动构建、变量树或表达式求值。
`connectionTest: true` 配置仅验证 DAP 连接，不启动用户程序或 lldb-dap。

## 命令行使用

在 MoonBit 项目目录中运行 `moondbg <包目录>`，例如 `moondbg main`。
也支持包的项目内相对名称和完整包名。目标必须是支持 native 的可执行包；library 包会被拒绝。
启动时调用当前环境中的 `moon check` 获取包信息，再调用
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

开发工具链要求见 [AGENTS.md](AGENTS.md)。先选择工具链并构建 moondbg：

```sh
source ~/.zshrc
set_moon_stable
moon info && moon fmt
moon check
moon test
moon build --target native -g main
alias moondbg="$PWD/_build/native/debug/build/main/main.exe"
```

这个 alias 只供当前终端使用。VS Code 固定启动 `$MOON_HOME/bin/moondbg --dap`，
安装或链接方法见 [扩展 README](extensions/vscode/README.md#更新到本阶段)。

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
