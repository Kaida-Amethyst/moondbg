# Changelog

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
