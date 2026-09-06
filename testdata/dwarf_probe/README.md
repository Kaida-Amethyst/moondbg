# MoonBit DWARF 与函数断点验收 fixture

这个 fixture 提供一条稳定的 native 调试路径，覆盖：

- `main/main.mbt` 的源码行断点；
- 当前包入口 `main` 和普通函数 `sum`；
- 跨包普通函数 `@probe.increment`；
- 分别单态化为 `Int`、`String` 的泛型函数 `@probe.identity`；
- 不存在函数的 rejected 结果；
- stopped 状态动态添加与下一 execution 重放；
- `point` 包中 `Point` 和嵌套 `Line` 的 struct 变量打印与字段路径查询。
- `fixed_array_int` 包中长度 10/100 的 `FixedArray[Int]` 有界打印。
- `array_double` 包中长度 10/100 的 `Array[Double]` 逻辑长度与有界打印。
- `array_points` 包中 `Array[Point]` 的精确下标及后续字段路径打印。
- `list` 包中 boxed enum 的 active constructor 与浅层 payload 打印。
- `stack_frames` 包中跨包、普通函数、递归和泛型调用组成的调用栈，以及各 frame 的参数、
  局部变量、shadowing 和作用域边界。
- `breakpoint_management` 包中三轮普通函数与 `Int`/`Double` 泛型调用，用于断点集合替换、
  禁用/启用和删除的 T-07 验收。

## 断点管理 fixture

运行 `moon debug breakpoint_management` 后，现阶段可以用 `b main`、`run`、`b ordinary`、
`b identity`、`continue` 观察普通函数与两个 generic locations。管理命令在 T-07 后续阶段
接入；P1 使用原始 DAP 探针验证底层语义，不要求尚未实现的 REPL 命令。

可通过 `rg -n 'MOONDBG_BREAKPOINT_' breakpoint_management/main.mbt` 查找普通函数、
generic 函数和第一轮末尾 checkpoint 的稳定源码标记。三轮分别输出：

```text
first: 11, 1.5
second: 21, 2.5
third: 31, 3.5
```

从 moondbg 仓库根目录运行诊断（先用 `moon debug breakpoint_management` 构建并退出）：

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/breakpoint_management_probe.py \
  --output _build/breakpoint_management_probe.json
```

探针保存完整请求/响应和停点证据，只有全部检查通过才返回 0；它不依赖 moondbg 的产品
断点实现，也不是产品运行时依赖。协议观察和当前查询上限见 T-07 的 P1 验证结果。

## 使用完整调试信息构建

必须使用开发工具链。`moon debug` 会在相关 moonc 阶段传入 `-g -O0`，随后把构建
产物和当前包/alias 上下文传给 moondbg：

```sh
source ~/.zshrc
set_moon_dev
cd testdata/dwarf_probe
moon debug main
```

可以在 REPL 中运行 Q-02 的完整闭环：

```text
(moondbg) b main
(moondbg) run
(moondbg) b main/main.mbt:13
(moondbg) b sum
(moondbg) continue
(moondbg) continue
(moondbg) b @probe.increment
(moondbg) continue
(moondbg) b @probe.identity
(moondbg) continue
(moondbg) continue
(moondbg) b missing
(moondbg) run
```

其中源码、`sum` 和 `increment` 都应立即 verified；`identity` 应报告两个 locations，并在两次
`continue` 中分别命中 `Int`、`String` 实例；`missing` 应立即 rejected。最后一次 `run` 会
重启 execution，以原有逻辑编号重放全部断点。

生成的程序位于：

```text
testdata/dwarf_probe/_build/native/debug/build/main/main.exe
```

可以通过以下命令检查实际编译命令；`build-package` 和 `link-core` 都应包含 `-g -O0`：

```sh
moon debug --dry-run main
```

## 运行原始 DAP 探针

回到 moondbg 仓库根目录后，可以用四个互补的探针直接连接真实 lldb-dap：

```sh
python3 tools/dap_capability_probe.py \
  testdata/dwarf_probe/_build/native/debug/build/main/main.exe \
  testdata/dwarf_probe/main/main.mbt \
  --line 3

PYTHONDONTWRITEBYTECODE=1 \
  python3 tools/dynamic_breakpoint_probe.py

PYTHONDONTWRITEBYTECODE=1 \
  python3 tools/struct_variable_probe.py

PYTHONDONTWRITEBYTECODE=1 \
  python3 tools/fixed_array_probe.py
