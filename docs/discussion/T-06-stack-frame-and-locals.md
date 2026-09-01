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
分类的 frame。frame 序号始终使用物理调用栈深度：真实顶帧为 `#0`；默认视图隐藏部分
frame 时保留序号间隔，不能重新编号成一个无法与 `frame <index>` 对应的连续列表。

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

`up` 选择调用者方向的下一个可见 MoonBit frame，`down` 选择被调用者方向的下一个可见
MoonBit frame。即使当前显式选择的是 native frame，也使用同一可见性规则跳转。到达边界时
保持当前选择，并返回稳定的用户错误，不发送无意义的 DAP 请求。

显式选择 runtime/native frame 是允许的，但该 frame 可能没有 MoonBit 源码或可用 locals；
这种情况应明确报告能力缺失，不能悄悄退回之前的 MoonBit frame。

### 3. `locals`

`locals` 获取当前 frame 的局部变量和参数，不包含 registers，也不默认混入全局变量。
默认采用紧凑摘要：标量显示值，Array/FixedArray 显示类型和长度，struct、enum 及其他
聚合值只显示类型或当前 constructor，不递归展开完整对象。每个变量先形成轻量领域摘要，
再由 renderer 统一输出；命令文件不直接处理 DAP JSON 或终端文本。需要查看完整内容时，
用户继续使用 `p <path>`；本轮不增加 `locals --verbose`。

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

线程列表和线程切换已经是 T-01 的第一版目标，但不纳入 T-06。本主题只操作 `stopped`
event 所确定的当前线程，同时在领域模型和 backend API 中保留 thread 维度，不得假设程序
永远只有一个线程。`threads` 与 `thread <id>` 后续单独实施。

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

## 已确认决策

### D1. T-06 不同时实现线程列表和线程切换

T-06 只实现当前停止线程的 stack/frame/locals。领域模型、缓存键和 backend 接口继续保留
thread 维度，为 T-01 已确认的后续 `threads` 与 `thread <id>` 留出边界，但本轮不增加这两条
命令，也不处理显式线程切换、线程消失或其他线程调用栈的预取。

### D2. frame 序号使用物理调用栈深度

真实顶帧固定为 `#0`。默认 `backtrace` 隐藏 runtime/native frame 时允许序号出现间隔；
`backtrace --all` 使用完全相同的序号补齐隐藏项。`frame <index>` 始终只有一种含义，并允许
显式选择隐藏 frame。`up`/`down` 按默认可见 MoonBit frame 导航。

### D3. `locals` 默认输出紧凑摘要

标量直接显示值；Array/FixedArray 显示类型和长度；struct、enum 及其他聚合值只显示类型或
当前 constructor，不递归展开完整对象。详细内容由 `p <path>` 承担。本轮不实现
`locals --verbose`。

### D4. frame 切换后立即显示简化 frame 卡片

`frame <index>`、`up` 和 `down` 成功后立即输出 frame 序号、MoonBit 函数、源码位置和与
当前 `list` 默认相同的源码窗口，不重复 stop reason、线程列表或 locals。

## 待决策问题

暂无。T-06 的产品范围和交互细节已经足以进入任务划分；实施中发现的编译器 DWARF 缺陷
按事实定位并修复，不把已有标准调试语义重新升级为产品决策。

## 任务划分

### P1. 建立真实 stack、frame 与 locals 协议基线

**目标：** 在修改正式领域接口之前，明确当前编译器 DWARF 和真实 lldb-dap 已经提供什么，
把缺失信息准确归属到 moondbg、编译器或构建系统。

**工作内容：**

1. 新增专用 native DWARF fixture，包含跨包三层调用、递归、泛型单态化、参数、shadowed
   local、不可用变量和可识别的 runtime/native 边界；
2. 使用真实 lldb-dap 记录 `stackTrace` 分页、frame name/source/line/column、`scopes` 和
   `variables` 的原始形状；
3. 检查源码函数名与 linkage name、frame 顺序、runtime/artificial 分类、参数和 lexical
   scope 是否足以支撑 T-06；
