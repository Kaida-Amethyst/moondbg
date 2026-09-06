# T-07. 断点列表、删除与启停管理

> 最后更新日期：2026-09-06
> 仓库：moondbg
> 记录者：Codex

## 主题描述

本轮在已有源码行断点、精确函数断点和 MoonBit function family 断点上，增加完整的基本
管理闭环：用户能查看已配置的断点，删除不再需要的断点，临时禁用并重新启用断点；重新
`run` 后保留用户配置。

```text
(moondbg) breakpoints
... 按稳定编号显示源码断点和函数断点 ...
(moondbg) disable 3
... 确认断点 3 已禁用 ...
(moondbg) continue
... 当前 execution 不再命中断点 3 ...
(moondbg) enable 3
... 确认断点 3 重新启用，并报告安装结果 ...
(moondbg) delete 2
... 确认断点 2 已删除 ...
```

上例是交互语义示意，不固定最终英文输出文案。方案、状态边界和任务划分统一记录在本
文档，不拆分 Q 文档。

本轮主要修改 moondbg，不预设修改 readline、async、moon 或 ideas5。命令在用户提交输入
后执行，不依赖 Ctrl-C 暂停、运行中输入或编辑期间异步输出重绘。

## 关联主题

- [Q-01. 函数名解析与泛型函数断点](Q-01-function-name-resolution.md)：复用函数名解析、
  family selector 和底层匹配逻辑。
- [Q-02. Stopped 状态动态新增断点](Q-02-dynamic-breakpoints-while-stopped.md)：复用持久
  逻辑配置与 execution 安装结果的分离，以及停止时动态同步能力。
- [T-03. 持久 REPL 与 execution 生命周期](T-03-persistent-repl-and-execution-lifecycle.md)：
  复用重复运行、故障回收和 adapter 预热。
- [T-05. 项目架构重构](T-05-project-architecture-refactoring.md)：沿用独立命令文件、领域
  接口、adapter 边界和结构化 presentation。

## 用户交互与本轮边界

### 1. 命令

| 命令 | 行为 |
| --- | --- |
| `breakpoints` | 按稳定编号升序列出所有未删除的逻辑断点，包括禁用和安装失败的断点 |
| `delete <id>` | 删除一个逻辑断点；存在 stopped execution 时同步移除底层断点 |
| `disable <id>` | 保留编号和目标配置，但不再让该断点打断程序 |
| `enable <id>` | 恢复启用；存在 stopped execution 时立即同步并报告结果 |

三个管理命令只接受一个十进制正整数编号。缺少编号、非法编号、不存在或已删除的编号、
额外参数均返回明确错误，不修改其他断点。无参数 `delete` 不能解释为删除全部断点。
重复启用或禁用是幂等操作，报告当前状态，不重复创建底层断点；删除不要求交互确认。

本轮不增加命令缩写、多编号、范围、批量清空、条件断点、命中次数、临时断点、watchpoint、
线程筛选或关闭 moondbg 后的配置落盘。重复执行 `b` 的行为维持现状，不顺带引入目标去重。

### 2. 状态与持久性

- `Ready`：可以管理逻辑配置，不为这些命令启动 debuggee，也不等待后台 adapter 预热。
- `Stopped`：管理命令等待底层同步结果后再返回提示符；成功的删除或禁用对紧接着的
  `continue`、`next`、`step`、`finish` 生效。
- 其他状态：修改命令继续拒绝，不引入 Running 状态下的并发修改；正常 execution 结束后
  外层会话沿用已有逻辑回到 `Ready`。
- 列表始终可以返回会话持有的逻辑配置；没有当前有效 execution 时，不为查询列表创建
  target。实际安装信息缺失时明确标记，不阻塞等待预热。
- 所有断点共用同一套稳定编号。编号在一次 DebugSession 中单调递增，不因删除而重排或
  复用。重新 `run` 保留剩余断点的编号、目标和启用状态，底层 ID 则重新建立。
- 成功修改断点不恢复程序执行，不改变所选 frame，也不使当前有效变量缓存无故失效。

### 3. 列表内容

每个逻辑断点以一条主记录呈现，至少包含：

