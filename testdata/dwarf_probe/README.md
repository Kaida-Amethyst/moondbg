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

## 使用完整调试信息构建

必须使用开发工具链。`moon debug` 会在相关 moonc 阶段传入 `-debug-info full`，随后把构建
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

可以通过以下命令检查实际编译命令；`build-package` 和 `link-core` 都应包含
`-debug-info full -O0`：

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

Array REPL 闭环可以通过以下命令人工验证：

```text
moon debug array_double
(moondbg) b sum
(moondbg) run
(moondbg) p arr
(moondbg) continue
(moondbg) p arr
```

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

## 运行 REPL 端到端验收

从 moondbg 仓库根目录运行：

```sh
source ~/.zshrc
set_moon_dev
python3 tools/repl_e2e.py
```

真实链路覆盖上述动态断点、重放和 struct 打印闭环；fake adapter 链路另外覆盖请求顺序、
动态安装期间 adapter 退出后的配置保留/恢复、初始化超时、终端控制和进程组清理。
