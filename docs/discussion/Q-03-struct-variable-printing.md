# Q-03. Struct 变量的递归打印 待讨论

> 最后更新日期：2026-08-28
> 仓库：moondbg
> 记录者：Codex-GPT-5

## 问题描述

moondbg 目前的 `print` 只展示根变量的 name、type 和 LLDB value 摘要。对
MoonBit struct 执行 `p p1` 时，用户只能看到类型和对象地址，看不到字段。

本问题讨论第一版 struct 打印的领域模型、`lldb-dap` 子变量读取、递归
边界、REPL 渲染与验收方式。本轮只支持 struct 及嵌套 struct；`FixedArray`、
`Array`、tuple、enum 和任意 MoonBit 表达式求值不在范围内。

## 问题引发模型

### 问题复现

`testdata/dwarf_probe/point/main.mbt` 定义了包含 `Double` 字段的 `Point`，以及
嵌套两个 `Point` 的 `Line`。使用开发工具链运行：

```text
moon debug point
(moondbg) b distance
(moondbg) run
(moondbg) p p1
```

当前输出为：

```text
p1: Kaida-Amethyst/moondbg-dwarf-probe/point/Point & = 0x0000054a0a020068
```

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

`Point` 需要展开一层字段；`Line` 需要经过 `start`/`end` 再展开到 `x`/`y`，
因而同时覆盖了叶子值、struct 和嵌套 struct 三种最小情况。

### 问题分析

真实 LLDB 和 `lldb-dap` 探测已确认现有编译器 DWARF 足以完成该功能：

1. `p1` 在 DAP 中带有非零 `variablesReference`，子项为 `x = 1` 和 `y = 2`；
2. `line1` 的子项为 `start` 和 `end`，两者各自带有可继续展开的
   `variablesReference`，下一层是 `Point.x` 和 `Point.y`；
3. 因此本轮暂不需要修改编译器。

信息丢失发生在 moondbg 内部：`lldb_dap/variable.mbt` 的 `DapVariable` 已解析
`variablesReference`，但 `DapVariable::snapshot` 转换到领域层 `VariableSnapshot`
时只保留 name、value 和 type。现有 `StopVariableCache` 已可以按 stop epoch 和
reference 缓存子变量，因而可在不泄漏 DAP 临时引用的前提下建立递归值模型。

## 关联问题

无。

## 建议的解决方案

### A1. 有界的 struct 变量树与 MoonBit 导向渲染 【建议采纳】

#### 方案描述

把“DAP 中可展开的临时变量”和“可交给 REPL、AI 与未来对外 DAP 的调试值”
继续分层，由 backend 在当前 stop epoch 内将 struct 物化为有界的领域变量树：

1. 扩展 `VariableSnapshot`，用领域状态表示叶子、已展开子项和因预算裁剪的
   子项；不在公共模型中保存 `variablesReference`；
2. `lldb_dap` 在找到根变量后，仅对按当前 MoonBit DWARF 类型表示识别为
   struct 的值请求子项，递归复用 `StopVariableCache`。不把“非零
   `variablesReference`”直接等同于 struct，以免提前展开其他容器；
3. 递归读取使用最大深度和总节点预算，建议初始值为 8 层和 256 个节点，
   防止递归 struct、环和指数级展开；达到边界时在领域值中记录裁剪；
4. REPL renderer 递归渲染字段，使用 MoonBit 结构化形式和稳定缩进。struct
   成功展开时默认不显示 LLDB 地址，但仍在快照中保留原始 value 摘要；
5. 标量的现有输出和错误语义保持不变。`FixedArray`、`Array` 等本轮未支持
   类型继续显示当前摘要，不因递归树基础设施而被自动展开。

目标输出示例：

```text
p1: Point = {
  x: Double = 1
  y: Double = 2
}
```

```text
line1: Line = {
  start: Point = {
    x: Double = 1
    y: Double = 2
  }
  end: Point = {
    x: Double = 4
    y: Double = 6
  }
}
```

#### 优点

- 直接复用现有 DWARF、DAP `variables` 请求和 stop-epoch 缓存，不需要先改
  编译器；
- 公共值模型不依赖 LLDB/DAP 临时 ID，REPL、AI 和未来对外 DAP 可复用同一
  结构；
