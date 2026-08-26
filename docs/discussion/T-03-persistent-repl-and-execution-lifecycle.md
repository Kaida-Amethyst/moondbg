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
- `run -- <args>` 对持久参数的更新语义，以及 cwd、环境变量后续接入的位置；
- 终止事件、迟到 response 和旧 epoch 消息不能污染下一次运行；
- 为重复运行、停止状态重启和异常恢复建立端到端测试闭环。

当前暂不把具体类型名称、公开 API、阶段划分和命令扩展写成已确认决策；这些内容在 review
主题边界后继续讨论。栈导航、线程切换、条件断点和复杂表达式求值不属于 T-03 的核心范围，
可在持久会话模型稳定后另开主题。

## 关联问题

暂无。当前先确认 T-03 的主题边界，尚未拆分具体 Q 文档。
