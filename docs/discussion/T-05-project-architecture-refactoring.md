# T-05. 项目架构重构

> 最后更新日期：2026-08-27
> 仓库：moondbg
> 记录者：Codex-GPT-5

## 主题描述

T-02 至 T-04 以尽快建立调试闭环为目标，已经实现 lldb-dap 预热、持久 execution、源码
断点、运行、继续、单步、变量查询和源码卡片。但现有代码主要沿功能闭环逐步生长，尚未
形成能够长期承载 REPL、未来 DAP frontend 和 AI frontend 的项目级架构。

本主题讨论一次保持用户行为稳定的架构重构。重构不增加新的调试能力，目标是建立明确的
组件模型、package 依赖方向、状态所有权和测试边界，使后续增加命令、线程与栈帧导航、
变量展开、DAP frontend 或结构化 AI 接口时，不再继续扩大中央解析器和单体 session。

当前已经确认的方向是：

1. REPL 采用按命令纵向切分的结构，每个命令由 `repl` 下的一个专用 `.mbt` 文件负责；
2. 每个命令使用独立 struct，例如 `CommandRun`、`CommandList`、`CommandPrint`，参数和
   命令内部方法由该类型持有；
3. 各命令实现统一 trait，由共同接口约束执行行为；MoonBit async trait 与 trait object
   可以支持这一模型；
4. `repl/main.mbt` 保持为入口，读取一行后先分离命令名和参数，再根据第一个 token 分派；
5. 不能只整理 `repl` 文件，必须同时处理 application session、lldb-dap backend 和 DAP
   transport 之间尚未建立的依赖边界。

本主题的关键架构决策已经全部确认，具体边界集中列在文档底部“已确认决策”。

## 关联问题

暂无。按照当前讨论方式，本主题把架构方案和决策直接记录在 T-05，不拆分 Q 文档。

## 当前结构及问题

当前仓库只有三个正式 MoonBit package：模块根 package、`repl` 和 `render`。`render` 只依赖
MoonBit lexer，源码高亮边界相对独立；主要问题集中在根 package 和 `repl`。

### 1. REPL 以中央分支组织命令

`repl/command.mbt` 中的 `parse_repl_command` 通过连续的 `match command_arguments(...)`
依次尝试完整命令名和别名。命令定义同时散落在：

- `ReplCommand` enum；
- 中央解析函数；
- `print_help`；
- `run_repl` 分派；
- `main.mbt` 中的命令执行与输出函数；
- 单元测试和 Python REPL 端到端脚本。

因此新增或改变一条命令需要同时修改多个中央位置。更重要的是，命令不能独立持有参数、
解析规则、执行逻辑、帮助和测试，缺少真正的命令组件边界。

### 2. `repl/main.mbt` 不是单纯入口

当前 `main.mbt` 同时负责 CLI、可执行文件校验、adapter 定位、REPL 循环、命令分派、
session 操作、错误转换、debuggee output、breakpoint、变量、源码卡片和退出信息渲染。
这导致入口、应用控制和 presentation 混合，命令无法通过统一接口执行，也难以替换为面向
AI 的结构化输出。

### 3. 根 package 混合 application 与 lldb-dap 实现

`dap_session.mbt` 已超过 1100 行，同时包含：

- 用户可见的 `DebugSession`；
- 每次运行的 `DebugExecution`；
- DAP initialize/launch/configurationDone 和 execution 生命周期；
- breakpoint 配置与 response 解析；
- thread、stack frame、scope 和 variable 请求；
- adapter failure 恢复和下一 adapter 预热。

目前 `DebugSession::start` 直接接收 adapter 路径并创建 DAP execution，
`DebugSessionMachine::accept_event` 直接依赖 `DapEvent`。公共 `VariableSnapshot` 暴露
`variablesReference`，`DebugOutput` 暴露未经建模的 DAP category 字符串，公共状态中的
`Configuring` 也来自 DAP 生命周期。这些都说明 debugger application 尚未与 backend
protocol 解耦。

### 4. 文件拆分存在，但 package 依赖没有表达架构

`dap_protocol.mbt`、`dap_transport.mbt` 和 `dap_dispatcher.mbt` 已经按职责拆成文件，但仍与
session 和领域模型位于同一个 package。文件边界只能帮助阅读，不能阻止 application
直接依赖 DAP JSON、临时 request ID 或 adapter event，也不能通过 backend trait 注入 fake
实现进行隔离测试。

