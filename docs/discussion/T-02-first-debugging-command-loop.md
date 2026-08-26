# T-02. 第一个可执行调试命令闭环

> 最后更新日期：2026-08-26
> 仓库：moondbg
> 记录者：Codex-GPT-5

## 主题描述

本主题确定 moondbg 在当前仍使用同步 `readline.mbt` 的条件下，第一个可执行调试闭环的
范围、内部前置工作和验收标准。该里程碑不是 T-01 所定义“第一版 REPL”的全部实现，
而是先完成一条能够在真实 MoonBit 程序上验证 DAP、DWARF、命令层和源码展示的最小
纵向链路。

当前决定不等待 `readline.mbt` 的 async API。同步 readline 暂时只允许 target 停止时
显示提示符；执行 `run` 或 `continue` 后，moondbg 等待 target 再次停止、退出或失败，
停止时恢复提示符，程序退出时则直接退出 moondbg。运行期间持续接收命令、即时呈现 DAP
事件和 Ctrl-C 暂停仍是 T-01 的第一版目标，但不作为本里程碑的前置条件。后续替换为
async readline 时，不应重写命令语义、断点模型或 DAP 会话状态机。

## 关联问题

- 暂不拆分 Q 文档。本主题当前没有待决策问题，已确认的里程碑决策记录在文档底部。
- 上游主题：[T-01. 第一版 REPL 交互模型与 lldb-dap 会话边界](T-01-repl-and-lldb-dap-interaction.md)。T-02 继承 T-01 已确认的用户模型和分层边界，只收窄首个实现里程碑的范围。

## 目标闭环

第一个闭环应能在一个带完整 DWARF 的简单 MoonBit 程序上完成如下交互：

```text
(moondbg) break main.mbt:8
Breakpoint 1 pending at main.mbt:8

(moondbg) run
Breakpoint 1 verified at main.mbt:8

Stopped at main.mbt:8
   6 │ fn main {
   7 │   let answer = 42
>  8 │   println(answer)
   9 │ }

(moondbg) p answer
answer: Int = 42

(moondbg) continue
Process exited normally (code 0).
```

用户可以在 `Ready` 状态、尚未创建本次 target 时设置源码断点。`run` 创建一次新的执行
会话、把逻辑断点配置给 lldb-dap 并启动程序。命中断点后，moondbg 自动选择当前线程和
顶层 MoonBit 用户帧，显示停止位置及当前行上下各两行源码。`p <name>` 从当前 frame 的
变量 scope 中查询一个简单变量。`continue` 恢复执行，并等待下一次停止或进程退出；
程序正常或异常退出后，moondbg 完成资源清理并随之退出，不再恢复 REPL。

## 本里程碑的范围

### 1. 最小命令面

本里程碑实现以下命令及固定别名：

```text
run                  r
break <file>:<line>  b
continue             c
list
print <name>         p
help
quit                 q, exit
```

`list` 重新显示当前 frame 附近的源码。停止时已经自动显示一次相同格式的源码上下文。
命令解析需要区分参数缺失、格式错误和当前状态不允许执行；不能把 lldb-dap 的原始协议
错误直接作为主要用户提示。

T-01 已确认的函数断点、变量字段/索引路径、线程与 frame 选择、单步、backtrace、locals、
断点列表和删除等命令仍属于第一版，但可以在后续里程碑补齐。

### 2. 临时同步交互边界

当前同步 readline 下采用以下临时行为：

- `Ready` 和 `Stopped` 状态可以读取命令；
- `Running` 状态不显示普通提示符；
- `run` 和 `continue` 发送请求后继续驱动 DAP，直到收到 `stopped`、`exited`、单独的
  `terminated` 或确定的失败；
- 收到进程退出事件后只输出一次退出反馈，随后清理 adapter 并结束 moondbg，不进入可
  再次输入命令的 `Exited` REPL 状态；
- 等待期间仍应处理 response 与 event 的交错顺序，但暂不接受新的 REPL 命令；
- 该里程碑暂不承诺运行期间 Ctrl-C 转换为 DAP `pause`，测试程序必须能命中断点或正常
  退出，避免无限等待。

