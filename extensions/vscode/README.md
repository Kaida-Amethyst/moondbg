# moondbg 的 VS Code DAP 连接验证

这一版由 VS Code 启动 `$MOON_HOME/bin/moondbg --dap`，验证 DAP 初始化、配置及结束会话。
**不会启动 lldb-dap 或 MoonBit 程序，也不能通过 VS Code 设置真正的 MoonBit 断点。**

扩展使用普通 JavaScript，没有 npm 依赖，不需要 `npm install` 或编译。
无需安装 VSIX、发布到 Marketplace，或卸载现有 MoonBit 扩展。

## 更新到本阶段

如果上一阶段的开发窗口仍然开着，请先关闭它，再从原窗口重新启动。仅重载旧开发窗口
不会获得新启动配置里的环境变量。

主会话会构建最新的 moondbg。以后手动更新时，先按根目录 AGENTS.md 检查开发环境，再执行：

```sh
source ~/.zshrc
set_moon_dev
moon build
```

根目录的扩展开发配置显式将新窗口的 `MOON_HOME` 设置为 `${env:HOME}/.moon_dev`，
不修改系统设置。扩展仍然检查该环境变量及其 `bin/moondbg` 软链接，不从 PATH 查找、
不执行 shell、不自动修复链接或构建。若在其他环境运行扩展，必须给扩展宿主提供相同环境。

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
   moondbg 扩展已加载。可运行 DAP 连接验证；尚不支持调试用户程序。
   ```

这一步只确认扩展加载，可以跳过；开始 DAP 会话时扩展会自动激活。

### 4. 新窗口：运行 DAP 连接验证

1. 确认新窗口打开的是 `testdata/dwarf_probe`。
2. 按 `Cmd+Shift+D` 打开“运行和调试”。
3. 在顶部下拉框选择 **moondbg：DAP 连接验证（不运行程序）**。
4. 点击绿色三角形或按 `F5`。
5. 底部会打开 **Debug Console（调试控制台）**，显示：

   ```text
   DAP 连接验证成功。未启动用户程序或 lldb-dap；验证会话已结束。
   ```

6. 调试会话自动结束，工具栏消失或恢复空闲；**开发窗口不会关闭**。可以再按 F5 重复验证。

成功提示来自 moondbg 的 DAP `output` 事件，不是扩展本地伪造的通知。
原窗口仍在调试扩展宿主；真正结束的是新窗口内的连接验证会话。
启动配置在 `testdata/dwarf_probe/.vscode/launch.json`，不需要指定 `.exe` 或先构建测试项目。

## 如何区分两个窗口

| 窗口 | 打开的目录 | 当前用途 |
| --- | --- | --- |
| 原窗口 | `moondbg` 仓库根目录 | 编辑扩展代码，启动/停止扩展开发会话 |
| 扩展开发窗口 | `testdata/dwarf_probe` | 启动 DAP 连接验证，查看成功输出 |

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
  查看扩展宿主错误；DAP 会话的输出看新窗口的调试控制台。将具体错误消息发给主会话。
- **MOON_HOME 未设置或不正确**：关闭旧开发窗口，从根目录的新启动配置重新打开。
  仅在 VS Code 内置终端里运行 `set_moon_dev`，不能改变已经运行的扩展宿主环境。
- **moondbg 路径无效**：检查 `$MOON_HOME/bin/moondbg` 是否仍是存在且可执行的软链接。
  `moon clean` 可能删除链接指向的构建产物；按 AGENTS.md 的环境问题处理规则向主会话反馈。
- **出现 REPL 提示或协议解析错误**：可能是软链接指向旧的 moondbg，旧版本不支持 `--dap`。
  请反馈实际链接目标与错误，不要将 REPL 输出当成 DAP。
- **没有代码高亮或变量窗口**：这是本阶段预期行为，连接测试没有运行任何用户程序。

## 本地静态与单元检查

在仓库根目录执行：

```sh
node --check extensions/vscode/extension.js
node --test extensions/vscode/extension.test.js extensions/vscode/launcher.test.js
MOONDBG_TOOLCHAIN_ACCEPTANCE=1 moon test acceptance/dap_connection_wbtest.mbt --no-parallelize
```

Node 测试检查启动路径、清单、命令注册与环境错误；MoonBit 门控实际启动开发版 moondbg，
验证握手、UTF-8 消息、EOF、非法输入、取消和退出。它们不代替真实扩展开发窗口验收。

`test/host.js` 是无 npm 依赖的真实 VS Code 集成测试入口，可通过官方
`--extensionTestsPath` 配合 `--extensionDevelopmentPath` 运行。它检查自动激活、真实协议
往返和断开，不调用状态命令来提前激活扩展。隔离测试时使用临时 `--user-data-dir` 和
`--extensions-dir`，避免修改日常 VS Code 配置。

## 当前协议边界

- `initialize` 只声明本阶段实际能力，随后 `launch` 必须携带 `connectionTest: true`。
- `launch` 发出 `initialized`，继续接收配置请求，不阻塞等待自身响应。
- 收到 `configurationDone` 后回复配置和启动请求，再发成功 `output` 与 `terminated`。
- 不发送虚假的 `process`、`stopped` 或 `exited`；`threads` 返回空数组。
- 编辑器已有的行断点返回未验证；不支持的请求返回失败响应。
- `disconnect` 回复后退出；提前断开取消尚未完成的 launch，不输出成功提示。
- EOF 退出；握手读取超过 15 秒无进展时报错退出。`terminated` 后最多等待 3 秒断开，
  避免客户端忘记断开时留下 adapter。
- stdout 只传 DAP。启动参数和协议错误走 stderr；不进入 readline，不启动下游 adapter。

官方参考：[Your First Extension](https://code.visualstudio.com/api/get-started/your-first-extension)。
