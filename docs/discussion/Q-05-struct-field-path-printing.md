# Q-05. Struct 字段路径查询的实现边界 已解决

> 最后更新日期：2026-08-29
> 仓库：moondbg
> 记录者：Codex-GPT-5

## 问题描述

moondbg 已经可以通过 `p p1` 和 `p line1` 递归打印 struct，但 `print` 命令目前仍只接受
简单变量名，不能执行 `p p1.x` 或 `p line1.start.x`。

T-01 已经确认 `print` 的产品语义是“变量路径查询”，而不是任意 MoonBit 表达式求值。
本问题不重新讨论这一用户边界，只比较 struct 字段路径的两种内部实现：在已完整物化的
`VariableSnapshot` 中查找字段，或者把结构化路径传入 debugger backend，利用
`variablesReference` 按需逐层读取。第一版只讨论由标识符和 `.` 组成的字段链，不包含
数组索引、运算符、函数调用、方法调用、可选链或 LLDB expression evaluator。

## 问题引发模型

### 问题复现

`testdata/dwarf_probe/point/main.mbt` 中的 `Point` 和 `Line` 已可递归打印：

```text
(moondbg) p p1
p1: Point = {
  x: Double = 1
  y: Double = 2
}
```

但字段访问会在 REPL 本地解析阶段被拒绝：

```text
(moondbg) p p1.x
print only accepts a simple variable name
```

这说明编译器 DWARF 和 lldb-dap 已提供字段数据，当前缺口主要位于命令语法、领域查询接口
以及 backend 的查询粒度，而不是 struct 布局或底层调试能力。

### 最小复现例子

```moonbit
struct Point {
  x : Double
  y : Double
}

struct Line {
  start : Point
  end : Point
}
```

第一层路径 `p1.x` 覆盖根变量到标量字段；多层路径 `line1.start.x` 覆盖经过中间 struct
继续读取下一层字段。若去掉 `.` 后的字段段，现有 `p <name>` 已经可以工作；因此问题的
最小新增能力是解析并执行一条有限的字段访问链。

### 问题分析

现有实现同时具备两种路线所需的基础：

1. 领域层 `VariableSnapshot` 已能表达叶子、递归 struct 和有界裁剪；
2. lldb-dap 层保留每个 `DapVariable` 的 `variablesReference`，并按 stop epoch 缓存
   scopes 和 variables；
3. struct 根变量与嵌套字段在 DAP 中都能通过 `variablesReference` 继续取得子项；
4. 当前递归 struct 物化设有最大深度 8 和总节点 256 的预算，避免递归引用和无界展开。

因此“先完整打印再查找”在功能上可行，但字段查询会受到展示快照预算的影响。另一条路线
可以只读取路径经过的节点，并在最终节点才执行现有的有界物化；其改动面更大，但查询语义
不会被“根 struct 应该展示多少内容”反向约束。

两种方案都不应把用户输入直接发送给 LLDB evaluator。`p1.x` 是 moondbg 定义的稳定
MoonBit 调试 DSL；字段解析、错误分类和结果名称应由 moondbg 自己控制。

## 关联问题

1. [Q-03. Struct 变量的递归打印](Q-03-struct-variable-printing.md)（前置能力：建立递归
   `VariableSnapshot`、struct 类型识别和 lldb-dap 子变量读取）
2. [Q-04. FixedArray 值的有界打印](Q-04-fixed-array-printing.md)（后续扩展关系：字段路径
   模型可以继续扩展出 `arr[i]` 一类索引步骤，但索引不属于本问题范围）

## 建议的解决方案

### A1. 在完整 VariableSnapshot 中遍历字段 【不建议作为正式实现】

#### 方案描述

REPL 把输入拆成根变量名和字段数组，例如：

```text
line1.start.x
  root   = line1
  fields = [start, x]
```

命令仍调用现有 `DebugSession::find_variable("line1")`。backend 按当前行为递归物化整个
`line1`，得到包含 `start`、`end` 及其所有已展开字段的 `VariableSnapshot`。REPL 或领域层
随后在快照中依次寻找 `start` 和 `x`，最后把找到的子快照重命名为完整路径
`line1.start.x` 并交给 renderer。