1. 稳定编号与目标种类；
2. 用户期望的启用状态；
3. 请求位置：源码路径与行号，或用户输入的函数名（保留包别名）；
4. 当前安装结果及失败原因；
5. adapter 能可靠提供的实际源码落点；多落点断点显示位置汇总，不伪装成唯一落点；
6. function family 的已解析 location 数量。

源码请求保留用户可识别的展示路径，独立保存用于同步的规范路径。启用状态和安装结果
是两个字段：`enabled` 不等于 `verified`，`disabled` 也不等于安装失败。

当前 `location_count` 表示 LLDB 断点位置数量，不严格等于泛型单态化实例数量。本轮显示
`N locations`，不声称这是精确的“N 个泛型实例”；按符号去重统计实例不在本轮范围内。

尚未运行、底层没有提供源码位置或安装失败时，位置/count 可以未知，未知不能写成 0。
禁用后保留的旧解析信息只能标为上次结果；execution 结束或重建后，不能把旧 ID、旧落点
冒充当前安装结果。对于多落点，主列表使用数量和代表性位置汇总，明细输出必须有界。

## 建议的实现方案

### 1. DebugSession 拥有权威配置

将现有“仅可追加”的断点存储升级为按稳定 ID 管理的逻辑配置。源码目标和函数目标仍保留
各自的强类型信息，共用编号、启用状态、管理结果和列表视图；具体内部容器不由 REPL 决定。

`DebugSession` 校验状态和 ID，维护逻辑配置，通过 `DebugBackend` 请求同步。列表和管理
结果先形成 backend 无关的领域对象，再由 renderer 输出。未来 AI/DAP frontend 不需要
解析表格、LLDB 命令输出或用户错误字符串。

### 2. 替换按数组长度导入的同步方式

当前 `LldbDapBackend` 的 `imported_source_breakpoints` 和 `imported_function_breakpoints`
只记录已导入数量，只适用于 append。删除中间元素、改变启用状态以及随后新增断点都会
破坏这一假设。

应统一为按稳定 ID 比较目标配置与当前安装记录的同步机制：

- application 配置是唯一权威来源，backend 不再维护一套可独立修改的长期逻辑真相；
- execution 保存本次运行的已应用目标、底层句柄、解析结果和同步状态；
- 添加、删除和启停使用同一同步基础设施，不能为新增保留计数器、为删除再补特殊分支；
- 下一次运行从当前配置重新安装启用项，不使用旧 execution 的 ID 或安装快照。

同步范围仍按 adapter 语义决定，不因“全量目标配置”而每次重建所有 family 断点。

### 3. 三类底层断点分别同步

| 类型 | 同步方式 |
| --- | --- |
| 源码行 | 对受影响 source 发送全部启用行断点的 `setBreakpoints` |
| 精确函数 | 发送全部启用精确函数断点的 `setFunctionBreakpoints` |
| MoonBit function family | 用当前 execution 的 LLDB breakpoint ID 管理对应 regex 断点 |

源码和精确函数请求是集合替换，而非单点追加。删除或禁用最后一项时必须发送空数组；
当前精确函数配置函数中“空集合直接返回”的逻辑必须调整。响应可能改变底层 ID，应刷新
整个受影响集合的映射。

family 使用已有 DAP `evaluate(context="repl")` 的 LLDB 命令通道。禁用保留已创建的
family 句柄，重新启用复用句柄，删除则清除句柄；尚未安装的禁用项不创建底层断点，之后
启用时才安装。一次逻辑管理操作覆盖该 family 的全部 locations。

必须明确区分 DAP breakpoint ID 与 LLDB breakpoint ID，不能仅凭整数相同或当前共用
`dap_id` 字段就混用。对于创建了零 location 的 LLDB breakpoint，即便用户结果是 rejected，
仍需保留其清理句柄，避免删除逻辑项后留下未管理的底层断点。

P1 先用真实 adapter 验证 DAP 集合替换与 LLDB family 命令混用时的隔离行为。底层命令
只接收内部生成的合法句柄，不直接插入用户命令文本；不引入 Python formatter 或脚本依赖。

### 4. 实际落点与安装快照

