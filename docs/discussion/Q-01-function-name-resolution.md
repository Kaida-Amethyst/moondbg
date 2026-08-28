# Q-01. 函数名解析与泛型函数断点 已解决

> 最后更新日期：2026-08-28
> 仓库：moondbg
> 记录者：Codex-GPT-5

## 问题描述

moondbg 当前只支持源码行断点。下一轮希望支持 `b <函数名>`，例如 `b main` 和 `b foo`。
MoonBit native 后端输出的函数使用 name mangling，泛型函数还可能产生多个带不同类型参数的
单态化符号。因此需要确定如何从用户输入的源码函数名找到二进制中的物理函数，以及是否
需要编译器预先提供全部实例的函数索引。

本问题讨论函数符号的解析、构建系统提供的包上下文和函数断点的建立。方法、trait 实现
方法、局部函数和闭包的输入语法不在本轮范围内。

## 问题引发模型

### 最小复现例子

假设包中存在泛型函数：

```moonbit
fn foo[T](value : T) -> T {
  value
}
```

程序实际使用了 `foo[Int]` 和 `foo[String]` 后，native 二进制中存在的是两个带类型参数后缀
的单态化物理符号，不一定存在一个名为 `foo` 或只有基础 mangled name 的可执行函数。因此
把 `b foo` 作为精确函数名交给 LLDB，无法表达“命中 `foo` 的全部单态化实例”。去掉泛型后，
精确 mangled name 可以直接对应一个普通顶层函数；问题由泛型实例后缀和多 location 语义
引发。

### 问题分析

MoonBit 的 mangling 规则可以把包路径和源码函数名编码成顶层函数的物理名称基础部分；泛型
实例在该基础部分之后追加类型参数编码。反向解析时，长度前缀和元素标记也允许恢复符号的
包、函数种类、源码名称及实例化类型信息。

LLDB 能通过 `breakpoint set --func-regex` 在目标的符号和调试信息中搜索匹配的函数，并让
一个 breakpoint 包含多个 location。因此 moondbg 不必事先枚举一个泛型函数究竟生成了哪些
单态化实例：它可以根据基础 mangled name 构造带合法后缀边界的正则，让 LLDB 从当前二进制
中找出全部实例。正则必须排除名字仅具有相同文本前缀的其他函数，以及嵌套函数、闭包等不应
由 `b foo` 隐式命中的符号。

标准 DAP `setFunctionBreakpoints` 表达的是函数名断点，当前 lldb-dap 的该请求走精确名字
查找，不能直接携带上述正则。moondbg 需要继续通过 lldb-dap，但使用其 LLDB 命令通道执行
正则断点命令。实施前需要用一个最小协议测试确认：由命令通道创建断点后，lldb-dap 是否
发送结构化 breakpoint event，以及如何取得并保存 LLDB breakpoint ID。这个验证影响断点
状态同步的实现方式，但不改变函数发现方案。

函数符号解析不替代 DWARF。源码文件、行号、变量和栈帧位置仍以 DWARF 为事实来源；
mangle/demangle 子包只负责 MoonBit 源码身份与物理符号身份之间的转换，以及为函数断点
生成匹配条件。

## 关联问题

无。

## 建议的解决方案

### A1. 独立 mangle/demangle 子包与 LLDB 正则函数断点 【已采纳】

#### 方案描述

新增一个不依赖 REPL 和 lldb-dap 的 MoonBit 子包，集中实现当前版本 MoonBit name mangling
规则。子包至少承担以下职责：

1. 表达顶层函数等 MoonBit 符号的结构化身份；
2. 编码标识符、包路径和顶层函数的 mangled name 基础部分；
3. 对 `_M0...` 顶层函数物理符号进行 demangle，并以明确错误拒绝未知版本或非法编码；
4. 提供顶层函数 family 的 mangled base 和合法后缀边界信息，由 lldb-dap backend 生成
   LLDB 函数正则；
5. 用普通函数、转义标识符、泛型实例和非法符号的 MoonBit 单元测试固定规则。

