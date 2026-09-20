# moondbg 的 VS Code 调试

这一版由 VS Code 启动 `$MOON_HOME/bin/moondbg --dap`，再由 moondbg 启动 lldb-dap。
支持预编译 native 程序的行断点、调用栈、三种单步、继续运行、暂停、局部变量树、实时输出和停止清理。
原有 `connectionTest: true` 配置仍然只验证连接，不启动 lldb-dap 或用户程序。

暂不支持自动构建、程序参数、环境变量覆盖、交互式 stdin、attach、重启、条件断点、
算术表达式、函数调用或赋值。调试控制台支持只读变量路径（如 `point.x`、`arr[0]`），
不能输入 REPL 的 `p`、`n` 等命令。一次会话只启动一个程序，再按 F5 是新会话。

## 已完成连接验证后：开始真实调试

1. **关闭旧的扩展开发窗口**，在仓库根目录的原窗口重新选择
   **运行 moondbg 扩展（开发窗口）**并启动，让新窗口加载更新后的扩展。
2. 确认 moondbg 已按下面“更新到本阶段”一节构建并配置启动路径。
   目标程序也需要手动构建；以后改过源码或执行过 clean，需重新执行：

   ```sh
   source ~/.zshrc
   set_moon_stable
   cd /Users/karlliu/Projects/Moonbit/moondbg/testdata/dwarf_probe
   moon run main --build-only --target native -g
   ```

   此调试构建模式生成调试信息并关闭优化（`-g -O0`），不会运行用户程序。
   不要修改源码后直接调试旧 `.exe`；源码行号和 DWARF 必须对应。
3. 在**新窗口**打开 `main/main.mbt`（不是其它包的 `main.mbt`）。
   在 `let len = p.length()` 这一行（当前第 16 行）的行号左侧单击，出现红点。
4. 按 `Cmd+Shift+D`，顶部配置选择 **moondbg：调试 main（预编译）**，
   点击绿色三角形或按 F5（部分 Mac 键盘需 Fn+F5）。不要选择“连接验证”。
5. 程序停在断点，编辑器高亮当前行；左侧 **CALL STACK / 调用堆栈**显示调用栈。
   想看多层栈，可再在 `Point::length` 内部计算表达式那行（当前第 11 行）设置断点，
   继续后就能看到 `length` 与 `main`。点击调用栈中的帧可以查看对应源码位置。
6. 按 F5 或点击调试工具栏的 **Continue / 继续**。输出出现在新窗口底部的
   **Debug Console / 调试控制台**，自然运行结束后会话自动关闭。
7. 想提前结束，点击**新窗口**调试工具栏的红色方块 **Stop / 停止**。
   这会结束用户程序和本次 adapter；不要在原窗口停止整个扩展宿主。

配置位于 `testdata/dwarf_probe/.vscode/launch.json`。`program` 是可执行文件绝对路径，
可使用 `${workspaceFolder}`；`cwd` 是程序工作目录，省略时使用可执行文件所在目录。
不需要配置 lldb 的命令脚本；函数断点暂不通过 VS Code 暴露。

扩展使用普通 JavaScript，没有 npm 依赖，不需要 `npm install` 或编译。
无需安装 VSIX、发布到 Marketplace，或卸载现有 MoonBit 扩展。

## 更新到本阶段

### 单步和暂停试用

构建下面两个示例（在 `testdata/dwarf_probe` 目录，使用 stable）：

```sh
moon run dap_steps --build-only --target native -g
moon run dap_pause --build-only --target native -g
```

在扩展开发窗口选择 **moondbg：单步试用（dap_steps）**，打开 `dap_steps/main.mbt`，
在 `let second = first + 2`（第 10 行）打断点，按 F5：

1. 停住后按 F10（Step Over / 单步越过），移动到 `increment(second)`。
2. 按 F11（Step Into / 单步进入），进入 `increment`，调用栈增加该函数。
3. 按 Shift+F11（Step Out / 跳出），返回 main；再按 F5，打印 `13` 并结束。

Mac 若拦截功能键，可直接点击调试工具栏中对应的按钮，或配合 Fn。
单步的实际源码落点由 LLDB 和 DWARF 决定，跳出可能停在调用行或下一行。

然后选择 **moondbg：暂停试用（dap_pause）**，按 F5。示例会持续运行，没有输出，
点击工具栏 **Pause / 暂停**（两条竖线），应显示当前调用栈及可用的源码位置。
按 F5 继续后可再次暂停；结束时点击红色方块 **Stop / 停止**。
该示例是忙循环，会占用一个 CPU 核心，请在试用后停止。

