# Changelog

## 0.1.2 — panic、条件断点与变量探查

- 与本 release 的 CLI 配套：提供默认开启的 MoonBit panic 停点，并定位最近的项目源码 frame。
- 支持行、普通函数和泛型函数的条件断点；支持类型化整数/Bool 比较及短路组合条件。
- 改进 String/Bytes 分段查看、tuple/Result 位置成员、嵌套摘要及明确的变量读取错误。
- 自动摘要限制为 2 层、每层 4 个成员、合计 16 个值、160 个字符，不限制主动展开。
- 扩展运行时代码不变；上述能力由 CLI 提供。仅升级 VSIX 不会更新 CLI，安装步骤见 README。
- 优化表示的 Option 仍等待编译器支持，不宣称已完整支持；平台及 MoonBit 兼容性限制不变。

## 0.1.1 — 当前源码直接启动

- 未配置目标时，从当前源码所属的 native 可执行包自动生成会话配置，不写入 launch.json。
- library、测试文件或未打开源码时提示“未确定 main 函数位置”，不搜索其他入口。
- 新增“moondbg：调试当前包”命令；默认模板仅保留该入口，验收专用配置移入开发示例。
- 复用 CLI 的 `--resolve-source` 元数据定位接口；支持取消，旧 CLI 给出升级提示。

## 0.1.0 — 本地技术预览

- 提供 macOS Apple Silicon（aarch64-apple-darwin / VSIX darwin-arm64）安装包。
- 使用 `moon install Kaida-Amethyst/moondbg` 安装的 CLI，不捆绑或自动安装工具链。
- 新增用户设置 `moondbg.moonHome`，支持 `~/.moon`；留空使用 MOON_HOME。
- 支持按包自动构建、行断点、函数断点、单步、暂停、调用栈、变量树、Watch 和只读求值。
- MoonBit 支持基线为 v0.10.4；本次开发验收使用 nightly，v0.10.4 专项验收尚待完成。

此 VSIX 使用本地发布者 `moondbg-local`，尚未发布到 Marketplace。