## 目标架构

### 1. 总体依赖方向

采用 ports and adapters 形式的依赖方向：

```text
                         REPL frontend
                               │
future DAP frontend ───────► DebugSession ◄─────── future AI frontend
                               ▲
                               │ DebugBackend port
                               │
                        LldbDapBackend
                               │
                               ▼
                  DAP protocol/client/transport
                               │
                               ▼
                           lldb-dap
```

根 `moondbg` package 是 debugger application/core，只声明用户可见的调试模型、session 和
backend port，不依赖 DAP、JSON、async process 或 lldb-dap。`lldb_dap` 实现 backend port，
并依赖独立的 DAP client package。REPL、未来 DAP frontend 和 AI frontend 都只复用
`DebugSession`，不复用彼此的输入语法或终端输出。

### 2. 确定的 package 与目录

```text
/
  backend.mbt                 DebugBackend port 与 backend 领域结果
  session.mbt                 持久 DebugSession 与用户动作编排
  state.mbt                   用户可见状态、execution/stop epoch
  breakpoint.mbt
  stack.mbt
  variable.mbt
  output.mbt

/dap
  protocol.mbt                DAP message 与 JSON 编解码
  framing.mbt                 Content-Length framing
  dispatcher.mbt              seq、response 配对和 event 分派
  transport.mbt               lldb-dap 子进程和 pipe

/lldb_dap
  backend.mbt                 DebugBackend 实现与 capability
  execution.mbt               单个 adapter/target execution
  launch.mbt                  initialize/launch/configurationDone
  breakpoint.mbt
  stack.mbt
  variable.mbt

/render                       MoonBit 源码高亮，暂时保持现有边界

/repl
  main.mbt                    CLI 与 composition root
  repl.mbt                    readline 循环
  command.mbt                 ReplCommand trait 与基础类型
  registry.mbt                名称/别名查找、帮助和补全元数据
  context.mbt                 命令共享的 session 与 frontend context
  result.mbt                  命令结果与 REPL 控制流
  run.mbt                     CommandRun
  break.mbt                   CommandBreak
  continue.mbt                CommandContinue
  next.mbt                    CommandNext
  step.mbt                    CommandStep
  finish.mbt                  CommandFinish
  print.mbt                   CommandPrint
  list.mbt                    CommandList
  help.mbt                    CommandHelp
  quit.mbt                    CommandQuit
```

根 package 不能依赖 `lldb_dap` 或 `dap`。`lldb_dap` 依赖根 package 和 `dap`；`repl` 作为
composition root 同时依赖根 package、`lldb_dap`、`render` 和 `readline`，创建具体 backend
并注入 `DebugSession`。

### 3. REPL 命令组件

每个命令 struct 是一次提交命令产生的不可变对象，只持有该次执行所需的已解析参数。共享
session、registry、输出策略和后续 frontend 状态由 `ReplContext` 持有，不能复制进每个命令
对象。

确定的执行链为：

```text
read_line
  → 分离 command name 与剩余 tokens
  → 根据名称/别名取得命令描述
  → 由对应命令文件解析私有参数并构造 CommandXxx
  → 转换为 &ReplCommand
  → async execute(context)
  → CommandResult
  → REPL 根据控制流继续或退出，并由 renderer 输出
```

`ReplCommand` trait 至少约束 async `execute`。构造函数不能放进面向 trait object 的静态
接口，因此使用命令描述对象保存规范名称、别名、usage、summary 和 parser/factory。
每个命令文件同时提供自己的描述对象和具体命令实现。这样 help 与未来 readline completion
可以读取同一份命令元数据，不再与 parser 手工同步。

命令执行不能知道 DAP command、JSON 或 lldb-dap 临时 ID；它只调用 `DebugSession` 的用户
动作。命令参数错误属于该命令的 parse error，不构造 `Invalid` 或 `Unknown` 伪命令。

### 4. Session 与 backend 状态所有权

按生命周期区分状态：

