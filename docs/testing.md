# moondbg 测试体系

moondbg 采用 MoonBit-first、但不是 MoonBit-only 的分层测试。默认测试必须可移植：
`moon test` 不启动 Python、真实 `lldb-dap`、真实 `moondbg <package>` 或仓库外的 fake adapter
进程。真实工具链和跨进程诊断回归使用显式命令运行。

## 默认测试

在按 `AGENTS.md` 选择工具链后运行：

```sh
moon test
```

默认测试包含以下边界：

| 层 | 主要测试手段 | 负责的行为 |
|---|---|---|
| application/session | 纯 MoonBit `FakeDebugBackend` | 稳定逻辑断点重放、用户状态、execution/stop epoch、选择失效和 backend failure |
| CLI 包启动 | 元数据解析单测 + 门控真实项目验收 | 包目录/名称选择、native 可执行资格、构建产物、alias、错误退出 |
| REPL command/presentation | 纯 MoonBit fake backend 与结构化结果断言 | parser、alias、registry、命令调用、事件顺序、human renderer 边界 |
| DAP protocol/framing | 纯 MoonBit JSON 与字节测试 | message classification、UTF-8 framing、request/response inbox |
| DAP dispatcher | `testkit/dap` 的进程内 scripted transport | 完整 request 与 seq、乱序 response、event、adapter request、非法/重复 response、EOF/error/close |
| lldb-dap mapping/lifecycle | 进程内 scripted DAP 会话 | initialize、launch、断点、stop、stack/scopes/variables、struct 递归物化与裁剪、FixedArray/Array 有界内存读取、boxed enum active constructor 浅层物化、next/step/finish、disconnect、稳定断点 ID、cache/epoch、output filtering、失败恢复 |
| readline/PTY | MoonBit 驱动与 `testkit/pty/pty.c` | 真实 `run_repl` + readline 链路、即时提示符、本地 help、quit/exit、Ctrl-C、Ctrl-D 和子进程清理 |
| 源码渲染 | 纯 MoonBit renderer 测试 | 源码窗口、高亮、ANSI 状态和原文本保持 |

PTY 测试会重新执行当前 MoonBit 测试二进制，并让同一个二进制充当一个永不完成 initialize
的最小 adapter 角色。这能验证“提示符和本地命令不等待后台 adapter”，但不依赖 Python 或
`lldb-dap`。单独运行该层可以使用：

```sh
moon test repl/pty_wbtest.mbt --no-parallelize
```

## 真实工具链 acceptance

真实 MoonBit DWARF 闭环位于 capability-gated suite。默认 `moon test` 会在读取工具路径、
探测能力或创建子进程之前跳过它；只有显式设置开关才执行：

```sh
MOONDBG_TOOLCHAIN_ACCEPTANCE=1 \
  moon test acceptance/toolchain_acceptance_wbtest.mbt --no-parallelize
```

先构建本次待测的 CLI：

```sh
moon build --target native -g repl
MOONDBG_TOOLCHAIN_ACCEPTANCE=1 moon test acceptance --no-parallelize
```

默认待测程序为仓库 `_build/native/debug/build/repl/repl.exe`；使用其他构建目录时，设置
`MOONDBG_ACCEPTANCE_EXECUTABLE=/绝对路径/repl.exe`。验收检查 `MOON_HOME` 中的
`moon`、`moonc` 存在且可执行、编译器支持 `-g -O0`，以及 `moon run` 支持
`--build-only --target --debug`。不要求安装 `moondbg` 或提供 `moon debug` 子命令。

随后它在 `testdata/dwarf_probe` 中实际运行 `moondbg pkg_scope`、`moondbg point`、
`moondbg fixed_array_int`、`moondbg array_double`、`moondbg array_points`、
`moondbg list` 和 `moondbg stack_frames`，通过 PTY 完成运行前入口断点、stopped
源码/普通函数/跨包函数/泛型 family 断点、rejected 反馈、命中、跨 execution 重放、
struct 递归打印、字段路径逐层查询、查询失败分类、同 stop cache 与跨 stop 失效、
FixedArray/Array 短值、长值、跨 stop 打印、boxed enum 浅层打印和 `quit`。该层负责工具链集成、MoonBit DWARF、真实
lldb-dap 映射和 moondbg 对 `moon` 的构建调用和包上下文装配，不替代默认的确定性进程内测试。

`package_launch_wbtest.mbt` 使用临时项目验证 `source` 目录、包相对名和完整名、包内 `.`、
空格路径、自动 import alias 以及 library/非 native/缺失目标/编译失败的拒绝行为。

真实验收在 capability gate 之后获取包内共享互斥锁，整个用例结束后释放。
`moon test --no-parallelize` 不禁止同一测试进程中的异步用例并发；现有 C PTY 的同步
`poll` 会阻塞同进程的 DAP IO 和超时处理，因此这些真实会话必须串行执行。
默认 gate 关闭时不会获取锁或创建外部进程。

`stack_frames` 还覆盖物理 backtrace、frame/up/down、caller locals/p/list、内外同名 local
在两个源码位置的选择、continue 后 stop-epoch 重置和 debuggee output event。产品 launch
通过 `!settings set target.input-path /dev/null` 只关闭短期不支持的交互 stdin；acceptance
明确断言 stdout 仍以 begin/end terminal output 区块返回，避免 PTY 后台进程组因读取终端而
收到 `SIGTTIN`。

