# T-03. 持久 REPL 与 execution 生命周期

> 最后更新日期：2026-08-26
> 仓库：moondbg
> 记录者：Codex-GPT-5

## 主题描述

T-02 已经打通 `break`、`run`、停点源码显示、简单变量查询和 `continue` 的首个真实调试闭环，
但仍采用“一次运行结束后 moondbg 随之退出”的临时模型。本主题讨论如何把这个闭环扩展为
持久 REPL，并落实 [T-01](T-01-repl-and-lldb-dap-interaction.md) 已确认的正式会话边界。

T-03 继承以下已经确认的目标，不重新讨论其产品方向：

- moondbg REPL session 是持久状态的所有者；debuggee 退出后恢复提示符，允许再次 `run`；
- 逻辑断点、程序参数、环境变量和 cwd 跨运行保留；
- `lldb-dap`、target、PTY 以及 DAP 临时 ID 属于单次 execution；每次 `run` 都创建新的
  adapter session，并重放持久配置；
- 每次进入 `Ready` 后立即向用户显示提示符，同时在后台为下一次 execution 准备
  `lldb-dap`；提示符不等待 adapter 启动完成；
- 用户可以在 adapter 准备期间输入命令；不依赖 adapter 的命令立即执行，第一个依赖
  adapter 的命令在准备尚未完成时等待同一个后台任务，准备完成后继续执行，不重复启动
  adapter；
- 在 `Stopped` 状态执行 `run` 时直接回收当前 execution 并重新运行，不额外询问；
- adapter failure 只结束和清理当前 execution，不自动重跑程序，也不应破坏外层 REPL。

本主题需要建立的核心边界，是把当前 `DebugSession` 中混合存在的两类状态拆开：

1. **Debugger session：** 生命周期与 REPL 相同，保存可跨运行复用的用户配置和稳定编号；
2. **Execution：** 生命周期只覆盖一次 `run`，拥有 adapter、target、进程状态、execution
   epoch、stop epoch、frame 和 variablesReference 等临时资源。

围绕这条边界，后续讨论和实施主要包括：

- `Ready`、`Running`、`Stopped`、`Exited` 和 adapter failure 后的用户可见行为；
- 正常退出、非零退出、主动重启、`quit` 和 adapter 异常时的统一资源清理；
- 新 execution 的创建、旧 execution 的销毁，以及断点和运行配置的重放时机；
- adapter 后台准备任务的所有权、就绪结果交接，以及用户提前 `quit` 时的取消和清理；
- `run -- <args>` 对持久参数的更新语义，以及 cwd、环境变量后续接入的位置；
- 终止事件、迟到 response 和旧 epoch 消息不能污染下一次运行；
- 为重复运行、停止状态重启和异常恢复建立端到端测试闭环。

当前暂不把具体类型名称、公开 API、阶段划分和命令扩展写成已确认决策；这些内容在 review
主题边界后继续讨论。栈导航、线程切换、条件断点和复杂表达式求值不属于 T-03 的核心范围，
可在持久会话模型稳定后另开主题。

## 关联问题

暂无。当前先确认 T-03 的主题边界，尚未拆分具体 Q 文档。

## 任务划分

T-03 的实施按 `P1` 至 `P5` 推进。阶段状态使用“待实施”、“进行中”、“已完成”或
“阻塞”。P2 和 P3 完成后分别 review；P4 与 P5 可以连续完成后进行最终 review。

### P1. 建立可控的 fake adapter 测试设施

**状态：已完成**

**目标：** 为 adapter 后台准备、请求时序、故障和清理建立不依赖真实 LLDB 启动速度的
确定性测试入口。

**工作内容：**

1. 增加可配置的 fake DAP adapter，支持延迟 `initialize` response、记录请求顺序、正常
   结束和主动异常退出；
2. 让测试可以确认 `initialize`、`launch`、`setBreakpoints`、`configurationDone` 和
   `disconnect` 是否发生及其先后关系；
