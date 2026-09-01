# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## Project Structure

- MoonBit packages are organized per directory; each directory contains a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in
  `_wbtest.mbt`).

- In the toplevel directory, there is a `moon.mod` file listing module
  metadata.

## Coding convention

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.

- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.

## 开发工具链环境

本项目必须使用 MoonBit 的本地开发工具链。凡是需要构建、测试、运行或调试 moondbg，
开始任务前都必须完成以下检查，不能直接使用系统中偶然出现在 `PATH` 里的稳定版工具链。

1. 确认 `MOON_HOME` 展开后的路径是 `~/.moon_dev`。工具执行环境不一定自动加载交互式
   zsh 配置；如果 `MOON_HOME` 未设置或不是该路径，必须先运行：

   ```sh
   source ~/.zshrc
   set_moon_dev
   ```

   `set_moon_dev` 的定义位于 `~/.zshrc`。运行后需要重新检查 `MOON_HOME`，不能只假定
   函数调用成功。

2. 确认 `$MOON_HOME/bin/moonc`、`$MOON_HOME/bin/moon` 和
   `$MOON_HOME/bin/moondbg` 都是有效的软链接，链接目标存在且可以执行。同时确认
   `command -v moonc`、`command -v moon`、`command -v moondbg` 分别解析到这三个路径，
   避免实际运行到其他工具链。

3. 确认开发版 `moonc` 的 `build-package` 和 `link-core` 子命令同时支持 `-g` 和 `-O0`。
   当前工具链已经取消 `-debug-info full`；完整的调试构建改为同时传入 `-g -O0`，分别生成
   调试信息并关闭优化。可以使用以下命令检查：

   ```sh
   moonc build-package -help 2>&1 | rg -- '-g .*debugging information'
   moonc build-package -help 2>&1 | rg -- '-O0 .*optimization'
   moonc link-core -help 2>&1 | rg -- '-g .*debugging information'
   moonc link-core -help 2>&1 | rg -- '-O0 .*optimization'
   ```

4. 确认开发版 `moon` 提供 `moon debug` 子命令，并检查 `moon debug --help` 能正常显示
   `moon debug [OPTIONS] <PACKAGE>`。

如果以上任一条件不满足，说明本地开发环境出现问题。必须立即暂停当前任务并向用户汇报
具体失败项、实际路径和检查输出；不得静默退回稳定版 `moon`/`moonc`、绕过检查继续实现，
也不得在没有用户指示时自行重建工具链或修改这些软链接。

## Tooling

- `moon fmt` is used to format your code properly.

- `moon ide` provides project navigation helpers like `peek-def`, `outline`, and
  `find-references`. See $moonbit-agent-guide for details.

- `moon info` is used to update the generated interface of the package, each
  package has a generated interface file `.mbti`, it is a brief formal
  description of the package. If nothing in `.mbti` changes, this means your
  change does not bring the visible changes to the external package users, it is
  typically a safe refactoring.

- In the last step, run `moon info && moon fmt` to update the interface and
  format the code. Check the diffs of `.mbti` file to see if the changes are
  expected.

- Run `moon test` to check tests pass. MoonBit supports snapshot testing; when
  changes affect outputs, run `moon test --update` to refresh snapshots.

- Prefer `assert_eq` or `assert_true(pattern is Pattern(...))` for results that
  are stable or very unlikely to change. For snapshot tests that record
  structured debugging output, derive `Debug` and use `debug_inspect`, rather
  than deriving `Show` for debugging. For solid, well-defined results (e.g.
  scientific computations), prefer assertion tests. You can use
  `moon coverage analyze > uncovered.log` to see which parts of your code are
  not covered by tests.
