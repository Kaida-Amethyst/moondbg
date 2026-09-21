# Option view：实验实现与编译器改动留痕

## 当前状态（2026-09-21）

编译器补丁尚待团队 review，契约可能变化。moondbg 保留已实现的 Option 解析、单元测试、
fixture 和真实验收代码，但不将完整 Option 观察能力作为当前 stable 工具链的保证。
本文记录的是这次实验的实际设计，不是要求编译器最终采用的固定接口。

日常开发恢复使用 `source ~/.zshrc` 后的 `set_moon_stable`，选择 `~/.moon`。
本机该目录当前实际版本为 `moon 0.1.20260911 (def8c9e)`、
`moonc v0.10.12+2583f1173-nightly (2026-09-11)`；“stable”是环境选择函数的名称，
不等于该目录中的编译器版本字符串一定是正式发行版。不修改工具链软链接或 shell 配置。

编译器实验位于 `~/Devlopment/ideas` 的 `ziyue/debug_option` 分支。记录时 HEAD 为
`fe369c5555da91553172b5c967c9f0cf0097a7db`，Option 补丁仍在工作区，**该 SHA 不包含补丁**。
本轮切回 stable 不撤销、不修改 ideas 的实现。编译器侧另有 `docs/option-debug-info.md`。

## 要解决的问题与边界

原有布局降低会把源语言 Option 擦成存储类型。例如 `Int?` 降成 Int64，`Point?` 降成
可空指针；仅凭这些类型，调试器不能区分普通整数/指针与 Option，更不能恢复完整类型参数。
某些 Option 仍采用 boxed enum 表示，但其内部载荷也可能被擦除，例如 `Int??` 的内层。

本次方案只增加调试视图，不改变 Option 的 ABI、GC 布局或程序的 Some/None 运行逻辑。
moondbg 不解析用户源码来补类型、不根据裸数值猜 Option、不调用 Debug trait 或用户函数，
也不依赖 `moonbit.py`。首轮实际验收平台为 macOS arm64，调试构建为 `-g -O0`。

## ideas 改动位置

以下路径相对于编译器仓库根目录。

| 文件 | 本次改动及作用 |
| --- | --- |
| `lib/xml/mir/pass_layout.ml` | 新增 `debug_option_value`。machine debug 模式下，用保留源类型的 identity 包装被优化的 Some/None 表达式，避免在进入 Clam 前已丢失 Option 类型；非调试构建维持原逻辑。 |
| `lib/xml/clam_linear/clam_debug_types.ml`、`.mli`（新增） | 独立收集调试语义类型。`Storage` 保留原 Ltype，`Option` 保存源名称、版本标记、存储宽度及载荷类型；记录 binder、记录/构造器/tuple 字段和 FixedArray 元素的对应关系。 |
| `lib/xml/clam_linear/clam1.ml`、`.mli` | `prog` 增加可选的 `debug_source`；访客将它作为不展开的元数据携带，sexp 输出不展开它。 |
| `lib/xml/clam_linear/clamlinear_of_core.ml` | `transl_prog` 在 machine debug 模式下调用语义类型收集，并将结果传入 Clam1。实际 ABI 降低仍走现有类型系统。 |
| `lib/xml/machine/machine_of_clam_lower.ml` | 注册源类型信息和 Option 类型缓存；`debug_type_of_source` 生成 Option DWARF 视图。参数、循环参数、普通局部变量经 `debug_type_of_binder` 获取语义类型；字段和数组元素使用收集的源类型；MutLocal 中的可变 Option 沿用 payload 内存位置配方。递归类型的支持检查同步使用语义类型。 |
| `test/aarch64_test/option_debug.mbt`、`check_option_debug.cjs`（新增）及 `dune` | 编译真实样例，检查 DWARF 有效性、标记、成员偏移/类型、参数、局部变量、可变变量和嵌套载荷。 |
| `docs/option-debug-info.md`（新增） | 编译器侧的实验契约说明。 |

