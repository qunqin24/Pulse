# CLAUDE.md

本仓库给 AI 的入口。人的工作流程、证据规则和文档地图见 [CONTRIBUTING.md](CONTRIBUTING.md) 与 [Docs/README.md](Docs/README.md)。改代码时，在同一个提交里修改**负责该主题的文档**；不要往本文件里加内容。

Pulse 是一个 macOS 菜单栏用量监视器。面板由 SwiftUI 绘制；尺寸、位置和输入由一个透明、不激活的 AppKit `NSPanel` 负责。七十七个服务商，没有 Pulse 后端，也没有 Pulse 账号。各服务商的读取通道、鉴权、cookie 和额外登录见 [Docs/providers/README.md](Docs/providers/README.md)。

源码分在 `Sources/Pulse` 下的六个目录：**App**（生命周期、设置存储、更新）、**Panel**（窗口、窗口位置，以及其中绘制的一切）、**Settings**（设置窗口）、**Usage**（存储、缓存、账本、预测、提醒）、**Providers**（每个产品一个服务，以及它们的辅助代码）、**Auth**（密钥、登录、cookie）。Swift 没有目录命名空间，SwiftPM 会递归读取，所以文件所在的目录只表明它属于哪一部分，别无他意；这个归属不再成立时就移动文件。

## 命令

```bash
swift run Pulse
swift build
./Scripts/bundle.sh
./Scripts/dmg.sh
./Scripts/check-localization.sh
swift test
./build.noindex/Pulse.app/Contents/MacOS/Pulse --json
```

**`xcode-select` 必须指向 Xcode，不能是 CommandLineTools。** `#Preview` 由 Xcode 插件展开，否则每次构建都会报 `PreviewsMacros plugin not found`。用 `xcode-select -p` 检查。临时指定：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`。

**不要为了让构建通过而删掉 `#Preview` 块。** 这会掩盖其中的错误，并且已经因此发布过一个坏掉的版本。见 [Docs/decisions/never-strip-previews.md](Docs/decisions/never-strip-previews.md)。

`swift build` 没有报错不等于通过 Xcode 检查。actor 隔离的错误在这里可能只是警告，在 Xcode 里却是硬错误（每个 `View` 都是 `@MainActor`）。声称改动可以构建之前：

```bash
swift build
```

剩余的警告一律按失败处理。macOS 14+，Swift tools 6.0，没有 linter。**`swift test` 是有的**：覆盖规则、缓存合并和服务商样例；要运行它，改动规则时要补测试。见 [Docs/testing.md](Docs/testing.md)。CI 和发版需要 macOS 26 SDK（`glassEffect`）。**写进二进制的 SDK 版本决定 macOS 用哪种控件样式绘制**：SwiftPM 写入的是部署目标，所以 `Package.swift` 在 `linkerSettings` 里设置它，`bundle.sh` 会从每个架构切片读回来核对。低于 26 时，app 会在没有任何提示的情况下按旧样式绘制。见 [Docs/decisions/sdk-stamp-and-appearance.md](Docs/decisions/sdk-stamp-and-appearance.md)。

## 不可违反