| 所有者 | 长期持有内容 |
|---|---|
| `DebugSession` | executable 与运行配置、用户逻辑断点及稳定编号、用户可见状态、当前线程/frame 选择、execution/stop epoch、最近一次稳定结果 |
| `LldbDapBackend` | adapter capability、当前 target/execution、DAP breakpoint ID、thread/frame ID、scope 与 variables reference、DAP request/event 转换 |
| DAP client | framing、sequence、request/response 配对、未解释的 message/event、子进程与 pipe |

`DebugSession` 不接受或返回 `DapEvent`、JSON、request seq、`variablesReference` 等协议细节。
`LldbDapBackend` 把 DAP 数据转换成 backend/domain result；DAP client 不知道 breakpoint、
stepping、MoonBit frame 选择或 session restart 语义。

`DebugBackend` 的存在不仅用于假设中的 GDB backend，也用于让 application session 可以注入
纯 MoonBit fake backend，独立测试断点重放、状态转换、stop epoch 和 adapter failure，减少
对 Python fake adapter 子进程的依赖。

### 5. 输出、DAP frontend 与 AI

REPL 命令是 human frontend 的输入适配器，未来 DAP frontend 不解析 REPL command，也不
调用 `CommandRun` 等类型；二者共享的是 `DebugSession` 与领域结果。

为了支持 AI 和稳定测试，命令不直接调用 `println`，而是返回结构化 `CommandResult`，
其中包含 REPL 控制流以及一组可渲染事件，例如 debuggee output、breakpoint update、stop、
variable、source view、error 和 process exit。human renderer 将其转为带高亮终端文本；未来
plain/JSON renderer 可以消费相同事件。

readline 编辑期间的真正异步消息将来可以通过 event sink 进入 frontend；不应为了尚未完成
的 readline 重绘能力，让每个命令直接拥有终端或后台 reader。

### 6. 测试边界

架构重构阶段保留现有 Python fake adapter 与 PTY E2E 作为回归基线，同时按组件建立必要的
测试边界：

- 每个命令文件测试自己的名称、别名、参数和执行结果；
- registry 测试名称冲突、别名查找、help 和 completion 元数据；
- `DebugSession` 使用 fake `DebugBackend` 测试 application 状态与持久配置；
- `lldb_dap` 在重构阶段继续使用 Python fake adapter 测试 request/event 映射和 adapter
  生命周期；
- DAP client 独立测试 framing、message classification、response 配对和异常关闭；
- REPL PTY 端到端测试只保留关键用户闭环、readline 与资源清理；
- 真实 `moon debug main` 继续负责 MoonBit DWARF 验收。

架构重构完成后，再单独迁移为 D6 确认的 MoonBit-first 分层测试体系；测试迁移不与本轮
package、backend、session 和 REPL 重组交叉进行。

## 任务划分（确认）

以下任务划分等待用户 review。P1 至 P8 完成本次架构重构，P9 在架构完成后单独迁移测试
体系。每个阶段完成后都暂停 review，并保持 `moon check`、MoonBit 测试和已有 Python fake
REPL 端到端回归通过；不采用先删除旧实现、最后再恢复功能的 big-bang rewrite。

### P1. 建立 core port 与迁移桥

在根 package 定义 DAP-independent 领域结果和高层 `DebugBackend`，让 `DebugSession` 通过
port 使用调试能力。现有 DAP 实现暂时留在根 package，并通过临时的 in-package backend
适配新接口；本阶段不移动大段协议代码。

本阶段重点 review `DebugBackend` 的能力粒度、backend/session 生命周期和领域结果是否仍
泄漏 DAP。允许公共 API 按 D5 变化，但用户可见行为保持不变。

### P2. 提取 DAP client package

建立 `dap` package，将 protocol、framing、dispatcher 和 transport 连同对应测试迁入其中，
使其只负责协议编码、可靠收发、response 配对和原始 event 分派。迁移桥可以暂时从根
package 依赖 `dap`，但 `dap` 不能依赖 debugger 领域模型。

本阶段只改变代码归属和 import graph，不改变 launch、breakpoint、stepping 或变量语义。

### P3. 提取 LldbDapBackend

建立 `lldb_dap` package，将临时 backend、`DebugExecution`、initialize/launch、DAP
breakpoint、stack、scope、variable、adapter failure 和预热逻辑迁入其中并实现
`DebugBackend`。`repl` 开始作为 composition root 创建具体 backend 并注入 `DebugSession`。

