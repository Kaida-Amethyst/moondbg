# MoonBit DWARF 能力探测 fixture

这个 fixture 验证 T-02/P1 所需的最小调试信息：

- 源码行断点；
- 一个真实函数调用；
- `input` 函数参数；
- `answer` 简单局部变量；
- 停点处的源码与 stack frame 信息。

探针通过 `MOONDBG_BREAKPOINT` marker 自动寻找断点行，因此在 marker 之前增加代码时不需要
同步修改脚本中的固定行号。`input` 在停点之后还会参与计算，以保证它在该位置仍是活跃
变量，避免把正常的变量生命周期结束误判为 DWARF 缺失。

## 使用完整调试信息构建

必须使用开发工具链。这里有意使用 `moon debug` 而不是普通 `moon build`，因为前者会在
相关的两个 moonc 阶段传入 `-debug-info full`，并在构建后进入 moondbg REPL。

```sh
source ~/.zshrc
set_moon_dev
cd testdata/dwarf_probe
moon debug main
```

可以在 REPL 中运行完整的 T-02 闭环：

```text
(moondbg) break main/main.mbt:4
(moondbg) run
(moondbg) p input
(moondbg) p answer
(moondbg) continue
```

生成的程序位于：

```text
testdata/dwarf_probe/_build/native/debug/build/main/main.exe
```

可以通过以下命令检查实际编译命令；`build-package` 和 `link-core` 都应包含
`-debug-info full -O0`：

```sh
moon debug --dry-run main
```

## 运行 DAP 能力探针

回到 moondbg 仓库根目录运行：

```sh
python3 tools/dap_capability_probe.py \
  testdata/dwarf_probe/_build/native/debug/build/main/main.exe \
  testdata/dwarf_probe/main/main.mbt \
  --expect-variable input=41 \
  --expect-variable answer=42
```

命令输出一份 JSON 报告。只有以下条件全部满足时才以状态码 0 退出：

- 源码断点 verified；
- stopped frame 指向 marker 所在的源码与行号；
- 所有预期变量都有非空的类型和值；
- 变量值与命令行给出的预期值一致。

报告同时保留本次会话观察到的 DAP 消息顺序。能力缺失时仍会尽可能输出已经获得的
breakpoint、frame、scope 和 variable 信息，并以状态码 2 退出。

## 2026-08-26 探测结果

本次使用：

- moon `0.1.20260825 (2c2f404b 2026-08-25)`；
- moonc `v0.10.10+976e725ee-fix (2026-08-26)`；
- LLVM `21.0.0`、liblldb `lldb-2100.0.17.203`。

当前结果为全部通过：

| 能力 | 结果 |
| --- | --- |
| 源码行断点 | line 4、column 3，`verified: true` |
| stopped frame | `$Kaida-Amethyst/moondbg-dwarf-probe/main.inspect_value`，源码路径与 line 4 正确 |
| 函数参数 | `input`，type `int`，value `41` |
| 简单局部变量 | `answer`，type `int`，value `42` |
| 继续与退出 | `continue` 成功，随后收到 `continued`、`output`、`exited(0)`、`terminated` |

三次连续重复探测均通过全部检查。当前开发版编译器已经满足 P1 对行断点、源码 frame、
参数和简单局部变量的要求，进入 P2 前不需要增加编译器修改。

## 运行 REPL 端到端验收

从 moondbg 仓库根目录运行：

```sh
source ~/.zshrc
set_moon_dev
python3 tools/repl_e2e.py
```

该脚本自动覆盖 MoonBit 的双断点、变量查询、两次继续和正常退出，也会编译 C exit fixture
验证非零退出，并检查运行前 quit、adapter failure 和子进程组清理。