字段遍历必须区分三种失败：根变量不存在、中间值不是 struct、struct 中不存在指定字段。
如果某层快照标记为 truncated，则不能把“没有出现在已物化 children 中”直接解释为字段
不存在；至少需要报告该路径未包含在当前有界快照中。

目标输出为：

```text
(moondbg) p line1.start.x
line1.start.x: Double = 1
```

#### 优点

- 对现有 `DebugBackend::find_variable` 和 lldb-dap 查询逻辑改动最小；
- 可直接复用已经实现的递归 struct 快照和 children API；
- parser、快照遍历和 renderer 测试即可形成快速原型。

#### 缺点

- 查询一个叶子字段也会先展开根变量的所有兄弟字段，产生无关 DAP 请求和领域对象；
- 字段是否可访问会受到展示用最大深度和总节点预算影响，可能出现字段实际存在但无法从
  truncated 快照中判断的情况；
- backend 已经掌握精确的 DAP 子变量关系，却把字段查找退回到 presentation-oriented
  快照之后完成，错误语义容易混入 REPL；
- 将来增加 `arr[i]` 时，FixedArray 的有界预览可能根本不包含目标索引，无法复用同一模型
  进行可靠随机访问；
- 适合作为短期验证，但容易形成后续必须替换的查询路径。

### A2. 建立领域 VariablePath，并由 backend 按需逐层解析 【已采纳】

#### 方案描述

在 debugger core 中增加与 DAP 无关的变量路径模型。第一版只需要根标识符和字段步骤：

```text
VariablePath {
  root: "line1"
  steps: [Field("start"), Field("x")]
}
```

REPL 的 `print` parser 负责把用户输入解析为该模型。第一版接受一个或多个合法 MoonBit
标识符，以 `.` 连接；拒绝空段、连续点、前后点、空白、`[]`、括号、运算符和调用。路径
模型保留结构化的 root 与 steps，同时能够生成稳定的完整显示文本
`line1.start.x`。

`DebugBackend` 的变量查询接口从简单 `name` 提升为 `VariablePath`。这不是把 DAP 细节放入
core：路径表达的是用户要求的调试语义，`variablesReference`、JSON 和 adapter 临时 ID
仍只存在于 `lldb_dap` package。fake backend、未来 AI frontend 和未来对外 DAP frontend
都可以直接消费同一领域请求。

lldb-dap backend 按以下顺序解析：

1. 在当前 frame 的相关 scopes 中查找 root，继续沿用 `name`/`evaluateName` 匹配、同名
   活跃变量选择和 stop-epoch cache；
2. 对每个 `Field(name)`，确认当前节点是允许字段访问的 MoonBit struct，而不是仅凭非零
   `variablesReference` 把 FixedArray、enum 或其他 adapter aggregate 当作 struct；
3. 使用当前节点的 `variablesReference` 加载一层 children，在其中按字段名选择下一节点；
4. 中间节点只用于导航，不递归物化其无关兄弟；到达最终节点后才调用现有有界
   materialization。最终节点如果仍是 struct，可以正常递归打印其内容；如果是 FixedArray，
   可以复用现有有界数组预览；
5. 将最终快照的顶层名称规范化为完整用户路径，输出 `line1.start.x: Double = 1`，而不是
   只输出字段名 `x` 或 LLDB 的展示名称；
6. 所有 `variablesReference` 与逐层查询结果继续受当前 stop epoch 约束；程序恢复运行后
   整体失效。

变量查询结果应从笼统的 found/not-found 扩展出足够稳定的领域失败原因，至少区分：

- 根变量不存在；
- 某个字段不存在，并指出已经成功解析到的 owner 路径；
- 对非 struct 值继续访问字段；
- 变量或中间节点在当前机器位置不可用；
- adapter/协议失败。

建议的用户反馈示例：

```text
Variable 'missing' was not found in the current frame.
Field 'z' was not found in 'p1'.
Cannot access field 'x' because 'value' is not a struct.
Variable 'line1.start' is unavailable at the current location.
```

若查询结果本身仍是 struct：

```text
(moondbg) p line1.start
line1.start: Point = {
  x: Double = 1
  y: Double = 2
}
```

