# moondbg 第一版实现提案

> 状态：提案
>
> 最后更新：2026-08-22

## 1. 背景

MoonBit native 后端已经开始生成可供 LLDB 使用的 DWARF 信息，`moon debug
<executable-package>` 也能够使用 full debug info 构建可执行文件并打开 LLDB。下一步需要
一个 MoonBit 感知的调试前端，为用户提供稳定的 MoonBit 命令、值展示和错误信息，同时
隐藏底层 LLDB/GDB 的符号名、运行时布局和命令差异。

本项目暂名 `moondbg`。用户的主要入口仍然是 `moon debug`；`moondbg` 是由构建系统调用
的独立工具，也可以直接接收一个已经构建好的 native 可执行文件。

## 2. 核心决定

第一版采用以下实现方式：

1. `moondbg` 使用 MoonBit 编写，并只支持 native target。
2. REPL 引入 `Kaida-Amethyst/readline.mbt`，复用其行编辑、History、Ctrl-C 恢复和补全能力。
3. 不控制面向人类的 `lldb` CLI，也不解析 LLDB 的终端文本。
4. 启动 `lldb-dap` 子进程，通过 stdin/stdout 上的 Debug Adapter Protocol（DAP）通信。
5. 用户 DSL 先解析成与具体 debugger 无关的内部命令，再由 LLDB backend 翻译为 DAP
   request。
6. 人类 REPL、未来的 DAP server 和面向 AI 的结构化接口共享同一个调试 session。

本机 macOS 工具链可以通过 `xcrun --find lldb-dap` 定位 adapter。Linux 上则从 PATH
查找 `lldb-dap`，也允许用户通过命令行参数显式指定路径。

## 3. 目标与非目标

### 3.1 第一版目标

- 从 `moon debug <executable-package>` 接收可执行文件、工作目录、参数和 source map。
- 直接以可执行文件启动 `moondbg`，不依赖 `moon` 也可以建立调试 session。
- 提供带 History 和补全的同步 REPL。
- 支持断点、运行、继续、源码级单步、调用栈、frame 选择、局部变量和基础表达式查看。
- 使用结构化的 DAP response/event 生成稳定、可测试的人类输出。
- 保留执行原始 LLDB 命令的逃生通道，但不让它成为正常实现路径。
- 为后续 GDB、DAP server 和 AI client 保留清楚的扩展边界。

### 3.2 第一版非目标

- 完整实现 MoonBit 表达式编译和求值。
- 支持赋值、函数调用和可能有副作用的表达式。
- watchpoint、reverse debugging、多进程和远程调试。
- 同时支持 LLDB 和 GDB；第一版只实现 LLDB backend。
- 向 IDE 暴露完整 DAP server；第一版先把内部模型设计成可复用。
- 在程序运行期间保持一个可并发输入的 REPL。
- 完整支持需要共享终端输入的交互式被调试程序。

## 4. 总体架构

```text
moon debug <pkg>
        │
        │ full DWARF build
        ▼
     moondbg
        │
        ├── REPL (readline.mbt)
        │       │
        │       ▼
        ├── DSL parser ──> DebugCommand
        │                       │
        │                       ▼
        ├── DebugSession / state machine
        │                       │
        │                       ▼
        ├── DebugBackend ──> LldbDapBackend
        │                       │
        │                       ▼
        └── native transport ──> lldb-dap ──> LLDB ──> debuggee
```

推荐的源码边界如下，实际目录可以在实现过程中根据 MoonBit package 粒度调整：

```text
command/       DSL token、parser 和 DebugCommand
session/       session 状态机、request 协调和 debugger 无关的事件
backend/       DebugBackend 接口
lldb/          DebugCommand 到 LLDB-DAP 的映射
dap/           DAP 消息类型、framing、client 和 capability negotiation
transport/     MoonBit API 与少量 native C stub
render/        human、plain/JSON 等输出格式
repl/          readline.mbt 驱动的可执行程序
tests/         fake adapter 和端到端 fixture
```

DSL parser 不应直接返回 LLDB 命令字符串。内部命令需要表达用户意图，例如
`SetSourceBreakpoint`、`Continue` 和 `Evaluate`。这样未来增加 GDB backend 时不必重写
REPL 和 MoonBit 语义层。

## 5. 与 `moon debug` 的边界

`moon` 继续负责构建相关工作：