扩展当前 `BreakpointSnapshot`、`FunctionBreakpointSnapshot` 和 execution outcome，
保留可用的实际源码路径、行及多落点信息，而不只保留行号或数量。

DAP 返回的结构化字段优先使用。family 的位置补查局限于 `lldb_dap` 内部，复用既有 LLDB
命令通道并以 P1 验证的输出契约解析；信息无法可靠识别时返回未知及必要诊断，不猜测位置。
查询数量和展示数量要有界，不为列表无界展开所有泛型落点。

补查失败不能掩盖已经确认成功的启停操作；“操作是否成功”与“位置详情是否可用”分别记录。

### 5. 失败处理

以下为本方案建议的默认行为，不改写 Q-02 对“新增失败仍保留逻辑断点”的既有约定：

1. 新增、启用后无法解析目标：保留启用配置，显示 pending/rejected，允许下次运行重试；
2. 删除、禁用：只有当前 execution 已确认同步成功，才向用户确认操作完成；不能只改
   本地状态后报告成功；
3. adapter 明确拒绝管理操作，且能确认当前安装配置未改变：保留操作前的逻辑配置，
   报告失败，当前停止上下文仍可继续使用；
4. 连接断开、响应不完整或多步同步部分完成，无法确认实际配置：沿用已有故障回收
   路径，不允许在状态不确定的 execution 上继续执行；管理操作不报告成功，保留删除/
   禁用操作前的逻辑配置，后续 `run` 重建。错误信息须说明当前 execution 已被回收；
5. 无论失败发生在哪一步，都不能让已删除项在下一次 `run` 复活、让用户 ID 错配到其他
   断点，或把某一项的失败误报成全部断点同步成功。

每次用户操作是领域层事务。不能假设 LLDB/DAP 的多步操作具有原子性；无法证明未改变
时按第 4 条处理，而不是假装回滚底层已经成功。

## 改动范围

- 根包：断点配置、统一列表/操作结果、`DebugSession` 管理方法及 `DebugBackend` 同步契约。
- `lldb_dap`：移除 append-only 导入模型，增加三类断点的管理、句柄生命周期、快照与恢复。
- `dap`：仅按需要补齐通用协议字段，不加入 MoonBit 断点业务规则。
- `repl`：新增 `breakpoints.mbt`、`delete.mbt`、`disable.mbt`、`enable.mbt`，各自实现独立
  Command struct 和 `ReplCommand`；注册命令、帮助及结构化输出。
- 测试：领域测试、scripted/fake adapter、REPL 测试和门控真实工具链验收。
- `testdata/dwarf_probe`：可新增专用包，提供多次调用、同一文件多个断点和泛型多落点场景。

## 待决策问题

暂无必须在实施前由用户决策的产品分歧。上述单编号语法、编号不复用、未知信息展示和
失败处理作为本方案的建议默认行为，供本次 review 一并确认。

P1 的底层 ID、混合管理和位置查询属于技术验证，不作为产品选择交给用户猜测。若验证
发现现有 adapter 无法满足本方案，或需要修改外部依赖、扩大产品范围，则暂停并报告，
不能静默降低为“只改配置、当前执行不生效”。

## 任务划分

按 `P1` 至 `P6` 顺序推进，阶段状态为“待实施”“进行中”“已完成”或“阻塞”。本文件只记录
计划，不代表任何阶段已经验收。

### P1. 验证 adapter 管理语义与落点信息

**状态：已完成（主会话独立复跑 30 项检查通过，已 review）**

**工作内容：**

1. 在专用或已有 fixture 上验证源码、精确函数与 family 断点的删除、启停和再次命中。
2. 验证空集合清空、集合替换后的 ID 更新、三类断点混用及互不误删。
3. 验证零 location family 的句柄保留与清理，以及 family 所有 locations 一起禁用。
4. 确定函数落点/count 查询契约和有界展示策略，区分可靠字段与未知信息。
5. 保留可复跑的请求/响应证据，并记录当前 adapter 的限制。

**完成条件：** 明确三类断点的同步路径、底层 ID 所属和成功/失败判据，没有尚未解决的
协议阻塞；测试程序可用于后续手动观察。

#### P1 验证结果（2026-09-06）