这些是实施顺序上的暂缓，不推翻 T-01 对最终第一版运行态输入、Ctrl-C 暂停、独立 PTY
和异步消息显示的要求。

## 实施前置工作

### 1. 把一次性 bootstrap 拆成 DebugSession 状态机

当前 `bootstrap_session()` 直接执行 initialize、launch、configurationDone，并一直读取到
程序停在入口。这一结构无法承载多条命令，需要拆成可持续存在的 `DebugSession`。

本里程碑至少需要表达以下状态：

```text
Ready → Preparing → Configuring → Running → Stopped → Exited
                     │              │          │
                     └──────────────┴──────────┴──→ Failed
```

`Exited` 在本里程碑中是触发资源清理和 moondbg 退出的终止状态，不是能够再次读取命令的
稳定 REPL 状态。

状态机负责：

- 当前 adapter/target 是否存在；
- 当前 execution epoch 与 stop epoch；
- 当前选中的 thread 和 frame；
- 当前源码位置；
- 运行、停止、退出和 adapter failure 的状态转换；
- 恢复运行时使旧 frameId、variablesReference 和变量缓存失效。

`Ready` 是外层 moondbg session 的稳定状态，不要求 target 已创建。逻辑断点属于外层
session，adapter、target 和 DAP 返回的临时 ID 属于本里程碑唯一一次 `run`。

### 2. 建立唯一 DAP 消息入口和请求关联

DAP response 与 `initialized`、`stopped`、`exited`、`terminated`、`output` 等 event 可以
交错到达；`launch` response 也可能晚于 `initialized` event。实现不能继续假定“发送一个
请求，下一条消息就是它的 response”。

需要做到：

- 所有 adapter 输出只由一个逻辑入口读取；
- 通过 request `seq`/response `request_seq` 关联请求与响应；
- 等待特定 response 时仍能处理先到达的 event；
- event 统一交给 `DebugSession` 推进状态；
- REPL 命令不直接读取 DAP JSON，也不自行消费 transport 消息；
- 稳定状态以 `stopped`、`exited` 或单独的 `terminated` event 为准，而不是只看执行请求
  的成功 response。

首个实现可以暂时只允许一个用户动作在途，但 transport 和 session 的边界不能依赖
response/event 的固定到达顺序，以便 async readline 接入后扩展为持续 reader。

### 3. 建立持久的逻辑断点集合

moondbg 自己分配稳定的用户断点编号，并至少保存：

- 规范化后的源码路径；
- 用户请求的行号；
- 当前 adapter 内的 verified 状态、实际行号、DAP breakpoint ID 和错误信息。

DAP `setBreakpoints` 是按源文件替换完整集合，而不是追加单个断点。因此某个文件发生断点
变化时，必须重新发送该文件的全部启用断点。尚未 `run` 时设置的断点先标记为 pending；
adapter 发出 `initialized` 后，按文件重放全部断点，再发送 `configurationDone`。

DAP breakpoint ID 只在当前 adapter 内有效，不能代替 moondbg 分配的用户断点编号。虽然
本里程碑不支持重复 `run`，断点所有权仍应保持这一层次，避免后续扩展时改变用户编号。

### 4. 完成 run 与 continue 的执行事务

`run` 至少完成：

1. 为本次唯一的 execution epoch 创建全新 `lldb-dap`；
2. 发送 initialize 并保存 capabilities；
3. 发起 launch，同时继续处理可能先到达的 `initialized` event；
4. 收到 `initialized` 后配置全部逻辑源码断点；
5. 发送 configurationDone；
6. 根据 response 和 event 推进到 Running；
7. 等待 stopped、exited、terminated 或失败；
8. 停止时建立新 stop epoch，退出时回收本次 adapter/target 资源。

`continue` 只允许在 `Stopped` 状态执行。成功 response 只表示 adapter 接受请求；命令必须
继续等待新的稳定状态 event。恢复执行前要清空上一 stop epoch 的 thread、frame、scope
和 variablesReference。程序退出后完成清理并结束 moondbg；本里程碑不重新进入 `Ready`
或 `Exited` 提示符，也不接受第二次 `run`。

