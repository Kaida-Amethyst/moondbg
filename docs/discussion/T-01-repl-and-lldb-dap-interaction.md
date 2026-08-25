# T-01. 第一版 REPL 交互模型与 lldb-dap 会话边界

> 最后更新日期：2026-08-25
> 仓库：moondbg
> 记录者：Codex-GPT-5

## 主题描述

本主题讨论 moondbg 第一版 REPL 的用户交互模型，以及 REPL 与 `lldb-dap` 之间的会话模型。当前阶段直接在本主题内记录讨论前提、已确认决策、建议和待决策问题，暂不拆分 Q 文档。没有列入“已确认决策”的建议仍不视为已经采用的设计。

已经明确的前提是：第一阶段先实现 REPL，后续再实现面向编辑器的 DAP；底层调试能力当前倾向于复用 `lldb-dap`，不自行实现 native debugger；MoonBit 构建系统、编译器以及 `../readline.mbt` 都可以为最终体验进行修改，不要求 moondbg 被当前接口和 DWARF 行为反向约束。

## 关联问题

- 暂无。本主题继续按约定直接记录已确认决策，不拆分 Q 文档。

## 当前建议与分析

### 1. 总体模型：用户同步，内部异步

已经确认第一版采用“停点驱动的同步 REPL”：用户在同一时刻只看到一个提示符；执行 `run`、`continue`、`next`、`step` 或 `finish` 后，提示符消失；程序再次停止或退出时，moondbg 输出一次完整的停止信息，然后重新显示提示符。程序运行期间不接受普通 REPL 命令，只保留 Ctrl-C 暂停入口。

这只是用户交互上的同步模型。内部的 DAP 会话必须是异步、事件驱动的，不能实现成“发送一个请求，阻塞等待对应响应，再处理下一条消息”。DAP response 与 `initialized`、`output`、`stopped`、`exited` 等 event 可能交错到达，而且可能同时存在多个尚未完成的请求。

建议用户可见状态先收敛为四种：

```text
Ready ──run──> Running ──stopped──> Stopped
                  │                    │
                  └────exited────────> Exited
```

`Ready`、`Stopped`、`Exited` 状态下可以显示提示符；`Running` 状态下不显示普通命令提示符。启动和配置等短暂中间状态可以存在于内部，但不必成为用户需要理解的概念。

### 2. 基本使用过程

```text
$ moon debug main
Ready: target/debug/build/main/main.exe

moondbg> b main
Breakpoint 1 at main/main.mbt:12

moondbg> r
Breakpoint 1 hit — main
main/main.mbt:12
  10 │ fn main {
  11 │   let x = 3
> 12 │   let y = square(x)
  13 │   println(y)
  14 │ }

moondbg> n
Step complete — main
main/main.mbt:13
  11 │   let x = 3
  12 │   let y = square(x)
> 13 │   println(y)

moondbg> p y
9 : Int

moondbg> c
9
Program exited normally (code 0).

moondbg> r
```

进入 REPL 后处于 `Ready`，不自动运行程序，用户可以在第一次运行之前设置断点。程序退出后仍保留 REPL，允许再次执行 `run`。

断点、程序参数、环境变量和工作目录属于当前 REPL session，跨多次运行保留。`run -- new args` 替换当前 session 的程序参数，后续不带参数的 `run` 继续复用这组参数。在 `Stopped` 状态执行 `run` 时，moondbg 输出 `Restarting program...`，终止当前 debuggee 并重新启动，第一版不额外询问确认。

### 3. 停点卡片是主要反馈单元

已经确认每次由于断点、单步、异常、信号或用户暂停而停止时，使用统一的“停点卡片”输出，而不是要求用户随后手动执行 `where`、`frame` 或 `list` 才知道当前位置。

停点卡片至少应表达：

- 停止原因；
- 当前选中的栈帧；仅在多线程或异常停止时额外显示线程信息；
- MoonBit 函数名及源码位置；
- 当前行上下各两行源码。

停点卡片不自动打印全部局部变量。局部变量可能很多，展开也可能触发额外 DAP 请求；用户可以通过 `locals` 主动查看。

