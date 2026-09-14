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

moondbg 直接调用当前环境中的 `moon` 构建目标，不依赖 `moon debug`。
构建、测试、运行前确认所选工具链，并保证 `moon`、`moonc` 来自同一 `MOON_HOME`。
用户明确指定的工具链优先；本机可用以下命令选择 stable：

```sh
source ~/.zshrc
set_moon_stable
```

选择后检查 `MOON_HOME`、`command -v moon`、`command -v moonc` 和 `moon version --all`。
`moon`、`moonc` 必须存在且可执行，不要求 stable 安装使用软链接。
需要排查编译器开发版本时，可按用户指示使用 `set_moon_dev`，并重新检查路径。

包调试要求 `moon run --help` 支持 `--build-only`、`--target` 和 `-g`，
`moon check` 能生成 `native/debug/check/packages.json` 包元数据。
完整调试构建使用 `-g -O0`；`moonc build-package -help` 与 `moonc link-core -help`
都必须支持这两个参数，不使用已取消的 `-debug-info full`。
如果所选工具链缺少所需能力，应报告实际版本和失败项，不能静默切换工具链、重建工具链
或修改工具链软链接。

真实验收前先构建 `main`（`moon build --target native -g main`）。默认验收启动仓库内
`_build/native/debug/build/main/main.exe`，也可用 `MOONDBG_ACCEPTANCE_EXECUTABLE`
指定本次构建的绝对路径，避免误测旧的已安装版本。

VS Code 扩展只启动 `$MOON_HOME/bin/moondbg --dap`，允许普通可执行文件或有效软链接，
不搜索 PATH 或自动安装。仓库的扩展开发窗口默认设置 `MOON_HOME=~/.moon`，并将其
`bin` 放在 PATH 最前面；修改启动配置后需重新启动开发窗口。若缺少 moondbg，应报告
实际路径，由用户安装或配置链接，不静默修改用户工具链。

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
