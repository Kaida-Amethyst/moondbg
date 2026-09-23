# 本地 VSIX 打包

打包命令只生成本地预览包，不自动上传 GitHub Releases 或 Marketplace，也不改动 `$MOON_HOME/bin`。
CLI 由用户通过 `moon install Kaida-Amethyst/moondbg` 安装。

在本目录执行（打包需要 Node.js 22+；使用扩展本身不需要另外安装 Node.js）：

```sh
npm ci
npm run package
```

输出：`dist/moondbg-0.1.2-darwin-arm64.vsix`。
`@vscode/vsce` 版本与传递依赖由 package-lock.json 锁定；仅打包白名单中的运行时代码、用户文档和许可证。
不会包含 node_modules、测试、开发文档、CLI 或本机配置。`LICENSE` 必须与仓库根目录一致。

使用 `--target darwin-arm64 --pre-release`，扩展本身也检查平台。
当前 publisher 为 `KaidaAmethyst`，上传 Marketplace 时必须选择这个发布者 ID。
扩展完整 ID 为 `KaidaAmethyst.moondbg`；安装前卸载或禁用旧 `moondbg-local.moondbg`，
避免两个扩展同时注册调试类型。CLI 和 `moondbg.moonHome` 设置不变。

发布基线为 MoonBit v0.10.4；当前 nightly 验收不能替代 v0.10.4 的独立兼容性验收。
打包成功不代表该项验收已完成。

用户使用普通 VS Code 的“从 VSIX 安装”即可。开发者的扩展宿主验收见 DEVELOPMENT.md；
`test/installed-host.js` 在独立测试驱动宿主中确认 moondbg 来自已安装的 VSIX，再执行函数断点、
源码断点、变量展开及求值验收。运行时清除 MOON_HOME，测试通过用户设置 `~/.moon` 启动已安装 CLI。
测试驱动本身不注册调试类型，moondbg 不能从 extensionDevelopmentPath 加载。

无配置启动需要 CLI 的 `--resolve-source` 协议 v1；0.1.2 的新调试能力还需要配套标签的 CLI。
开发验收可将 `moon install --path . --bin <临时工具链>/bin` 安装到隔离目录，再通过
`MOONDBG_TEST_MOON_HOME` 传给已安装 VSIX 测试；不覆盖用户的 `~/.moon/bin/moondbg`。
`test/automatic-host.js` 验证无 launch.json 项目的 Run and Debug / 当前包命令、源码断点和 library 拒绝。

打包参考：[VS Code Publishing Extensions](https://code.visualstudio.com/api/working-with-extensions/publishing-extension)。

## GitHub Release

注意：已发布的 `vscode-v0.1.2` 标签及资产使用旧 publisher `moondbg-local`。
当前本地上传用包保留版本 0.1.2，但身份已改变；不要覆盖该历史标签或资产。
后续若发布新的 GitHub Release，应另选版本和标签，并同步下列路径及发布说明。

扩展使用独立标签 `vscode-v0.1.2`，与 MoonBit CLI 模块版本区分。
先提交并推送对应源码与文档，创建、推送该标签，再发布为 **prerelease**，上传
`dist/moondbg-0.1.2-darwin-arm64.vsix`。发布说明见
[vscode-v0.1.2](../../docs/releases/vscode-v0.1.2.md)。
发布前重新打包，确保扩展内的 README 与标签中的源码一致；发布后下载资产并核对 SHA-256。
不要把 VSIX 提交到 Git，也不要自动发布 Mooncakes 包或 Marketplace 扩展。