如果真实顶帧被编译器明确标记为 artificial/runtime，默认选择最近的 MoonBit 用户帧，同时明确输出类似 `Stopped in runtime; showing MoonBit frame #2` 的说明，避免隐藏真实停止位置。`backtrace --all` 展示未经隐藏的完整调用栈；如果找不到 MoonBit 用户帧，则展示真实顶帧。

停点卡片在内部应先形成结构化的 `StopSnapshot`，再由 REPL renderer 输出文本。以后 AI 接口和对外 DAP 可以复用同一个语义对象，而不是重新解析终端文本。

### 4. 第一版命令面

已经确认第一版采用一组边界清楚的规范命令：

```text
run [-- program args]
break <function|file:line>
breakpoints
delete <breakpoint-id>

continue
next
step
finish

backtrace
frame <index>
up
down
list
threads
thread <id>

locals
print <name-or-path>
lldb <command>

help [command]
quit
```

固定别名包括 `r`、`b`、`c`、`n`、`s`、`bt`、`p`、`q`，不支持未在文档中定义的任意前缀匹配。固定命令与固定别名更容易形成稳定文档，也更适合 AI 可靠调用。

空行不重复上一条命令。调试器传统上常用空行重复命令，但意外重复 `continue` 或 `next` 会直接改变程序状态；历史命令可以通过 readline 的方向键访问。

错误信息应基于用户可见状态表达，例如在 `Ready` 状态执行 `next` 时提示“程序尚未启动，请先执行 `run`”，而不是暴露 adapter 的协议错误。

已经确认第一版同时提供 `threads` 和 `thread <id>`，并采用 all-stop 用户模型：任一线程停止后，用户将整个进程视为已停止。`stopped` event 指明线程时默认选中该线程；切换线程后重新选择该线程最近的 MoonBit 用户帧并输出停点卡片，不保留该线程此前选择的 frame。`backtrace`、`frame`、`up`、`down`、`locals` 和 `print` 始终作用于当前线程和当前帧。程序恢复运行后，所有线程和栈帧选择失效，下次停止时重新选择。

### 5. `print` 的能力边界

已经确认第一版把 `print` 定义为“变量路径查询”，不承诺任意 MoonBit 表达式求值。

具体支持局部变量和结构化路径，例如：

```text
p x
p point.x
p items[3]
p matrix[2][1]
```

根变量通过当前 frame 的 DAP `scopes` 和 `variables` 查找，字段和索引通过 `variablesReference` 逐层访问。输出应包含 MoonBit 类型和简要值，并允许继续展开子项。第一版不支持运算符表达式、函数调用等完整表达式，也不静默退回 LLDB expression evaluator。

同时提供显式的 `lldb <command>` 逃生通道。该命令的语法和输出不属于 moondbg 的稳定接口，面向 AI 的接口也不应默认使用它。

### 6. 键盘、进程输出与终端所有权

已经确认区分 Ctrl-C 的两种语义：

- 提示符正在编辑时，Ctrl-C 清空当前输入并返回一个干净的新提示符；
- 被调试程序正在运行时，Ctrl-C 请求暂停 debuggee，并在收到 `stopped` event 后显示停点卡片，不能终止 moondbg。

第一版为 debuggee 分配独立 PTY，并支持交互式 stdin。程序处于 `Running` 时，普通终端输入转发给 debuggee，Ctrl-C 由 moondbg 截获并用于暂停；回到 `Stopped` 后，终端输入重新属于 readline。每次从 `Running` 切回 `Stopped` 都恢复终端模式，避免 debuggee 对终端的修改破坏 REPL。

程序运行时，stdout/stderr 原样持续输出，不添加逐行前缀。提示符下 Ctrl-D 等同于 `quit`；`quit` 在 debuggee 仍存活时终止它，然后关闭 adapter。第一版不提供 detach。

### 7. DAP 请求、响应、事件与 adapter 生命周期

