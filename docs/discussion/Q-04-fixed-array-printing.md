# Q-04. FixedArray 值的有界打印 已解决

> 最后更新日期：2026-08-28
> 仓库：moondbg
> 记录者：Codex-GPT-5

## 问题描述

Q-03 已让 `p <struct>` 可以通过 DWARF 和结构化 DAP 子变量递归展示字段。下一步希望让
`p arr` 展示 MoonBit `FixedArray[T]` 的长度和元素，而不是只显示 LLDB 类型摘要与地址。

本问题确定第一版 FixedArray 值模型、目标内存读取边界和 REPL 展示策略。第一版优先解码
基础元素类型；非基础元素只展示静态类型占位符，不递归读取每个元素。`p arr[i]`、普通
`Array`、enum、完整 MoonBit 表达式求值和依赖 `moonbit.py` 的 LLDB formatter 均不在本轮
范围内。

## 问题引发模型

### 问题复现

`testdata/dwarf_probe/fixed_array_int/main.mbt` 依次把长度为 10 和 100 的
`FixedArray[Int]` 传入 `sum`。使用开发工具链运行：

```text
moon debug fixed_array_int
(moondbg) b sum
(moondbg) run
(moondbg) p arr
```

当前未加载 `moonbit.py` 的原始 lldb-dap 只把 `arr` 表示为
`moonbit.array_i32 @ <address>`，没有直接给出 MoonBit 数组文本。

### 最小复现例子

```moonbit
fn main {
  let short : FixedArray[Int] = [1, 2, 3]
  let long : FixedArray[Int] = [for i in 1..<=100 => i]
  // 分别在使用 short 和 long 的函数中停止并执行 p arr。
}
```

短数组可以完整显示；长数组若完整读取和拼接，会产生无界的目标内存读取和终端输出。
问题由“数组长度在 runtime header 中，而元素数量没有天然展示上限”共同引发。去掉长数组
或设置有界预览后，读取与输出都可保持稳定。

### 问题分析

真实原始 DAP 探测已经确认，当前 native 后端无需加载 Python formatter 也提供了第一版
实现所需的信息：

1. 根变量 `arr` 带有 `evaluateName`、`memoryReference` 和非零
   `variablesReference`，原始子变量 `body` 的类型为元素指针，例如 `int *`；
2. 当前 native runtime 的数组 payload 前 8 字节是两个 32 位 header word，其中
   `body - 4` 保存长度；lldb-dap 声明支持 `readMemory`，可以先单独读取 header；
3. 基础元素连续存放在 `body` 后，可以按选定范围批量读取；只读 DAP evaluate
   `arr.body[i]` 也能返回指定元素的结构化结果，为以后支持复合元素提供了接口；
4. 因此不能把“先读取所有元素，再截断字符串”作为实现模型。应先取得长度，再根据读取
   预算决定元素索引，最后由 renderer 应用单行字符预算；
5. runtime header 偏移、标量大小、符号性、浮点编码和目标字节序属于 MoonBit runtime
   值解释层，不应散落在 REPL renderer 或直接解析 LLDB 文本。

## 关联问题

1. [Q-03. Struct 变量的递归打印](Q-03-struct-variable-printing.md)（前置能力：提供不泄漏
   DAP 临时引用的领域变量快照和递归 renderer 边界）

## 建议的解决方案

### A1. moondbg 原生 FixedArray 解码与有界单行预览 【已采纳】

#### 方案描述

在 moondbg 内建立不依赖 `moonbit.py` 的 MoonBit indexed collection 领域语义，由
lldb-dap backend 使用结构化变量和 `readMemory` 物化有界预览，再由 REPL renderer 输出
稳定的单行数组内容。

第一版按以下规则实施：

1. **长度优先。** 取得 `body` 地址后先只读取 runtime header，验证并保存
   `total_length`，随后才决定读取哪些元素；空数组直接形成空预览；
2. **读取预算与展示预算分离。** 初始最大预览元素数为 16，数组内容行的初始字符预算为
   100。长度不超过 16 时最多读取全部元素；超过时只读取有界的头部元素和最后一个元素；
3. **批量读取基础元素。** 对连续的基础元素使用少量 `readMemory` 请求读取头部范围和最后
   一个元素，不为每个元素单独产生 DAP 往返。第一版覆盖 `Bool`、`Int`、`UInt`、`Int64`、
   `UInt64`、`Float` 和 `Double`；`Char`、`Byte`、`String` 留待各自展示语义明确后接入；
4. **领域模型保持结构化。** FixedArray 快照明确保存元素类型、总长度、已读取元素及其
   原索引和省略数量，不把最终的 `[1, 2, ..., 100]` 字符串塞入 backend，也不把 indexed
   collection 伪装成 struct 字段；