新增 `testdata/dwarf_probe/breakpoint_management`：连续三轮调用普通函数 `ordinary`、
`identity[Int]` 和 `identity[Double]`，第一轮末尾设置独立源码 checkpoint，能够观察
“禁用两个泛型落点但普通/源码仍命中—启用后两个泛型落点再次命中—删除后第三轮直接结束”。
验证使用 `tools/breakpoint_management_probe.py` 复用现有原始 DAP 探针基础，独立于产品
断点实现；它是显式开发诊断，不是运行时 Python 依赖，也不加入默认测试的外部环境要求。

当前 adapter 为 `lldb-2100.0.17.203`（Apple Swift 6.3.3）。30 项检查全部通过：

| 验证项 | 观察与后续实现约束 |
| --- | --- |
| 源码/精确函数集合替换 | 两者的空数组均真正清空自己的集合；不删除另外一类，也不删除 LLDB regex family |
| 底层 ID 生命周期 | 本次源码 ID 2/3、精确函数 ID 1/4；清空再加变成 7/8；始终重新读取整组响应，不假定 ID 保持 |
| 重复逻辑目标 | 重复源码行返回同一 DAP ID（2/2）；重复精确名称也是同一 ID（4/4）；删掉一个重复目标后剩余项仍 verified。逻辑 ID 与底层 ID 是多对一，不能按逻辑项直接删除共享句柄 |
| DAP/LLDB ID | 当前 adapter 的 DAP ID 数字可在 LLDB `breakpoint list` 查到；family 5 的两次 stopped 都返回 `hitBreakpointIds: [5]`。这只是当前 adapter 的映射证据，仍分别保存/标明 DAP 与 LLDB 句柄来源 |
| 零 location | 创建返回 `Breakpoint 6: no locations (pending).`，但 LLDB 6 确实存在；`breakpoint delete 6` 后才消失，rejected 结果不得丢清理句柄 |
| family 启停 | `breakpoint disable 5` 禁用全部 locations；普通函数仍命中，两个 generic 调用均跳过并停在 checkpoint。`enable 5` 复用原句柄，随后依次命中 5.1/5.2 两个不同 PC |
| 删除 family | 删除 5 后第三轮两个 generic 调用均不再停止，程序正常结束 |
| 命令失败 | 无效 `breakpoint disable/delete` 的 DAP `evaluate` 仍可能 `success: true`，但 `body.result` 是 `error:`；必须核验具体操作确认文本，不能只核验 DAP success |

启停的已验证成功文本分别是 `1 breakpoints disabled.`、`1 breakpoints enabled.`；
删除成功文本为 `1 breakpoints deleted; 0 breakpoint locations disabled.`。解析时允许
末尾换行差异，但未知文本不能当作已确认成功。错误/未知结果进入前文定义的失败分类，
需要确认操作未改变时才保留当前 execution。

**落点信息与有界补查契约：**

1. 源码和精确函数的 DAP `Breakpoint` 响应可直接提供 `source.path`、`line`、`column`
   和 `instructionReference`，优先保存这些结构化字段；不把响应的一个位置说成所有位置。
2. family 先发送 `breakpoint list --brief <LLDB ID>`，其 summary 提供 `locations = N`，
   不展开 locations。`breakpoint list <ID>.1` 实测仍打印全部 locations，不能用作分页。
3. 本轮将详细补查上限固定为 **8 locations**：仅 count 在 1..8 时使用 `--full <ID>`；
   count 大于 8 或无法识别时不发送 full。零 location 保留句柄和已知 0；查询失败才是未知。
4. full 中的 `at main.mbt:9:16` 只有 basename，不能擅自拼规范路径。解析至多 8 个内部
   address，对每个地址发送 `disassemble(memoryReference=address, instructionCount=1,
   resolveSymbols=false)`；当前 adapter 返回结构化 `location.path`、`line`、`column`。
   两个 generic locations 均已验证到 fixture 完整源码路径的第 9 行。
5. 列表最多显示 3 条代表位置；有界补查的结果不足或 count 超过 8 时，可以只有 count
   而没有代表位置，明确显示源码位置未知。不得仅为得到代表位置无界读取整个 family。