没有新增 Machine debug type 种类或修改底层 DWARF writer，而是复用现有结构、引用和基本
类型的调试信息表示。源类型与存储类型分开，字段偏移仍取真实 heap layout，不按源字段顺序猜测。

## moondbg 改动位置

以下路径相对于本仓库根目录。

| 文件 | 本次改动及作用 |
| --- | --- |
| `lldb_dap/option.mbt`（新增） | `is_option_type` 识别源 Option 类型；`optimized_option_members` 验证表示标记、原始值类型和宽度，返回当前构造器及有效载荷。此文件是编译器契约变化时的主要适配点。 |
| `lldb_dap/positional.mbt` | `positional_members` 先尝试新 Option 视图，无标记时仍尝试既有 boxed enum；与 tuple/enum 共用 `.0` 访问。已知 Option 缺少调试表示时明确报错。 |
| `lldb_dap/variable.mbt` | Option 不按普通 struct 处理；提取 `materialize_enum_members` 复用浅层 enum 渲染；`p` 与 `locals` 分别显示值/构造器摘要；补充识别 `<unavailable>`。 |
| `lldb_dap/option_wbtest.mbt`（新增） | 进程内验证 Some/None、非法或未知标记、不可用载荷，以及 None 不触发子引用读取。始终参加默认单元测试。 |
| `acceptance/option_values_wbtest.mbt`（新增） | 两个真实 REPL/DAP 验收。覆盖 Some/None、边界整数、Point、嵌套 Option、Bool、Double、String、数组元素、可变变量及跨暂停状态的引用失效。当前额外门控，见下文。 |
| `testdata/dwarf_probe/option_values/main.mbt`、`moon.pkg`（新增） | 可手工试用的 executable fixture；`OPTION_READY`、`OPTION_CHANGED` 标记前后两次观察位置。 |
| `docs/testing.md` | 记录实验验收的额外开关，并指向本文。 |

不需要独立改写 REPL renderer 或 DAP 前端：现有 `VariableInspector`、enum snapshot 和
`variable_tree.mbt` 的共享位置成员访问负责复用。REPL 保持 `Some(Point)` 这样的浅层摘要，
用 `.0.x` 继续查看；VS Code 通过 variables 请求逐层展开，Watch 使用同一条变量路径。

## 实验契约快照（v1，待 review）

优化后的 Option 使用名为 `moonbitlang/core/option/Option[T]` 的 DWARF structure。
它不是额外分配的对象，而是覆盖原有存储的调试视图。恰有两个偏移均为 0 的成员：
一个版本化的表示标记，以及类型正确的 `.0` 载荷。

| 标记成员名 | DAP 基本类型对应 | 视图字节数 | None 原始值 |
| --- | --- | --- | --- |
| `__moonbit_option_v1_i64_4294967296` | UInt64 | 8 | 4294967296 |
| `__moonbit_option_v1_i32_4294967295` | UInt | 4 | 4294967295 |
| `__moonbit_option_v1_i32_65536` | UInt | 4 | 65536 |
| `__moonbit_option_v1_null` | UInt64 | 8 | 0 |

关键约束：

- 必须同时有源 Option 类型和受支持的标记，不能仅凭整数值或指针推断。
- 判别值来自 lldb-dap 的带类型子变量，不解析 REPL 输出。UInt/UInt64 的值按无符号十进制读取。
- Int 和 UInt 的 Some 都沿用现有 I32 到 I64 的符号扩展；当前小端表示下，`.0` 指向低 4 字节，分别按 Int/UInt 解读。
- None 没有有效载荷；即使 LLDB 暴露了重叠的 `.0`，也不能继续读取它。`p none.0` 必须失败。
- 不把 DAP `memoryReference` 当作可靠的 Option 对象地址，寄存器里的整数 Option 未必有可读地址。
- boxed Option 沿用 `__moonbit_enum_marker` 及现有 constructor/tag 规则；外层 Option 的 `.0` 必须保留内层 Option 类型，而不是 Int64/裸指针。
- 继续执行后旧变量引用失效，新的暂停状态重新判别 Some/None；不缓存跨暂停的内存解释。

## 与旧工具链共存