4. 对发现的编译器问题建立最小复现，区分 DWARF 生成错误、LLDB 映射限制与 moondbg 解析
   问题；
5. 本阶段不通过 renderer 文本修补缺失语义，也不提前实现 REPL 命令。

**完成条件：** 当前工具链的能力矩阵和缺口有可重复证据；每个缺口都有明确归属和后续处理
位置，fixture 可以稳定停在预期调用链中。

**Review 节点：** review 原始 DAP/DWARF 证据和问题归属，确认是否需要先修改 `ideas5` 或
`moon`，再建立正式领域模型。

### P2. 建立 stack/frame 领域模型与 session 选择状态

**目标：** 在 core 中表达调用栈、稳定物理深度、frame 分类和当前选择，不泄漏 DAP 临时 ID。

**工作内容：**

1. 增加 `StackSnapshot`、`StackFrameSnapshot`、`FrameKind` 及必要的结构化失败类型；
2. 让 frame 序号固定为物理调用栈深度，分别表达默认可见性和 `--all` 可见性；
3. 将 `FrameSelection` 从默认 frame 占位扩展为当前 stop epoch 内的逻辑选择；
4. `DebugSession` 在新 stop 时选择最近的 MoonBit 用户 frame，恢复运行或替换 execution 时
   清空选择；
5. 扩展 `DebugBackend` 的高层 stack/frame/locals 能力，不引入 frameId、DAP JSON 或
   variablesReference；
6. 使用纯 MoonBit fake backend 测试默认选择、物理序号间隔、选择失效、边界失败和状态
   限制。

**完成条件：** core 能在不依赖 lldb-dap 类型的条件下完整表达本主题的 stack/frame 语义；
`.mbti` 变化符合 T-05 的依赖方向；现有 stop、list 和 print 行为保持可用。

**Review 节点：** review 逻辑选择与 adapter ID 的隔离、stop epoch 生命周期和未来 thread
维度，确认没有把当前单线程里程碑固化为永久单线程 API。

### P3. 实现 lldb-dap 分页调用栈、选帧与缓存

**目标：** 将领域 stack/frame 语义映射到真实 DAP，并让停点卡片与所有观察命令使用同一
选帧结果。

**工作内容：**

1. 实现 `stackTrace(startFrame, levels)` 首批 20 帧预取和按需分页，保存 totalFrames/完成
   状态并拒绝重复、越界或协议不一致的页面；
2. 基于 DWARF/DAP 事实分类 MoonBit、runtime/artificial、native 和 unknown frame；
3. 建立物理 frame 序号与当前 stop epoch 内 frameId 的私有映射；
4. 统一 stopped 默认选帧、停点卡片、`list`、`print` 和后续 `locals` 的 frame 来源；
5. 实现 `frame`、`up`、`down` 所需的 backend/session 操作和可见 frame 导航；
6. 按 thread、stop epoch 和分页范围缓存 stack；恢复运行后清空 frame、scope 和 variable
   引用；
7. 使用 scripted DAP 测试分页、隐藏序号间隔、runtime 顶帧、显式 native frame、重复查询、
   迟到响应、adapter failure 和跨 epoch 失效。

**完成条件：** backend 可以稳定返回默认与 `--all` stack，选择任意物理 frame，并证明
`list`/`print` 使用同一 frame；默认路径不预取无关线程或 locals。

**Review 节点：** review DAP 请求数量、分页终止条件、frame 分类依据、缓存键和所有恢复
执行路径的失效逻辑。

### P4. 实现 `backtrace`、`frame`、`up` 与 `down` REPL 体验

**目标：** 开放完整的调用栈和栈帧导航命令，并按已确认规则显示默认视图、完整视图和简化
frame 卡片。

**工作内容：**

1. 分别新增 `backtrace.mbt`、`frame.mbt`、`up.mbt` 和 `down.mbt`，每条命令使用独立
   command struct 和统一 `ReplCommand` trait；
