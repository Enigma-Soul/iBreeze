<img src="iBreeze/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png" width="120" alt="iBreeze 图标">

# iBreeze

用 Breeze 插件系统当内核的 iOS 漫画阅读器。界面参照 [EhViewer-Apple](https://github.com/felixchaos/EhViewer-Apple)，
插件运行时是按 [Breeze](https://github.com/deretame/Breeze) 的插件规范用 Swift + JavaScriptCore 重写的——
Breeze 生态里现成的插件不用改一行代码就能装进来用。

[![Build](https://github.com/ryongcai/iBreeze/actions/workflows/build.yml/badge.svg?branch=develop)](https://github.com/ryongcai/iBreeze/actions/workflows/build.yml)
[![Platform](https://img.shields.io/badge/platform-iOS%2018%2B-blue.svg)](#快速开始)
[![License](https://img.shields.io/badge/license-MPL--2.0-blue.svg)](LICENSE)

## 特性

**插件**

- 从 Breeze 官方插件列表一键安装、更新、卸载，也支持手填 bundle 地址安装
- 兼容 `getInfo`、`searchComic`、`getComicDetail`、`getReadSnapshot`、`fetchImageBytes` 等契约，
  以及 `bridge`、缓存、定时器、完整加密（MD5/SHA/HMAC/AES-CBC/ECB/GCM/PBKDF2）与 `BreezeHtml` 网页解析
- 插件列表与下载走国内可达的 jsDelivr 转发，Release 资产有 GitHub 加速兜底

**阅读**

- 三种翻页：纵向连续、左右翻页、右到左翻页
- 三段点击区（左右翻页、中间切换工具栏），上下留死区防误触
- 玻璃工具栏 + 页码滑杆 + 页码网格跳转（两百页的本子直接点页码）
- 图片内存 + 磁盘两级缓存，滚动时预取后三页
- 浏览记录与本地收藏，详情页可「继续阅读」

**界面**

- 悬浮玻璃标签栏，滚动时收起；iOS 26 上使用液态玻璃，低版本回退毛玻璃
- 首页即数据源切换：插件图标作源标签，插件声明的入口（最新 / 热门 / 排行）作筛选
- 简繁自动转换、深浅色主题、HTTP / SOCKS5 代理

## 快速开始

> [!WARNING]
> 仓库只产出**未签名 ipa**，需要自己用 AltStore、Sideloadly、TrollStore 等工具重签后再安装。

1. 打开 [Actions](https://github.com/ryongcai/iBreeze/actions/workflows/build.yml) 里最新一次成功的构建
2. 下载产物 `iBreeze-unsigned-ipa`
3. 重签并安装到设备（iOS 18 及以上）

首次启动后：设置 → 插件管理 → 从在线列表安装插件；回到首页从顶部源标签切换。

> [!NOTE]
> 部分漫画站点只对国内线路开放。若图源报 403 或超时，可在设置里配置 HTTP / SOCKS5 代理。

## 插件

插件是 TypeScript 打包出的单文件 `.cjs`，经 npm（jsDelivr）或 GitHub Release 分发。
安装时会先把 bundle 放进一次性运行时跑 `getInfo()`，用返回的 uuid / version 作为权威信息，uuid 不一致则拒绝安装。

当前插件列表 20 个条目的实测情况（`node Tools/plugin-matrix.mjs --net`）：

| 情况 | 数量 | 说明 |
| --- | --- | --- |
| 带浏览入口 | 11 | 首页源标签直接看到列表 |
| 仅搜索 | 6 | 不声明浏览入口，用首页搜索框或「搜索该插件」 |
| 上游已失效 | 3 | npm 包与 GitHub 仓库都已删除，客户端无法安装 |

自己写插件请参考官方文档：<https://deretame.github.io/plugin-dev-docs/>

## 架构

```
UI (Features/*)                    首页 / 搜索 / 收藏 / 详情 / 阅读 / 设置
  └─ PluginRegistry                每个插件一个常驻运行时
       └─ PluginSource             按 fnPath 调用契约
            └─ PluginRuntime       串行化所有 JS 执行
                 ├─ PluginRuntimeThread   16MB 栈线程（JavaScriptCore 递归深度受线程栈限制）
                 ├─ PluginJSLayer         注入 JS 层：宿主垫片 + Breeze polyfill + BreezeHtml
                 └─ PluginHostBridge      bridge.call 路由表：缓存 / 配置 / 网络 / 加密
```

- JS 运行时 = 本仓库自研的垫片 + Breeze 官方 polyfill（`Resources/PluginRuntime/`，来源与许可见该目录 NOTICE）
- 插件图片不直接用 URL：一律经 `PluginSource.imageBytes` 交给 `ComicImageLoader` 缓存
- 插件设置页由 `getSettingsBundle` 的字段声明泛化渲染

## 开发

项目在 Windows 上开发，**本地没有 macOS 工具链**，编译与测试都走 GitHub Actions：

```bash
git push origin develop    # macos-26 → xcodegen → 单元测试 + 真实插件冒烟 → 未签名 ipa
```

工程用 XcodeGen 描述（`project.yml`），`.xcodeproj` 不入库。有 Mac 时：

```bash
brew install xcodegen
xcodegen generate
xcodebuild test -project iBreeze.xcodeproj -scheme iBreeze \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

不依赖 Mac 的本地验证工具（JS 层改动请在推送前跑一遍）：

```bash
node Tools/plugin-js-harness.mjs                                  # JS 层自检 50 项
node Tools/plugin-js-harness.mjs <bundle.cjs> <fnPath> '[json]'   # 直接跑某个插件 bundle
node Tools/plugin-matrix.mjs [--net]                              # 批量体检插件列表
node Tools/prepare-app-icon.mjs <源图>                            # 生成 App 图标（1024、去 alpha）
```

真实插件冒烟测试默认跳过，本地要跑需设 `TEST_RUNNER_IBREEZE_SMOKE=1`（CI 已默认开启）。

## 已知限制

- `image.crop_by_regions`（长条图切分）与 `gzip` 尚未实现，个别插件的特殊图源会受影响
- 插件的云端收藏工作流（`startFavoriteAction`）未接，收藏目前只存在本地
- iOS 对 HTTP 代理的支持度依赖系统版本，SOCKS5 更可靠
- 阅读器的双页模式、亮度调节、音量键翻页尚未实现

## 致谢

- [Breeze](https://github.com/deretame/Breeze)：插件规范与运行时接口的来源，`Resources/PluginRuntime/`
  下部分 JS 直接取自该项目
- [EhViewer-Apple](https://github.com/felixchaos/EhViewer-Apple)：界面结构与交互逻辑的参照
- [Pixiv-SwiftUI](https://github.com/Eslzzyl/Pixiv-SwiftUI)：早期版本的外观参照

本项目以 MPL-2.0 授权，详见 [LICENSE](LICENSE)。