本阶段完成后，根 application package 不再依赖 `dap`、JSON、async process 或 lldb-dap，
package graph 达到 D4 确认的方向。

### P4. 收敛 DebugSession 与 core 模型

按职责拆分根 package 中的 session、state、breakpoint、stack、variable 和 output，确保
`DebugSession` 只持有持久用户配置和 application 状态。清除公共模型中的 DAP 临时字段，
由 backend 负责用户逻辑选择与当前 execution 临时 ID 的映射。

为本次新架构补充必要的纯 MoonBit fake `DebugBackend` 测试，验证断点重放、状态转换、
stop epoch 和 failure；这不代表提前迁移 D6 所述的既有 Python 测试体系。

### P5. 建立 REPL 命令框架

实现 `ReplCommand`、`CommandSpec`、`CommandRegistry`、`ReplContext`、`CommandResult` 和
human renderer 骨架。先迁移 `help`、`quit` 和 `exit`，验证名称/别名冲突检查、参数解析、
统一执行和继续/退出控制流。

其余命令在本阶段可以继续走临时旧路径，但 registry、help 和未来 completion 使用同一份
命令元数据，不能再增加新的中央分派分支。

### P6. 迁移执行控制命令

依次迁移 `break`、`run`、`continue`、`next`、`step` 和 `finish`。每条命令由独立文件中的
具体 struct、私有参数解析和 trait 实现负责，并通过 `DebugSession` 执行领域动作，返回
结构化 `CommandResult`。

每迁移一条命令，就删除旧 parser/dispatcher 中对应分支并保留完整名称与现有别名行为；
不得让命令引用 DAP 或直接输出终端文本。

### P7. 迁移观察命令与 presentation

迁移 `print` 和 `list`，并将 source view、variable、stop、breakpoint update、debuggee
output、process exit 和 user error 收敛为可渲染事件。human renderer 负责源码高亮和终端
文本，命令及 `DebugSession` 不直接 `println`。

本阶段删除剩余中央命令 enum、parser、dispatcher 和分散的输出函数，使 `repl/main.mbt`
不再感知具体命令类型。

### P8. 架构封口与完整验收

删除临时 backend、迁移桥、兼容分支和已被替代的旧文件，使 `repl/main.mbt` 只保留 CLI、
依赖组装与程序入口。检查最终 package graph、公共 `.mbti` 和状态所有权，并更新架构文档。

完成格式化、检查和测试，运行现有 Python fake E2E 与真实 `moon debug main` 调试闭环。
本阶段验收通过即表示架构重构完成。

### P9. 迁移 MoonBit-first 测试体系

在 P8 完成后，按 D6 将 session、command 和 DAP 行为下沉到纯 MoonBit fake backend、内存
client/transport 和结构化结果测试；使用 MoonBit 测试代码配合极小 native C PTY stub
覆盖真实 readline 交互，并把真实 `moon debug main` 保留为独立 capability-gated acceptance
suite。

迁移期间 Python E2E 继续作为行为基线。只有等价场景已被新测试覆盖后，才删除对应 Python
fake adapter 或 E2E 驱动；开发诊断脚本不因测试迁移而被机械删除。

## 已确认决策

### D1. 命令名分派采用显式 CommandRegistry

已确认采用显式 `CommandRegistry`。每个命令文件提供包含规范名称、固定别名、usage、
summary 和 parser/factory 的 `CommandSpec`；默认 registry 显式列出全部 spec，并在启动或
测试时拒绝名称或别名冲突。`main` 读取输入并分离首 token 后，只调用 registry 查找并构造
命令，不感知 `CommandRun`、`CommandList` 等具体类型。help 和未来 readline completion
复用同一份 spec 元数据。

### D2. 命令执行统一返回结构化 CommandResult

已确认各个 `ReplCommand` 不直接调用 `println`，而是统一返回 `CommandResult`。
`CommandResult` 是 REPL frontend 的执行结果，不是 debugger core 的领域结果；它至少包含
继续或退出 REPL 的控制流，以及按顺序排列的结构化 presentation events。`DebugSession`
先返回领域结果，具体命令将其转换为 `CommandResult`，再由 renderer 统一输出。

第一轮只实现 human renderer；plain/JSON renderer 可以后续增加。命令执行周期之外到达的
debuggee 异步输出不强行塞入返回值，将来通过独立 event sink 进入同一 presentation 层。

