# moondbg 的 VS Code 扩展骨架

这一版只验证本地扩展能被 VS Code 加载，并能执行一个命令。**尚未实现 DAP 服务端，
不会启动 moondbg、lldb-dap 或 MoonBit 程序，也不能通过 VS Code 设置 MoonBit 断点。**

扩展使用普通 JavaScript，没有 npm 依赖，不需要 `npm install` 或编译。
无需安装 VSIX、发布到 Marketplace，或卸载现有 MoonBit 扩展。

## 第一次打开（macOS）

### 1. 原窗口：打开 moondbg 仓库根目录

在 VS Code 菜单选择 **File → Open Folder…（文件 → 打开文件夹）**，打开：

```text
/Users/karlliu/Projects/Moonbit/moondbg
```

注意：打开的是整个仓库，不是 `extensions/vscode` 或 `testdata/dwarf_probe`。
此启动配置按单文件夹工作区编写。若有其他项目，建议通过 **File → New Window**
先开一个普通窗口，再在其中打开上述目录。

若出现 Workspace Trust（工作区信任）提示，确认目录是自己的仓库后选择信任。
只重启 VS Code 不会自动加载开发扩展；还需要下面的启动步骤。

### 2. 原窗口：启动扩展开发窗口

1. 点击左侧 **Run and Debug（运行和调试）**，图标是三角形旁边带一只小虫。
   也可以按 `Cmd+Shift+D`。
2. 在面板顶部的启动配置下拉框中，选择 **运行 moondbg 扩展（开发窗口）**。
3. 点击配置旁边的绿色三角形。也可以按 `F5`；部分 Mac 键盘需要 `Fn+F5`。
4. 等待一个新的 VS Code 窗口出现。标题通常包含
   **Extension Development Host（扩展开发宿主）**，并自动打开 `testdata/dwarf_probe`。

根目录的 `.vscode/launch.json` 负责启动这个窗口，并加载 `extensions/vscode`。
这不是独立安装的另一个编辑器，而是当前 VS Code 的扩展测试窗口。

### 3. 新窗口：验证扩展加载

1. 切换到刚打开的**新窗口**。
2. 按 `Cmd+Shift+P` 打开命令面板（不是底部 Terminal 终端）。
3. 输入 `moondbg`。
4. 选择 **moondbg: 检查扩展加载**。
5. 应出现通知：

   ```text
   moondbg 扩展已加载。当前仅验证扩展加载，尚未接入 DAP 调试。
   ```

看到这条通知，就完成了本阶段验证。此时不要在新窗口再按 F5 来调试 MoonBit；
真正的 DAP 入口将在后续接入。

## 如何区分两个窗口

| 窗口 | 打开的目录 | 当前用途 |
| --- | --- | --- |
| 原窗口 | `moondbg` 仓库根目录 | 编辑扩展代码，启动/停止扩展开发会话 |
| 扩展开发窗口 | `testdata/dwarf_probe` | 执行扩展命令，后续用于测试 MoonBit 调试 |

扩展只通过本次开发启动加载，普通窗口里找不到这个命令是正常的。

## 关闭、重载和排查

- **结束测试**：关闭扩展开发窗口即可；或在原窗口点击调试工具栏的红色停止按钮。
- **修改扩展后再试**：在开发窗口的命令面板执行
  `Developer: Reload Window（开发人员: 重新加载窗口）`，然后再次执行检查命令。
  修改启动配置后，应停止旧会话并从原窗口重新启动。
- **没有启动配置**：确认原窗口打开的是仓库根目录，并且能看到 `.vscode/launch.json`。
- **按 F5 弹出选择调试器**：先停止选择，回到“运行和调试”面板，确认选择了上述命名配置。
  本阶段不需要安装其他语言的调试扩展。
- **找不到检查命令**：确认操作的是扩展开发窗口，而不是原窗口；再尝试重载。
  扩展要求 VS Code 1.74 或更新版本。
- **启动失败**：在原窗口打开 **View → Debug Console（视图 → 调试控制台）**，
  将错误消息发给主会话。不要把扩展加载成功当作 DAP 已连接成功。

## 本地静态与单元检查

在仓库根目录执行：

```sh
node --check extensions/vscode/extension.js
node --test extensions/vscode/extension.test.js
```

这些测试检查启动路径、扩展清单、命令注册和资源释放，使用模拟 VS Code API；
它们不代替上面的真实扩展开发窗口验收。

官方参考：[Your First Extension](https://code.visualstudio.com/api/get-started/your-first-extension)。