`CommandBreak` 继续拥有 `b` 命令的用户语法，但不自行拼接 `_M0...` 字符串。它把函数名
解析为结构化查询，再调用应用层的函数断点操作；lldb-dap backend 使用上述子包得到匹配
条件，通过 LLDB 命令通道建立一个可能包含多个 location 的断点。`main` 对应 native 入口
符号的特殊规则也由该子包或应用层符号解析策略集中处理，不散落在 REPL 中。

第一阶段实现顶层函数。`b foo` 固定解释为当前调试目标包中的 `foo`；跨包函数使用
`b @pkg.foo`，其中 `pkg` 是当前包在 `moon.pkg` 中可见的导入别名。该别名不能直接参与
mangling，必须先解析为被导入包的规范全名。本轮不能靠模糊文本前缀静默命中不相关包或
其他函数种类。

`name_mangle` 不读取 `moon.pkg`，也不依赖 moon。moon 构建系统已经掌握当前包的规范全名
以及解析后的 import alias，应在调用 moondbg 时传递这些包上下文。这样可以覆盖默认别名、
别名冲突处理和构建图解析结果，避免 moondbg 重复实现构建系统。第一版通过
`--current-package` 和可重复的 `--package-alias` 参数传递；元数据继续增长时再考虑独立的
调试 context 文件。

#### 优点

- 泛型实例由 LLDB 从真实二进制中发现，不要求编译器额外生成单态化函数清单；
- name mangling 规则与 REPL、session 和具体 DAP 请求解耦，可供断点、调用栈显示和后续
  符号诊断复用；
- 一个用户逻辑断点自然对应多个 LLDB location，符合 `b foo` 的预期；
- 结构化编解码和独立测试比在命令代码中拼接字符串更容易跟随 mangling 版本演进。

#### 缺点

- moondbg 需要跟踪编译器 name mangling 规范的版本变化；
- lldb-dap 的标准函数断点请求不能直接承载正则，需要维护一条 LLDB 专用命令路径；
- 命令创建断点后的 ID、事件和重复运行重放行为需要额外验证和封装；
- 跨包重名、方法、trait 实现方法、局部函数和闭包仍需要后续设计，不能由简单前缀匹配
  一并解决。

## 最终采用方案

A1. 独立 mangle/demangle 子包与 LLDB 正则函数断点

## 任务划分

Q-01 按 P1 至 P4 顺序实施。每一阶段完成检查和测试后单独提交，再进入下一阶段。P2 横跨
moondbg 与 moon 两个独立 Git 仓库，因此两个仓库分别产生一个标记为 P2 的提交。

### P1. 实现 `name_mangle` 子包

**状态：已完成**

**目标：** 建立不依赖 REPL、debugger core 和 lldb-dap 的 MoonBit v0 顶层函数符号模型。

**工作内容：**

1. 新建 `name_mangle` package，实现标识符转义、包路径编码和顶层函数 mangled base；
2. 同时实现限定于顶层函数的 demangle，解析规范包名、函数名和可选泛型实例后缀；不在
   本阶段扩展到方法、trait 实现、局部函数和闭包；
3. 明确区分完整物理符号和函数 family base，拒绝未知 mangling 版本、非法长度与非法转义；
4. 使用编译器规范及真实 native 符号建立 golden tests，覆盖普通名称、特殊字符、core
   package、泛型实例和错误输入；不能只依赖自身 mangle/demangle 往返测试；
5. `name_mangle` 不生成 LLDB 命令或正则，不读取项目配置。

**完成条件：** package 的公共接口和边界清晰；golden tests、`moon check`、`moon test`、
`moon info` 和格式化均通过。

**实施结果：** 新增独立 `name_mangle` package，对外提供
`mangle_top_level_function_base` 和 `demangle_top_level_function`。实现覆盖 MoonBit v0
标识符 UTF-8 字节转义、普通/core/builtin package 编码、顶层函数 family base、普通与
错误多态泛型后缀，以及 primitive、容器、tuple、函数和命名类型参数的解析；其他符号种类
和未知版本会被明确拒绝。公共解码结果保持为与 LLDB/DAP 无关的结构化值。