### D3. 采用高层 DebugBackend 并明确状态所有权

已确认建立面向调试能力的高层 `DebugBackend`。它提供 launch、breakpoint、continue、
stepping、stack 和 variable 等当前已经需要的调试动作，不提供 `send_request` 一类 DAP
协议接口，也不为尚未实现的通用 debugger 能力预先设计抽象。

`DebugSession` 持有用户配置、逻辑断点及稳定编号、用户的线程和 frame 选择、execution/
stop epoch 与用户可见状态；`LldbDapBackend` 持有 adapter capability、当前 execution 以及
DAP breakpoint/thread/frame ID、scope 和 variable reference 等临时状态；DAP client 只
负责 framing、sequence、response 配对、原始消息和子进程管道。用户的逻辑选择与当前
execution 的 DAP 临时 ID 分离，由 backend 负责映射。

backend 方法只返回 stop、stack frame、variable 等领域结果，不向 `DebugSession` 暴露
JSON、`DapEvent` 或 `variablesReference`。该边界同时允许使用纯 MoonBit fake backend
隔离测试 application session。

### D4. 采用由编译器强制的 package 边界

已确认通过 MoonBit package 和 import graph 强制关键架构边界，而不只依靠 `.mbt` 文件
划分。根 package 只包含 application/core，不依赖 `dap` 或 `lldb_dap`；`dap` 只负责协议、
framing、dispatcher 和 transport，不理解调试领域；`lldb_dap` 依赖根 package 和 `dap`，
实现 `DebugBackend`；`repl` 作为 composition root，依赖根 package、`lldb_dap`、`render`
和 readline，负责组装具体实现；`render` 继续保持独立。

该拆分允许 `moon check` 直接发现违反依赖方向的引用。跨 package 所需接口按边界公开，
但 REPL 各命令仍采用“一个命令一个文件”的纵向切片并共同留在 `repl` package，不为每条
命令创建微型 package。

### D5. 允许本次重构打破现有 MoonBit 公共 API

已确认 moondbg 是 `moon debug` 的专用工具，不作为 MoonBit library 对外提供兼容承诺。
本次重构允许直接改变 `DebugSession::start`、`VariableSnapshot::variables_reference` 等现有
公开接口，不为尚未发布的内部 API 建立 facade 或 deprecated 兼容层，尤其不能为兼容而
保留 DAP 临时标识向 application 层的泄漏。

重构期间稳定的是 `moon debug main`、`moondbg <executable>`、现有 REPL 命令及用户可见
语义。每个阶段仍须独立可构建、可测试、可 review，并核对 `.mbti` 变化、fake 回归和真实
调试闭环，避免 big-bang rewrite。重构完成后形成的跨 package 接口作为项目内部架构契约
维护。

### D6. 架构重构完成后迁移为 MoonBit-first 分层测试

已确认采用“MoonBit-first，而非 MoonBit-only”的分层测试体系，并将迁移安排在本次架构
重构完成之后。重构期间继续保留 Python fake adapter 和 PTY E2E 作为行为基线，不把测试
语言迁移与 package、backend、session 或 REPL 重组混在同一阶段。

迁移后的分层为：

1. 默认 `moon test` 使用纯 MoonBit fake `DebugBackend`、内存 DAP client/transport 和命令
   结果测试，不依赖 Python、lldb-dap 或开发版 `moon debug`；
2. `lldb_dap` 只保留少量跨进程协议集成测试。需要真实 readline 交互的测试由 MoonBit
   编写断言和驱动，使用类似 `readline.mbt` 现有测试的极小 native C PTY stub；
3. 真实 `moon debug main` 作为独立、显式执行且带 capability 检查的 toolchain acceptance
   suite，在本地开发环境和具备依赖的 CI 机器运行，不混入默认可移植测试；
4. 迁移期间保留 Python E2E 作为行为基线，待对应场景被 MoonBit 测试覆盖后再逐步删除。

这不是把 Python 脚本逐行重写为 MoonBit。D3 的 fake backend、D4 的 package 边界和 D2 的
结构化结果应先把绝大多数行为下沉为进程内测试，只把 PTY、process framing 和真实工具链
留在更窄的集成层。

## 待决策问题

暂无。
