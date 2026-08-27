# T-04. 源码级单步执行

> 最后更新日期：2026-08-27
> 仓库：moondbg
> 记录者：Codex-GPT-5

## 主题描述

T-02 和 T-03 已经建立断点、运行、继续执行、停点源码显示、简单变量查询以及持久 REPL
闭环。本主题在现有 `Stopped → Running → Stopped/Exited` 生命周期上增加源码级单步执行，
首版只支持以下三个完整命令名：

### `next`

执行当前源码行，但不主动进入当前行调用的函数，在当前栈帧的下一个可停源码位置停止。
对应 DAP `next` request。若当前栈帧在执行过程中返回，最终停点由 lldb-dap 决定；程序也
可能直接退出。

### `step`

执行当前源码行，并在存在可调试的被调用函数时进入该函数；没有可进入目标时继续到下一
个可停源码位置。对应 DAP `stepIn` request。

### `finish`

继续执行，直到当前栈帧返回，并尽量在调用者的下一个可停源码位置停止。对应 DAP
`stepOut` request。若最外层可执行栈帧返回，程序可以正常或异常退出。

本主题只要求 `next`、`step` 和 `finish` 三个完整命令名；缩写、同义命令和带参数形式不在
本轮范围内，但不限制以后增加。三个命令都只允许在 `Stopped` 状态执行，并使用最近一次
stop event 所确定的当前线程。首版不增加线程切换或栈帧选择功能。

执行任一单步命令时，REPL 已经结束本次 `read_line`，因此可以同步等待下一次 `stopped`、
`exited` 或 adapter failure，再复用现有输出和源码卡片逻辑。单步期间不显示新的 prompt，
也不依赖 readline 对“编辑过程中插入异步输出并重绘”的支持。

单步请求恢复 debuggee 时必须使旧 stop epoch、frame、scope 和 `variablesReference` 立即
失效；再次停住后重新获取 stack frame、源码位置和变量上下文。adapter failure、程序退出、
execution 清理以及下一次 adapter 预热继续沿用 T-03 已建立的统一路径。

源码级单步会直接检验编译器生成的 DWARF line table、函数范围和序言/结尾信息。本主题不
预设必须修改编译器；先通过最小 MoonBit 程序和真实 lldb-dap 验证。如果出现重复停在同一
行、跳过有效源码、进入运行时或无法进入/退出 MoonBit 函数等行为，需要先区分 DAP 请求
处理与编译器 debug info，再决定是否修改编译器。

以下能力不属于 T-04：

- `bt`、`frame`、`up`、`down` 等栈帧导航；
- `locals` 及基于选中栈帧的变量查询；
- 线程列表与线程切换；
- 指令级单步和自定义 stepping granularity；
- 条件断点、watchpoint 和表达式求值；
- readline 编辑期间的异步程序输出。

## 关联问题

暂无。按照本主题约定，不拆分 Q 文档，命令语义和任务划分直接记录在本文件中。

## 任务划分

T-04 的实施按 `P1` 至 `P4` 推进。阶段状态使用“待实施”、“进行中”、“已完成”或
“阻塞”。P2 完成后 review 单步状态边界；P4 完成后进行真实链路验收和最终 review。

### P1. 扩展 DAP 协议与 fake adapter

**状态：已完成**

**目标：** 为三类单步操作建立可测试的 DAP request、response 和 event 闭环。

**工作内容：**

1. 增加 `next`、`stepIn` 和 `stepOut` request 的协议编码，三个请求均携带当前 stopped
   thread ID；
2. 保持用户语义为源码行级，不在 REPL 暴露指令级 granularity；
3. 扩展 fake adapter，使测试能够分别响应三种 request，并可配置随后发送 `stopped`、
   `exited`、`terminated` 或主动异常退出；
4. 在 request trace 中记录 command、thread ID 和先后顺序；
5. 增加协议测试，验证 JSON 字段、response 配对及停止/退出事件解析。

**实施结果：** 新增内部 `DapStepKind` 和统一的 stepping request 构造，将三种操作映射到
`next`、`stepIn`、`stepOut`，始终携带 stopped thread ID；adapter 声明支持 stepping
granularity 时显式发送 `line`，否则只发送规范要求的最小参数。通用 request JSON 编码从
transport 中提取为可测试的协议函数。

fake adapter 现在可以配置 stopped thread ID，以及单步后的 `stopped`、`exited`、仅
`terminated` 和 adapter failure 四类结果；request trace 同时保存完整 arguments，并会
拒绝错误 thread ID 或非法 granularity。协议白盒测试覆盖三种 command、完整 JSON、无
granularity fallback、request/response 配对和 response 前到达的 stop event。独立 fake
协议验证覆盖全部结果，原有 fake REPL 生命周期回归保持通过；最终 `moon check` 无警告，
72 个 MoonBit 测试全部通过。

**完成条件：** fake adapter 可以确定性地制造三种单步成功、程序退出和 adapter failure，
协议测试能够发现错误的 command 或 thread ID。

### P2. 实现单步执行生命周期

**状态：已完成**

**目标：** 在 `DebugExecution` 和 `DebugSession` 中实现可复用的单步状态转换，并保证所有
DAP 临时引用按 stop epoch 隔离。

**工作内容：**