- 递归和裁剪语义一次建立，后续支持其他组合值时可复用；
- 仅开启 struct 展开，不提前锁定数组长度、分页和元素显示策略。

#### 缺点

- `VariableSnapshot` 从平面快照变为递归模型，backend fake、REPL 渲染和现有测试
  都需要调整；
- 只依赖 DAP 的 `variablesReference` 无法区分 struct 与其他可展开容器，
  backend 需要明确维护 MoonBit DWARF struct 类型识别边界；
- 递归展开会增加 DAP 往返，即使有缓存也需要预算和完整的截断测试。

## 最终采用方案

待定

## 任务划分

Q-03 建议按 P1 至 P4 顺序实施。P1 先固定协议事实和领域契约，P2 实现
backend 物化，P3 完成用户可见输出，P4 用真实工具链收口。

### P1. 固化 struct DAP 行为与递归变量模型

**目标：** 在功能实现前把真实 `Point`/`Line` 协议形状和不泄漏 adapter ID 的
领域模型固定下来。

**工作内容：**

1. 将 `Point -> x/y` 与 `Line -> start/end -> x/y` 的真实 `lldb-dap` 响应固化为
   最小协议探针或脚本化测试；
2. 为 `VariableSnapshot` 定义叶子、已展开子项和裁剪状态，并提供只读领域
   API；
3. 为递归模型增加单元测试，确认空 struct、单层 struct、嵌套 struct 和
   裁剪状态的结构化结果；
4. 保持 `variablesReference` 只存在于 `lldb_dap` 内部。

**完成条件：** 真实协议行为可重复验证，领域值可表达目标输出和裁剪，公开
接口不包含 DAP 临时引用。

### P2. 实现 lldb-dap struct 物化

**目标：** 在当前 stop epoch 内将根 struct 转换为有界的递归 `VariableSnapshot`。

**工作内容：**

1. 在 `lldb_dap/variable.mbt` 中保留并使用私有 `variablesReference`，递归请求
   struct 字段；
2. 实现私有的 struct 类型识别边界，本轮不展开其他类型；
3. 复用 `StopVariableCache`，并在恢复运行后继续使旧子项和变量引用失效；
4. 实现深度、总节点和已访问 reference 保护，达到边界时生成裁剪状态；
5. 增加 scripted transport 白盒测试，覆盖请求顺序、嵌套字段、缓存复用、裁剪
   和 stop epoch 失效。

**完成条件：** backend 查询 `Point` 和 `Line` 时返回完整的有界变量树；
查询标量和未支持容器的行为不变，恢复运行后不复用旧 reference。

### P3. 实现 REPL struct 递归渲染

**目标：** 让 `p p1` 和 `p line1` 产生稳定、可读的 MoonBit 结构化文本。

**工作内容：**

1. 把 `render_variable` 改为递归渲染，区分叶子、struct 和裁剪子项；
2. 对 struct 类型名使用 MoonBit 导向的显示，隐藏正常展开对象的原始地址；
3. 用快照测试覆盖 `Point`、`Line`、空 struct、裁剪提示和无类型字段；
4. 保留普通数值和未支持容器现有的单行输出。

**完成条件：** REPL 输出与 A1 示例的层次和语义一致，嵌套缩进稳定，
达到预算时明确显示裁剪，现有标量打印快照不回归。

### P4. 完成真实工具链验收

**目标：** 确认 struct 打印在真实 `moon debug` 和 lldb-dap 链路上可用，并且不破坏
现有变量和 execution 生命周期。

**工作内容：**

1. 使用 `testdata/dwarf_probe/point` 验证 `b distance` / `p p1` 和
   `b is_parallel` / `p line1`；
2. 在同一 stop epoch 重复打印变量，验证子项缓存没有产生重复 DAP 请求；
3. 恢复运行并再次停止，验证旧变量树不导致 reference 跨 epoch 复用；
4. 增加 fake/PTY 与真实 lldb-dap 端到端验收，并执行项目规定的格式、检查、
   测试和接口生成命令。

**完成条件：** `Point` 和嵌套 `Line` 可递归打印，标量和未支持容器保持
现有行为，stop epoch、缓存、adapter 进程和真实工具链回归全部通过。