1. 确认参数指向 executable package。
2. 使用 native target、`-O0` 和 full debug info 构建。
3. 完成链接和平台需要的符号处理，例如 macOS 的 `dsymutil`。
4. 释放 build lock。
5. 执行 `moondbg`，传入 program、cwd、程序参数、source map 和必要的工具链路径。

`moondbg` 不重新实现 package 解析或构建图。它只负责一个已经确定的 native 调试
session。现有 `moon debug` 中执行 `lldb -- <executable>` 的最后一步，可以替换为执行：

```text
moondbg --program <executable> --cwd <workspace> [-- <program-args>]
```

## 6. REPL

项目需要把 `preferred_target` 改为 `native`，并在 module/package 配置中引入
`Kaida-Amethyst/readline.mbt`。

第一版使用同步 REPL：

1. 仅在 debuggee 处于未启动、停止或已退出状态时显示 prompt。
2. 用户提交命令后，REPL 将命令交给 `DebugSession`。
3. 如果命令恢复了进程，主循环读取并处理 DAP response/event，直到收到 `stopped` 或
   `terminated`。
4. session 再次达到稳定状态后重新显示 prompt。

推荐 prompt：

```text
moondbg> 
```

readline completer 根据当前 token 和 session 状态提供候选：命令名、现有断点编号、frame
编号和可见变量名。第一版不在 completer callback 中执行耗时的 debugger 请求；需要动态
数据时，由 session 在停止后提前缓存。

这种同步模型避免第一版立即处理“调试程序输出、DAP event 和 readline 重绘同时发生”的
复杂问题。后续如果允许程序运行期间继续输入命令，再引入后台 reader、事件队列以及安全
的外部输出重绘接口。

## 7. 第一版命令

命令应当有完整名称和常用短别名。解析结果是 `DebugCommand`，别名不进入 backend。

### 7.1 Session

| 命令 | 别名 | 行为 |
|---|---|---|
| `run [args...]` | `r` | 首次启动 debuggee；已经启动过时执行 restart |
| `quit` | `q` | 终止或 detach 当前 session，并退出 REPL |
| `help [command]` | `h` | 显示命令或某个命令的帮助 |

允许在第一次 `run` 前设置断点。此时断点保存在 `DebugSession`；`run` 发出 DAP `launch`
后，等待 `initialized` event，再把断点提交给 adapter 并发送 `configurationDone`。

### 7.2 Breakpoint

| 命令 | 别名 | 行为 |
|---|---|---|
| `break <function>` | `b <function>` | 设置函数断点 |
| `break <file>:<line>` | `b <file>:<line>` | 设置源码断点 |
| `break list` | `bl` | 显示已有断点及 verified 状态 |
| `break delete <id>` | `bd <id>` | 删除指定断点 |
| `break clear` |  | 删除所有断点 |

`b main` 是 executable package 入口的稳定语义。非 main 函数第一版接受 DWARF 暴露的
完整 MoonBit 名称，例如：

```text
b "$username/play/main.is_prime"
```

短函数名解析和重名候选展示可以后续增加，不应让首版静默选择多个同名函数之一。

### 7.3 Execution

| 命令 | 别名 | DAP request |
|---|---|---|
| `continue` | `c` | `continue` |
| `next` | `n` | `next` |
| `step` | `s` | `stepIn` |
| `finish` |  | `stepOut` |

这些命令必须显式携带当前 thread id。收到 `stopped` event 后，session 更新当前 thread、
frame、源码位置和 stop reason，再交给 renderer 输出。

### 7.4 Stack 与变量

| 命令 | 别名 | 行为 |
|---|---|---|
| `backtrace` | `bt` | 获取并显示当前线程调用栈 |
| `frame [id]` | `f [id]` | 显示或切换当前 frame |
| `up` |  | 选择调用者 frame |
| `down` |  | 选择被调用者 frame |
| `locals` |  | 显示当前 frame 的局部变量和参数 |
| `print <expr>` | `p <expr>` | 在当前 frame 中查看表达式 |

`print` 第一版至少支持单个标识符。字段访问和固定整数下标可以逐步加入 MoonBit
expression parser，并通过当前 frame 的类型信息做翻译。尚未支持的 MoonBit 表达式应返回
明确的 `unsupported expression`，不能悄悄把它当作 C/C++ 表达式改变语义。

第一版可以保留一个显式 backend escape hatch：

```text
lldb <raw-command>
```

该命令通过 LLDB-DAP 的 REPL evaluation/command escape 机制执行普通 LLDB 命令。它的
结果标记为 raw backend output，不经过 MoonBit 值格式化，也不承诺跨 LLDB 版本稳定。