- **卡片打开时的面板窗口：** 不要改变窗口尺寸，也不要把卡片和胶囊放进同一个 stack。只有方向变化（侧边 ↔ 顶部）*可以*改变尺寸。见 [Docs/ui/panel-geometry.md](Docs/ui/panel-geometry.md)。
- **悬停：** SwiftUI 的 `.onHover` 在这个 accessory、非 key 的面板上不起作用。进入靠 tracking area，离开靠采样指针位置，绝不依赖 exit 事件。拖动和圆环点击归 `FloatingPanel.sendEvent` 处理。`hitTest` 和合成事件不能证明真实输入可用。见 [Docs/ui/input.md](Docs/ui/input.md)。
- **百分比：** Pulse 不编造用量百分比。服务商没有报告，就如实说明。例外只有以下几种，每一种都在界面上标明是推算的（按 API 价格估算的本机金额，在设置的「Token 消耗」页说明，卡片上不重复，以保持简洁；用户 2026-10-23 决定），并且在输入缺失时**什么都不画**，而不是画成 0：金额估算；Command Code 的月度套餐额度（报告了剩余量，没有报告套餐大小）；以及所有只报告金额、不报告额度的 API 账号或扩展（`BalanceRing`，最早是 DeepSeek 的规则）——它的分母要么是 Pulse 观察到的，要么是用户自己填的，要么没有；只有服务商自己的标记才能判定用完。见 [Docs/refresh-and-data.md](Docs/refresh-and-data.md)、[Docs/providers/command-code.md](Docs/providers/command-code.md)、[Docs/providers/deepseek.md](Docs/providers/deepseek.md)。
- **用户看到的文字只有一个标准，处处适用。** 用户会读到的一切——各语言的界面文案、通知、Sparkle 窗口、CHANGELOG 和发布页、README、设置指南、issue 回复——都要写得平实、正式，不逐词转换，也不刻意用「大白话」口吻：主语是含糊的「它」的句子，或者把修复写成「削平」，都是文字上的 bug。列表的加粗引导语要能独立成句；一个概念只用一个词（简体中文：服务商 / 账号）；**本项目所有更新日志**（CHANGELOG，以及由它生成的 GitHub 发布页和 Sparkle 更新窗口）参考 [Open WebUI](https://github.com/open-webui/open-webui/blob/main/CHANGELOG.md) 的格式（不用 emoji）：每条一个加粗短标题，再用一句话写是什么、在哪开启，末尾附 issue / PR 链接；不写背景、原理和注意事项，细节链接到文档。遵循 `Scripts/changelog.py` 的语法。2026-10-07 为此重写了所有发布页，不要让它退回去。见 [Docs/development.md](Docs/development.md#writing-users-can-read)。
- **本地化：** 只用 `String.localized(_:)` / `Text(localized:)`。不要用隐式的 `Text("…")`。`localized:` 里不要写条件表达式。插值用 `String`，不用 `Int`（`%lld` 与 `%@` 的区别）。运行 `./Scripts/check-localization.sh`。**译文是写出来的，不是转换出来的**：不用英文句法，不用读者没有对应说法的术语，开关的名称要和它下面的子选项一致。脚本只检查键，不检查文案读起来是否通顺。见 [Docs/development.md](Docs/development.md)。
- **通知只说 Pulse 亲眼看到的事。** 只有服务商说用完了才算用完；只有证据明确才算重置；读不到数据不自动等于故障；**推送**通道（Claude Code 的状态栏）没有动静也不算故障。开启设置时已经越过阈值的额度**要**通知一次——先沉默、再突然撞墙，等于这个功能失效。所有通知默认关闭；都使用默认提示音，由 macOS 的单个应用开关静音。`UNUserNotificationCenter` **在没有 app bundle 时会抛异常**——每个入口都由 `UsageAlerts.isSupported` 把守，所以要用 `./Scripts/bundle.sh` 打包后测试，不要用 `swift run`。见 [Docs/notifications.md](Docs/notifications.md)。
- **关闭的服务商不读取。** 共用的 `Unavailability` 文案不点名任何服务商。
- **布局常量是预算**（`PanelMetrics` 用计算属性 `var`，不用 `static let`）。面板上新增的任何东西都从这些预算里取尺寸。
- **不要在这里读取或记录服务商的鉴权信息。** 见 [Docs/providers/README.md](Docs/providers/README.md)。
- **Pulse 只读；窗口启动器是唯一的例外。** 它通过服务商自己的 CLI 发送一句「hi」，默认关闭，只能经过风险确认后开启，不保存任何内容。除此之外，任何功能都不得代表用户发送内容。见 [Docs/window-starter.md](Docs/window-starter.md)。

## 按任务查阅

| 任务 | 阅读 |
|---|---|
| 应用外壳、设置、登录项、默认值 | [Docs/architecture.md](Docs/architecture.md) |
| 面板尺寸、停靠、浮层、缩放 | [Docs/ui/panel-geometry.md](Docs/ui/panel-geometry.md) |
| 拖动、悬停、点击、命中测试 | [Docs/ui/input.md](Docs/ui/input.md) |
| 玻璃效果、圆环、颜色、活动标记 | [Docs/ui/rings-and-surface.md](Docs/ui/rings-and-surface.md) |
| 设置窗口的文案与布局 | [Docs/ui/settings.md](Docs/ui/settings.md) |
| 刷新、缓存、活动、账本 | [Docs/refresh-and-data.md](Docs/refresh-and-data.md) |
| Token 消耗页面、agent、消耗读取器 | [Docs/token-spend.md](Docs/token-spend.md) |
| 月度与年度回顾卡片和窗口 | [Docs/recap.md](Docs/recap.md) |
| 通知与提醒规则 | [Docs/notifications.md](Docs/notifications.md) |
| 测试范围与样例数据 | [Docs/testing.md](Docs/testing.md) |
| `--json` 输出约定 | [Docs/json-output.md](Docs/json-output.md) |
| 开发者集成、账号链接 | [Docs/integrations.md](Docs/integrations.md) |
| 重置后启动用量窗口 | [Docs/window-starter.md](Docs/window-starter.md) |
| 本地化、资源、新增界面 | [Docs/development.md](Docs/development.md) |
| 打包、打 tag、Sparkle、DMG | [Docs/releasing.md](Docs/releasing.md) / [Docs/build-from-source.md](Docs/build-from-source.md) |
| 设计缘由与失败教训 | [Docs/decisions/README.md](Docs/decisions/README.md) |
| 服务商读取通道与额外账号 | [Docs/providers/README.md](Docs/providers/README.md) |

## 当前事实（关键时请在代码里核实）

七十七个内置服务商（`Provider.builtIn`）：二十四个逐个手写，五十三个是 `Providers/Profiled/` 下的 `ProviderProfile`（见 [Docs/providers/README.md](Docs/providers/README.md#adding-a-provider)）；另有 `.pulseExtension`，用户添加的每个扩展都作为它的一个账号（见 [Docs/extensions.md](Docs/extensions.md)）。支持额外账号的：Claude Code、Codex、Grok、Grok Bot（`supportsMultipleAccounts`）。自适应刷新是**单次**定时器，间隔 **2–30 分钟**（`AdaptiveRefresh.floor` 120 秒 / `ceiling` 1800 秒），不是每 60 秒循环。液态玻璃下的拖动：可命中测试的 `PanelSurface`、窗口的 `sendEvent`，以及玻璃下方的 `PanelGlass.claim`，让窗口拥有自己的像素——已用真实输入验证（#68）。