6. address/文本无法解析、adapter 不支持 disassemble 或返回无源码时，位置详情为未知；
   不否认已经确认成功的启停/删除。count 是 LLDB location 数，不是单态化实例统计。

当前工具链 `stackTrace.name` 返回 `$包.identity|[Int]|` / `$包.identity|[Double]|`，
不是二进制 linkage 名的 `GiE` / `GdE` 后缀。探针校验实际源码名、family ID、两个不同 PC
与 LLDB location 明细的对应关系。最初失败是探针误用了 linkage 名断言，不是启用失败；
原始请求、响应、stopped 与 frame 均保留在探针生成的证据中。

**复跑：**

```sh
source ~/.zshrc
set_moon_dev
cd testdata/dwarf_probe
printf 'quit\n' | moon debug breakpoint_management
cd ../..
PYTHONDONTWRITEBYTECODE=1 python3 tools/breakpoint_management_probe.py \
  --output _build/breakpoint_management_probe.json
```

JSON 保存全部有序请求/响应以及命中现场；探针失败返回非零，退出时 disconnect 并回收
自身 adapter/debuggee。动态地址与本地路径证据不提交到仓库，通过上述命令重新生成。

本阶段没有修改产品功能或外部工具链。主会话另行发现的既有门控验收中 generic 名称、
enum 可用性和 shadowing 差异，不属于本探针管理语义的失败，也不能用本阶段通过替代
旧验收；后续阶段应单独记录这些基线问题。

默认测试 228/228 通过，`moon check` 通过。`moon info` 同时将两份生成接口中损坏的
`StringView` 参数文本恢复为正确类型；已核对没有实际 API 变更。

### P2. 建立可修改的逻辑配置与同步契约

**状态：已完成（主会话 review 与独立检查通过，236/236 测试通过）**

**工作内容：**

1. 增加启用状态、按 ID 管理和统一列表/操作结果，保持编号单调且跨 run 稳定。
2. 调整 backend 接口与配置传递，移除按已导入数量同步的假设。
3. 统一添加和管理操作所用的同步基础，定义配置事务及失败恢复边界。
4. 更新测试 backend，覆盖中间项删除后再新增、重复启停、非法 ID、状态限制及失败配置。

**完成条件：** 领域测试能证明编号、目标、状态和配置所有权正确；已有添加断点及重复
运行行为不回退，REPL 不接触底层句柄。

#### P2 实施结果（2026-09-06）

- `SourceBreakpoint` / `FunctionBreakpoint` 增加不可变 `enabled`；源码配置独立保存
  `display_path` 和规范 `source_path`，原 `b` 命令已把用户输入路径传到领域层。
- `DebugSession.breakpoint_configuration()` 返回防御性复制的完整配置，backend 无法通过
  修改收到的数组改写权威配置。删除不复用 ID，重复目标仍是独立逻辑项；重跑只安装启用项。
- 增加统一 `breakpoints()` 视图与 `manage_breakpoint(id, operation)`；列表使用 ID Map
  汇总并按稳定编号排序，启用意图与 `NotInstalled / CurrentInstallation /
  PreviousInstallation` 分开，不把 Ready 后的旧 verified 信息冒充当前安装。
- backend 的旧两个 `install_*` 入口被统一 `synchronize_breakpoints(configuration)`
  取代；结果必须为每个启用逻辑 ID 返回唯一、匹配目标的 snapshot。遗漏、重复或错配结果
  按不确定处理，不能把缺失响应伪装成 pending 后确认管理成功。
- 删除/禁用仅在同步确认后提交配置；明确未修改的拒绝保留 stopped 上下文。启用的无法
  解析结果保留 enabled 与 rejected snapshot；不确定故障回收 execution、保留启用意图。
  新增依然遵循 Q-02：先保留逻辑项，失败后可在下一次 run 重试。
- 增加 `abandon_execution` 后端能力，回收不确定执行但允许重新 run；错误明确附带
  `current execution was discarded`。成功管理不改变 stop epoch、所选 frame 或变量观察。