已经确认执行控制命令不能把对应 request 的 response 当作命令完成。每次 `run`、`continue`、`next`、`step`、`finish` 或 `pause` 建立新的 execution epoch；成功 response 只表示 adapter 接受请求，`continued` 只推进到 `Running`，两者都不恢复提示符。REPL 应继续处理并输出中途的 `output` event，直到目标进入下一个稳定状态。

收到 `stopped` 时，当前执行事务完成，建立新的 stop epoch、生成停点卡片并恢复提示符；收到 `exited` 时记录退出码、进入 `Exited` 并恢复提示符；只有 `terminated` 而没有正常 `exited` 时，按“调试会话终止”结束等待。`exited` 与 `terminated` 应合并为一次用户反馈。request 明确失败且程序没有恢复运行时回到原来的 `Stopped` 状态并报告错误。若稳定状态 event 先于对应 response 到达，以 event 为用户状态依据，晚到的 response 只用于协议记账。

初始化过程也不能假设严格的串行顺序。已经观察到 `lldb-dap` 可能在 `launch` response 返回之前发送 `initialized` event，因此建议的逻辑顺序是：

1. 发送 `initialize` 并记录 capabilities；
2. 发起 `launch`，但不因等待它而停止处理其他消息；
3. 收到 `initialized` 后发送源码断点和函数断点；
4. 发送 `configurationDone`；
5. 根据后续 response 和 event 推进到 `Running`、`Stopped` 或失败状态。

DAP transport 应只有一个持续读取消息的入口，通过 `seq` 将 response 分派给 pending request，同时把 event 交给 `DebugSession` 状态机。REPL 命令不应直接读写 DAP JSON 或自行消费 adapter 输出。

已经确认 moondbg REPL session 是持久状态的所有者，而 `lldb-dap`、target 和 PTY 是单次 `run` 的资源。`Ready` 状态可以尚未启动 adapter；每次 `run` 创建全新的 `lldb-dap`，完成 initialize/launch/configuration，并重放逻辑断点、参数、环境变量和 cwd。debuggee 退出后正常 disconnect 并回收本次 adapter 与 PTY；在 `Stopped` 状态执行 `run` 时，先回收旧资源再创建新的一套。

adapter 崩溃时不静默重跑程序。moondbg 恢复终端、尽力回收已启动的 debuggee，并报告 adapter failure；用户随后显式执行 `run` 时创建全新 adapter 并恢复 session 配置。第一版不尝试恢复崩溃前的执行位置、调用栈或变量状态。

### 8. 停点生命周期与查询策略

已经确认每次 `stopped` 建立一个新的 stop epoch。`frameId`、`variablesReference` 等 DAP 引用只在该次停止期间有效；程序恢复运行后，上一 stop epoch 的栈帧、scope 和变量缓存全部失效。

已经确认采用“最小必要预取＋stop epoch 内按需缓存”。收到 `stopped` event 后，在恢复提示符前获取线程列表、当前线程首批 20 个栈帧、选中帧的源码位置和上下各两行源码；仅在异常停止时额外获取 `exceptionInfo`。如果首批 20 个栈帧中没有 MoonBit 用户帧，则继续分页，直到找到用户帧或调用栈结束。

停点时不预取 `scopes`、`variables`、其他线程的 backtrace、当前线程剩余栈帧或变量子项。`backtrace`、`thread <id>`、`locals` 和 `print` 在用户执行时按需加载；同一个 stop epoch 内缓存并合并重复请求，恢复运行后整体失效。提示符出现后不做投机式后台预取，避免用户立即继续运行时产生无用请求和跨 epoch 消息。

执行控制的状态变化以 event 为准，而不是假定 response 和 event 的到达顺序。当用户暂停与自然断点同时发生、进程在请求途中退出、或者连续收到多个停止相关 event 时，应按 execution epoch 合并为一次稳定状态变化和一次用户反馈。

### 9. 断点的所有权

用户看到的断点编号和生命周期建议由 moondbg 管理，例如 `Breakpoint 1` 在重新运行时仍表示同一个用户断点。`lldb-dap` 返回的 breakpoint ID 只属于当前 adapter session，不应直接成为稳定用户接口。

