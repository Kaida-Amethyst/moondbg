# T-06. 调用栈、栈帧导航与局部变量

> 最后更新日期：2026-09-01
> 仓库：moondbg
> 记录者：Codex-GPT-5

## 主题描述

moondbg 已经能够设置源码和函数断点、重复运行程序、继续执行、源码级单步、显示当前停点
源码，并通过结构化变量路径查看标量、struct、FixedArray、Array 和 boxed enum。当前主要
缺口不再是“能否停住并看到一个值”，而是缺少对一次停止的完整执行上下文：用户只能查看
自动选中的一个 frame，不能看到调用链、切换到调用者，也不能主动列出所选 frame 的局部
变量。

本主题实现当前线程的调用栈、栈帧选择和局部变量查询，使以下调试过程形成闭环：

```text
(moondbg) bt
> #0  @app.math.sum      math.mbt:12
  #1  @app.service.run  service.mbt:31
  #2  @app.main         main.mbt:8

(moondbg) up
Selected frame #1: @app.service.run at service.mbt:31
  ... source view ...

(moondbg) locals
request: Request
result: Result

(moondbg) p request.path
request.path: String = ...
```

T-06 是 T-01 已确认的第一版 REPL 交互模型的后续实施里程碑，不重新讨论“是否需要调用栈
和 frame 模型”。本主题允许同时修改 moondbg、`lldb-dap` 映射、MoonBit 编译器调试信息
生成以及 `moon debug` 的构建产物接口。遇到源码语义缺失时，应优先补齐编译器 DWARF 或
明确的构建元数据，而不是长期依靠函数名前缀、构建目录或 LLDB 展示文本猜测。

## 关联主题

- [T-01. 第一版 REPL 交互模型与 lldb-dap 会话边界](T-01-repl-and-lldb-dap-interaction.md)
  已确认命令面、停点卡片、线程/frame 选择生命周期、首批 20 帧预取和 stop-epoch 缓存；
- [T-03. 持久 REPL 与 execution 生命周期](T-03-persistent-repl-and-execution-lifecycle.md)
  已建立 execution/stop epoch、重复运行和 adapter 资源所有权；
- [T-04. 源码级单步执行](T-04-source-level-stepping.md) 已建立 `next`、`step`、`finish`
  以及恢复运行后旧 frame 状态失效的基础；
- [T-05. 项目架构重构](T-05-project-architecture-refactoring.md) 已确认
  `DebugSession` 保存用户逻辑选择，`LldbDapBackend` 封装 DAP thread/frame ID，REPL 只
  消费结构化领域结果。

本主题暂不拆分 Q 文档。方案和需要进一步确认的实施细节先统一记录在 T-06。

## 已继承的产品决策

以下内容已经在 T-01 确认，本主题直接继承：

1. 提供规范命令 `backtrace`、`frame <index>`、`up`、`down` 和 `locals`；`backtrace` 的
   固定别名是 `bt`，不支持未声明的任意前缀匹配；
2. 每次停止自动输出停点卡片，展示当前选中 frame 的 MoonBit 函数、源码位置和源码窗口，
   但不自动打印全部 locals；
3. 若真实顶帧是 runtime/artificial frame，默认选择最近的 MoonBit 用户 frame，同时明确
   告知用户发生了自动跳转；`backtrace --all` 可以显示未经隐藏的完整调用栈；
4. `backtrace`、`frame`、`up`、`down`、`locals`、`list` 和 `print` 始终作用于当前线程和
   当前 frame；
5. 收到新的 `stopped` event 后重新建立 frame 选择；程序恢复运行后，旧 frame 选择、
   frameId、scope、variablesReference 和相关缓存立即失效；
6. 停点阶段只预取当前线程首批 20 个 frame；没有找到 MoonBit 用户 frame 时继续分页，
   `backtrace` 和其他线程的调用栈按需加载；同一 stop epoch 内缓存已经取得的页面；
7. frame、locals 和 stop 信息先形成 backend 无关的领域对象，再转换为 presentation event，
   human REPL、未来 AI frontend 和未来 DAP frontend 不解析终端文本。

## 本轮计划实现的用户能力

