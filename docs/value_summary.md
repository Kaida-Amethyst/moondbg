# 有界嵌套摘要与变量读取错误

本轮仅修改 moondbg，不依赖新的编译器调试信息。继续使用 `set_moon_stable`
选中的工具链；优化表示的 Option 支持仍等待编译器契约落地，参见
[option_view.md](option_view.md)。不能从已丢失的类型信息推测 Some/None。

## 自动摘要规则

REPL 的 enum 预览和 VS Code 的复合值预览复用 `lldb_dap/value_summary.mbt`。
例如，原来的 `Ok(Point)` 现在显示 `Ok(Point { x: 1, y: 2 })`。

- 最多展开 **2 层复合结构**：构造器占第 1 层，内部 Point 占第 2 层。
  更深的复合值保留类型和 `…`，例如 `Nested(Envelope { point: Point { … } })`。
- 每个复合值最多显示 **4 个直接成员**。
- 每条摘要合计最多访问 **16 个值**，包括根值；兄弟成员共用预算。
- 每条摘要最多 **160 个 Unicode 字符**，包括标点和省略标记。
  这里按 Unicode scalar value 计数，不按 UTF-8 字节、UTF-16 单元或终端列宽计数。
  字符预算用尽后显示 `…`，可能在字符串或括号中途结束。
- 遇到重复的 LLDB 变量引用停止自动递归；不同引用指向同一对象时仍受深度限制。
- String/Bytes 沿用已有的有界内存预览，嵌入摘要时再受整条摘要的字符预算限制。
- 数组不自动展开元素。嵌套时显示类型和长度，例如
  `Points(Array[Point] with length = 2)`；直接 `p arr` 仍沿用数组的已有展示策略。

预算会阻止进一步遍历和内存请求，不是先无限读取再截断字符串。
不过 LLDB 返回一层成员元数据时可能一次返回全部成员；这里不承诺限制该响应的字节数。

这些预算只约束**自动单行摘要**。REPL 直接打印 struct/tuple 的多行视图、
`locals` 的紧凑风格，以及现有字符串/数组范围查看方式保持不变。
显式 `.x`、`.0`、`[i]` 访问和 VS Code 点击展开不受摘要深度/成员数限制：
每次主动查看的值获得自己的新预览预算。DAP 保留完整的直接子成员数量，
不会因为摘要只显示 4 项而丢失第 5 项之后的展开入口。

摘要仅用于展示，不参与路径解析和条件比较，也不调用用户的 Debug trait。

## 错误分类

- 内存读取失败：`Memory read failed for '…': …`，保留读取失败原因；
  拒绝的 readMemory 请求、部分读取、长度不足和无效数据都不会变成空值。
- LLDB 明确报告变量不可用：`Variable '…' is unavailable: lldb-dap reported …`，
  保留 LLDB 的原因。`locals`/Variables 列表保留失败项，不因此隐藏其他变量。
- 当前 frame 未找到根变量：明确说明找不到，并说明无法区分“超出作用域”和
  “调试信息缺失”。没有证据时不替调试器断言原因。
- 不支持的布局、缺失的字段或越界访问仍报告各自的检查错误，不冒充内存读取失败。
- 嵌套摘要中一个成员读取失败，保留错误占位，并在预算允许时继续显示其他成员。
  取消操作和失效的暂停状态仍中断读取，不被伪装成普通值。

## 手工试用

在 moondbg 仓库根目录运行：

```sh
moondbg testdata/dwarf_probe/value_summaries
```

```text
(moondbg) b inspect_values
(moondbg) run
(moondbg) p item
item: View

  Item(Point { x: 1, y: 2 })
(moondbg) p nested
  Nested(Envelope { point: Point { … } })
(moondbg) p many
  Many(1, 2, 3, 4, …)
(moondbg) p nested.0.point.x
(moondbg) p many.5.x
(moondbg) p text
(moondbg) p text.0[0:4]
(moondbg) p points
(moondbg) p missing
```

其中 `many.5.x` 仍可读出 `6`，`text.0[0:4]` 读出两个 emoji
（String 范围使用 UTF-16 单元，沿用已有规则）。

VS Code 打开 `testdata/dwarf_probe/value_summaries/main.mbt`，在 `SUMMARY_READY`
标记处打断点后 F5；在 Variables 或 Watch 中查看 `item`、`nested`、`many`、`text`、
`points`。展开 `many` 可以看到全部 6 个载荷，再展开 `.5` 查看 Point 字段。

## 验证

```sh
source ~/.zshrc
set_moon_stable
moon check
moon test
moon build --target native -g .
MOONDBG_TOOLCHAIN_ACCEPTANCE=1 MOONDBG_OPTION_VIEW_ACCEPTANCE=0 \
  moon test acceptance --no-parallelize
```

测试覆盖深度、成员数、共享节点数、Unicode 字符预算、循环引用、数组不自动读元素、
读取失败类别、主动探查不受摘要限制，以及真实 LLDB 上 REPL/DAP 的一致性。