DAP 的源码断点以文件为单位设置。某个文件的断点发生增删时，moondbg 需要重新发送该文件的完整断点集合，而不是只发送增量。函数断点也应维护对应的完整集合。未启动前设置的断点可以先进入 moondbg 的逻辑集合，在 adapter 完成初始化后统一配置，并把 verified、实际位置和错误反馈给用户。

### 10. 建议的内部边界

建议至少保持以下三个逻辑层次：

```text
REPL / controller
    │  run、step、print、StopSnapshot、用户错误
    ▼
DebugSession
    │  会话状态、断点、线程/栈帧选择、stop epoch
    ▼
DAP transport
       framing、seq/request 映射、唯一 reader、原始消息
```

REPL 层只处理用户命令和结构化结果；`DebugSession` 把多个 DAP 请求和事件组合成一次用户动作；transport 只保证协议消息的可靠收发和分派。这个边界有利于以后增加面向 AI 的结构化接口和对外 DAP，而不必复制调试状态机。

具体执行模型可以是单事件循环，也可以是 DAP reader 与 REPL 分离的并发模型。无论选择哪一种，都不能让 readline 的阻塞读取阻止 DAP 消息被及时读取，否则 adapter pipe 可能阻塞，异步输出和外部终止事件也无法正确处理。

### 11. 构建系统、编译器与 moondbg 的接口契约

已经确认不让当前 DWARF 或符号命名的不足决定最终命令语义。整体调用链为：

```text
moon debug main
  ├─ moon 以 --debug-info full 调用编译器
  ├─ 编译器生成包含完整 DWARF 的 program.exe
  ├─ moon 生成版本化的 debug artifact manifest
  ├─ moon 释放构建锁
  └─ moon 调用 moondbg，以 program.exe 为主要参数并传入其他选项
```

moondbg 的调用形态如下；具体选项名可以在实现阶段固定：

```text
moondbg <program.exe> --artifact-manifest <manifest> [其他选项] -- [程序参数]
```

`.exe` 是被调试目标的主要参数。artifact manifest、cwd、参数覆盖、工具链位置等作为其他选项或运行时配置传入。`moon` 不直接启动 LLDB 或 `lldb-dap`；moondbg 不反向调用 `moon build`。正式环境从当前 MoonBit toolchain 中定位配套 moondbg，不依赖用户 `PATH`，开发阶段可以提供显式覆盖路径。

静态 artifact manifest 使用版本化 schema，只保存构建产物事实，例如：

```text
schemaVersion
workspaceRoot
module/package/target
targetTriple
compilerBuildId
artifactBuildId
sourceRoots/sourceMappings
sourceDigests
MoonBit entry identity
runtime/artificial frame metadata
```

继承的环境变量不写入 manifest，避免持久化敏感信息。cwd、程序参数、环境覆盖和终端配置属于动态 moondbg session。moondbg 启动时校验 manifest schema、artifact build ID 和传入的 `.exe` 是否匹配；源码摘要不一致时提示用户重新执行 `moon debug`。

编译器通过 `--debug-info full` 产生完整 DWARF，并负责让 LLDB 获得以下 MoonBit 源码语义：

- `break main` 指向 MoonBit 入口，而不是 C `main` 或 runtime wrapper；
- 正确的源码文件、行和列；
- 源码函数名及 linkage name；
- 参数、局部变量和 lexical scope；
- MoonBit 类型、字段和内存布局；
- 变量 location 和 optimized-out 状态；
- artificial/generated、prologue/epilogue 和 stepping 边界；
- debug profile 允许 inline 时的 inline call-site 信息。

DWARF 是源码位置、变量和类型信息的事实来源。只有 LLDB/DAP 无法表达的 MoonBit 特有信息，例如 runtime 帧分类、入口逻辑身份和源码路径映射，才进入 manifest 或编译器 sidecar。moondbg 不猜测构建目录，不从 mangled symbol 反推完整源码身份，不根据函数名前缀猜测 runtime 帧，也不修补本应由 line table 或 lexical scope 表达的信息。