1. 保存最近一次 stop event 对应的 thread ID，作为下一次单步 request 的目标；
2. 为三种单步建立共享执行路径：校验 `Stopped`、使当前 stop 上下文失效、发送 request、
   进入 `Running` 并等待新的停止或退出结果；
3. 新 stop 到达后重新获取 stack trace 顶帧并生成 `StopSnapshot`；
4. 复用 `continue` 已有的 debuggee output、adapter failure、execution 归档和下一次预热
   逻辑，避免形成另一套生命周期；
5. 增加白盒测试，验证非 `Stopped` 状态拒绝单步、旧 frame/variable reference 失效、
   三种操作使用正确 request，以及停止、退出和失败后的最终状态。

**实施结果：** 新增内部 `ExecutionResumeKind`，把 `continue` 和三种单步统一到同一条
resume transaction：先校验当前 stop 与 thread ID，随后清除 `StopSnapshot`、stop context
和变量缓存，发送对应 request，并通过现有 `complete_execution` 等待新的 stop 或退出。
session 层同样共用 adapter failure 恢复、execution 归档、正常退出和下一 adapter 预热
路径，没有为 stepping 建立第二套生命周期。

`DebugSession` 对外新增 `next`、`step`、`finish` 三个 async 方法。step request 根据
initialize capabilities 决定是否显式发送 `granularity: line`。stop event 未提供 thread ID
时，已有 `threads` fallback 得到的 ID 现在会写回当前 stop epoch，保证后续 resume 使用同一
线程；恢复运行后该 ID 与 frame、scope、`variablesReference` 一起失效。

新增纯协议/状态白盒测试和真实启动 fake adapter 的 async 白盒测试。测试覆盖 Ready 状态
拒绝单步、run 后连续执行 `next → step → finish`、stop reason 与 thread ID、stop epoch 从
1 增长到 4、旧变量缓存失效、每次重新构建 snapshot，以及最终 disconnect 清理。`moon
info` 的预期公开接口变化只有三个新方法；`moon check` 无警告，75 个 MoonBit 测试和原有
fake REPL 端到端回归均通过。

**完成条件：** 三种单步都能从同一执行路径得到 `Stopped` 或 `Exited` 结果；不存在跨 stop
使用旧 DAP 引用、重复处理终止事件或 adapter failure 后破坏外层 REPL 的情况。

**Review 节点：** P2 完成后重点检查 stopped thread ID 的所有权、状态转换、旧 stop
上下文失效时机，以及与 `continue` 共用逻辑的程度。

### P3. 接入 REPL 命令与用户反馈

**状态：待实施**

**目标：** 让用户可以通过 `next`、`step` 和 `finish` 完成源码级单步闭环。

**工作内容：**

1. 在命令模型和解析器中加入三个无参数命令，只接受本主题确认的完整命令名；
2. 更新 `help`，简要说明越过、进入和跳出语义；
3. 将三个命令分派到对应 session 操作，非 `Stopped` 状态沿用统一的
   `OperationNotAllowed` 用户反馈；
4. 单步停止后依次呈现 debuggee output、停止原因、函数与源码位置以及高亮源码卡片；
5. 单步导致程序退出时复用当前退出反馈并恢复持久 REPL，不增加特殊询问；
6. 增加命令解析和 REPL 行为测试，覆盖空参数、额外参数、非法状态和正常结果。

**完成条件：** 三个命令的名称、帮助文本、非法状态反馈和停止/退出输出一致；命令执行
期间不会提前显示 prompt，也不会要求 readline 支持编辑中异步打印。

### P4. fake 与真实 lldb-dap 端到端验收

**状态：待实施**

**目标：** 验证单步功能在确定性测试和真实 MoonBit DWARF 上都形成稳定闭环。

**工作内容：**

1. 使用 fake adapter 分别执行 `next`、`step` 和 `finish`，核对 request trace、thread ID、
   stop/exit 输出和 prompt 恢复；
2. 扩展 `testdata/dwarf_probe`，提供至少两层 MoonBit 函数调用以及足够清晰的连续源码行；
3. 使用真实 `moon debug main` 验证 `step` 进入 MoonBit 函数、`next` 越过函数调用、
   `finish` 返回调用者，并检查每次停点的高亮源码卡片；
4. 验证单步期间变量引用失效、再次停住后 `p` 和 `list` 使用新 stop 上下文；
5. 验证单步导致正常退出、非零退出和 adapter failure 时，REPL 与下一 execution 仍可用；
6. 检查所有路径结束后没有遗留 lldb-dap、debuggee 或测试子进程组，并执行项目规定的
   接口生成、格式化、检查和测试流程；
7. 若真实行为不符合源码级语义，构造最小复现并记录问题位于 moondbg、lldb-dap 还是
   MoonBit DWARF；只有确认 debug info 缺陷后才进入编译器修改。

**完成条件：** fake adapter 测试稳定通过；真实 MoonBit 程序能够完成三个命令的代表性
路径，或者已经得到可复现且归因明确的编译器/adapter 阻塞报告；所有资源均被正确清理。

**Review 节点：** P4 完成后 review 用户语义、真实停点质量、DWARF 暴露的问题、错误恢复
和进程清理，再决定下一主题进入栈帧导航还是断点管理。