本方案第一版只建立 `Field`。但路径模型可以在后续独立问题中增加 `Index(Int)`，让
`arr[99]` 直接访问目标元素，而不依赖 `p arr` 的 16 个预览元素是否包含该索引。

#### 优点

- 查询成本与路径长度相关，不会为 `line1.start.x` 展开 `line1.end` 等无关字段；
- 字段可达性不受最终展示快照的深度和节点预算影响，展示策略与查询语义保持分离；
- core 持有稳定的变量访问语义，DAP 临时 ID 继续封装在 adapter 内，符合现有 package
  依赖方向；
- 可以返回精确的字段不存在、类型不支持和当前位置不可用错误，REPL、AI 与未来 DAP
  frontend 无需解析 LLDB 文本；
- 为以后增加 `arr[i]` 建立可扩展边界，而不要求现在实现索引或完整表达式 AST。

#### 缺点

- 需要调整 `DebugBackend`、`DebugSession`、fake backend 和相关测试的变量查询接口；
- lldb-dap 需要增加路径导航逻辑，并明确中间节点的 struct/enum/container 类型边界；
- 需要为路径 parser、逐层 DAP 请求、cache、错误分类和最终快照命名增加测试，改动面明显
  大于 A1；
- 路径模型要控制在当前需求内，避免提前膨胀成不完整的 MoonBit 表达式 AST。

## 最终采用方案

A2. 建立领域 VariablePath，并由 backend 按需逐层解析

## 任务划分

Q-05 按 P1 至 P4 顺序实施。每个阶段都保持项目可构建、可测试；P1 只迁移领域契约并保持
现有简单变量查询，P2 先在 backend 内完成路径能力，P3 再开放用户语法，P4 使用真实
MoonBit DWARF 完成验收。

### P1. 建立 VariablePath 领域契约并迁移 backend port

**目标：** 让 debugger core 能结构化表达根变量与字段步骤，同时不泄漏 DAP 临时状态，
并在 API 迁移后保持现有 `p <name>` 行为不变。

**工作内容：**

1. 在 core 变量领域模型中增加 `VariablePath` 与第一版 `Field(String)` 路径步骤，提供
   root、steps 和稳定完整显示文本的只读接口；
2. 路径模型只表达已解析的调试语义，不保存 `variablesReference`、DAP JSON、frame ID 或
   LLDB 表达式文本，也不提前加入未实施的索引和运算节点；
3. 将 `DebugBackend`、`DebugSession` 的变量查询参数从简单 `String` 迁移为
   `VariablePath`，同步纯 MoonBit fake backend 和相关测试；
4. 扩展变量查询领域结果，使后续可以区分根变量不存在、字段不存在、非 struct 字段访问
   和当前位置不可用；adapter failure 继续沿用独立 backend error；
5. 本阶段 REPL parser 仍只接受简单变量名，但把它构造成无字段步骤的 `VariablePath`；
   lldb-dap 对无步骤路径继续执行现有根变量查询，用户输出不得变化；
6. 更新 `.mbti` 并检查 core 公共接口没有出现 DAP/LLDB 类型。

**完成条件：** `p answer`、`p p1` 和现有 FixedArray/struct 打印行为保持不变；所有 backend
实现和测试已迁移到结构化路径契约；项目可独立通过格式化、检查和测试。

### P2. 实现 lldb-dap 按路径逐层导航

**目标：** 在用户语法尚未开放前，让真实 backend 可以按 `VariablePath` 精确取得最终
字段，并且只展开路径经过的节点。

**工作内容：**

1. 将当前根变量查找整理为可复用步骤，继续处理相关 scope、`name`/`evaluateName`、同名
   活跃变量和不可用候选；
2. 对每个 `Field(name)` 验证当前节点属于可访问字段的 MoonBit struct，不能把仅仅具有
   `variablesReference` 的 FixedArray、enum 或其他 aggregate 当作 struct；
3. 使用当前节点的 `variablesReference` 加载一层 children 并选择字段；导航到下一节点时
   不请求无关兄弟字段自身的 `variablesReference`；
4. 到达最终节点后才调用现有有界 materialization。最终值是标量、struct 或 FixedArray
   时分别复用已有领域快照；顶层名称规范化为路径完整文本；
