# Q-02. Stopped 状态动态新增断点 已解决

> 最后更新日期：2026-08-28
> 仓库：moondbg
> 记录者：Codex-GPT-5

## 问题描述

moondbg 已支持在 `run` 前配置源码行、普通函数和泛型函数 family 断点，但程序停住后不能
继续增加断点。例如先执行 `b main`、`run`，再执行 `b sum`，当前会报告在 `Stopped` 状态
不允许添加函数断点。

本问题讨论如何让用户在当前 execution 停住时动态新增断点并立即得到 verified/rejected
结果。删除断点、启停断点、条件断点、运行中断点以及并发修改不在本轮范围内。

## 问题引发模型

### 问题复现

在 `testdata/dwarf_probe` 中运行：

```text
moon debug main
(moondbg) b main
(moondbg) run
# 程序停在 main
(moondbg) b sum
```

实际结果为：

```text
Cannot set breakpoint: add function breakpoint is not allowed while the debugger is Stopped
```

如果把 `b sum` 移到 `run` 之前，断点可以 verified，并在 `continue` 后正常停在 `sum`。
这说明函数符号、DWARF 和优化级别不是问题来源，差异只在添加断点时 session 所处的状态。

### 问题分析

当前限制来自两层实现：

1. `DebugSession::add_source_breakpoint` 和 `add_function_breakpoint` 只接受 `Ready`；
2. lldb-dap backend 只在 `launch` 的配置阶段导入逻辑断点，依次完成
   `setBreakpoints`、`setFunctionBreakpoints` 或 LLDB function-family 命令，没有在当前
   stopped execution 上增量同步断点的接口。

因此只放宽 application state guard 并不能解决问题：新断点虽然会进入持久逻辑配置，却
不会安装到当前 execution，用户执行 `continue` 时仍然无法命中。正确闭环必须同时更新
持久 session 配置、当前 adapter 断点和 execution-scoped ID/location 映射。

REPL 命令执行本身已经是 async，且动态安装发生在用户提交命令之后、下一次提示符之前，
不需要 readline 支持编辑期间异步插入输出。lldb-dap 通常允许在 stopped target 上修改
断点，但源码断点、精确函数断点和 function family 使用不同协议路径，实施前仍需用当前
开发环境逐项验证替换语义、返回 ID 和事件行为。

## 关联问题

1. [Q-01. 函数名解析与泛型函数断点](Q-01-function-name-resolution.md)（依赖）：Q-02 复用
   Q-01 建立的逻辑函数断点、family regex、LLDB ID/location 解析和跨 execution 重放模型。

## 建议的解决方案

### A1. 持久逻辑配置与当前 execution 的异步动态同步 【已采纳】

#### 方案描述

把“接受一个用户逻辑断点”和“把它安装到某次 execution”继续保持为两个层次，并为 stopped
execution 增加显式的动态同步接口：

1. `DebugSession` 继续拥有稳定逻辑断点、用户编号和跨运行配置；
2. `DebugBackend` 增加异步动态添加源码断点和函数断点的能力，由具体 backend 维护当前
   execution 的 adapter ID/location；
3. `DebugSession::add_source_breakpoint` 与 `add_function_breakpoint` 改为 async：
   - `Ready` 时只保存配置并返回 pending，保持现有 `run` 前体验；
   - `Stopped` 时保存配置后立即调用 backend，在当前 execution 中安装，并直接返回本次
     verified/rejected snapshot；
   - 其他状态继续拒绝；本轮不引入 Running 状态下的并发断点修改；
4. backend 按协议语义分别处理：
   - 源码行断点重新发送该 source 的完整 `setBreakpoints` 集合；
   - 精确函数断点重新发送完整的 `setFunctionBreakpoints` 集合，并刷新受影响的映射；
   - MoonBit function family 只为新逻辑断点执行一次 LLDB regex 命令，避免重复创建已有
     family breakpoint；
5. 动态安装结果进入当前 `ExecutionBreakpointState`，稳定逻辑 ID 不变；下一次 `run` 仍从
   session 配置重放全部断点，不能依赖上一 execution 的 LLDB/DAP ID；
6. REPL 在命令边界同步展示结果。Stopped 状态下成功添加 `b sum` 时，应立即显示 verified，
   随后的 `continue` 可以直接命中。

#### 优点

- 保留现有 session/execution 所有权边界，不把 DAP 临时 ID 泄漏到 application 或 REPL；
- 同时满足“立即对当前进程生效”和“下一次运行自动重放”；
- 利用现有 async command、稳定逻辑断点和 family 解析基础设施，改动集中在明确接口上；
- 为后续删除、禁用、条件修改断点提供一致的动态配置入口。

#### 缺点

- 三类断点的 adapter 更新语义不同，不能用一次简单的 append 请求统一处理；
- `setBreakpoints` 和 `setFunctionBreakpoints` 的整组替换可能改变已有 adapter ID，必须更新
  整组 execution 映射；
- 动态同步期间若 adapter 退出，需要同时处理当前 stop 失效和持久配置是否保留的语义；
- fake adapter 与真实 lldb-dap 都需要覆盖 stopped 状态请求，测试面会有所增加。

## 最终采用方案

A1. 持久逻辑配置与当前 execution 的异步动态同步

## 任务划分

Q-02 建议按 P1 至 P4 顺序实施。P1 先固定本机 lldb-dap 的 stopped 状态协议行为，P2 和 P3
分别建立 backend 与 application/frontend 闭环，P4 完成真实验收。每一阶段完成检查和测试
后单独提交。

### P1. 验证 stopped 状态下的 lldb-dap 断点更新语义

**状态：已完成**

**目标：** 在修改架构前确认三类动态断点请求在当前开发版 lldb-dap 上的实际行为。

