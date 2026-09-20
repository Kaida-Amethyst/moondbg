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

从 [GitHub Release：vscode-v0.1.1](https://github.com/Kaida-Amethyst/moondbg/releases/tag/vscode-v0.1.1)
下载 `moondbg-0.1.1-darwin-arm64.vsix`。这是技术预览，尚未上架 Marketplace。

1. 在终端使用你的 MoonBit 工具链安装 CLI：

   ```sh
   moon install Kaida-Amethyst/moondbg
   ```

   默认安装位置是 `~/.moon/bin/moondbg`。此扩展不包含 CLI，也不会自动安装或更新它。
   自动定位需要 CLI 支持 `--resolve-source`；旧 Mooncakes 包可能尚未提供此接口。
   要安装与本 release 匹配的 CLI，可在新的目录中执行：

   ```sh
   git clone --branch vscode-v0.1.1 --depth 1 https://github.com/Kaida-Amethyst/moondbg.git moondbg-preview
   cd moondbg-preview
   moon install --path .
   ```

   这会替换原来的 moondbg CLI，不会升级 MoonBit 工具链。
2. 在普通 VS Code 窗口按 `Cmd+Shift+P`，执行 **Extensions: Install from VSIX… / 扩展：从 VSIX 安装…**，
   选择 `moondbg-0.1.1-darwin-arm64.vsix`，如有提示则重新加载窗口。
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

## 已知限制与排错

- 暂不支持程序参数、环境变量覆盖、交互式 stdin、attach、会话内 restart、条件断点、
  算术表达式、函数调用或赋值。再次 F5 开始新会话。
- 按包启动需要整个项目 `moon check` 通过，其他包或测试的错误也可能阻止启动。
- 找不到 `moondbg`：查看错误中的实际路径，检查 `moondbg.moonHome`，并用对应工具链执行安装。
- 找不到 `lldb-dap`：检查 `xcrun --find lldb-dap`。如果使用其他已安装版本，可在启动 VS Code
  的环境中设置 `MOONDBG_LLDB_DAP` 为其绝对路径；扩展不下载 LLDB。
- 没有源码红点：检查当前文件的语言模式是否为 MoonBit、语言扩展是否已启用。
- 单步行号、局部变量可见性依赖编译器 DWARF 与 LLDB。无法提供的值不等同于零或空数组。

反馈问题时请附上 VS Code、macOS、`moon version --all`、`lldb-dap --version` 的版本信息，
启动配置、错误输出和最小复现源码；请勿包含敏感环境变量。