测试包含编译器输出和真实 native fixture 中的普通函数、builtin 泛型函数与 core error
polymorphic 函数 golden symbol，并覆盖转义、复合类型参数和非法输入；没有只使用自身往返
验证。最终 `moon info`、`moon fmt`、`moon check` 和 119 个 MoonBit 测试全部通过。

### P2. 从 moon 向 moondbg 传递包上下文

**状态：待实施**

**目标：** 让 moondbg 得到当前调试包的规范全名，并能把当前包可见的 import alias 解析为
依赖包规范全名。

**工作内容：**

1. 在 moon 已解析的 run selection 和 package dependency graph 中提取当前 `PackageFQN`；
2. 从当前 source target 的依赖边提取编译器实际使用的 `short_alias` 与依赖包 FQN，不让
   moondbg 自行读取 `moon.pkg`；
3. 扩展 moondbg CLI，接受 `--current-package` 和可重复的 `--package-alias`，并构造与
   lldb-dap 无关的 `DebugContext`；
4. 修改 `moon debug` 的委托命令传入上述参数，同时保留直接执行 moondbg 时对缺失上下文的
   明确诊断；
5. 增加 moon dry-run/委托测试和 moondbg CLI 测试，覆盖默认别名、显式别名、未知别名与
   参数错误。

**完成条件：** `moon debug --dry-run <pkg>` 可观察到准确的当前包和 alias 映射；真实委托
后 moondbg 得到相同上下文；两个仓库原有测试保持通过。

### P3. 实现非泛型函数名断点

**状态：待实施**

**目标：** 建立 `b foo` 和 `b @pkg.foo` 到精确 LLDB 函数断点的第一个闭环。

**工作内容：**

1. 扩展 `CommandBreak`，在保留 `file:line` 的同时解析当前包函数和带 import alias 的跨包
   顶层函数；
2. 在 application session 中增加结构化函数断点请求，不让 REPL 接触 mangled string 或
   DAP command；
3. 根据 `DebugContext` 解析规范包名，再调用 `name_mangle` 得到普通顶层函数的精确物理名；
4. lldb-dap backend 通过标准 `setFunctionBreakpoints` 建立精确名字断点，并映射为稳定的
   用户逻辑断点；
5. 单独验证并集中处理当前 executable package 的 `main` 与 native 入口 `moonbit_main`，
   不把入口 ABI 特例伪装成通用 mangling 规则；
6. 增加命令、session、fake adapter 和真实 native fixture 测试。

**完成条件：** 普通 `b foo`、跨包 `b @pkg.foo` 和 `b main` 能在真实 `moon debug` 链路中
停住；未知 alias、非法函数语法和不存在的函数得到稳定反馈；源码行断点不回归。

### P4. 实现泛型函数 family 断点

**状态：待实施**

**目标：** 让同一个 `b foo` 自动命中当前二进制中 `foo` 的普通本体或全部已生成泛型实例，
而不要求编译器提供单态化函数索引。

**工作内容：**

1. 根据 `name_mangle` 返回的 family base 构造带合法符号边界的 LLDB regex，排除相同文本
   前缀的其他函数、局部函数和闭包；
2. 通过 lldb-dap 的 LLDB 命令通道执行 `breakpoint set --func-regex`；
3. 用最小协议探针确认命令创建断点后的 breakpoint ID、结构化 event 和多 location 行为，
   再决定使用事件映射还是封装最小的命令结果解析；
4. 将多个 LLDB location 保持为一个用户逻辑断点，并纳入 session 重放和 execution 生命周期；
5. 扩展 native fixture，使同一泛型函数至少生成两种单态化实例，验证两处均可停住，同时
   验证不存在实例时的 unresolved 行为；
6. 完成 fake/真实链路测试和两个仓库的最终回归。

**完成条件：** 用户无需写类型参数即可用一个函数断点命中全部已链接实例；普通函数行为
保持不变；断点 ID、location、重放、停止与错误反馈稳定，所有规定检查通过。