**工作内容：**

1. 启动 native fixture，在命中已有断点并进入 stopped 后发送源码 `setBreakpoints`；
2. 验证 stopped 状态下重新发送完整 `setFunctionBreakpoints` 是否保留全部精确函数断点，
   并记录已有断点 ID 是否变化；
3. 验证 stopped 状态下通过 `evaluate(context="repl")` 新建 function-family regex 断点，确认
   返回 ID/location、breakpoint event 和随后的 stopped event；
4. 验证零 location、重复请求和 adapter 拒绝路径；
5. 把观察结果固化为最小协议测试，不能只记录一次人工输出。

**完成条件：** 三类请求的替换/增量语义、ID 更新和错误行为明确，足以决定 backend 的同步
实现；测试不依赖用户手动操作。

**验证结果：** `tools/dynamic_breakpoint_probe.py` 已使用真实 lldb-dap 固化以下行为：

1. stopped 状态接受源码 `setBreakpoints` 和完整 `setFunctionBreakpoints`；整组重发时未删除的
   断点保留 adapter ID，新断点得到新 ID，成功后可能异步发送 `breakpoint/changed`；
2. function-family `evaluate` 每执行一次都会新建一个 LLDB breakpoint，重复相同 regex 会产生
   新 ID 和重复 locations，因此 backend 必须保证每个逻辑 family 只增量安装一次；
3. family 命令不发送 DAP `breakpoint` event，结果必须从命令文本解析；无匹配会得到带 ID 的
   `no locations (pending)`，应映射为 rejected；
4. DAP 参数错误以失败 response 返回；动态安装的精确函数断点在随后 `continue` 中可以直接
   通过该次 execution 的 adapter ID 命中。

探针同时验证源码完整集合、已有 ID 保留、两个泛型实例、重复 family、零 location、请求拒绝
和随后命中，所有断言通过。

### P2. 实现 backend 动态断点同步

**状态：待实施**

**目标：** 让当前 stopped execution 可以接收一个新的稳定逻辑断点，并维护正确的本次
adapter 映射。

**工作内容：**

1. 扩展 `DebugBackend` 与 `LldbDapBackend` 的异步动态断点接口；
2. 源码行断点按 source 重发完整集合，精确函数断点重发完整集合，更新所有受影响 snapshot；
3. function family 只安装新逻辑断点，并复用现有 LLDB command 结果解析；
4. 维护 imported stable breakpoint 与 execution outcome 的一致性，避免同一 family 被重复
   创建；
5. adapter rejection 返回语义化 rejected snapshot，transport/adapter failure 走现有
   execution 恢复边界；
6. 增加 scripted transport 白盒测试，覆盖 ID 变化、多 location、零 location 和请求失败。

**完成条件：** backend 在 stopped 状态动态添加三类断点后可以立即报告本次结果；已有断点
仍然有效，稳定 ID 与 adapter ID 不混用，下一 execution 不复用旧映射。

### P3. 接入 DebugSession、REPL 与持久配置语义

**状态：待实施**

**目标：** 建立用户输入 `b` 到当前 stopped execution 的完整应用层闭环。

**工作内容：**

1. 将两个 session 添加断点操作改为 async，并允许 `Ready`、`Stopped` 两种状态；
2. `Ready` 保持 pending 行为，`Stopped` 立即调用 backend 并返回 verified/rejected；
3. 无论当前 execution 的安装结果如何，稳定逻辑断点编号和跨运行配置按已确认语义维护；
4. REPL 对 stopped 动态添加展示即时结果，不先输出误导性的 pending；
5. 保持 Running、Exited、Failed 状态的拒绝行为，并确保 breakpoint 命令失败不会误改选中
   frame、stop epoch 或程序运行状态；
6. 更新 command、session、renderer 和 recording backend 测试。

**完成条件：** `b main`、`run`、`b sum` 会立即得到可理解的结果；成功时 `continue` 可以
命中新断点，已有 run 前断点和重启行为不回归。

### P4. 真实链路、重放与异常回归

**状态：待实施**

**目标：** 验证动态断点既作用于当前 execution，也作为持久配置正确作用于后续 execution。

**工作内容：**

1. 使用 `testdata/dwarf_probe` 验证 `b main`、`run`、`b sum`、`continue`；
2. 在 stopped 状态分别验证源码行断点、精确入口断点、跨包普通函数和含两个实例的泛型
   function family；
3. 验证不存在函数的 rejected 反馈、adapter failure 和动态同步后的状态恢复；
4. 再次 `run`，确认所有动态添加的逻辑断点以原用户编号重放且没有重复 LLDB locations；
5. 扩展 fake/PTY 与真实 lldb-dap 验收，检查请求顺序、ID/location、stop 位置和进程清理；
6. 执行 `moon info`、`moon fmt`、`moon check`、`moon test` 及规定的真实工具链测试。

**完成条件：** 当前 execution 与后续 execution 都能命中动态添加的断点；断点编号、location、
重放、错误反馈和资源清理稳定，项目规定检查全部通过。

## 已决策事项

### D1. 当前 execution 动态安装失败后保留逻辑断点 【已采纳】

用户输入已经通过语法、包上下文和符号解析，但 lldb-dap 在当前 execution 中返回零 location、
语义拒绝或 adapter failure 时，需要确定该断点是否继续属于持久 session 配置。

保留逻辑断点。当前 execution 的 snapshot 标记为 rejected；若 adapter failure
使当前 stop 失效，则按现有恢复逻辑结束该 execution。无论哪种情况，稳定用户编号和逻辑
配置都保留，下一次 `run` 使用新 execution 重新尝试。这样不会因为某次二进制未链接实例或
临时 adapter 故障静默丢失用户意图，也与现有跨运行断点重放模型一致。