## 2026-09-14 包启动改造验收

本机通过 `set_moon_stable` 选择 `~/.moon`：moon `0.1.20260911`（`def8c9e`），
moonc `v0.10.12+2583f1173-nightly`，macOS Apple Silicon / 本机 LLDB。

- 默认测试：291/291 通过（真实工具链用例按默认 gate 返回）。
- 完整真实验收：20/20 通过，启动本仓库本次构建的 `repl.exe`。
- 独立手动验证：直接可执行文件 + `--current-package`，函数断点、结构体字段打印、
  `next`、变量打印和正常退出均通过。
- `moon info && moon fmt`、构建及 `git diff --check` 通过，生成接口无变更；
  工具链仍报告仓库已有的 unused import / native stub 警告。

验收迁移同时修正了 T-07 对旧 `$...identity|[Int]|` 函数显示格式的断言，
并用共享互斥避免同步 PTY 等待阻塞同进程的其他异步测试。

## 可选 Python 诊断回归

`tools/repl_e2e.py` 与 `tools/fake_dap.py` 暂时保留为可选的跨进程诊断基线，不被任何默认
MoonBit test package 调用：

```sh
python3 tools/repl_e2e.py --fake-only
python3 tools/repl_e2e.py --real-only
```

新 MoonBit 测试已经等价覆盖正常 fake lifecycle、stepping、preparation/launch failure
恢复、readline 控制键和 early quit。Python E2E 仍额外覆盖独立解释器 fake adapter 进程、
跨进程 trace、stopped 动态断点与失败后重放、running/continue failure、真实 wall-clock
initialization timeout、异常退出和进程组资源回收，因此目前保留为显式诊断回归，而不是
默认依赖。

`tools/dap_capability_probe.py` 是面向真实 adapter 的原始协议诊断工具，不属于默认测试，也
不因测试语言迁移而删除。用法见其 `--help`；它适合检查新 lldb-dap 版本的 capability、
消息顺序和变量结果。

`tools/stack_frame_probe.py` 固化 T-06/P1 的真实调用栈、栈帧和局部变量协议基线。先构建
`stack_frames` fixture，再从仓库根目录运行：

```sh
source ~/.zshrc
set_moon_stable
cd testdata/dwarf_probe
moon check
moon build --target native --debug
cd ../..
PYTHONDONTWRITEBYTECODE=1 python3 tools/stack_frame_probe.py
```

探针通过源码中的唯一 `MOONDBG_STACK_LEAF_BREAKPOINT` 标记定位停点，默认以 3 帧为一页
请求 `stackTrace`，并逐 frame 记录 `scopes`、Locals 和直接 variables。标准输出是带
`schemaVersion` 的 JSON，包含未经 renderer 改写的 DAP frame/scope/variable、推断出的
availability、请求与消息顺序、结构检查和已知工具链 findings。它还重新选择顶层 frame，并
在 continue 后探测旧 frame/variables reference 的 adapter 行为。该工具是显式诊断，不由
默认 `moon test` 调用；地址、threadId、frameId 和错误寄存器值会随运行变化，不应把完整
JSON 当作文本快照。

当前 Apple LLDB 会在同一个 subprogram 同时具有 `DW_AT_name` 和 `DW_AT_linkage_name` 时，
把 `stackTrace.name` 映射成 linkage symbol。探针因此有意检查未经 moondbg 改写的 `_M0F...`
raw name；用户可读名称由 lldb-dap backend 的结构化兼容映射产生，不应把探针的 raw name
误当成 renderer 契约。

`tools/dynamic_breakpoint_probe.py` 固化 Q-02 所依赖的 stopped 状态动态断点协议语义。先在
`testdata/dwarf_probe` 中执行 `moon build --target native --debug`，再从仓库根目录运行：

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/dynamic_breakpoint_probe.py
```

它会直接连接真实 lldb-dap，验证源码与精确函数断点的整组替换、function-family 增量命令、
重复 family、零 location、请求拒绝，以及动态断点随后的命中。

`tools/struct_variable_probe.py` 固化 Q-03 依赖的 MoonBit struct 协议形状。先通过
`moon build --target native -g point` 生成完整 DWARF 产物，再从仓库根目录运行：

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/struct_variable_probe.py
```

它验证 `Point -> x/y` 和 `Line -> start/end -> x/y` 的 `variablesReference`、
字段类型、值与递归请求。

`tools/fixed_array_probe.py` 固化 Q-04 依赖的原始 FixedArray header、payload pointer 和
首尾元素行为。先通过 `moon build --target native -g fixed_array_int` 生成完整 DWARF 产物，再从仓库根目录运行：

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/fixed_array_probe.py
```

它不加载 `moonbit.py`，直接验证 `readMemory` capability、长度 10/100、`int *` payload
以及两次停点的首尾值。

## 变更时应运行的层

- 修改 core/session：默认 `moon test`。
- 修改 command、renderer 或 readline 组装：默认测试并单独运行 PTY suite。
- 修改 DAP dispatcher 或 lldb mapping：默认测试；涉及真实 adapter 兼容时再运行
  toolchain acceptance。
- 修改包启动流程、debug-info 或 MoonBit DWARF：必须运行 toolchain acceptance；必要时
  再运行 Python real-only 和 capability probe 取得详细诊断。