### 1. `backtrace` 与 `bt`

`backtrace` 显示当前线程的 MoonBit 用户调用栈，标出当前选中的 frame。每一项至少包含：

- 用户可引用的 frame 序号；
- MoonBit 源码函数名；
- 源码文件、行，存在可靠信息时再显示列；
- 当前 frame 标记；
- 信息不完整、源码缺失或变量不可用等必要状态。

`backtrace --all` 显示同一线程未经隐藏的完整物理调用栈，包括 runtime、C/native 和无法
分类的 frame。默认视图不能通过删除信息制造一个看似连续但无法与 `frame <index>` 对应的
调用栈。

调用栈较深时，backend 使用 DAP `stackTrace` 的 `startFrame` 和 `levels` 分页加载。默认
停点只承担 T-01 已确认的最小预取；用户显式执行 `backtrace` 时才继续取得当前视图所需的
剩余页面。

### 2. `frame <index>`、`up` 与 `down`

`frame <index>` 在当前 stop epoch 和当前线程中选择一个 frame。成功后不重新制造 stop
reason，而是输出一次“已选择 frame”的结构化反馈，并显示该 frame 的源码窗口。随后：

- `list` 以所选 frame 的源码位置为中心；
- `locals` 查询所选 frame 的 scopes；
- `p <path>` 从所选 frame 解析根变量；
- 再次执行 `backtrace` 时在对应项上显示当前标记。

`up` 选择调用者方向的下一个可导航 frame，`down` 选择被调用者方向的下一个可导航 frame。
到达边界时保持当前选择，并返回稳定的用户错误，不发送无意义的 DAP 请求。

显式选择 runtime/native frame 是允许的，但该 frame 可能没有 MoonBit 源码或可用 locals；
这种情况应明确报告能力缺失，不能悄悄退回之前的 MoonBit frame。

### 3. `locals`

`locals` 获取当前 frame 的局部变量和参数，不包含 registers，也不默认混入全局变量。每个
变量先形成现有 `VariableSnapshot` 或更轻量的领域摘要，再由 renderer 统一输出；命令文件
不直接处理 DAP JSON 或终端文本。

局部变量必须继续遵守已经建立的规则：

- 使用编译器产生的源码变量名和 MoonBit 类型；
- 区分“不存在”和“当前位置不可用/optimized out”；
- 不暴露 `variablesReference`、frameId、原始 JSON 或 C backend 表达式；
- 同名 shadowed locals 选择当前 lexical scope 中有效的实例；
- `locals` 得到的变量与随后 `p <name-or-path>` 使用同一 frame 和同一 stop-epoch cache；
- 聚合值的默认展开深度和输出预算必须有界，不能因为一个命令无界读取整棵对象图。

### 4. 停点卡片与 frame 选择统一

现有停止处理已经会从 `stackTrace` 中寻找第一个带 `.mbt` 源码的 frame。T-06 不应在
`stopped`、`backtrace`、`frame` 和变量查询中保留多套互相独立的选帧规则，而应由同一个
stack/frame 模型生成：

1. 真实停止位置；
2. 默认选中的用户 frame；
3. 是否发生 runtime → MoonBit 自动跳转；
4. 停点卡片使用的函数、源码位置和线程上下文；
5. 后续命令使用的稳定逻辑 frame 选择。

这样可以避免停点卡片显示 frame A，而 `p`、`list` 或 `locals` 实际查询 frame B。

## 领域模型与状态所有权

debugger core 建议增加或完善以下领域概念，具体类型名在实施阶段确定：

- `StackSnapshot`：某个逻辑线程在一个 stop epoch 中的调用栈视图、分页完成状态和当前选择；
- `StackFrameSnapshot`：稳定 frame 序号、源码函数名、源码位置、frame 分类和可用性；
- `FrameKind`：至少区分 MoonBit 用户 frame、MoonBit artificial/runtime frame、native frame
  和 unknown frame；
- `FrameSelection`：session 保存的逻辑选择，不直接保存 DAP frameId；
- `LocalVariableSnapshot` 或等价摘要：`locals` 的结构化结果。

依赖边界继续遵守 T-05：