### 12. readline.mbt 的角色

同步 REPL 的基本输入、历史和补全由 `readline.mbt` 承担。已经确认第一版需要支持异步消息立即显示，并无损恢复正在编辑的提示符、输入内容和光标位置，因此可以按需要扩展该库。

即使程序只在停止状态显示提示符，adapter 仍可能在用户编辑命令时产生 output、terminated 或其他事件。DAP reader 只把事件放入队列，不能直接写终端；UI/readline 所在的线程负责消费事件，通过类似 `print_above + redisplay` 的能力输出消息并恢复编辑现场。若事件改变了会话状态，恢复的提示符应反映新状态，但保留用户尚未提交的输入。

## 已确认决策

1. **采用停点驱动的同步 REPL。** 程序运行时收起普通提示符，只保留 Ctrl-C 暂停入口；停止或退出后输出停点信息并恢复提示符。
2. **每次停止自动输出统一的停点卡片。** 默认展示停止原因、MoonBit 函数与位置、当前行上下各两行源码；线程信息按需出现，不自动展示 locals。runtime/artificial 顶帧默认跳到最近的 MoonBit 用户帧，但明确告知真实停止位置，并通过 `backtrace --all` 保留完整视图。
3. **采用可重复运行的持久 REPL session。** 首次进入停在 `Ready`，不自动运行；程序退出后保留 REPL；断点、参数、环境变量和 cwd 跨运行保留；`run -- ...` 更新参数；停止状态执行 `run` 直接终止并重启，不额外确认。
4. **采用规范命令与固定别名。** 不支持任意前缀匹配；空行无操作；历史命令通过 readline 访问。
5. **第一版提供显式线程和栈帧模型。** 提供 `threads`、`thread <id>` 并采用 all-stop；默认选中停止线程，切换线程时重置到最近的 MoonBit 用户帧；恢复运行后所有线程和 frame 选择失效。
6. **`print` 只承诺变量路径查询。** 支持变量、字段和索引逐层访问，不支持完整表达式，也不静默退回 LLDB evaluator；提供非稳定的显式 `lldb <command>` 逃生通道。
7. **第一版通过独立 PTY 支持交互式 debuggee。** Running 时普通输入属于 debuggee、Ctrl-C 用于暂停；Stopped 时输入属于 readline；提示符下 Ctrl-D 等同 `quit`，`quit` 终止存活的 debuggee 并关闭 adapter，第一版不支持 detach。
8. **异步消息立即显示并无损重绘 readline。** DAP reader 只投递事件，UI 线程统一输出；提示符编辑期间通过 `print_above + redisplay` 恢复输入和光标，不把状态变化延迟到下一条命令。
9. **执行控制以 execution epoch 的稳定状态 event 为完成条件。** response 和 `continued` 不恢复提示符；`stopped`、`exited` 或单独的 `terminated` 完成事务；response 与 event 可以任意交错，重复退出事件合并为一次反馈。
10. **每次 `run` 创建全新的 lldb-dap session。** 持久状态属于外层 moondbg session；每次运行重建 adapter、target 和 PTY，并重放配置。adapter 崩溃后不静默重跑程序，只做终端恢复和尽力清理；下次用户显式 `run` 时使用新 adapter。
11. **停点采用最小必要预取和 stop epoch 内按需缓存。** 恢复提示符前只获取线程、当前线程首批 20 帧、选中帧源码及必要的异常信息；变量、其余栈帧和其他线程栈按命令加载，不做投机式后台预取。
12. **moon、编译器和 moondbg 采用明确的分层接口。** `moon debug main` 以 `--debug-info full` 构建完整 DWARF，释放构建锁后以生成的 `.exe` 为主要参数调用工具链内的 moondbg；版本化 manifest 补充静态构建事实，动态运行配置属于 session；DWARF 承载源码、变量和类型语义，sidecar 只补充 LLDB/DAP 无法表达的信息。

## 待决策问题

暂无。T-01 初始列出的决策问题 1—12 均已确认；后续发现的新问题再继续补充。