暂停不依赖终端 Ctrl-C 或 readline。停止位置取决于按下暂停时程序正在执行哪里；
普通程序也可能停在 runtime 或系统函数中，可通过调用栈查看 MoonBit 调用者。
这里不自动跳到用户 frame。Apple LLDB 在响应主动暂停时可能报告 `SIGSTOP` 异常，
moondbg 仅将这类已请求的暂停标为 pause；实际断点、其他异常及外部 SIGSTOP 保留原始原因。

### 变量面板试用

在 `testdata/dwarf_probe` 下执行 `moon run dap_variables --build-only --target native -g`。
重新打开扩展开发窗口，选择 **moondbg：变量面板试用（dap_variables）**，
打开 `dap_variables/main.mbt`，在 `let marker = point.x` 和 `println(marker)` 两行打断点。

按 F5 停在第一处断点，在左侧 **VARIABLES / 变量 → Locals** 中：

- 展开 `point`，查看 `x = 3`、`y = 4`。
- 展开 `values`，查看 `[0] = 1.5` 等 Double 元素。
- 展开 `fixed`，共有 1000 项。VS Code 可显示分组；展开末组查看 `[999] = 1000`。
- 展开 `points → [1]`，查看 Point 字段 `x = 5`、`y = 6`。
- 展开 `list`，查看当前构造器 `Cons` 的 `.0 = 3` 和 `.1`；逐次展开 `.1`，最终到 `Empty`。
- 在 **CALL STACK / 调用堆栈** 中点击 main，Locals 切换到调用者，可查看 `caller_only = 700`。
  再选回 `inspect_values`，恢复查看被调用函数的参数。

按 F5 到第二处断点，展开 `values`，`[0]` 应更新成 `42`。旧的停止状态不会继续提供变量数据。
编译器或 LLDB 无法提供的变量会显示 `<unavailable>`；生命周期已结束的局部变量可能消失，
这不等于其值为 0 或空数组。当前仅提供 Locals（含参数），不提供 globals/registers 或修改变量。

树节点展示简短摘要，只有展开时才读取子值，不调用用户的 Debug trait 或 MoonBit 函数。
基本类型数组的每页至多读取 100 项；无分页参数或超大页请求使用可展开的范围节点，
不会静默丢弃剩余元素。递归 enum 按用户点击逐层查看，不自动展开整个链表。
Watch、悬停和调试控制台可以读取同一套变量路径，试用步骤见下一节。

### 悬停、Watch 和调试控制台试用

使用上面的 `dap_variables` 示例和两个断点，无需新增启动配置：

1. 在仓库根目录执行 `moon build --target native -g .`。确认 `$MOON_HOME/bin/moondbg`
   指向本次构建产物；结束旧调试会话，再启动扩展开发窗口。
2. 在 `testdata/dwarf_probe` 执行 `moon run dap_variables --build-only --target native -g`。
   选择 **moondbg：变量面板试用（dap_variables）**，按 F5 停在 `let marker = point.x`。
3. 将鼠标悬停在源码中的 `point` 上，查看并展开调试值。若编辑器没有识别完整的
   `point.x`，可选中完整表达式再悬停，或在 Watch 中输入它。
4. 左侧 **WATCH / 监视** 点 `+`，分别添加 `point.x`、`values[0]`、`fixed[999]`、
   `points[1]` 和 `points[1].y`；应分别看到 `3`、`1.5`、`1000`、可展开的 Point 和 `6`。
   从变量面板对可表达的节点使用 **Add to Watch / 添加到监视** 也能生成完整访问路径。
5. 打开 **Debug Console / 调试控制台**，直接输入 `points[1].x` 并回车，应得到 `5`。
   输入 `point`、`fixed` 或 `list`，结果可以按需展开。不要加 `p` 前缀。
6. 在调用栈中选择 main，再求值 `caller_only`，应得到 `700`。选择 inspect_values 时
   这个变量不在当前 frame 中，会报错，不会沿用上一个 frame 的值。
7. 按 F5 到 `println(marker)`，Watch 中 `values[0]` 应刷新为 `42`。
   可以尝试 `values[3]`（越界）和 `point.missing`（字段不存在），确认有明确错误。

支持的语法为变量名后接任意组合的 `.字段` 和 `[非负整数字面量]`，例如
`lines[0].start.x`、`matrix[1][2]`；允许首尾空白，不允许路径内部空白。
暂不支持 `arr[i]`、`list.0`、包级变量、算术、赋值、函数调用或 REPL 命令。
enum 本身仍可求值并通过树展开载荷；暂不为其数字载荷生成 Add to Watch 表达式。
路径最多 4096 个字符、64 个后缀，防止意外的大输入占用调试会话。