- `DebugSession` 持有当前线程/frame 的逻辑选择，并验证命令是否允许在当前状态执行；
- `LldbDapBackend` 保存逻辑 frame 与当前 stop epoch 内 DAP frameId 的映射、分页结果、scope
  和 variables 缓存；
- `dap` package 只负责请求、响应、事件和 framing，不理解 MoonBit frame；
- `repl` 中每个新命令使用独立文件和独立 `ReplCommand` 实现，返回结构化
  `CommandResult`；
- renderer 负责 human 文本，core 同时保留未来 AI/DAP frontend 可消费的完整字段。

不得让 DAP frameId 成为跨 stop 或跨 execution 的用户 frame ID。即使 adapter 在两次停止
中返回相同整数，也必须视为两个不同生命周期的临时引用。

## lldb-dap 交互模型

本轮主要使用以下 DAP 能力：

1. `stopped` event 提供当前停止线程线索；缺失 threadId 时按现有策略查询 `threads`；
2. `stackTrace(threadId, startFrame, levels)` 分页获取 frame；
3. `scopes(frameId)` 获取当前选中 frame 的 Locals 等 scope；
4. `variables(variablesReference)` 获取该 scope 的直接变量，并复用现有变量物化能力；
5. frame 切换本身是 moondbg 的逻辑选择，不要求向 lldb-dap 发送“select frame”命令；只有
   随后的 `scopes`、变量查询或源码请求使用选中 frameId；
6. 同一个 stop epoch 内合并重复 stack/scopes/variables 请求；恢复执行时整体清空；
7. adapter 返回缺页、重复 frame、非法 frameId、源码位置缺失或中途终止时，转换为稳定的
   backend/领域错误，不把原始协议对象交给 REPL。

当前 `print` 已经接受 `ThreadSelection` 和 `FrameSelection`。T-06 应把其中仍然只是
“默认 frame”占位的部分接成真实选择，而不是在每条观察命令里额外保存 frameId。

## 编译器与构建系统协作

T-06 同时把真实调用栈作为编译器 debug info 的验收面。编译器通过标准 DWARF 提供以下
事实：

- 源码层函数名与独立的 linkage/mangled name；
- 函数声明位置和每个 frame 的 call-site/source location；
- 形式参数、局部变量、lexical block 与 shadowing；
- 变量 location list 和 optimized-out/unavailable 状态；
- artificial/generated frame、prologue/epilogue 和可停语句边界；
- 泛型单态化 frame 与原始 MoonBit 函数身份之间的关系；
- 后续支持优化内联时所需的 inline call-site 信息。

建议的名称契约是：`DW_AT_name` 表达 MoonBit 源码身份，`DW_AT_linkage_name` 表达 native
链接符号。若真实 lldb-dap 只能返回 mangled name、错误源码位置或错误作用域，应先定位
DWARF 生成缺口并修改 `ideas5`，而不是让 renderer 解析 LLDB 文本。精确 demangle 可以作为
兼容信息，但不能取代编译器提供 source identity。

Moon 构建系统继续保证 `moon debug <pkg>` 使用完整 debug info。如果 runtime/artificial
分类、源码路径映射或入口逻辑身份无法可靠放入标准 DWARF，可以按 T-01 规划增加版本化
artifact manifest；manifest 只保存构建事实，不保存 DAP 临时 ID 或运行时状态。

本轮不预设必须关闭全部优化。先使用跨包、泛型、递归和局部变量 shadowing 样例检查当前
行为，再决定 debug profile 是否需要调整优化级别或要求编译器生成更完整的 location list。

## 对 AI 与未来 DAP frontend 的要求

调用栈和 locals 不能只有拼接好的终端字符串。结构化结果至少应保留：

- stop/thread/frame 的逻辑身份；
- frame 顺序、当前选择、分类和是否被默认视图隐藏；
- 源码函数名、linkage name（若需要）、源码位置和可用性；
- 调用栈是否已经完整加载；
- locals 的名称、类型、可用状态和值摘要；
- 用户操作失败的结构化原因。

