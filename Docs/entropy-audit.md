# 软件熵审计（2026-09-26）

Historical snapshot, not a contract. When this page and the code disagree, the code wins.

只读。源码 250 个 Swift 文件、64,485 行；测试 137 个文件、27,678 行；Docs 186 篇、7,756 行；提交 379。行号与计数对应当日工作树。

高 4，中 10，低 4；另有 2 条原列为高、复核后撤回，见文末「复核更正」。`Sources` 与 `Tests` 内 `TODO` / `FIXME` / `HACK` 为 0。

本次未跑 `swift build` 与 `swift test`。Panel 的真实指针输入未在运行中的应用上复测。

## 按目录的源码行数

| 目录 | 行数 |
|---|---:|
| Usage | 21,295 |
| Providers | 20,815 |
| Panel | 9,587 |
| Settings | 6,470 |
| App | 3,346 |
| Auth | 2,972 |

## 体积与提交触及

触及次数合并了 `36826f5`（六目录搬迁）前后的两条路径。近 60 条提交主题以新增 provider 与发版为主。

| 文件 | 行数 | 提交触及 | 测试 |
|---|---:|---|---|
| `SettingsView.swift` | 3,423 | 约 102 | 无 |
| `AppSettings.swift` | 1,693 | 约 53 | 旁路偏好有，类本身无 |
| `UsageStore.swift` | 1,186 | 约 53 | 编排无集成测试 |
| `BotMarkEngine.swift` | 1,566 | 不在 churn 前 40 | `BotMark*` 行为测试 |
| `UsageLedger.swift` | 1,001 | — | 部分经 spend 套件 |
| `TokenSpendView.swift` | 973 | 不在 churn 前 40 | `SpendReadState` / `SpendSpan` |

## 高

### `SettingsView.swift`

`Sources/Pulse/Settings/SettingsView.swift`。3,423 行，一个 struct，38 个 `@State`，文件内零个嵌套 View 类型。`accountPaneBody` 292 行（1529–1821），`connection(for:)` 252 行（2494–2746）。构造函数持有 `UsageStore`、`AppSettings`、`PanelPlacement`、`AppUpdate`、`UsageAlerts`、`GlobalShortcutMonitor`。视图内直接构造 `ZaiUsageService`、调用 `DevinUsageService.fromBrowser`，状态类型含 `ZaiUsageService.HistoryRead`、`OAuthLogin.DevicePrompt`、`GitHubDeviceLogin.Prompt`。该文件无测试。目录搬迁前后合计约 102 次提交触及，为全树最高。

### `AppSettings.swift`

`Sources/Pulse/App/AppSettings.swift`。1,693 行，`@Observable final class`，无 `@MainActor`。`private enum Key` 有 53 个 `static let`。`init` 有 50 个参数。同一类型同时是偏好仓库、账户目录和副作用总线：`didSet` 写 `UserDefaults`，并调用 `PanelMetrics.use`、`NetworkSession.apply`、`LocalizationSource.use`。`showsCodexResetCredits`、`balanceBases`、`balanceBudgets` 不在 `init` 参数里，由 `restored()` 在 1555–1558 行事后赋值。合并历史约 53 次提交触及。

### `UsageStore.swift`

`Sources/Pulse/Usage/UsageStore.swift`。1,186 行，约 32 个存储属性。`refresh(dueOnly:)`（约 409–727）与 `refresh(_ account:)`（735–902）各写一套 20 余个服务构造和 `switch`；`fetchAdded`（941–989）第三次列出全部 profiled case。文件头 7–9 行仍写 “The two providers”。合并历史约 53 次提交触及。被测的是抽出去的纯函数（`AdaptiveRefresh`、`AlertMemory`、`UsageCache`）；队列、stall、one-shot timer 的编排没有集成测试。

### `Provider` 的 exhaustive switch