### 5. 生成最小 StopSnapshot 并显示源码

收到 `stopped` 后，在恢复 prompt 前执行最小必要查询：

1. 从 event 取得停止线程；缺失时使用 `threads` 选择可用线程；
2. 请求该线程的 stackTrace；
3. 选择顶层 MoonBit 用户帧；首个测试程序没有 runtime/artificial 顶帧时可以先使用顶帧，
   但内部结果应保留未来加入用户帧筛选的位置；
4. 取得函数名、源码路径、行和列；
5. 从本地源码读取当前行上下各两行；
6. 形成结构化 `StopSnapshot`，再由 REPL renderer 输出停点卡片。

如果 DAP 只提供 `sourceReference` 而没有可读的本地路径，可以使用 DAP `source` 请求作为
回退。源码文件不存在、路径无法映射或行号越界时，仍应显示停止原因和 frame 信息，并
给出明确的源码不可用提示，不能让整个 stopped 事务失败。

### 6. 实现简单变量查询

本里程碑的 `p` 只接受一个简单变量名，不支持 `point.x`、`items[3]`、运算符或函数调用。
实现流程为：

1. 使用当前 frameId 请求 `scopes`；
2. 按需请求各相关 scope 的 `variables`；
3. 按 DAP 返回的源码变量名精确查找根变量；
4. 展示 name、type、value，并保留 variablesReference 供后续路径展开使用；
5. 在同一 stop epoch 内缓存 scopes 和已经获取的变量列表；
6. target 恢复运行时整体丢弃缓存。

第一版查询不得静默调用 LLDB expression evaluator。LLDB 不理解完整 MoonBit 表达式语义；
如果变量未出现在 DAP scopes/variables 中，应明确报告“当前 frame 中未找到变量”或
“变量已被优化掉”，而不是把 LLDB/C 表达式错误暴露给用户。

## DWARF 能力验证

在大量编写 REPL 展示逻辑之前，需要用当前 `--debug-info full` 编译一个最小 MoonBit
程序，并通过 lldb-dap 实际验证：

1. `setBreakpoints` 能否 verified，实际地址和行号是否正确；
2. `stopped` 后的 stackTrace 是否包含正确的 MoonBit 文件、函数名、行和列；
3. `scopes` 和 `variables` 能否看到函数参数与简单局部变量；
4. 变量的 name、type、value 和 variablesReference 是否适合直接展示；
5. target 恢复运行后，旧 frameId 和 variablesReference 是否按预期失效；
6. 程序退出时 `exited`、`terminated` 和相关 response 的实际顺序。

测试程序至少包含一个参数、一个简单局部变量和一次函数调用，并保证断点所在行会实际
生成可停止的机器指令。C 语言 fixture 可以继续用于验证通用 DAP transport，但不能替代
MoonBit fixture 对 DWARF 的验收。

若源码位置缺失，应先检查 line table；若局部变量缺失，应分别检查 variable DIE、lexical
scope、location、类型信息和优化状态。只有验证表明确实是编译器或构建产物问题时，才在
编译器仓库增加对应修改；moondbg 不通过猜符号名、反汇编或解析 LLDB 文本输出来掩盖
DWARF 缺失。

## 建议的实施顺序

1. 增加专用 MoonBit debug fixture 和一条可重复执行的 lldb-dap 能力探测路径；
2. 将 bootstrap 拆成 DAP dispatcher 与 `DebugSession` 状态机；
3. 建立命令解析和本地 `help`、`quit`；
4. 建立逻辑断点 store，实现 `break <file>:<line>`；
5. 实现 `run` 的 initialize/launch/breakpoints/configurationDone/stable-event 链路；
6. 在 stopped 时取得 frame、建立 `StopSnapshot` 并自动显示源码；
7. 实现 `list` 和 `p <name>`；
8. 实现 `continue` 和 stop epoch 缓存失效；
9. 验证正常退出、adapter failure 和 quit 的资源清理及 moondbg 进程结束行为；
10. 在 `moon debug main` 的真实链路中完成端到端验收。