- `LldbDapBackend` 已去掉两个导入数量游标与旧 import helper。每次 launch 用当前配置
  替换执行副本；停止时按稳定 ID 比较配置并复用已有动态新增实现。**本阶段尚未实现的
  底层删除/禁用在发出任何 DAP 请求前明确拒绝**，不提前替换执行副本或假报成功；P3/P4
  在同一个同步入口内继续补齐协议操作。REPL 四个新管理命令仍留给 P5。
- 新增独立领域与 adapter 管理测试文件，覆盖中间删除再新增、重复目标其中一项禁用、
  跨 run 编号/启用状态、防御性复制、幂等/非法 ID/状态限制、rejected 启用、不确定启用、
  删除/禁用失败配置保留、不完整响应回收，以及非零 frame 1 的 stop/观察保持。
- `moon info && moon fmt`、`moon check` 通过，无新增警告；默认 `moon test` **236/236**。
  生成接口变更对应本阶段领域值与 backend 契约。已知旧真实门控基线差异未修改或弱化。

### P3. 实现源码与精确函数断点管理

**状态：已完成（主会话 review 与独立检查通过，242/242 测试通过）**

**工作内容：**

1. 按受影响范围同步启用集合，正确处理空数组与整组响应。
2. 更新当前 execution 映射，清除已删除或禁用项的当前安装记录。
3. 接入实际路径/行快照，处理拒绝、响应缺失和连接失败。
4. 验证重新 run 只安装启用项，删除最后一项和改变中间项不会污染后续同步。

**完成条件：** 源码与精确函数的管理对当前 execution 和后续 run 都生效，失败不伪报成功。

#### P3 实施结果（2026-09-06）

- 统一同步入口按受影响的源码文件替换行断点集合，按完整启用集合替换精确函数断点；
  删除或禁用最后一项会显式发送空数组。初次 launch 没有精确函数断点时仍不发送多余请求。
- 整组响应重新映射到逻辑 ID，不按单个逻辑项删除 DAP 句柄；两个相同源码/精确目标共享
  DAP ID 时，禁用其中一个不会删除另一个。成功后才更新执行副本并移除失效安装记录。
- 增加结构化 `BreakpointLocation` 与列表 `locations`，保存 adapter 实际返回的路径、
  行、列及 instruction reference；没有返回的字段保持未知，不把请求路径冒充实际落点，
  不把 DAP 返回的一个代表位置推断为总 location count。
- 响应必须包含长度精确匹配的 `breakpoints` 数组，每项 `verified` 与可选字段类型必须
  正确；整组解析完成后才写入快照。单项 `verified: false` 是正常的 rejected 安装结果，
  启用意图仍保留；request 失败、不完整/畸形响应或连接结束均按不确定处理并回收 execution。
  删除/禁用失败保留旧逻辑配置，随后重新 run 可以重新安装。
- 初次 launch 的严格解析失败同样会回收 adapter，并允许下一次 run；未实现的 family
  删除/禁用在任何源码或精确函数请求之前预检拒绝，避免部分执行后错误声称配置未改变。
  family 底层管理仍留给 P4，REPL 新命令仍留给 P5。
- 独立 adapter 管理测试覆盖重复目标、最后一项空集合、禁用后重启、rejected 再启用、
  完整响应校验、源码/精确函数空数组操作的三类故障与重跑恢复，以及非零 frame 1 和
  stop epoch 保持。旧动态添加测试改用同一同步入口，区分单项未解析与协议级失败。
- `moon info && moon fmt`、`moon check` 通过，无新增警告；默认 `moon test` **242/242**。
  生成接口变更仅对应结构化落点与统一列表字段；没有修改或弱化已知旧真实门控基线差异。

### P4. 实现 function family 管理与落点快照

**状态：已完成（主会话 review、250/250 测试与真实函数断点链路通过）**

**工作内容：**

1. 显式管理 LLDB family 句柄，完成删除、禁用、启用及未安装项的首次安装。
2. 保证重复启停不重复创建，零 location/rejected 句柄也能清理。
3. 接入 location count 和可用源码落点，区分当前结果、历史结果与未知。
4. 增加多 location、混合断点、部分失败与跨 execution 重建测试。

**完成条件：** 一个逻辑 ID 控制完整 family；不会误用旧 ID，也不会遗留隐藏断点或
把 locations 数量当作精确泛型实例数。