5. **单行渲染。** renderer 先用已读取的候选元素构造一行；若超过字符预算，就从头部预览
   的末端逐步减少元素，但始终保留首元素和最后一个真实元素。省略号只表达未展示区间；
6. **非基础元素不读取实例。** `FixedArray[Point]` 第一版只根据静态元素类型和长度输出
   有界的类型占位符，不访问每个 `Point`。在 `p arr[i]` 真正可用前不输出不可执行的操作
   提示；
7. **集中维护 runtime ABI。** header 偏移、目标字节序、元素宽度、越界与整数溢出检查由
   独立的 MoonBit runtime 值解释组件负责。非法长度、空指针、短读或不支持的标量类型返回
   明确的调试器错误，不进行无界或猜测式读取；
8. **保持现有边界。** struct 继续使用 Q-03 的字段树；普通标量输出不变；本轮不把用户
   输入原样交给 LLDB expression evaluator，也不实现 `p arr[i]`。

短数组目标输出：

```text
arr: FixedArray[Int] with length = 10

  [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
```

长数组目标输出：

```text
arr: FixedArray[Int] with length = 1000

  [1, 2, 3, 4, 5, 6, ..., 1000]
```

非基础元素目标输出：

```text
arr: FixedArray[Point] with length = 100

  [Point, Point, Point, ..., Point]
```

#### 优点

- 不依赖 Python、LLDB formatter 或 LLDB 文本格式，moondbg 自己拥有 MoonBit 值语义；
- 先读长度再决定范围，使目标内存读取、DAP 往返、领域对象大小和终端输出都有硬边界；
- indexed collection 的结构化领域模型可以由 REPL、未来对外 DAP 和 AI 共同复用；
- 基础元素可以批量读取，后续 `p arr[i]` 和复合元素递归仍有清晰扩展点；
- 非基础元素在尚未支持随机访问时不会触发昂贵且价值有限的全量递归。

#### 缺点

- moondbg 需要承担并测试 MoonBit native runtime 数组布局、目标字节序和标量解码规则；
- 领域模型和 backend 查询接口需要从 struct/leaf 二分扩展到 indexed collection；
- 字符预算发生在 renderer，而读取预算发生在 backend，第一版可能读取少量最终没有展示的
  候选元素；
- 非基础元素第一版只能提供类型级摘要，尚不能检查某个具体元素的字段。

## 最终采用方案

A1. moondbg 原生 FixedArray 解码与有界单行预览

## 任务划分

Q-04 按 P1 至 P4 顺序实施。P1 固化原始 DAP 与领域契约，P2 实现无 Python 的值解码，P3
完成用户可见渲染，P4 使用新增 fixture 和真实工具链收口。

### P1. 固化原始 FixedArray DAP 行为与 indexed collection 领域模型

**状态：已完成**

**目标：** 在读取目标内存前固定当前 native backend 的事实，并让公共领域模型能准确表达
数组总长度、有索引的预览元素和省略区间。

**工作内容：**

1. 使用 `testdata/dwarf_probe/fixed_array_int` 固化根变量、`body`、元素指针类型、
   `memoryReference`、header 字节和指定元素 evaluate 的真实 DAP 响应；
2. 为领域层增加 indexed collection 表达，保持 adapter reference、地址和 raw DAP JSON
   只存在于 lldb-dap backend；
3. 定义预览元素的原索引、总长度、元素类型和省略数量，覆盖空、短、长和非法快照测试；
4. 保持现有 leaf/struct 构造和公开行为不回归。

**完成条件：** 原始协议事实可重复验证；领域模型无需解析终端文本即可表达三种目标输出，
公开接口不包含 DAP 临时 ID。

**实施结果：** 新增的真实原始 DAP 探针在未加载 `moonbit.py` 时验证了两个 `sum` 停点：
`arr` 分别暴露长度为 10 和 100 的 header，raw `body` 为 `int *`，首尾元素分别为
`1/10` 和 `1/100`。领域层已改为 leaf、structure、indexed collection 的判别联合；indexed
collection 保存元素类型、总长度、原索引、有值/类型占位预览及省略数量，并验证长度、索引
范围和严格递增顺序。公开模型不保存地址、memory reference 或 variablesReference，现有
struct 与 scalar 输出保持不变。

### P2. 实现基础元素 FixedArray 的原生解码

**状态：已完成**

**目标：** 在 lldb-dap backend 中先读长度，再按固定读取预算物化基础元素预览。

**工作内容：**

1. 建立集中的 native runtime array layout 与标量类型映射，不依赖或加载
   `$MOON_HOME/share/lldb/moonbit.py`；