前两步属于命令闭环的必要地基，不应扩展成通用 DAP framework。每完成一步都应保留可以
直接检查的结构化结果或测试，避免只能通过人工观察终端判断是否正确。

## 验收标准

本里程碑完成时应满足：

1. `moon debug main` 进入 REPL 后可以在运行前设置一个 MoonBit 源码行断点；
2. `run` 创建新的 adapter/target，正确完成 DAP 配置并命中该断点；
3. response 与 initialized/stopped/exited event 改变常见到达顺序时，状态机仍能工作；
4. 断点反馈区分 pending、verified、实际移动位置和 adapter 拒绝；
5. 停止时自动显示原因、函数、文件、行号和上下各两行源码；
6. `list` 可以再次显示当前源码上下文；
7. `p <name>` 可以显示 fixture 中一个参数或简单局部变量的名称、类型和值；
8. `continue` 后程序可以再次停止或正常退出，退出反馈只显示一次；
9. 运行后旧 frameId、variablesReference 和变量缓存不会被下一 stop epoch 复用；
10. `quit`、正常退出和 adapter failure 都能回收子进程并恢复终端；正常或异常退出
    debuggee 后，moondbg 随之退出且不再显示 prompt；
11. 同步 readline 仍可用于当前闭环，后续替换为 async readline 时不需要改变命令和
    `DebugSession` 的公开语义；
12. C fixture 与真实 MoonBit fixture 的自动化测试均通过。

## 本里程碑暂不实现

- 运行期间的普通命令输入和 Ctrl-C → DAP pause；
- readline 编辑期间的异步消息插入与无损重绘；
- debuggee 独立 PTY 和交互式 stdin；
- 函数断点、断点列表、删除和禁用；
- `next`、`step`、`finish`；
- threads、frame、backtrace、locals；
- 变量字段、数组索引和完整 MoonBit 表达式；
- runtime/artificial frame 分类；
- artifact manifest 与 source mapping 的最终格式；
- 面向 AI 的结构化协议和对外 DAP。
- `Exited → run` 或 `Stopped → run` 的重复运行与断点重放。

这些能力仍保留在 T-01 的第一版目标中。本节只是划定首个闭环的交付边界，不代表取消
或推翻已有决策。

## 已确认决策

1. **首个闭环只实现源码行断点。** 只接受 `break <file>:<line>`；函数断点需要额外解析
   MoonBit 函数身份和符号映射，因此不进入本里程碑。这个收窄不取消 T-01 中正式第一版
   对函数断点的要求。
2. **没有断点时，`run` 正常运行程序。** 本里程碑不隐式设置入口停点，也不强制
   `stopOnEntry: true`。用于验收源码和变量功能的 fixture 会先显式设置行断点。这只是
   当前闭环的运行语义，不预先决定正式产品是否提供默认入口停点或相关配置。
3. **本里程碑不支持重复 `run`。** 只允许一次 `run`；debuggee 运行结束后，moondbg 输出
   退出信息、回收 adapter 和其他资源，然后自身退出。`Exited → run`、`Stopped → run`
   和跨运行断点重放均留到后续里程碑。该临时限制不推翻 T-01 对正式 moondbg 持久 REPL
   和可重复运行的目标。
4. **先增加同步 REPL 的最小退出命令。** `quit` 和 `exit` 都直接退出，不询问确认，也不把
   后续参数解释成退出码。解析时忽略行首空白；首个词必须严格等于小写 `quit` 或 `exit`，
   因此 `exit`、`quit`、` exit 0`、`   quit 1122` 有效，`exiting`、`exit0`、`quitter`
   和 `QUIT` 无效。命令命中后 REPL 正常返回，由既有会话清理路径关闭 lldb-dap。

## 待决策问题

暂无。

## 任务划分