3. 扩展现有 PTY 端到端测试设施，支持观察 prompt、在 adapter ready 前发送命令，并检查
   子进程组是否完全回收；
4. 为所有等待设置硬超时，失败路径不能遗留 fake adapter 或 moondbg 子进程。

**实施结果：** 新增 `tools/fake_dap.py`，通过环境变量控制 initialize 延迟、launch
response 与 initialized event 顺序、源码位置、trace 文件和 initialize 前异常退出；请求
trace 可以核对完整 DAP 命令序列与 adapter PID。`tools/repl_e2e.py` 已接入正常 fake
调试闭环和 initialize failure，并提供 `--fake-only`、`--real-only` 选择；所有 PTY session
继续使用硬超时和进程组残留检查。fake adapter 正常闭环与准备期失败测试均已通过。

**完成条件：** 测试设施能够稳定制造“adapter 尚未 ready”“initialize 成功”和
“准备期间 adapter 退出”三种场景，并为 P3、P5 提供可复用断言。

### P2. 拆分持久 debugger session 与单次 execution

**状态：已完成**

**目标：** 建立 T-03 的所有权边界，同时暂时保持 T-02 的外部单次运行行为，避免把结构
重构和用户体验变化混在同一步。

**工作内容：**

1. 让持久 debugger session 保存 executable、逻辑断点、稳定用户编号和可跨运行配置；
2. 提取单次 execution，使其拥有 `DapDispatcher`、adapter process、capabilities、DAP
   状态机、execution/stop epoch、frame、variablesReference、变量缓存和待输出事件；
3. 让逻辑断点状态与 adapter 本次返回的 verified、actual line 和临时 ID 分离；
4. 明确 execution 的创建、交接、关闭和失败接口，保证关闭操作幂等；
5. 调整状态机和白盒测试，验证旧 execution 的 frame、变量引用和消息不能被另一
   execution 接受。

**实施结果：** `DebugSession` 现只持有 executable、逻辑断点、稳定编号、当前
`DebugExecution?` 和 execution 分离后的状态；新提取的 `DebugExecution` 独占 dispatcher、
adapter process、DAP 状态机、capabilities、事件、stop/variable 缓存、输出队列和本次
adapter 断点结果。`LogicalBreakpoint` 只保存稳定用户事实，verified、actual line、DAP ID
与 rejected 状态进入 `ExecutionBreakpointState`；白盒测试证明同一个逻辑断点在两个
execution 中的 adapter 结果彼此隔离。现有公开方法由持久 session 委托给当前 execution，
关闭后会移除全部 adapter-scoped 资源。`moon info` 确认公开 `.mbti` 无变化。

**完成条件：** 当前 T-02 的真实调试闭环保持可用；持久状态不再依赖某一个 dispatcher，
execution 可以被完整替换，相关单元测试通过且公开接口变化符合预期。

**Review 节点：** P2 完成后 review 类型所有权、状态机边界、`.mbti` 变化和资源关闭路径，
确认没有把 adapter 临时状态留在持久 session 中，再开始并发预热。

### P3. 接入后台预热与立即提示符

**状态：待实施**

**目标：** 启动 moondbg 后不等待 lldb-dap ready 就显示 prompt，并确保首个需要 adapter
的命令只消费同一个后台准备结果。

**工作内容：**

1. 进入 `Ready` 时启动后台准备任务，创建新的 lldb-dap、发送 `initialize` 并等待其
   response，缓存 capabilities；准备阶段不发送 `launch`，也不等待通常在 launch 后才
   出现的 `initialized` event；
2. 创建 readline editor 后立即进入异步 `read_line()`，让后台准备任务在用户编辑期间
   继续推进；
3. `help`、`break` 和 `quit` 等不依赖 adapter 的命令立即执行；`run` 复用并等待当前准备
   任务，ready 后才继续 launch，不重复启动 adapter；