解析代码保留，不增加强制编译器版本检查，也不要求启动调试时开启 Option 开关。
能力取决于**被调试二进制的 DWARF**，不是当前 shell 中编译器的版本名。

- 带实验标记的产物：进入新解析路径。
- 仍有完整 boxed enum 信息的旧产物：使用已有 enum 路径。
- 已擦成 Int64/指针的旧产物：保留原先的底层显示能力，不补造 Some/None；旧工具链未提供的局部变量也不会凭空出现。
- 已知源 Option 类型但表示缺失、未知版本或表示无效：明确报告不可用/不支持，不猜测载荷。

因此，切回 stable 不代表删除解析器，也不代表完整 Option 功能已可在旧编译器上使用。
尤其不能承诺旧产物中的嵌套 Option 可以完整展开。

真实 Option 验收现在需要同时设置两个变量为 `1`：

- `MOONDBG_TOOLCHAIN_ACCEPTANCE`：允许真实工具链验收。
- `MOONDBG_OPTION_VIEW_ACCEPTANCE`：额外允许实验 Option 契约验收。

这是**测试开关**，不是运行时功能开关。未开启时，两条实验用例在创建子进程前提前返回；
测试框架可能仍将它们计为通过，不能将这个计数当作实验能力已验证。显式开启后，编译器不
支持契约必须导致验收失败，不能遇到错误再静默跳过。默认单元测试中的协议形状检查不关闭。

日常 stable 验证，在 moondbg 根目录执行：

```sh
source ~/.zshrc
set_moon_stable
moon info && moon fmt
moon check && moon test
moon build --target native -g .
MOONDBG_TOOLCHAIN_ACCEPTANCE=1 MOONDBG_OPTION_VIEW_ACCEPTANCE=0 \
  moon test acceptance --no-parallelize
```

本次切回上述 `~/.moon` 工具链后的验证结果：`moon info`、`moon fmt`、`moon check` 和
根入口 native debug 构建通过，默认测试报告 412/412，常规真实验收报告 57/57。
后一个数字包含两条提前返回的实验 Option 用例，**不代表它们在旧编译器上通过了完整验收**。
生成的 `.mbti` 接口没有变化。

## 编译器方案确定后的恢复步骤

1. 对照最终 compiler diff，确认源类型保留发生的阶段、参数/局部变量/字段/数组元素覆盖范围，以及位置配方是否仍有效。不能只确认顶层 `Int?`。
2. 对照本契约检查类型名、标记及版本、原始值宽度/格式、None 判别、`.0` 类型和偏移。先用原始 lldb-dap 验证；若编译器方案变化，更新 `option.mbt` 和协议单测，而不是继续套用旧规则。
3. 使用带最终补丁的编译器重新构建目标程序，旧 DWARF 不会因更新 moondbg 自动补全。
4. 显式开启两个开关，运行两个真实验收。重点验证负数/UInt 最大值、None 引用不解引用、Some(None) 与 None 的区别、字段/数组/可变变量、REPL/DAP/Watch 一致性和旧引用失效。
5. 再运行旧工具链兼容验收；更新本文、`docs/testing.md` 及编译器契约文档。只有最低支持工具链确实包含最终契约后，才考虑取消实验验收的额外开关。

恢复联调时，在 moondbg 根目录执行（不属于当前日常 stable 流程）：

```sh
source ~/.zshrc
set_moon_dev
moon build --target native -g .
MOONDBG_TOOLCHAIN_ACCEPTANCE=1 MOONDBG_OPTION_VIEW_ACCEPTANCE=1 \
  moon test acceptance/option_values_wbtest.mbt --no-parallelize
```

编译器自身验证限制仍为 `dune build -p moonbit-lang`；需要测试时只运行
`dune test test/aarch64_test`。上轮默认 Clang 的 ASan 探针在初始化时卡住，改用
`CC=/usr/bin/clang dune test test/aarch64_test` 后通过；脚本自动关闭了该 Clang 不支持的
leak detection，ASan/UBSan 仍开启，未修改测试配置。不要将此宿主工具问题与 Option 契约混淆。