求值要求暂停且选中有效的调用栈 frame；不带 frameId 的协议请求表示全局求值，当前明确拒绝，
不会隐式选择另一个 frame。三个入口共用 DAP `evaluate` 和已有变量探查服务；返回的展开引用
在继续、单步、退出或断开后失效。只解析白名单路径，不将用户原始文本交给 LLDB 执行命令。
协议依据：[DAP Evaluate](https://microsoft.github.io/debug-adapter-protocol/specification#Requests_Evaluate)。

### 构建和启动路径

如果上一阶段的开发窗口仍然开着，请先关闭它，再从原窗口重新启动。仅重载旧开发窗口
不会获得新启动配置里的环境变量。

在仓库根目录按 AGENTS.md 检查 stable 环境，并构建最新的 moondbg：

```sh
source ~/.zshrc
set_moon_stable
moon build --target native -g .
ls -l "$MOON_HOME/bin/moondbg"
```

产物为 `_build/native/debug/build/moondbg.exe`。扩展只启动
`$MOON_HOME/bin/moondbg --dap`，不会使用终端里的 `alias moondbg`。
如果该路径尚不存在，可在仓库根目录手动建立链接：

```sh
ln -s "$PWD/_build/native/debug/build/moondbg.exe" "$MOON_HOME/bin/moondbg"
```

如果已有文件或链接，先检查其来源和目标，不要直接覆盖。普通可执行文件和有效软链接都可用；
复制安装的文件需要在重新构建后另行更新，链接则直接使用仓库本次构建的产物。

根目录的扩展开发配置显式将新窗口的 `MOON_HOME` 设置为 `${env:HOME}/.moon`，
同时将 `${env:HOME}/.moon/bin` 放在 PATH 最前面，不修改系统设置。
扩展接受显式指定的其他绝对 MOON_HOME 路径，不限定安装目录或要求软链接；它不从 PATH
查找 moondbg、不执行 shell、不自动修复链接或构建。若使用自定义工具链，应同步调整开发
启动配置的 MOON_HOME 和 PATH，并重新启动扩展宿主。

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
   moondbg 扩展已加载。支持已编译程序的行断点、调用栈、单步、继续和暂停。
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
| 扩展开发窗口 | `testdata/dwarf_probe` | 调试用户程序，或单独运行连接验证 |

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
  仅在 VS Code 内置终端里运行 `set_moon_stable`，不能改变已经运行的扩展宿主环境。
- **moondbg 路径无效**：检查 `$MOON_HOME/bin/moondbg` 是否为可执行文件或有效的可执行文件软链接。
  `moon clean` 可能删除链接指向的构建产物；按 AGENTS.md 的环境问题处理规则向主会话反馈。
- **出现 REPL 提示或协议解析错误**：可能启动了不支持 `--dap` 的旧 moondbg。
  请反馈实际文件路径（如果是链接，包含链接目标）与错误，不要将 REPL 输出当成 DAP。
- **没有停住**：确认选的不是连接验证配置，断点在可执行语句上，且 `.exe` 对应最新源码。
- **无法在行号旁打断点**：确认 `.mbt` 的语言模式是 MoonBit，开发窗口已加载 MoonBit 语言扩展。
- **没有变量**：先确认程序已停住并选择了用户 frame；runtime frame 可能没有可用的局部变量。
  若显示 `<unavailable>`，说明当前 DWARF/寄存器位置无法提供该值，不会使用旧停点的值补齐。
- **单步不可用**：单步只能在程序停住时使用；暂停只能在运行时使用。
  不支持指令级单步、指定调用目标的 step-in 或只运行某一线程。
- **求值时报错**：确认程序暂停且选中了用户 frame。直接输入 `point.x` 或 `arr[0]`，
  不要加 `p`；算术、调用、赋值和动态下标尚不支持。变量也可能已超出当前作用域。

## 本地静态与单元检查

在仓库根目录执行：

```sh
node --check extensions/vscode/extension.js
node --test extensions/vscode/extension.test.js extensions/vscode/launcher.test.js
MOONDBG_TOOLCHAIN_ACCEPTANCE=1 moon test acceptance/dap_connection_wbtest.mbt --no-parallelize
MOONDBG_TOOLCHAIN_ACCEPTANCE=1 moon test acceptance/dap_live_wbtest.mbt --no-parallelize
MOONDBG_TOOLCHAIN_ACCEPTANCE=1 moon test acceptance/dap_control_wbtest.mbt --no-parallelize
MOONDBG_TOOLCHAIN_ACCEPTANCE=1 moon test acceptance/dap_variables_wbtest.mbt --no-parallelize
MOONDBG_TOOLCHAIN_ACCEPTANCE=1 moon test acceptance/dap_evaluate_wbtest.mbt --no-parallelize
```

Node 测试检查启动路径、清单、命令注册与环境错误；MoonBit 门控实际启动仓库本次构建的 moondbg，
验证握手、UTF-8 消息、EOF、非法输入、取消和退出。它们不代替真实扩展开发窗口验收。

`test/host.js` 是无 npm 依赖的真实 VS Code 集成测试入口，可通过官方
`--extensionTestsPath` 配合 `--extensionDevelopmentPath` 运行。它检查自动激活、真实协议
往返和断开，不调用状态命令来提前激活扩展。隔离测试时使用临时 `--user-data-dir` 和
`--extensions-dir`，避免修改日常 VS Code 配置。

## 连接测试的协议边界

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

## 真实调试的协议和实现边界

- `initialize` 声明 moondbg 本轮实际支持的能力，不转发 LLDB 的完整 capabilities。
  当前仅接受本机路径及从 1 开始的行列号。
- `launch` 验证 `program`/`cwd` 后启动 adapter；收到 LLDB `initialized` 后才接受配置。
  `setBreakpoints` 对每个文件整批替换，空数组清空该文件。实际落点和 verified 状态来自 LLDB。
- 客户端输入和 adapter 输入分别由后台任务读取，进入有界队列，由同一个循环分派状态和写消息。
  启动/继续/单步的响应与随后发生的 stopped、output、exited 事件独立，因此运行期间仍能处理 pause 和 disconnect。
- `next`/`stepIn`/`stepOut` 使用 LLDB 默认源码单步；`pause` 只发送暂停请求，收到 stopped
  后才开放栈查询。拒绝重复恢复执行、重复暂停及无效状态请求；请求失败时只恢复属于本次
  请求的状态，不允许迟到的失败响应覆盖新停点或进程退出。
- `threads`/`stackTrace` 复用 LLDB 的线程和帧信息；可识别的 MoonBit 符号名使用已有 demangler。
  对外 frameId 和 variablesReference 由 moondbg 分配，绑定当前暂停状态；继续、单步、退出
  或断开后失效，并且不复用旧编号。`scopes` 提供 Locals，`evaluate` 支持只读变量访问路径。
- 一次会话只拥有一个启动的进程；disconnect 始终使用 `terminateDebuggee: true`，不支持 detach。
  EOF、异常和超时也尝试 disconnect，随后关闭传输并取消 adapter。配置/请求超时为 15 秒，
  结束握手窗口为 3 秒；正常运行或停在断点等待用户操作没有空闲超时。
- `dap.open_transport` 是与 REPL 共享的底层进程/帧传输；本轮没有让 DAP 绕进 REPL 的
  `DebugSession::run -> RunOutcome` 等待事务。`lldb_dap.VariableInspector` 是共享变量探查
  服务，复用类型识别、数组布局、enum tag、内存读取和同名局部变量解析；REPL 保留原有的
  有界文本渲染，DAP 使用路径式变量树。该服务不拥有 adapter，也不读取协议管道。
- DAP 的变量探查在串行后台任务中执行，通过主消息循环发送请求、获取响应；主循环始终
  能接收 continue/disconnect。每个变量任务绑定 stop epoch，恢复执行会立即取消其对外响应。
  每次展开重新建立对应 frame 的 scope 上下文，通过源级路径定位，避免 LLDB 复用原始引用。

`test/live-host.js` 是真实 VS Code 集成测试入口：默认验证编辑器行断点、自动调用栈请求、
继续和自然退出。若设置 `MOONDBG_TEST_RUNNING_PROGRAM` 为使用 cc 编译的
`testdata/dap_running/main.c` 的绝对路径，则验证运行中实时输出和 VS Code Stop 操作，
并确认目标 PID 已退出。可像 `test/host.js` 一样通过 `--extensionTestsPath` 在隔离宿主运行，
`MOONDBG_VSCODE_TEST_RESULT` 指定 JSON 验收记录路径。

DAP 时序依据：[Debug Adapter Protocol overview](https://microsoft.github.io/debug-adapter-protocol/overview)。
