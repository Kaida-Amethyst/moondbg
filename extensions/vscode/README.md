# moondbg for VS Code（技术预览）

通过 moondbg 与 lldb-dap 调试 MoonBit native 程序。支持自动构建、行断点、函数断点、
单步、暂停、调用栈、局部变量树、Watch、悬停、只读变量路径求值和程序输出。

## 支持环境

- macOS Apple Silicon：`aarch64-apple-darwin`（VSIX 平台名 `darwin-arm64`）。
  使用原生 ARM64 版 VS Code，不支持 Rosetta、Intel Mac、Windows 或 Linux。
- MoonBit 支持基线：**v0.10.4**。当前实际开发验收使用
  `moonc v0.10.12+2583f1173-nightly`；v0.10.4 专项验收尚待完成。
- 需要可用的 `lldb-dap`。可在终端执行 `xcrun --find lldb-dap` 检查；
  如果没有，应先安装/配置提供 lldb-dap 的 Xcode 工具链，再尝试调试。
- 安装 MoonBit 的 VS Code 语言扩展，使 `.mbt` 文件的语言模式为 **MoonBit**。
- 仅支持受信任的本地文件工作区。调试会编译并运行你的代码。

## 安装

从 [GitHub Release：vscode-v0.1.2](https://github.com/Kaida-Amethyst/moondbg/releases/tag/vscode-v0.1.2)
下载 `moondbg-0.1.2-darwin-arm64.vsix`。这是技术预览，尚未上架 Marketplace。

1. 在终端使用你的 MoonBit 工具链安装 CLI：

   ```sh
   moon install Kaida-Amethyst/moondbg
   ```

   默认安装位置是 `~/.moon/bin/moondbg`。此扩展不包含 CLI，也不会自动安装或更新它。
   本版的 panic、条件断点和变量探查能力由 CLI 提供；Mooncakes 包可能落后于本 release。
   要安装与本 release 匹配的 CLI，可在新的目录中执行：

   ```sh
   git clone --branch vscode-v0.1.2 --depth 1 https://github.com/Kaida-Amethyst/moondbg.git moondbg-preview
   cd moondbg-preview
   moon install --path .
   ```

   这会替换原来的 moondbg CLI，不会升级 MoonBit 工具链。
2. 在普通 VS Code 窗口按 `Cmd+Shift+P`，执行 **Extensions: Install from VSIX… / 扩展：从 VSIX 安装…**，
   选择 `moondbg-0.1.2-darwin-arm64.vsix`，如有提示则重新加载窗口。
   不需要克隆 moondbg 仓库或打开扩展开发窗口。
3. 打开用户设置（`Cmd+,`），搜索 `moondbg.moonHome`，填入 `~/.moon`。
   也可以通过 **Preferences: Open User Settings (JSON)** 添加：

   ```json
   {
     "moondbg.moonHome": "~/.moon"
   }
   ```

   自定义工具链请填对应的绝对目录。该设置优先于环境变量；留空才使用 VS Code 进程的 `MOON_HOME`。
   不会搜索 PATH 或自动尝试其他目录。扩展将所选目录传给 CLI，保证构建使用同一套工具链。

若之前装过 `moondbg-dev` 或启动了旧的 moondbg 扩展开发窗口，请先禁用旧扩展并关闭旧窗口，
避免两个扩展同时注册 `moondbg` 调试类型。本预览包的扩展标识是 `moondbg-local.moondbg`。
更新时下载相应 release 的 VSIX 重新安装，并按其说明同步 CLI。

## 第一次调试

打开 MoonBit 项目文件夹，再打开可执行包中的 `.mbt` 源码，打断点并按 F5。
首次询问调试器时选择 **moondbg**；默认入口是 **moondbg：调试当前包**，不要求 launch.json。
也可以按 `Cmd+Shift+P` 执行 **moondbg：调试当前包**，不受项目已选中其他调试器配置的影响。

当前文件属于 library、测试文件、非 native 可执行包，或没有打开已保存的源码时，提示
**未确定 main 函数位置**，不会搜索或自动选择其他包。入口定位仅检查元数据，不执行用户程序，
可通过通知中的取消按钮停止。编译诊断显示在 Output / 输出面板的 moondbg 频道。

自动定位需要新版 CLI 的 `--resolve-source` 接口。旧 CLI 会提示升级，不会猜测 `/main`。
CLI 新版发布到 Mooncakes 后可再次执行 `moon install Kaida-Amethyst/moondbg`；
开发试用可以在 moondbg 仓库根目录执行 `moon install --path .`，安装当前源码版本。

已有明确 `package` / `program` 的配置仍按原目标运行。若想固定入口，可在 `.vscode/launch.json` 中添加：

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "moondbg",
      "request": "launch",
      "name": "调试 MoonBit main",
      "package": "${workspaceFolder}/main",
      "internalConsoleOptions": "openOnSessionStart"
    }
  ]
}
```

`package` 是可执行包的目录。若 `moon.pkg` 就在项目根目录，改成 `${workspaceFolder}`；
若在 `src/main`，则改成 `${workspaceFolder}/src/main`。不能指向 library 包。

在 `.mbt` 文件的可执行语句旁打红点，按 F5。moondbg 会先检查项目并以 `-g -O0` 构建，
然后启动调试。程序停住后可查看变量和调用栈，使用工具栏继续、单步或暂停；红色方块结束会话。
修改源码后保存并开始新会话，程序会重新构建。构建失败不会运行旧二进制。

- **函数断点**：在断点面板添加 `main`、当前启动包的 `foo` 或 `@alias.foo`。
  泛型函数匹配所有已生成实例；别名来自启动包的 `moon.pkg`。
- **Watch / 调试控制台**：直接输入 `point.x`、`arr[0].x`，不要输入 REPL 的 `p` 或 `b`。
- **预编译程序**：可用 `"program": "绝对路径/program.exe"` 替换 `package`；两者只能选一个。
  程序需带完整调试信息。此模式不重新构建，函数断点仅支持 `main`。

## 条件断点（需要本 release 对应的 CLI）

在源码行号左侧右键 → **添加条件断点 / Add Conditional Breakpoint**，选“表达式”，
输入 `i == 7`。已有断点可右键编辑；清空表达式恢复无条件断点。
支持行断点的变量路径比较，例如 `point.x > 5`、`arr[0] == 7`、`line.start.x < limit`。
左右路径复用 Watch/print 的只读语法；支持 `Int`、`UInt`、`Int64`、`UInt64` 的六种比较，
以及 Bool 的 `==`、`!=`（例如 `ready == true`）。路径之间必须同类型，不隐式混合转换。
整数常量按左侧类型检查范围，64 位整数不会转成 Double；暂不支持浮点、算术或函数调用。

示例：打开仓库 `testdata/dwarf_probe/conditional/main.mbt`，在第 4 行设置 `i == 7`，
F5 后只在 `i = 7` 的那轮停止。条件变量读取失败会停住并明确报错。
run/continue 过滤 false 条件；单步保留 LLDB 原有停止，不额外自动继续。
此功能由 CLI 提供能力声明，更新 CLI 后重新启动调试即可，无需重新安装 VSIX。
当前尚不支持命中次数或 logpoint。

支持括号、`&&`、`||` 和 `!(condition)`，例如 `i >= 3 && i < 8`，采用短路求值。
函数断点也可右键 **编辑条件**；名称填 `probe`，条件单独填写，不要把 `if` 写进名称。
打开 `conditional_functions/main.mbt`，给函数 `probe` 设置上述条件，F5 后依次停在 i=3 到 7。
改为函数 `identity`、条件 `value == 7` 后，重启调试会先停在 Int 的 7，再停在 UInt64 的 7，
随后 Double 实例会明确报条件类型不支持并保留现场。一个泛型函数条目覆盖全部已生成实例，
每次只在实际命中的实例和 frame 中读取变量。试用时关闭其他断点。

路径示例：打开 `testdata/dwarf_probe/conditional_paths/main.mbt`，在第 32 行设置
`scene.points[0].x == limit`，F5 后 `scene.point.x = 7`。可改为 `ready == true` 或
`wide == 9007199254740993`，后一种只在 `scene.point.x = 1` 时命中。

## MoonBit panic（需要本 release 对应的 CLI）

新版 moondbg CLI 在 **运行和调试 → 断点** 面板提供默认开启的 **MoonBit panic**。
无需设置源码断点，panic 时会停止并优先定位最近的项目源码 frame，支持变量、Watch 和完整调用栈。
此功能由 CLI 提供，已有扩展无需重新安装；旧版 CLI 不显示此开关。

取消勾选只关闭内部 panic 停点，不影响普通断点，也不关闭 LLDB 的 SIGABRT 停止行为。
只报告 panic，不推断 runtime 未提供的具体原因。变量不可用时如实报告；直接调试预编译 exe
缺少项目源码上下文时，会提示手动在调用栈选择 frame。

## 变量与有界摘要

String/Bytes 显示内容与长度，长内容可点击展开分段查看；Watch 支持 `text[0:128]`、
`bytes[0:32]`，String 范围按 UTF-16 单元计数。tuple/当前 enum 构造器的载荷使用 `.0`、`.1`，
例如 `pair.0`、`result.0.x`；Watch、展开面板和调试控制台共用路径规则。

复合值预览最多 2 层、每层 4 个成员、合计 16 个值、160 个 Unicode 字符，
例如 `Ok(Point { x: 3, y: 4 })`。截断显示 `…`，不限制进一步主动展开；数组元素不自动递归展开。
不调用 Debug trait 或用户函数。内存读取失败、LLDB 报告不可用和找不到变量分别提示，
找不到变量时不直接断言超出作用域。继续运行后旧变量引用失效。

这些能力来自配套 CLI，不捆绑于 VSIX。优化表示的 Option 仍依赖未合入的编译器契约，
本版不宣称完整支持 Option。tuple/enum 位置成员内部的复合元素数组暂不能索引，
例如 `values.nested.1[0]`；普通命名数组的 `items[0].x` 仍可使用。

## 已知限制与排错

- 暂不支持程序参数、环境变量覆盖、交互式 stdin、attach、会话内 restart、命中次数、logpoint、
  算术表达式、函数调用或赋值。再次 F5 开始新会话。
- 按包启动需要整个项目 `moon check` 通过，其他包或测试的错误也可能阻止启动。
- 找不到 `moondbg`：查看错误中的实际路径，检查 `moondbg.moonHome`，并用对应工具链执行安装。
- 找不到 `lldb-dap`：检查 `xcrun --find lldb-dap`。如果使用其他已安装版本，可在启动 VS Code
  的环境中设置 `MOONDBG_LLDB_DAP` 为其绝对路径；扩展不下载 LLDB。
- 没有源码红点：检查当前文件的语言模式是否为 MoonBit、语言扩展是否已启用。
- 单步行号、局部变量可见性依赖编译器 DWARF 与 LLDB。无法提供的值不等同于零或空数组。

反馈问题时请附上 VS Code、macOS、`moon version --all`、`lldb-dap --version` 的版本信息，
启动配置、错误输出和最小复现源码；请勿包含敏感环境变量。