`case .clinePass, .alibabaCodingPlan` 在 11 个文件出现 16 处。`UsageProvider.swift` 占 6 处，其余为 `UsageStore`、`UsageRoute`、`MonitoredAccount`、`AgentActivity`、`SettingsView`、`ProviderDiscovery`、`ProviderAccess`、`ConnectionRemedy`、`BotMarkTint`、`OAuthLogin` 各 1 处。`Docs/development.md` 写 profiled provider “touching no shared switch”。`SettingsView.swift:1442` 的 `default` 分支文案是 “No Ollama session found. Sign in at ollama.com first.”。`UsageProvider.billing` 的 `default` 返回 `.subscription`。`ProfiledProviders.profile` 的 `default` 为 `nil`，`UsageStore` 对走到该处的账户返回 `.loading`。

## 中

| 位置 | 事实 |
|---|---|
| `AppSettings.removeAccount` 1604–1627 | 注释写 “everything stored against it”。实现只清 `pinnedWindows`、`sources`、`ringTints`、`sessionBrowsers`。`balanceBases`、`balanceBudgets`、`lowBalanceAlerts`、`botMarks`、`botPersonas`、`botShapes`、`botColours`、`serverAddresses` 仍按 `account.id` 存取。 |
| `Provider` 与 `SpendAgent` | `Provider.builtIn` 77 个环；`SpendAgent` 54 个 case。名字重叠，`sourceID` 与 inventory id 不同（`claude` 对 `claudeCode`）。Claude Code 与 Codex 走 `UsageLedgerReader` 与 `ledger-4-*.json`；其余走 `AgentLedgers`、`AgentCache` version 8，以及 5 个 legacy store。 |
| `ProviderUsage.Unavailability` | 约 60 个 case。Ollama、Xiaomi、Qoder、StepFun 各有 missing / expired / no-plan 专名；profiled 侧已有共享的 `sessionMissing`、`sessionExpired`、`noPlan`。每个新 case 同时进入 `message` 与 `AlertMemory.standing` 的三分。 |
| 手写用量解析，无 fixture | `Tests/PulseTests` 下没有 Cursor、Grok、Grok Bot、MiniMax、Kimi Code、OpenCode Go、Ollama Cloud 的用量套件。`CopilotLogReaderTests` 测的是 spend。`OpenCodeReviewReaderTests` 不是 OpenCode Go 的用量解析。`OllamaCloudClient` 用 `XMLDocument`、XPath 与 “% used” 正则。 |
| Panel 输入路径 | `PointerEntryReporter`（只报 enter）+ `PanelPointerWatcher` 每 0.15s + `ActiveDisplayFollower` 每 0.25s + `FloatingPanel.sendEvent` + `PanelHitArea`。无 `.onHover`，无 global/local event monitor。`PointerEntryReporter.swift:14` 仍写面板在卡片打开时会 resize。`UsageDockView.swift:430` 仍写 berth 不参与 hit testing；`PanelSurface` 当前是可命中的。 |
| `Usage/UsageSource.swift:308` | `enum PanelMetrics` 定义在 Usage 目录。8 个 `nonisolated(unsafe)` 静态字段加 `NSLock`。`FloatingUsagePanelView` 用 `.id` 拼接 language 等字符串强制重建，因为 `PanelMetrics` 对 SwiftUI 不可观察。 |
| `BotMarkEngine.swift` | 1,566 行，从 `grok-bot-engine.js` 移植。`updateStateTargets` 以字符串 `switch` 状态（`"sleeping"` 等 27 个以上 case），不是 enum。`BotMarkMorphs.swift` 另 477 行。每个启用的 ring 一个引擎，`TimelineView` 周期 1/30 秒。文件内注释写 7 个 mark 停稳约占一核 15%。 |
| 文档与代码 | `Docs/architecture.md:3` 写 “one SwiftUI view per file”。`Docs/refresh-and-data.md:3` 仍把余额环写成 DeepSeek 的例外；`BalanceRing` 已用于 API 账户，`CLAUDE.md` 与 `Docs/providers/README.md` 已改。`Package.swift` 注释写 “sixty-nine files”，当前 250 个 Swift 文件。 |
| 测试分布 | 约 52/137 个测试文件是 profiled provider 的二手 JSON 套件。`SettingsView` 无测试。Auth 无 `OAuthLogin`、`APIKeyStore`、`BrowserCookies`、`CursorWebLogin` 套件。App 无 `LoginItem`、`AppDelegate`、`AppUpdate`、`LegacyDefaults` 套件。`Docs/testing.md` 写明无 UI 测试。 |
| CI 与打包 | `ci.yml` 对 `**/*.md` 使用 `paths-ignore`。`bundle.sh` 手写 `Info.plist`、拷贝 Sparkle、`install_name_tool`。`Package.swift` 用 `linkerSettings` 与 `unsafeFlags` 把 SDK stamp 钉在 26.0。Sparkle 依赖为 `from: "2.6.0"`。 |