human renderer 可以生成适合终端浏览的紧凑文本；AI frontend 可以直接消费结构化对象，
不需要解析 `#0`、路径或缩进。未来对外 DAP frontend 也可以把逻辑选择映射为自己的 frame
响应，而不暴露内部 lldb-dap 的临时 ID。

## 非目标

以下内容不纳入 T-06 的核心实施范围：

- 任意 MoonBit 表达式求值；
- `.0` enum payload 路径；
- 条件断点、watchpoint 和断点生命周期管理；
- async task/协程的逻辑栈重建；
- reverse debugging；
- 完整 inline frame 体验；
- panic 专用停点和结构化 panic payload；
- 全局变量、寄存器和原始内存浏览命令。

线程列表和线程切换已经是 T-01 的第一版目标，但是否与本主题同时实施仍作为下面的里程碑
范围问题讨论；无论如何，T-06 的领域和 backend 接口不得假设程序永远只有一个线程。

## 验收闭环

建议新增一个专门的 native DWARF fixture，至少包含：

- `main → 跨包函数 → 普通函数` 的三层调用链；
- 递归调用，用于验证重复函数 frame 和稳定深度；
- 泛型函数的单态化 frame；
- 参数、普通局部变量、同名 shadowed local 和 optimized-out/unavailable 变量；
- 一个明确的 native/runtime frame 边界；
- 每个 frame 中可区分的源码行和局部值。

真实闭环至少验证：

```text
bt
bt --all
frame <index>
up
down
locals
p <caller-local>
list
continue
```

并证明：frame 切换后 `locals`、`p` 和 `list` 同时切换；重复查询命中 stop-epoch cache；恢复
执行后旧选择和 DAP 引用全部失效；runtime frame 的隐藏不会丢失 `--all` 视图；编译器缺陷
有独立最小复现和归属结论。

测试继续采用 MoonBit-first 分层：领域和命令行为使用纯 MoonBit/fake backend，DAP 分页、
请求顺序和缓存使用 scripted transport，REPL 使用 PTY，编译器 DWARF 与 `moon debug` 使用
显式 capability-gated toolchain acceptance。

## 待决策问题

### 1. T-06 是否同时实现 `threads` 与 `thread <id>`？

T-01 已确认第一版最终需要 all-stop 线程模型，但可以决定本里程碑的交付范围。建议 T-06
先实现“当前停止线程”的 stack/frame/locals，同时在领域模型和 backend API 中保留 thread
维度；`threads` 和显式线程切换随后单独实施。这样可以先验证 frame 与编译器 DWARF，不把
多线程选择、线程消失和每线程分页同时引入本轮。

### 2. 默认隐藏 runtime frame 时，frame 序号如何保持稳定？

建议 frame 序号始终使用当前线程物理调用栈的深度：真实顶帧为 `#0`，默认 `backtrace`
隐藏 runtime/native 项时允许序号出现间隔；`backtrace --all` 使用完全相同的序号补齐隐藏
项。`frame <index>` 因而没有两套含义，显式选择隐藏 frame 也可预测。`up`/`down` 在默认
模式下跳到相邻的可见 MoonBit frame，显式选择 native frame 后仍按同一可见性规则导航。

### 3. `locals` 默认采用紧凑摘要还是完整变量渲染？

建议默认采用紧凑摘要：标量显示值，Array/FixedArray 显示类型和长度，struct、enum 及其他
聚合值只显示类型或当前 constructor，不递归展开完整对象；用户通过 `p <path>` 查看详细
内容。这样 `locals` 的请求量和输出量与变量数量近似线性，不会因一个大型局部对象展开整棵
对象图。后续如确有需要，再独立讨论 `locals --verbose`，不在第一轮同时增加。

### 4. 切换 frame 后输出多少上下文？

建议 `frame <index>`、`up` 和 `down` 成功后立即输出一张简化 frame 卡片：frame 序号、
MoonBit 函数、源码位置和与当前 `list` 默认相同的源码窗口，但不重复 stop reason、线程列表
或 locals。这样用户切换后立刻知道位置，同时避免必须再输入一次 `list`。

在上述问题确认前暂不写任务划分；确认后再按可独立 review 的阶段追加到本文底部。