## 8. LLDB-DAP 通信

### 8.1 进程与管道

MoonBit core 当前没有满足需求的通用双向子进程 API，因此需要一个范围受限的 native C
stub。C 层负责：

- 使用 `posix_spawnp` 启动 `lldb-dap`，不经过 shell；
- 为 adapter stdin、stdout 和 stderr 建立独立 pipe；
- 提供 blocking `read`、`write_all`、`wait`、`terminate` 和资源释放操作；
- 保存 OS error code，并在 MoonBit 边界转换成结构化错误；
- 保证异常路径关闭 fd 并回收子进程。

DAP framing、JSON、状态机和业务逻辑全部使用 MoonBit 实现，不放进 C stub。

被调试程序的 stdin/stdout 不能复用 adapter 的协议 pipe。第一版默认通过 DAP `output`
event 接收程序输出，并优先支持非交互程序。交互式程序以后使用独立 PTY 或 adapter 的
console/stdio 能力。

### 8.2 DAP framing

DAP 消息由 ASCII header 和 UTF-8 JSON body 组成：

```text
Content-Length: <body 的 UTF-8 字节数>\r\n
\r\n
<JSON body>
```

reader 必须：

1. 读取到 `\r\n\r\n`，而不是按单行 JSON 解析；
2. 校验 `Content-Length`；
3. 精确读取指定字节数，正确处理 partial read；
4. 区分 request、response 和 event；
5. 对未知 JSON 字段保持向前兼容。

writer 为每个 request 分配递增的 `seq`。response 通过 `request_seq` 与请求关联；event
没有对应请求，必须独立驱动 session 状态变化。第一版可以限制为一个主要 request 在途，
但数据结构不应依赖 response 与 event 的到达顺序。

### 8.3 Session 建立

建议的启动流程：

1. 定位并启动 `lldb-dap`。
2. 发送 `initialize`，保存 adapter 返回的 capabilities。
3. REPL 进入“目标未启动”状态，允许用户先登记断点。
4. 用户执行 `run` 后发送 `launch`，包含 program、cwd、args、env、source map 和 formatter
   初始化命令。
5. 收到 `initialized` 后发送断点配置和必要的 exception 配置。
6. 发送 `configurationDone`。
7. 处理 `process`、`output`、`stopped`、`continued`、`exited` 和 `terminated` event。

`DebugSession` 至少区分：

```text
Created
Initialized
Configuring
Running
Stopped
Exited
Terminating
Closed
Failed
```

每个 DSL 命令声明允许的 session 状态。错误信息应包含当前状态和可执行的下一步，而不是
把 adapter 的底层错误原样打印给用户。

## 9. 值展示与 MoonBit 语义

第一版继续利用编译器生成的 DWARF 类型信息和 LLDB 中的 MoonBit formatter。DAP 的
`scopes`、`variables` 和 `evaluate` 返回结构化变量树，`moondbg` 再将它们渲染为 MoonBit
风格。

需要区分两类能力：

1. **展示已有值**：读取参数、局部变量、struct、Array、FixedArray、String、Bytes、
   nullable reference 和 enum。这主要依赖 DWARF 与 formatter。
2. **求值 MoonBit 表达式**：理解运算符重载、方法调用、泛型和 Option 等语言语义。这最终
   需要 MoonBit parser/type checker 或专门的 debug-expression 编译服务，不属于首版。

因此首版的 `print` 应采用可明确验证的小语法子集。每扩展一种表达式，都要定义它需要的
静态类型信息、对 LLDB 的翻译和副作用规则。

## 10. 输出与错误模型

backend 返回结构化 `DebugEvent`/`DebugResult`，renderer 决定如何展示。至少预留：

- `HumanRenderer`：REPL 默认输出，可使用颜色和源码片段；
- `PlainRenderer`：无 ANSI，适合日志和测试；
- `JsonRenderer`：以后供 AI、脚本和自动化使用。

不要让业务代码直接 `println` LLDB response。错误至少区分：

- DSL parse error；
- command 不适用于当前 session 状态；
- adapter capability 不支持；
- breakpoint 未验证；
- expression 不受支持；
- DAP protocol/framing error；
- adapter、debuggee 或 transport 异常退出。

可以提供 `--trace-dap <path>`，记录脱敏后的原始 DAP request、response 和 event，方便复现
adapter 兼容问题。