2. 从 raw `body` 子变量取得 element pointer、evaluate name 和 memory reference，使用
   `readMemory` 读取并校验 header；
3. 根据 16 个预览元素的预算选择头部索引和最后一个索引，对连续区间批量读取；
4. 解码已确定的基础类型，处理空指针、负数/异常长度、地址和大小溢出、短读及不支持类型；
5. 复用 stop epoch 生命周期，恢复执行后不得读取或复用旧地址和旧 reference；
6. 增加 scripted DAP 和纯解码测试，覆盖空数组、短数组、长数组、最后元素、各种基础类型
   及错误响应。

**完成条件：** `FixedArray[Int]` 等已支持基础类型返回有界、带真实索引和总长度的快照；
读取次数与数组总长度无关，非 FixedArray 和未支持元素类型不会被误读为标量数组。

**实施结果：** 新增独立的 `runtime_value` 包集中维护 native FixedArray header、基础标量
类型/宽度/字节序映射、预览计划和纯字节解码。lldb-dap backend 只对明确的 FixedArray
DWARF 类型读取 `body`，先用一次 `readMemory` 取得长度；长度超过 16 时再分别批量读取前
15 个元素和最后一个元素，读取请求数不随总长度增长。第一版已覆盖 `Bool`、`Int`、
`UInt`、`Int64`、`UInt64`、`Float` 和 `Double`；非基础元素只建立原索引类型占位符。
同一 stop epoch 的完整领域快照会缓存，恢复执行时与 raw variables 一起失效。纯解码和
scripted DAP 测试覆盖空、短、长、尾元素、各基础类型、非基础类型、非法 header、短 payload
和请求范围；真实 `moon debug fixed_array_int` 链路已验证可以在无 `moonbit.py` 时物化数组。

### P3. 实现 FixedArray 单行渲染与非基础类型摘要

**状态：已完成**

**目标：** 按 A1 产生稳定的 header、空行和单行数组内容，同时保持长值可裁剪。

**工作内容：**

1. 为 indexed collection 增加专门 renderer，统一 MoonBit 类型名、长度和元素格式；
2. 对候选基础元素应用 100 字符预算，完整显示短数组，长数组保留头部和最后一个真实元素，
   并用一个省略号表示中间未展示区间；
3. 对非基础元素只生成有界的静态类型占位符，不请求实例字段，也不输出尚不可用的
   `p arr[i]` 提示；
4. 增加快照测试，覆盖空数组、单元素、恰好达到预算、元素数量裁剪、字符宽度裁剪、负数、
   浮点、Bool 和非基础类型；
5. 保持普通标量、struct 和错误输出快照不变。

**完成条件：** 数组内容在 renderer 中始终是一条逻辑行，目标输出与 A1 示例一致；字符预算
不会影响领域快照中的真实总长度、索引或省略数量。

**实施结果：** REPL renderer 现在为 indexed collection 输出 MoonBit `FixedArray[T]`、
真实长度、空行和一条缩进内容行。renderer 根据领域快照中的原索引插入省略号；候选内容
超过 100 字符时从头部末端逐步删减，但保留首元素和最后一个真实元素。非基础元素复用同一
预算输出静态类型占位符，不读取实例，也不提示尚未实现的 `p arr[i]`。快照测试覆盖空、
单元素、短数组、长数组、恰好 100 字符、字符裁剪、负数、浮点、Bool 和非基础元素；真实
链路已得到长度 10 的完整输出和长度 100、尾值为 100 的有界输出。

### P4. 完成真实工具链与回归验收

**状态：待实施**

**目标：** 在真实 `moon debug fixed_array_int` 链路中验证短数组和长数组，同时确认无 Python
formatter 依赖及既有值打印无回归。

**工作内容：**

1. 在第一次 `sum` 停点验证长度 10 的数组完整显示，在第二次 `sum` 停点验证长度 100 的
   数组有界显示且最后一个真实元素为 100；
2. 验证当前 execution 重复打印使用 stop-epoch 缓存，恢复运行后重新读取新数组 header，
   不跨 stop 复用旧地址；
3. 增加 MoonBit scripted/PTY acceptance 与可选真实 DAP 诊断探针，检查 `readMemory` 范围、
   请求次数、错误清理和无 `moonbit.py` 初始化命令；
4. 执行 `moon info`、`moon fmt`、`moon check`、默认 `moon test`、真实 toolchain acceptance
   和相关 Python real/fake E2E。

**完成条件：** 新 fixture 的两个停点均得到预期 FixedArray 输出；读取量受固定预算约束；
struct、标量、execution 生命周期、adapter 清理和开发工具链回归全部通过。