T-02 的实施按以下阶段推进。阶段编号固定使用 `P1`、`P2`、`P3`、`P4`、`P5`，阶段状态
使用“待实施”、“进行中”、“已完成”或“阻塞”。本次在原 P2 前增加最小退出命令阶段，
原 P2 至 P4 依次顺延为 P3 至 P5。

### P1. DWARF 能力探测

**状态：** 已完成

**目标：** 在修改主要 REPL 行为之前，确认当前开发版编译器生成的完整 DWARF 能否支撑
行断点、源码位置和简单变量查询。

**任务：**

1. 增加一个专用的最小 MoonBit debug fixture，包含函数参数、简单局部变量、函数调用和
   明确可停止的源码行；
2. 使用 `--debug-info full` 构建 fixture，并通过真实 lldb-dap 执行 initialize、launch、
   setBreakpoints、configurationDone、stackTrace、scopes、variables、continue；
3. 记录 breakpoint 是否 verified、实际源码位置、函数名、参数和局部变量的 name/type/value，
   以及 exited、terminated 和相关 response 的实际顺序；
4. 区分 moondbg/DAP 使用问题与编译器 DWARF 缺失。若发现后者，明确需要修改的 line table、
   variable DIE、location、scope 或类型信息，不在 moondbg 中增加猜测性绕过。

**完成条件：** 形成可以重复运行的 fixture 和能力探测结果，明确行断点、源码 frame、参数、
简单局部变量四项分别是否可用，并能据此判断 P4、P5 是否需要编译器前置修改。

**Review 节点：** P1 完成后先 review 能力结果。如果关键 DWARF 能力缺失，暂停依赖该能力
的后续阶段，先决定并完成编译器任务。

### P2. quit/exit 最小退出命令

**状态：** 已完成

**目标：** 在尚未实现其他调试命令前，先建立最小命令识别入口，并验证用户主动退出会走
完整的会话清理路径。

**任务：**

1. 在 REPL 层增加最小命令解析结果，把 `quit` 和 `exit` 统一映射为退出动作；
2. 忽略行首空格和制表符，严格按首个词匹配小写命令；命令词后可以是行尾，也可以是空格
   或制表符分隔的任意内容，后续内容全部忽略；
3. 保持 `exiting`、`exit0`、`quitter`、`QUIT` 等输入为普通未实现命令，避免前缀误判；
4. 命中退出动作后让 REPL 正常返回，不直接中止进程，使外层 `disconnect` 和 `close` 仍然
   执行；
5. 增加解析测试，并通过真实 lldb-dap 会话验证退出后不再显示提示符且没有遗留 adapter。

**完成条件：** 文档中的有效示例均可直接退出，无效示例继续得到普通未实现命令提示；
退出过程输出既有的 `Debugger exited.`，不询问确认，并完成 lldb-dap 资源清理。

**Review 节点：** P2 完成后 review 命令边界、退出控制流和真实子进程清理，再开始 DAP
dispatcher 与状态机重构。

### P3. DAP dispatcher 与 DebugSession 状态机

**状态：** 已完成

**目标：** 建立不依赖 response/event 固定顺序的协议与会话地基，同时不扩展成通用 DAP
framework。

**任务：**

1. 让 DAP response、event 和 adapter request 保留完整 body 及必要的协议字段；
2. 建立唯一 DAP 消息读取入口，通过 request_seq 匹配或暂存 response；
3. 等待特定 response 时继续处理 initialized、output、stopped、exited、terminated 等 event；
4. 将当前一次性 bootstrap 拆成 Ready、Preparing、Configuring、Running、Stopped、Exited、
   Failed 状态；
5. 建立 execution epoch 与 stop epoch，并在恢复运行时使旧 frameId、variablesReference 和
   stop 缓存失效；
6. 使用构造消息或 fake adapter 覆盖 initialized 早于 launch response、stable event 早于
   执行 response、exited/terminated 重复等顺序。