## 11. DAP 与 AI 的后续扩展

未来 `moondbg --dap` 可以作为 DAP server：

```text
IDE ──DAP──> moondbg ──内部命令模型──> LldbDapBackend ──DAP──> lldb-dap
```

大部分请求可以直接映射；涉及函数名、MoonBit expression、变量展示和 source map 的请求
由 MoonBit 语义层处理。REPL 与 DAP server 不应各自维护一套 session 状态。

面向 AI 时，不要求 agent 驱动终端或解析彩色文本。推荐在后续版本提供 NDJSON/JSON-RPC
入口，复用 `JsonRenderer`，并提供稳定的：

- session、thread、frame、breakpoint 和 variable id；
- `state`/`snapshot` 操作；
- 结构化 stop reason 与源码上下文；
- 可重放的调试 transcript；
- 稳定错误码。

MCP 可以建立在这一结构化接口之上，但不应成为第一版 transport 的前置条件。

## 12. 测试策略

### 12.1 不依赖 LLDB 的测试

- DSL parser 与别名测试；
- 命令合法状态测试；
- DAP header/body partial read 测试；
- request seq 与 response correlation 测试；
- response/event 交错顺序测试；
- 使用 fake DAP adapter 验证 initialize、launch、breakpoint 和 stepping 流程；
- Human/Plain/JSON renderer snapshot 测试；
- transport 资源释放和 adapter 异常退出测试。

fake adapter 是主要测试入口，避免大部分测试依赖特定 LLDB 版本和平台输出。

### 12.2 真实 LLDB 端到端测试

在安装了 `lldb-dap` 的 macOS/Linux 环境中，使用一个很小的 MoonBit executable 验证：

1. 设置源码/函数断点；
2. run 后命中断点；
3. next/step/finish；
4. backtrace、locals 和 `p <identifier>`；
5. 正常退出与显式 quit。

端到端断言针对结构化事件和关键字段，不依赖完整的人类输出文本。

## 13. 实施里程碑

### M1. REPL 骨架

- 把项目切换到 native target；
- 引入 `readline.mbt`；
- 完成命令 parser、History、help、quit 和静态补全；
- 建立 `DebugCommand`、`DebugEvent` 和 renderer 基础类型。

### M2. Transport 与 DAP client

- 实现受限的 native subprocess/pipe stub；
- 实现 DAP framing、JSON 消息和 fake adapter 测试；
- 跑通 `initialize` 并完成 capability negotiation。

### M3. Launch 与执行控制

- 跑通 launch/configurationDone；
- 实现 run、continue、next、step、finish；
- 处理 output、stopped、exited 和 terminated event。

### M4. 断点与检查

- 实现源码/函数断点及 breakpoint list/delete；
- 实现 backtrace、frame、locals 和基础 print；
- 加载 MoonBit LLDB formatter，并完成真实 LLDB 端到端测试。

### M5. `moon debug` 集成

- 让 `moon debug` 构建完成后执行 `moondbg`；
- 传递 program、cwd、args、source map 和工具链资源路径；
- 验证 build lock 生命周期、退出码和 Ctrl-C 行为。

### M6. 结构化模式

- 增加 Plain/JSON renderer 和 DAP trace；
- 固化 session snapshot 与错误码，为 DAP server 和 AI client 做准备。

## 14. 第一版完成标准

第一版完成需要同时满足：

- 用户可以执行 `moon debug <executable-package>` 进入 `moondbg` REPL；
- REPL 由 `readline.mbt` 提供行编辑、History、Ctrl-C 恢复和命令补全；
- 正常操作只使用结构化 LLDB-DAP，不解析 LLDB CLI prompt/output；
- 用户可以设置断点、运行、单步、查看调用栈、局部变量和标识符值；
- adapter/debuggee 退出、协议错误和不支持的表达式都有明确错误；
- 协议与状态机测试主要通过 fake adapter 稳定运行；
- 至少有一个真实 MoonBit native 程序通过 LLDB-DAP 端到端验收；
- 内部命令和事件模型不依赖 LLDB 名称，可以继续承载 GDB、DAP server 和 AI 接口。

## 15. 参考资料

- [Debug Adapter Protocol Overview](https://microsoft.github.io/debug-adapter-protocol/overview)
- [LLDB-DAP Documentation](https://lldb.llvm.org/use/lldbdap.html)
- [GDB Command Interpreters](https://sourceware.org/gdb/current/onlinedocs/gdb.html/Interpreters.html)