## 低

| 位置 | 事实 |
|---|---|
| `UsageDetailCard.swift:207`、357 | `String.localized` / `Text(localized:)` 的插值里含 `title ?? displayName`。`check-localization.sh` 把该模式收成 `%@`，脚本通过（706 键，4 份译文与源码键一致）。 |
| `UsageRingView.swift:112–188` | 11 个 `private static let` 尺寸与周期（`centreGap`、`haloRadius`、`clockGap` 等）。`DockLayout` 与 `DetailCardLayout` 本身是计算属性。 |
| 五份 `Localizable.strings` | 各 706 键、844 行，键集对齐。脚本不查死键。仍只出现在 strings 或预览标题里的键：`Providers`、`Floating panel`、`Devin's own app`。 |
| `try!` × 5 | `ReplicateUsageService.swift:100`、103、106 与 `TypeSafeUsageService.swift:179`、199，均为 `NSRegularExpression` 常量。`Sources` 内 `as!` 为 0，`fatalError` 为 2（`BotMarkData.swift`，缺 `bot-data.json`）。`try?` 约 411 处，集中在 JSON 与日志解析。 |

## 与代码一致的主张

`Provider.builtIn` 为 77（25 个手写 case + 52 个 profiled，滤掉 `pulseExtension`）。`Providers/Profiled` 下 52 个 `UsageService` 文件。`supportsMultipleAccounts` 为 `claudeCode`、`codex`、`grok`、`grokBot`。`AdaptiveRefresh.floor` 为 120，`ceiling` 为 1800。

未发现由本地 token 推算用量百分比、拉取已关闭 provider、或把未见过的读数写成 `spent`。`UsageAlerts.isSupported` 以 `Bundle.main.bundleIdentifier != nil` 围栏。五份 README 各 271 行，标题骨架对齐。provider 文档与 setup 页无孤儿 slug。

## 复核更正（2026-09-26）

初稿列为「高」的两条，复核后撤回：

- **「Swift 语言模式 5」不成立。** `swift-tools-version: 6.0` 的包，未设 `swiftLanguageModes` 时默认即 Swift 6 模式。`swift build -v` 实测 `Pulse` 模块以 `-swift-version 6` 编译；出现的 `-swift-version 5` 属于依赖。`Sources` 内 13 处 `nonisolated(unsafe)` 与 5 处 `@unchecked Sendable` 属实，是 Swift 6 模式下有意的逃生口，不是语言模式问题。
- **「cookie 前缀缺 `v20`」对 macOS 不成立。** `v20`（App-Bound Encryption）是 Windows 版 Chrome 的机制；macOS 版 Chromium 系浏览器用 `v10`，密钥在登录钥匙串（`BrowserCookies.swift:322`）。`ChromiumLocalStorage` 不读 `MANIFEST`、不校验 CRC 属实，但未见由此造成的读数错误，不列为高。