4. 用户在准备期间退出时取消任务并关闭已创建的 pipe、process 和 dispatcher；
5. 按 `readline.mbt@0.1.2` 的现有边界，编辑期间不直接输出后台消息；准备失败先保存在
   session 中，在安全的命令边界报告；
6. 使用 P1 的延迟 adapter 验证 prompt 先于 initialize ready 出现、`help` 不等待、`run`
   等待后只执行一次。

**完成条件：** 在 adapter 人为延迟时，用户仍能立即看到 prompt 并使用本地命令；`run`
不会重复创建 adapter，提前退出后没有遗留子进程或损坏终端。

**Review 节点：** P3 完成后 review 首屏延迟、命令等待体验、后台任务所有权和
`readline.mbt@0.1.2` 下的错误呈现，再开始改变重复运行行为。

### P4. 实现重复运行、重启与断点重放

**状态：待实施**

**目标：** 把 T-02 的一次性 REPL 改为持久 REPL，并确保每次运行使用全新的 execution
和 adapter。

**工作内容：**

1. debuggee 正常或非零退出后只输出一次退出信息，回收当前 execution，恢复 prompt，
   并后台准备下一次运行的 adapter；
2. 后续 `run` 使用新的 adapter session，重新完成 launch、initialized、断点配置和
   configurationDone；
3. 逻辑断点及用户编号跨运行保留，每次运行重新接收和呈现本次 adapter 的 verified、
   actual line 或 rejected 结果；
4. 在 `Stopped` 状态执行 `run` 时输出重启反馈，终止并回收当前 debuggee/execution，
   随后创建全新的 execution，不额外询问；
5. `continue`、变量查询和源码位置仍只访问当前 execution；恢复运行或替换 execution 后，
   旧 stop epoch 的缓存和 DAP 引用全部失效；
6. 丢弃或隔离旧 execution 的迟到 response、event 和终止通知，不能重复输出退出信息或
   推进新 execution 的状态。

**完成条件：** 同一 REPL 中可以完成至少两次独立运行；断点编号稳定且每次正确重放；
Stopped 状态可以直接重启；每次运行都能证明使用了新的 adapter，旧 DAP 引用不会泄漏。

### P5. 异常路径、资源清理与端到端验收

**状态：待实施**

**目标：** 让后台准备失败、运行中 adapter failure 和各种退出路径只结束相关 execution，
不破坏持久 REPL，并完成 T-03 的真实链路验收。

**工作内容：**

1. 处理准备期间 adapter 失败：保存失败结果，在安全命令边界报告，不静默执行程序，也不
   让外层 REPL 退出；
2. 处理运行中 adapter 崩溃：恢复终端、尽力终止 debuggee、清理当前 execution，并等待
   用户下一次显式 `run`；
3. 验证 `quit`、EOF、readline Ctrl-C、准备超时、task cancellation、正常退出和非零退出
   都走确定的幂等清理路径；
4. 使用 fake adapter 覆盖 initialize 延迟与失败、用户提前退出、迟到消息、重复终止事件
   和 execution 交接竞态；
5. 使用真实 lldb-dap 与 `testdata/dwarf_probe` 验证重复运行、断点重放、Stopped 状态重启、
   变量查询、continue 和退出反馈；
6. 检查所有端到端路径结束后没有遗留 lldb-dap、debuggee 或测试子进程组，并运行项目规定
   的格式化、接口生成、检查和测试流程。

**完成条件：** 正常路径和异常路径都保留可用的外层 REPL；不会静默重跑 debuggee、重复
呈现终止反馈或跨 execution 使用临时引用；开发工具链下完整检查通过且没有遗留进程。

**Review 节点：** P4 与 P5 完成后进行 T-03 最终 review，核对持久状态与 execution
所有权、首屏体验、重复运行、故障恢复、真实 LLDB 行为和资源清理。
