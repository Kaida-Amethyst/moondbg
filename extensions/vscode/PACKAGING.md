# 本地 VSIX 打包

打包生成预览包，发布到 GitHub Releases，不上传 Marketplace，也不改动 `$MOON_HOME/bin`。
CLI 由用户通过 `moon install Kaida-Amethyst/moondbg` 安装。

在本目录执行（打包需要 Node.js 22+；使用扩展本身不需要另外安装 Node.js）：

```sh
npm ci
npm run package
```

输出：`dist/moondbg-0.1.1-darwin-arm64.vsix`。
`@vscode/vsce` 版本与传递依赖由 package-lock.json 锁定；仅打包白名单中的运行时代码、用户文档和许可证。
不会包含 node_modules、测试、开发文档、CLI 或本机配置。`LICENSE` 必须与仓库根目录一致。

使用 `--target darwin-arm64 --pre-release`，扩展本身也检查平台。当前的 `moondbg-local`
仅为 VSIX 发布者标识；正式上传 Marketplace 前由项目维护者确认实际 publisher，并考虑扩展 ID 迁移。

发布基线为 MoonBit v0.10.4；当前 nightly 验收不能替代 v0.10.4 的独立兼容性验收。
打包成功不代表该项验收已完成。

用户使用普通 VS Code 的“从 VSIX 安装”即可。开发者的扩展宿主验收见 DEVELOPMENT.md；
`test/installed-host.js` 在独立测试驱动宿主中确认 moondbg 来自已安装的 VSIX，再执行函数断点、
源码断点、变量展开及求值验收。运行时清除 MOON_HOME，测试通过用户设置 `~/.moon` 启动已安装 CLI。
测试驱动本身不注册调试类型，moondbg 不能从 extensionDevelopmentPath 加载。

0.1.1 的无配置启动还需当前 CLI 的 `--resolve-source` 协议 v1。
开发验收可将 `moon install --path . --bin <临时工具链>/bin` 安装到隔离目录，再通过
`MOONDBG_TEST_MOON_HOME` 传给已安装 VSIX 测试；不覆盖用户的 `~/.moon/bin/moondbg`。
`test/automatic-host.js` 验证无 launch.json 项目的 Run and Debug / 当前包命令、源码断点和 library 拒绝。

打包参考：[VS Code Publishing Extensions](https://code.visualstudio.com/api/working-with-extensions/publishing-extension)。

## GitHub Release

扩展使用独立标签 `vscode-v0.1.1`，与 MoonBit CLI 模块版本区分。
先提交并推送对应源码与文档，创建、推送该标签，再发布为 **prerelease**，上传
`dist/moondbg-0.1.1-darwin-arm64.vsix`。发布说明见
[vscode-v0.1.1](../../docs/releases/vscode-v0.1.1.md)。
发布前重新打包，确保扩展内的 README 与标签中的源码一致；发布后下载资产并核对 SHA-256。
不要把 VSIX 提交到 Git，也不要自动发布 Mooncakes 包或 Marketplace 扩展。
