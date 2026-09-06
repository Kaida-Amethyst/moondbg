# moondbg

MoonBit native 程序的 REPL 调试器，通过 `lldb-dap` 调试，不依赖 Python formatter。

## 开发与验证

开发工具链要求见 [AGENTS.md](AGENTS.md)。先切换到本地开发环境并构建 moondbg：

```sh
source ~/.zshrc
set_moon_dev
moon info && moon fmt
moon check
moon test
moon build
```

默认测试不启动真实工具链验收。显式开启后，通过真实 PTY 执行 `moon debug`：

```sh
MOONDBG_TOOLCHAIN_ACCEPTANCE=1 moon test acceptance/breakpoint_management_wbtest.mbt --no-parallelize
MOONDBG_TOOLCHAIN_ACCEPTANCE=1 moon test acceptance --no-parallelize
```

第二条包含历史功能验收；本地工具链的已知基线差异及本轮实际通过数记录在
[T-07](docs/discussion/T-07-breakpoint-management.md)，不能把新增断点管理测试通过视为全部
历史验收通过。

## 手动体验断点管理

```sh
cd testdata/dwarf_probe
moon debug breakpoint_management
```

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