5. 将根不存在、字段不存在、非 struct、节点不可用转换为 P1 的领域结果，不解析或透传
   LLDB 错误文本，也不调用 DAP `evaluate`；
6. 路径导航和最终快照继续使用 stop-epoch cache；snapshot cache key 包含完整路径，恢复
   运行后 scopes、children 和结果整体失效；
7. 增加进程内 scripted DAP 白盒测试，覆盖 `p1.x`、`line1.start.x`、最终 struct、最终
   FixedArray、缺失字段、非 struct、中间节点不可用、重复查询缓存和新 stop epoch。

**完成条件：** 通过 core/session 直接提交路径时，backend 能得到正确的最终快照或精确
失败原因；查询 `line1.start.x` 不展开 `line1.end` 的子项；请求顺序、缓存和 epoch 行为
有确定测试，现有根变量查询无回归。

### P3. 开放 print 字段路径语法与用户反馈

**目标：** 让用户可以通过 `p p1.x` 和 `p line1.start.x` 使用 P2 能力，并获得稳定、
MoonBit 导向的结果与错误文本。

**工作内容：**

1. 将 `CommandPrint` 的私有参数改为 `VariablePath`，把 usage 更新为 `print <path>`，帮助
   文本明确第一版支持变量和 struct 字段路径；
2. parser 接受一个或多个以 `.` 连接的合法标识符，复用现有 ASCII、下划线、数字位置和
   Unicode 标识符边界；拒绝空段、前后点、连续点、点两侧空白、`[]`、括号、调用和
   运算符；
3. 命令把领域查询结果转换为结构化 presentation event；human renderer 分别显示根变量
   不存在、字段不存在、非 struct 和当前位置不可用，不在命令中直接输出文本；
4. 成功结果使用完整路径作为顶层名称，例如 `line1.start.x: Double = 1`；查询结果仍是
   struct 时保留现有递归缩进，查询结果是 FixedArray 时保留现有有界预览；
5. 增加 parser、registry/help、command/fake backend 和 renderer 测试，覆盖简单根变量、
   一层字段、多层字段、Unicode 字段、所有拒绝语法及各类领域失败；
6. 保持 `p` 固定别名、当前线程/frame 选择、debuggee output 顺序和 adapter failure
   恢复行为不变。

**完成条件：** 用户可执行 `p p1.x`、`p line1.start.x` 和 `p line1.start`；成功输出及
四类失败反馈稳定；非法表达式在 REPL 本地拒绝且不产生 DAP 请求；现有 `p name` 完全兼容。

### P4. 真实工具链验收与架构封口

**目标：** 在真实 `moon debug`、编译器 DWARF 和 lldb-dap 链路上确认字段路径查询，并
核对实现没有退化为完整根快照遍历或 LLDB evaluator。

**工作内容：**

1. 使用 `testdata/dwarf_probe/point` 验证 `b distance` 后的 `p p1.x`、`p p1.y`，以及
   `b is_parallel` 后的 `p line1.start.x`、`p line1.end.y` 和 `p line1.start`；
2. 在真实会话中验证缺失字段、对标量继续取字段和变量不可用反馈，不泄漏
   `variablesReference`、原始 DAP JSON 或 LLDB 错误文本；
3. 在同一 stop epoch 重复查询路径并恢复运行后重新查询，验证缓存复用和跨 epoch 失效；
4. 增加或更新 MoonBit acceptance 与保留的 Python real E2E，使关键字段路径闭环可自动
   回归，并确认没有加载 `moonbit.py`；
5. 审计 core、lldb_dap 和 repl 的依赖方向，确认路径解析属于 frontend、查询语义属于
   core、临时 reference 和逐层协议请求属于 adapter；
6. 执行开发工具链检查、`moon info && moon fmt`、`moon check`、`moon test`、fake/PTY 和
   真实 lldb-dap 验收，检查 `.mbti` 与工作区差异。

**完成条件：** 所有目标路径在真实 MoonBit 程序中得到正确结果；非法路径和运行时不可用
状态具有稳定反馈；查询成本按路径逐层增长，不依赖根 struct 的展示预算；格式、接口、
默认测试和真实调试闭环全部通过。