#### P4 实施结果（2026-09-06）

- `ExecutionBreakpointState` 独立保存逻辑 ID 对应的 family 句柄及启用状态；LLDB 句柄
  使用专用 `LldbBreakpointId` 类型，不再放入 DAP `dap_id` 字段。相同目标的多个逻辑
  family 分别拥有自己的句柄，不影响源码/精确函数集合及其他 family。
- 同步入口额外接收完整 family 配置，包括禁用项，以区分禁用与删除。禁用保留句柄，
  重新启用复用；删除释放句柄及结果；从未安装的禁用项不创建底层断点。重新 run 使用
  新 execution，旧句柄不跨次复用，禁用项之后启用才首次安装。
- 零 location 的创建结果保留 LLDB 句柄，用户快照仍为 rejected，已知 count 为 0；
  禁用、启用及删除均可管理。启用确认不等于已解析，后续详情未知时保留此前 rejected
  状态，count 与位置详情置为未知，不擅自升级为 verified。
- 创建结果只接受已验证的零落点、多落点及单地址格式，未知文本不再默认一个 location。
  启停/删除严格匹配确认文本；`evaluate.success: true` 内含 `error:` 或未知文本也按
  不确定处理并回收 execution，保留领域层既定的配置事务语义。
- 创建/启用后先查询 brief；仅可靠 count 在 1..8 时查询 full，再对至多 8 个地址分别
  请求单条 `disassemble`。校验 summary/各 location 的父 ID、数量和十六进制地址；
  若指令响应提供 address，按数值核对请求地址（允许大小写与前导零差异）。源码信息仅用
  结构化响应，不从 basename 猜路径。P5 的列表展示仍最多取 3 个代表位置。
- 可选详情请求被拒绝、不支持、缺字段或无法解析时，仅位置详情未知，不否认已确认的
  创建/启用；创建响应本身明确给出的 count 可保留，但 brief 未知时仍不发送 full。
  真正的连接结束/传输失败则回收 execution，不保留虚假的可继续状态。禁用/删除确认后
  不发送多余详情查询，禁用句柄保留既有内部快照供后续状态判断。
- 专项测试覆盖重复 family 与混合断点隔离、幂等启停、零落点、禁用未安装项、非零
  frame 1/stop epoch 保持、8/9 上限与未知 summary、错误地址/不支持 disassemble、
  12 组管理失败、部分 launch 已安装源码后的 family 故障，以及跨 execution 新句柄。
- `moon info && moon fmt`、`moon check`、`git diff --check` 通过，无新增警告；默认
  `moon test` **250/250**。接口仅为 rejected 函数快照增加可选 `location_count`，用于
  表达已知零落点。真实 REPL 管理闭环仍由 P5/P6 接入和验收，旧门控基线差异未改写。
- 主会话独立 `moon check`、`moon test`、`moon build` 通过；真实执行
  `moon debug breakpoint_management`，依次命中 main、ordinary、identity 的 Int/Double
  两个落点并正常退出，确认新增 family 创建与详情查询没有破坏实际调试链路。

### P5. 接入四个 REPL 命令

**状态：已完成（主会话 review、258/258 测试与真实停止提示验收通过）**

**工作内容：**

1. 按独立命令文件/struct/trait 接入 `breakpoints`、`delete`、`disable`、`enable`。
2. 增加严格参数解析、帮助、空列表、非法 ID、幂等操作及失败反馈。
3. renderer 输出按 ID 排序的混合列表，区分启用、安装和信息可用性。
4. 增加命令、presentation 与输出测试，保持原有 `b` 行为兼容。

**完成条件：** 四个命令通过统一领域接口工作；命令文件不拼 DAP/LLDB 请求，不解析
adapter 原始输出，列表能够清楚表达待安装、禁用、失败和多落点状态。

#### P5 实施结果（2026-09-06）

- 新增 `breakpoints.mbt`、`delete.mbt`、`disable.mbt`、`enable.mbt`，分别拥有独立
  command struct、parser、spec 与 `ReplCommand` 实现；统一 registry/help 注册，不增加
  别名。`breakpoints` 无参数，其余仅接受单个十进制正整数 ID；符号、小数、超界、多参数、
  范围及 `all` 均拒绝，前导零仍按十进制处理。