2. 注册 `backtrace` 及固定别名 `bt`，支持无参数默认视图和严格的 `--all`；
3. `frame` 只接受非负物理序号；`up`/`down` 不接受参数并按可见 MoonBit frame 跳转；
4. 成功切换后返回结构化简化 frame 卡片，包含函数、位置和当前默认源码窗口；
5. renderer 保留 frame 序号间隔、当前选择标记和 frame 分类，不让命令直接输出文本；
6. 为 Ready/Running/Exited、非法参数、frame 不存在、上下边界、无源码 frame 和 adapter
   failure 增加稳定反馈；
7. 增加 registry/help、parser、fake backend、presentation 和 PTY 测试。

**完成条件：** 用户可以通过 `bt`、`bt --all`、`frame N`、`up`、`down` 浏览当前线程调用栈；
切换后立即看到源码位置；现有命令和固定别名无回归。

**Review 节点：** review 命令文件边界、参数语法、默认/完整调用栈一致性、终端密度和切换
后的反馈是否足以继续操作。

### P5. 实现紧凑 `locals` 与所选 frame 变量闭环

**目标：** 列出当前 frame 的参数和局部变量摘要，并保证 `locals`、`p`、`list` 始终使用
同一个逻辑 frame。

**工作内容：**

1. 增加 backend 无关的 local summary 领域结果，表达名称、MoonBit 类型、可用状态、标量
   值、collection 长度和 enum constructor 等紧凑信息；
2. 只读取当前 frame 的 Locals/参数 scope，排除 Registers 和默认 Globals；
3. 复用当前 shadowed local 选择、MoonBit 类型转换、Array/FixedArray header 和 boxed enum
   descriptor 能力，但不递归物化 struct 或完整对象图；
4. 新增独立 `locals.mbt` 命令、presentation event 和紧凑 renderer；
5. frame 切换后验证 `locals`、`p <name-or-path>` 和 `list` 同时切换，切回原 frame 时复用
   stop-epoch cache；
6. 覆盖空 locals、不可用/optimized-out、同名 shadowing、聚合摘要、scope 缺失、native
   frame 和 adapter failure；
7. 保持 `p` 的详细打印能力和有界预算不变，不增加 `locals --verbose`。

**完成条件：** `locals` 输出稳定且有界；选择调用者后可以列出并打印调用者变量；不会加载
无关 frame、全局变量或聚合子树。

**Review 节点：** review 紧凑摘要是否泄漏 adapter 表示、请求量是否与 locals 数量近似
线性，以及 `locals` 与 `p` 的类型/可用性判断是否一致。

### P6. 修复编译器/构建缺口并完成真实验收

**目标：** 根据 P1 证据补齐源码级 stack/frame/locals 所需的工具链语义，并在真实
`moon debug` 链路完成最终验收。

**工作内容：**

1. 在 `ideas5` 修复已确认的函数 source name/linkage name、源码位置、参数/local、lexical
   scope、location list、artificial 标记或泛型身份问题；每项修复配最小回归；
2. 只有标准 DWARF 无法表达的静态构建事实才通过 `moon` 增加版本化 artifact manifest 或
   其他明确参数传给 moondbg；
3. 不用函数名前缀、构建目录、原始 LLDB 文本或静默 evaluator fallback 掩盖工具链缺口；
4. 使用专用 fixture 完成 `bt`、`bt --all`、frame 切换、上下导航、`locals`、调用者 `p`、
   调用者 `list`、继续执行和下一 stop 重置；
5. 验证跨包、递归、泛型、shadowing、unavailable 和 runtime/native 边界；
6. 更新测试文档和 capability-gated acceptance，执行各仓库规定的格式化、接口生成、检查、
   默认测试、scripted DAP、PTY 和真实工具链测试。

**完成条件：** T-06 的用户闭环在真实开发工具链稳定通过；编译器与构建系统改动各自有
回归；moondbg 不包含为当前样例硬编码的名称、路径或 frame 分类规则。

**Review 节点：** 最终 review 用户体验、DWARF 事实来源、跨仓库改动、结构化 frontend
复用能力和完整测试证据；通过后再标记 T-06 已完成。
