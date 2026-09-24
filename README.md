# iBreeze

一个 **iOS 漫画阅读器**：界面参照 [Pixiv-SwiftUI](https://github.com/Eslzzyl/Pixiv-SwiftUI) 的观感，
内核兼容 [Breeze](https://github.com/deretame/Breeze) 的**插件系统**——Breeze 生态里现成的插件
（禁漫、e-hentai 等）不用改一行代码就能装进来用。

- **UI**：SwiftUI，iOS 18 起；iOS 26 上使用液态玻璃（Liquid Glass），低版本回退系统毛玻璃
- **内核**：用 Swift + JavaScriptCore 重写 Breeze 的 QuickJS 插件运行时，保持插件契约一致
- **形态**：底部为 首页 / 搜索 / 收藏，设置从首页右上角进入

## 现状

已经跑通的部分：

- **插件**：从 Breeze 官方插件列表一键安装、更新、卸载；也支持手填 bundle 地址安装
- **契约**：`getInfo`、`searchComic`、`getComicDetail`、`getReadSnapshot`、`fetchImageBytes`、
  列表场景、插件设置等，见 [插件开发文档](https://deretame.github.io/plugin-dev-docs/)
- **运行时**：`fetch`/`Headers`/`Response`/`Blob`/`FormData`/`AbortController`/`URL`/`Temporal`/
  `structuredClone`/`Buffer`、`bridge.call`（异步与同步）、定时器、`BreezeHtml`（HTML 抓取）、
  完整加密（MD5/SHA/HMAC/AES-CBC/ECB/GCM/PBKDF2/随机数）
- **设置**：HTTP / SOCKS5 代理、简繁自动转换（对齐 OpenCC 配置名）、插件管理、插件自带设置页
- **阅读**：整章纵向连读、章节切换、图片内存 + 磁盘缓存、浏览记录、本地收藏

已在 CI 上用**真实插件 + 真实网络**验证：从 jsDelivr 下载 `breeze-plugin-ehentai` → 装载 →
`getInfo` → 抓列表 → 拉详情与章节 → 取章节图片。

## 已知限制

- `image.crop_by_regions`（长条图切分）与 `gzip` 尚未实现，个别插件的特殊图源会受影响
- 代理在 iOS 上对 HTTP 代理的实际支持度依赖系统版本，SOCKS5 可靠；建议真机验证
- 尚未做插件的云端收藏工作流（`startFavoriteAction` / `continueFavoriteAction`），
  收藏目前是本地记录

## 安装

CI 每次构建都会产出**未签名 ipa**（Actions → Artifacts → `iBreeze-unsigned-ipa`）。
自签安装可用 AltStore / Sideloadly / TrollStore 等工具重签。

## 开发

本项目在 Windows 上开发，本地无法编译 iOS，全部验证走 GitHub Actions：

```
git push origin develop      # 触发 CI：单元测试 + 真实插件冒烟 + 打包未签名 ipa
```

工程用 XcodeGen 描述（`project.yml`），`.xcodeproj` 不入库。

不依赖 Mac 的本地验证工具：

```bash
node Tools/plugin-js-harness.mjs                                  # JS 层自检（50 项）
node Tools/plugin-js-harness.mjs <bundle.cjs> <fnPath> [payload]  # 直接跑某个插件 bundle
node Tools/generate-app-icon.mjs                                  # 重新生成 App 图标
```

更多工程细节与踩坑记录见 [CLAUDE.md](CLAUDE.md)。

## 致谢与许可

- 插件运行时与 `BreezeHtml` 的接口规范来自 [Breeze](https://github.com/deretame/Breeze)，
  `Resources/PluginRuntime/` 下的部分 JS 文件直接取自该项目，遵循 MPL-2.0，
  详见该目录的 [NOTICE.md](iBreeze/Resources/PluginRuntime/NOTICE.md)
- UI 观感参照 [Pixiv-SwiftUI](https://github.com/Eslzzyl/Pixiv-SwiftUI)

本项目同样以 **MPL-2.0** 授权，见 [LICENSE](LICENSE)。