```

第一个探针验证源码断点、stopped frame 与基础 DAP 生命周期；第二个探针固定 stopped 状态
下源码/精确函数完整集合、function-family 增量命令、重复 family、零 location、请求拒绝和
随后命中的协议语义；第三个探针验证 `Point` 一层字段和 `Line` 两层字段的
递归 DAP 形状；第四个探针在不加载 `moonbit.py` 时验证 FixedArray 的 header 长度、payload
类型与首尾元素。探针只有在全部断言通过时才以状态码 0 退出。

struct REPL 闭环可以通过以下命令人工验证：

```text
moon debug point
(moondbg) b distance
(moondbg) b is_parallel
(moondbg) run
(moondbg) p p1
(moondbg) p p1.x
(moondbg) p p1.y
(moondbg) p p1.z
(moondbg) p p1.x.value
(moondbg) p dx
(moondbg) next
(moondbg) p p1.x
(moondbg) continue
(moondbg) p line1
(moondbg) p line1.start.x
(moondbg) p line1.end.y
(moondbg) p line1.start
```

FixedArray REPL 闭环可以通过以下命令人工验证：

```text
moon debug fixed_array_int
(moondbg) b sum
(moondbg) run
(moondbg) p arr
(moondbg) continue
(moondbg) p arr
```

boxed enum REPL 闭环可以通过以下命令人工验证：

```text
moon debug list
(moondbg) b list/main.mbt:34
(moondbg) run
(moondbg) p list
```

Array REPL 闭环可以通过以下命令人工验证：

```text
moon debug array_double
(moondbg) b sum
(moondbg) run
(moondbg) p arr
(moondbg) continue
(moondbg) p arr
```

Array struct 元素路径闭环可以通过以下命令人工验证：

```text
moon debug array_points
(moondbg) b array_points/main.mbt:25
(moondbg) run
(moondbg) p arr[0]
(moondbg) p arr[0].x
(moondbg) p arr[3]
```

## 调用栈与栈帧 fixture

`stack_frames` 是 T-06 调用栈、栈帧导航和局部变量功能的专用可执行包。它通过辅助 library
package `stack_support` 构造以下调用链：

```text
main
└─ @stack_support.enter_stack
   └─ ordinary_frame
      └─ recursive_frame(depth = 3)
         └─ recursive_frame(depth = 2)
            └─ recursive_frame(depth = 1)
               └─ recursive_frame(depth = 0)
                  └─ generic_leaf[Int]
```

程序可以独立运行，并确定性输出 `stack fixture result: 676`：

```sh
cd testdata/dwarf_probe
moon run stack_frames
```

调试时执行：

```sh
moon debug stack_frames
```

建议的叶子停点是 `stack_support/stack_support.mbt` 中带有
`MOONDBG_STACK_LEAF_BREAKPOINT` 标记的表达式。标记与可停语句位于同一源码行，可先用以下
命令取得当前位置，再按 moondbg 已支持的源码行断点语法设置断点：

```sh
rg -n 'MOONDBG_STACK_LEAF_BREAKPOINT' stack_support/stack_support.mbt
```

在该位置停住后，可以用 `bt`、`frame N`、`up`、`down`、`locals`、`list` 和 `p` 观察并切换
frame。例如先执行 `locals`，再切换到 `frame 5` 查看 `ordinary_frame`，最后切回 `frame 0`
验证叶子 frame 的摘要和详细打印。各层刻意使用不同的参数和 local 名称及数值：main 和跨包
frame 持有 Array，递归 frame 持有不同 depth，泛型叶子持有泛型 envelope 和 leaf Array。
`ordinary_frame` 的内外词法块包含同名 `shadowed_value`；
`nested_result`、`cross_result`、`stack_result` 等调用结果只在调用返回后才可用，用于验证
源码位置对应的变量可用范围。`main` 之下自然保留 MoonBit runtime/native 入口边界。

当前开发工具链在递归 caller frame 上仍可能把参数报告为 unavailable，并为部分 local 返回
错误寄存器值；`ordinary_frame` 的两个同名 binding 也缺少可判定当前词法作用域的 DWARF
信息。`locals` 会诚实显示 `<unavailable>` 或 `<ambiguous binding>`，不根据 LLDB 的寄存器
后缀猜测绑定。这些工具链问题留给 T-06/P6 修复。

## 2026-08-30 验收结果

当前开发工具链上的真实 lldb-dap 验收结果如下：

| 能力 | 结果 |
| --- | --- |
| stopped 源码断点 | 立即 verified，并在 `continue` 后命中 `main/main.mbt:13` |
| 当前包普通函数 | `sum` 立即 verified 并命中 |
| 跨包普通函数 | `@probe.increment` 立即 verified 并命中 |
| 泛型 function family | `@probe.identity` 为 2 locations，依次命中 `Int`、`String` |
| 不存在函数 | `missing` 立即 rejected，逻辑配置保留 |
| 跨 execution 重放 | 编号 1..6 保持，identity 仍为 2 locations，无重复 family |
| struct 变量 | `Point` 展开为 `x`/`y`，`Line` 递归展开 `start`/`end` |
| struct 字段路径 | 支持一层/多层/最终 struct，精确区分缺失字段、非 struct 与当前位置不可用 |
| FixedArray 变量 | 长度 10 完整显示；长度 100 有界显示并保留尾值 100 |
| Array 变量 | 使用逻辑长度而非底层容量；长度 10 完整显示；长度 100 有界显示并保留尾值 100 |
| Array struct 元素路径 | `arr[0]` 展开 `Point`，并支持继续访问 `arr[0].x`；越界返回结构化失败 |
| boxed enum 变量 | 识别 active constructor，显示直接标量 payload，聚合 payload 只显示类型名 |

## 运行 REPL 端到端验收

从 moondbg 仓库根目录运行：

```sh
source ~/.zshrc
set_moon_dev
python3 tools/repl_e2e.py
```

真实链路覆盖上述动态断点、重放和 struct 打印闭环；fake adapter 链路另外覆盖请求顺序、
动态安装期间 adapter 退出后的配置保留/恢复、初始化超时、终端控制和进程组清理。
