# moondbg 测试体系

moondbg 采用 MoonBit-first、但不是 MoonBit-only 的分层测试。默认测试必须可移植：
`moon test` 不启动 Python、真实 `lldb-dap`、开发版 `moon debug` 或仓库外的 fake adapter
进程。真实工具链和跨进程诊断回归使用显式命令运行。

## 默认测试

在按 `AGENTS.md` 切换到本地开发工具链后运行：

```sh
moon test
```

默认测试包含以下边界：

| 层 | 主要测试手段 | 负责的行为 |
|---|---|---|
| application/session | 纯 MoonBit `FakeDebugBackend` | 稳定逻辑断点重放、用户状态、execution/stop epoch、选择失效和 backend failure |
| REPL command/presentation | 纯 MoonBit fake backend 与结构化结果断言 | parser、alias、registry、命令调用、事件顺序、human renderer 边界 |
| DAP protocol/framing | 纯 MoonBit JSON 与字节测试 | message classification、UTF-8 framing、request/response inbox |
| DAP dispatcher | `testkit/dap` 的进程内 scripted transport | 完整 request 与 seq、乱序 response、event、adapter request、非法/重复 response、EOF/error/close |
| lldb-dap mapping/lifecycle | 进程内 scripted DAP 会话 | initialize、launch、断点、stop、stack/scopes/variables、struct 递归物化与裁剪、FixedArray/Array 有界内存读取、next/step/finish、disconnect、稳定断点 ID、cache/epoch、output filtering、失败恢复 |
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

该 suite 先检查：

- `MOON_HOME` 是 `~/.moon_dev`；
- `moon`、`moonc`、`moondbg` 是存在且可执行的软链接；
- `moonc build-package` 与 `moonc link-core` 支持完整 debug info；
- `moon debug` 子命令存在。

随后它在 `testdata/dwarf_probe` 中实际运行 `moon debug main`、`moon debug point`、
`moon debug fixed_array_int` 和 `moon debug array_double`，通过 PTY 完成运行前入口断点、stopped
源码/普通函数/跨包函数/泛型 family 断点、rejected 反馈、命中、跨 execution 重放、
struct 递归打印、字段路径逐层查询、查询失败分类、同 stop cache 与跨 stop 失效、
FixedArray/Array 短值、长值、跨 stop 打印和 `quit`。该层负责工具链集成、MoonBit DWARF、真实
lldb-dap 映射和 `moon` 到 `moondbg` 的装配，不替代默认的确定性进程内测试。

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

`tools/dynamic_breakpoint_probe.py` 固化 Q-02 所依赖的 stopped 状态动态断点协议语义。先在
`testdata/dwarf_probe` 中执行 `moon build --target native --debug`，再从仓库根目录运行：

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/dynamic_breakpoint_probe.py
```

它会直接连接真实 lldb-dap，验证源码与精确函数断点的整组替换、function-family 增量命令、
重复 family、零 location、请求拒绝，以及动态断点随后的命中。

`tools/struct_variable_probe.py` 固化 Q-03 依赖的 MoonBit struct 协议形状。先通过
`moon debug point` 生成完整 DWARF 产物，再从仓库根目录运行：

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/struct_variable_probe.py
```

它验证 `Point -> x/y` 和 `Line -> start/end -> x/y` 的 `variablesReference`、
字段类型、值与递归请求。

`tools/fixed_array_probe.py` 固化 Q-04 依赖的原始 FixedArray header、payload pointer 和
首尾元素行为。先通过 `moon debug fixed_array_int` 生成完整 DWARF 产物，再从仓库根目录运行：

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
- 修改 `moon debug`、debug-info 或 MoonBit DWARF：必须运行 toolchain acceptance；必要时
  再运行 Python real-only 和 capability probe 取得详细诊断。