- 命令只调用领域层的 `breakpoints()` / `manage_breakpoint()`，通过结构化
  presentation event 传递列表、管理结果及错误。Ready 管理不触发 backend 同步，列表
  不等待 adapter；Stopped 管理等待领域层确认同步结果。
- 新增独立 `breakpoint_renderer.mbt`：混合列表按稳定 ID 排序，显示 enabled/disabled、
  原始请求路径或函数名、`not installed / current / previous` 安装状态与 rejected 原因。
  实际源码只使用已知结构化路径/行，未知时明确输出 `source location unknown`，不拿请求
  位置补猜。历史落点/数量另加 `previous` 标记，不冒充当前安装。
- family 显示 `locations: N` 或 `locations: unknown`；已知零单独显示 0，不把单个
  代表位置当作总数 1。每项最多显示 3 个代表位置，超过时明确提示截断；不称作实例数量。
- 删除、禁用有明确完成反馈，重复启停显示 `already enabled/disabled`；启用反馈包含
  安装状态，因此 enabled 与 rejected 可同时清楚表达。未知 ID、明确拒绝、状态限制与
  不确定故障分别呈现，回收错误保留 `current execution was discarded` 信息。
- `run` 的旧断点反馈仅筛选启用逻辑项，保持原有先源码后函数的输出顺序；不会把禁用项
  打印为 pending/verified，与新列表保持一致。原 `b` 语法和反馈未改变。
- 断点停止原因统一显示 `breakpoint`，不透传 LLDB description 中的物理编号（例如
  `breakpoint 3.1`），避免与管理命令的逻辑 ID 混淆。本阶段不扩展命中逻辑 ID 映射；
  step、exception 等其他停止原因仍保留原描述。
- 专项测试覆盖严格参数边界、help 注册、Ready 零同步、Stopped 同步、幂等操作、无效
  ID/状态、拒绝与故障回收、rejected 启用、混合列表与历史状态、代表位置上限，以及
  `run` 不报告禁用项。`moon info && moon fmt`、`moon check`、`git diff --check` 通过；
  默认 `moon test` **258/258**，`moon build` 通过，无新增警告，无可见接口变更。
  完整真实交互验收留给 P6。
- 补充停止原因回归测试后，`moon check` 在 lldb_dap whitebox 检查阶段触发编译器
  `lib/xml/typing/typer.ml:4859` assertion failure（版本 `v0.10.11+050b1e1ee-nightly`，
  退出码 255），主会话原样复现后暂停。调查确认是 foreach 元组 pattern 的 typing
  分支尚未实现，并非 async 问题。经用户同意，将 `for (body, expected) in cases`
  等价改为 `for pair in cases`，在循环体内 `let (body, expected) = pair`；保留全部
  5 个停止原因测试输入和断言，不修改编译器或降低验收标准。改写后重新完成环境检查、
  info/fmt/check、258 项测试、build 与差异检查，阻塞解除。此前四命令真实闭环已由
  主会话验收；最终独立复核 258 项测试通过，真实 main/identity 停止提示均显示
  `Stopped (breakpoint)`，不暴露 LLDB 内部编号。

### P6. 真实闭环验收与收尾

**状态：待实施**

**工作内容：**

1. 用 `moon debug <fixture>` 验证添加、列表、禁用、不命中、启用、再次命中、删除及重跑。
2. 覆盖同文件多个源码断点、精确函数、泛型多落点、删除最后一项、混合管理和无效目标。
3. 验证管理命令不改变所选 frame，`p`/`locals`/`list` 在成功操作后仍正常工作。
4. 将真实链路加入门控工具链验收，默认测试不依赖本地真实 lldb-dap 和开发工具链布局。
5. 按 AGENTS.md 检查环境，运行 `moon info && moon fmt`、`moon check`、`moon test`，
   review 预期接口 diff，并记录真实工具链验收结果及手动使用方法。

**完成条件：** 默认测试与门控验收通过，重新 run 后设置保持，当前 execution 无残留
断点或后台进程，文档明确列出已验证能力和已知限制。