**实施结果：** DAP event、response 和 adapter request 已拆成保留完整 payload 与协议字段的
内部消息类型；`DapDispatcher` 是唯一调用 transport receive 的入口，并使用 `request_seq`
匹配或暂存乱序 response。`DebugSession` 启动后保持 `Ready`，不再隐式 launch 或停在入口，
因此 REPL 可以立即显示提示符；后续 `run` 将从 `Ready` 开始 execution epoch。状态机已经
覆盖七个状态、execution/stop epoch、旧 frame 与 variablesReference 失效、重复终止事件和
adapter failure。构造消息测试覆盖 initialized/stable event 提前、乱序 response、重复
stopped、exited/terminated 合并以及 stop epoch 缓存失效；真实 `moon debug main` 验证了
Ready 状态下的即时提示符、退出清理和无残留 adapter。

**完成条件：** REPL 不再直接读取 DAP JSON；所有 adapter 消息经过唯一 dispatcher；测试
证明常见的 response/event 重排不会丢失消息、错误匹配请求或重复推进稳定状态。

**Review 节点：** P3 完成后单独 review package API、唯一 reader、请求关联和状态所有权。
P3 的边界确认后再把调试命令建立在其上。

### P4. 行断点、run 与源码停点闭环

**状态：** 待实施

**目标：** 完成第一个用户可见的 `break → run → stopped → source` 纵向闭环。

**任务：**

1. 在 P2 的最小解析入口上扩展完整命令解析，并实现本地 help；
2. 实现 `break <file>:<line>`，相对路径暂时只相对于 moondbg 启动 cwd 解析，并向 DAP 使用
   规范绝对路径；
3. 建立 moondbg 逻辑断点编号和按文件保存的完整断点集合，区分 pending、verified、实际
   移动位置和 adapter 拒绝；
4. 实现唯一一次 `run` 的 initialize、launch、断点重放、configurationDone 和稳定 event
   等待；不设置隐式入口停点，没有断点时允许程序正常运行到退出；
5. 收到 stopped 后取得线程和 stack frame，建立最小 `StopSnapshot`；
6. 自动显示停止原因、函数、文件、行号和当前行上下各两行源码，并实现 `list` 重新显示；
7. 源码不可读时保留停止信息并给出明确提示，不让整个 stopped 事务失败。

**完成条件：** 在真实 MoonBit fixture 上可以运行文档中的 break/run 示例，命中行断点后
自动显示正确源码；无断点时程序正常退出；response/event 重排仍由 P3 状态机正确处理。

**Review 节点：** P4 完成后可以检查首个用户闭环；若没有出现新的交互或 DWARF 问题，
不要求在 P4 与 P5 之间停顿，可以继续完成 P5 后统一进行最终 review。

### P5. 简单变量、continue、退出与端到端验收

**状态：** 待实施

**目标：** 补齐 T-02 的完整闭环，使用户能在停点查询简单变量、继续程序，并让 debuggee
退出可靠地结束 moondbg。

**任务：**

1. 实现 `p <name>`，通过当前 frame 的 scopes/variables 精确查找简单变量，不调用 LLDB
   expression evaluator；
2. 在当前 stop epoch 内缓存 scopes 和已取得的 variables，恢复运行时整体失效；
3. 实现 `continue`，以新的 stopped、exited 或单独 terminated event 作为完成条件；
4. 处理并输出运行期间必要的 output event，合并 exited/terminated 为一次退出反馈；
5. debuggee 正常或异常退出后回收 adapter、恢复终端并结束 moondbg，不恢复 prompt，也不
   支持第二次 run；
6. 验证 quit、adapter failure、正常退出和异常退出的资源清理；
7. 通过真实 `moon debug main` 完成 `break → run → source → p → continue → exit` 端到端
   测试，并运行项目的格式化、接口检查和 native 测试。

**完成条件：** T-02“目标闭环”和“验收标准”全部满足；旧 stop epoch 的 DAP 引用不会被
复用；退出反馈只出现一次；debuggee 结束后 moondbg 自身退出且没有遗留 lldb-dap 进程。

**Review 节点：** P5 完成后进行 T-02 最终 review，核对完整终端体验、结构化结果、资源
清理、真实 MoonBit DWARF 表现以及 `moon debug main` 的端到端行为。
