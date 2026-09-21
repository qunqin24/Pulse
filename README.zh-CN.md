<p align="center">
  <img src="AppIcon/pulse-icon-1024.png" width="112" alt="Pulse">
</p>

<h1 align="center">Pulse</h1>

<p align="center">
  <b>优雅无扰的 macOS 屏幕边缘 AI 编码额度监视器。</b><br>
  实时掌握 Claude Code、Codex、Cursor、GitHub Copilot、Antigravity、Grok 等多平台的限额与剩余用量。
</p>

<p align="center">
  <a href="https://github.com/qunqin24/Pulse/releases/latest"><img src="https://img.shields.io/github/v/release/qunqin24/Pulse?color=black" alt="最新版本"></a>
  <img src="https://img.shields.io/badge/macOS-14.0%2B%20Sonoma-333333?logo=apple" alt="macOS 14+">
  <a href="https://github.com/qunqin24/Pulse/actions/workflows/ci.yml"><img src="https://github.com/qunqin24/Pulse/actions/workflows/ci.yml/badge.svg" alt="构建状态"></a>
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">
  <a href="LICENSE"><img src="https://img.shields.io/badge/许可-Apache%202.0-blue" alt="开源许可"></a>
  <a href="https://github.com/qunqin24/Pulse/stargazers"><img src="https://img.shields.io/github/stars/qunqin24/Pulse?label=%E6%98%9F%E6%A0%87&color=black" alt="GitHub 星标"></a>
  <a href="https://github.com/qunqin24/Pulse/releases"><img src="https://img.shields.io/github/downloads/qunqin24/Pulse/total?label=%E4%B8%8B%E8%BD%BD%E9%87%8F&color=black" alt="下载量"></a>
  <a href="https://github.com/qunqin24/Pulse/issues"><img src="https://img.shields.io/github/issues/qunqin24/Pulse?label=%E9%97%AE%E9%A2%98&color=black" alt="待处理问题"></a>
  <a href="https://github.com/qunqin24/Pulse/commits/main"><img src="https://img.shields.io/github/last-commit/qunqin24/Pulse?label=%E6%9C%80%E8%BF%91%E6%8F%90%E4%BA%A4&color=black" alt="最近提交"></a>
</p>

<p align="center">
  <sub><b>macOS 14 Sonoma 或更高版本</b> · Apple 芯片与 Intel 通用 · <a href="README.md"><b>English</b></a> · <b>简体中文</b> · <a href="README.zh-Hant.md"><b>繁體中文</b></a> · <a href="README.ja.md"><b>日本語</b></a> · <a href="README.ko.md"><b>한국어</b></a></sub>
</p>

<p align="center">
  <img src="Docs/demo.gif" width="340" alt="贴在屏幕边缘的 Pulse 悬浮胶囊">
</p>

Pulse 是一个停靠在屏幕边缘的小巧悬浮监视器。它展示各服务自己上报的剩余额度——走的是该产品自己的客户端通道，而不是 Pulse 的服务器——用你已有的登录态，不回传任何东西。屏幕上的每个百分比，都来自服务商自己报告的数字。

**1.2.0 新变化：** 可选的动画标记——用一个会随该账号状态反应的小机器人代替供应商图标，人格、形状和颜色都可以自己设置。[版本说明](https://github.com/qunqin24/Pulse/releases/tag/v1.2.0)。

<p align="center">
  <img src="Docs/bot-mark.gif" width="340" alt="Pulse 动画标记：每个环里的小机器人会随该账号的状态反应">
</p>

---

## 核心特性

### 一目了然的用量圆环
- **智能用量着色**：环形进度随使用率平滑变色（绿 → 琥珀 → 红 → 用尽深红），亦可按账号自定义专属高亮色。
- **实时工作状态灯**：圆环边缘带动态旋转光点，实时指示 Agent 是否正在生成或执行任务（支持 Claude Code 与 Codex）。
- **时间窗口进度弧**：可选的外层时钟副弧线，直观呈现当前限额窗口的时间流逝比例。
- **正数 / 倒数自由切换**：支持在“已消耗百分比（如 `75% used`）”与“剩余可用额度（如 `25% left`）”之间切换。

### 悬停详情卡与智能消耗预测
- **完整配额清单**：鼠标悬停在圆环上即可弹出详情卡，列出该平台的所有用量池、重置倒计时与生效状态。
- **消耗速率与耗尽预测（可选）**：开启后会分析当前使用节奏是否足以撑到本轮周期重置，并在存在耗尽风险时给出大致的枯竭时间；默认关闭。
- **置顶核心配额**：可自由指定将关注的配额钉在圆环主视图，或由系统默认展示最临近用尽的配额。

### 原生丝滑、静默无扰
- **多位置随心停靠**：可吸附停靠在屏幕左边缘、右边缘或顶部（菜单栏之上），亦可在屏幕任意位置自由悬浮。
- **多显示器支持**：随心拖拽到外接屏幕，自动记忆所在显示器位置；拔掉副屏后自适应回归主屏。开启**跟随活动显示器**后，唯一的那条胶囊会自动移动到指针所在的屏幕。
- **边缘微光收起**：闲置时自动折叠为一条极窄细线，不遮挡代码与工作视线；仅在额度见底预警时细线泛红提醒。
- **可选的系统通知**：默认全部关闭。开启后可在限额越过 75/80/90/95%、服务商判定用尽、之前提醒过的窗口重置、连续几次读不到用量（面板正悄悄显示旧数字）、以及预付费额度跌破你设定的金额时收到通知。每件事只说一次：打开开关时已经越线的限额会立刻告诉你一次，之后不再重复，直到它重置或者更糟。
- **全屏空间避让**：默认只留在你当前工作的 Space，全屏应用那边交给它自己。
- **原生质感**：提供沉稳耐看的纯黑底板，macOS 26+ 更可选原生 **Liquid Glass（流动玻璃）** 材质。
- **动画标记（可选）**：把供应商图标换成一个会随该账号状态反应的小机器人——正在干活、正在取数、额度用满还是闲着。默认关闭，按账号开启；八种人格、十八种形状，颜色也可以自己指定。
- **浮动栏菜单与快捷键**：右键浮动栏——或收起后的细线，按住 Control 点击同样有效——可打开含「设置」与「退出」的菜单。在 **设置 › 通用 › 快捷键** 中，可自行将全局快捷键分配给**打开设置**与**显示或隐藏面板**；两者默认都不绑定。
- **五种界面语言**：英文、简体中文、繁体中文、日语与韩语；大数缩写分别使用 K/M/B、万/亿、萬/億、万/億与 만/억。

### 多账号管理与本地消费账本
- **多账号并行**：支持同一服务绑定多个订阅（Claude Code、Codex、Grok、Grok Bot），并排查看并自定义标签。
- **Token 消耗（设置内查看）**：默认关闭，在页面顶部开启后才读取本机记录，关闭即可停止扫描。支持本地日志、数据库与导出文件，目录涵盖 **54 个客户端来源**，包括 Gemini CLI、Cline、Roo Code、OpenClaw 和 GitHub Copilot。Cursor、Trae 等导出来源需要先导出或捕获记录。这些来源与浮动栏上的 19 个配额服务商不同，各自支持的格式和真实客户端验证情况见[来源说明](Docs/token-spend-sources.md)。
- **明确的用量估算**：默认查看最近 7 天，并记住所选区间。费用按公开 API 价格折算，不是订阅账单；未知价格保留为不可用，计数不完整或时间粒度较粗会明确标注，没有 token 计数的来源会如实标注为不可用。
- **模型详情与图表**：点开单个模型可查看输入/输出/缓存读写用量与估算费用、有记录支撑的每日与每小时图表、各 Agent 的贡献，以及可排序、分页的明细表。指向图表即可读取对应日期或小时的 Token 数量。缺失的每日或每小时明细会标注为不可用。
- **二十个服务商**：Claude Code、Codex、Kiro、Antigravity、Cursor、GitHub Copilot、Grok、Grok Bot、OpenCode Go、Kimi Code、Ollama Cloud、z.ai、Zhipu、MiniMax（国际与国内）、火山引擎、Command Code、DeepSeek、Devin，以及小米 Coding Plan。
- **可脚本化**：`Pulse --json` 输出最近一次读数——套餐、每条限额、重置时间，以及数字有多旧——可接 tmux、sketchybar、Raycast 或 shell 提示符。它只读缓存，所以高频轮询几乎不花代价。
- **开发者集成**：在设置中导出 Raycast 扩展及可直接配置的 tmux、sketchybar、终端脚本；通过账户链接直达对应设置页。[安装指南](Docs/integrations.md)。
- **连接诊断**：查看实际读数来源、缓存使用情况、最近检查及回退结果；根据原因直接重连、重新登录或编辑凭据，并可复制不含账户信息和密钥的诊断报告。
- **本地优先**：Pulse 跑在你自己的 Mac 上，用你自己的登录态。它只发起三类连接，这里列的就是全部——你已在使用的服务商、为 Token 消耗页取公开模型价格的 [models.dev](https://models.dev)，以及检查更新的 GitHub/Sparkle。服务商请求、登录时的令牌交换和 models.dev 会使用「设置 › 通用 › 网络」里选择的代理，Pulse 也会把手动代理传给支持的辅助进程。Sparkle 的更新检查始终跟随 macOS 系统代理设置。

<p align="center">
  <img src="Docs/panel.webp" height="300" alt="详情卡片">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="Docs/settings.webp" height="300" alt="Pulse 设置界面">
</p>

<p align="center">
  <img src="Docs/account-claude-code.webp" height="290" alt="账户页：每条上报的限额、已用额度的估算价值与本地历史">
  &nbsp;&nbsp;
  <img src="Docs/account-codex.webp" height="290" alt="另一个账户页：套餐、信用余额与限额重置次数">
</p>

<p align="center">
  <img src="Docs/spend.webp" height="290" alt="Token 消费：合计、按类型的用量与每日规律">
  &nbsp;&nbsp;
  <img src="Docs/spend-history.webp" height="290" alt="按天、按月、按 agent 的 Token 消费">
</p>

<p align="center">
  <img src="Docs/spend-agent.webp" height="290" alt="单个 agent 的消费明细">
  &nbsp;&nbsp;
  <img src="Docs/spend-model.webp" height="290" alt="单个模型的消费，按 token 类型计价">
</p>

---

## 支持的服务商与读取方式

Pulse 只呈现各服务上报的数字，每个百分比都来自那份回复本身。各产品的读取通道不同（已文档化的客户端接口、编辑器登录态、本地 language server、粘贴的密钥），并不是每一行都有公开的官方配额 API。贡献者细节见 [Docs/providers/README.md](Docs/providers/README.md)。

| 服务商 | 读取通道与鉴权方式 | 说明与特性 |
|---|---|---|
| **Claude Code** | 账号 OAuth 用量接口；自动回退至 Claude 桌面端 Web 会话及状态栏 | 优先复用本机已存凭据，支持终端及桌面端混合无缝切换 |
| **Codex** | 客户端用量接口；回退至 `codex app-server` | 自动复用本地 Codex 登录凭证 |
| **Kiro** | Kiro CLI 原生 ACP 用量方法 | 借用 Kiro CLI 已登录的会话；Pulse 从不读取或保存 Kiro 凭据（[详情](Docs/providers/kiro.md)） |
| **Antigravity** | 编辑器本地运行的 Language Server (LSP) | 在 Antigravity 编辑器运行期间实时报告 |
| **Cursor** | Cursor 账号用量摘要接口 | 读取编辑器已保存凭据，分别展示 Fast / Slow 两个额度池 |
| **Grok** | Grok Build CLI 代理接口 | 一个统一的周额度池，与网页/CLI/API 全线 Grok 共享 |
| **Grok Bot** | Cursor 仪表盘接口 | Cursor 套餐内包含的 xAI 专属额度 |
| **GitHub Copilot** | GitHub 设备码（Device Code）登录 | 只申请 `read:user` 这一项权限 |
| **OpenCode Go** | 设置中填入 API Key，或读取 OpenCode CLI 登录信息 | — |
| **Kimi Code** | 设置中填入 API Key | — |
| **z.ai** | 设置中填入 API Key | 智谱国际站（`api.z.ai`），与国内账号独立 |
| **Zhipu** | 设置中填入 API Key，或读取本地 GLM 工具已保存密钥 | 智谱国内站（`open.bigmodel.cn`） |
| **MiniMax / MiniMax CN** | 设置中填入 API Key | 同时支持国际站（`minimax.io`）与国内站（`minimaxi.com`） |
| **Ollama Cloud** | 本地读取浏览器登录会话 Cookies | 官方无配额 API。详见 [Docs/ollama-cloud.md](Docs/ollama-cloud.md) |
| **Volcengine（火山引擎）** | `arkcli` 登录，或粘贴 Volcengine Access Key 对（签名走 Top OpenAPI） | Ark Coding / Agent 套餐；自动模式优先使用粘贴的密钥 |
| **Command Code** | 设置中填入 API Key，或读取 `cmd auth login` 已保存的登录 | 以美元计费的余额；含滚动 5 小时 / 周限额与月度套餐行（标记为**估算**） |
| **DeepSeek** | 设置中填入 API Key；官方文档化的 `GET /user/balance` | 仅报告预付余额、无额度；圆环的度量基准由你选择 |
| **Devin** | 什么都不用填——读取浏览器里的登录会话，无需钥匙串授权 | 每日与每周额度均由 Devin 报告。没有浏览器会话或手填凭据时，读取应用存下的带日期套餐；接口失败只使用账户与组织匹配的接口缓存（[Docs/providers/devin.md](Docs/providers/devin.md)）|
| **小米 Coding Plan** | 什么都不用填——读取浏览器里已登录的会话，也可以手动粘贴 `Cookie:` 头 | 小米 MiMo 控制台上的月度 token 额度，有结束时间就一并显示。预付余额作为一行附在卡片上。账号上没有 Coding Plan 时会直说，而不是画一个 0%（[Docs/providers/xiaomi-coding-plan.md](Docs/providers/xiaomi-coding-plan.md)） |

---

## 安装与快速上手

1. 前往 [Releases](https://github.com/qunqin24/Pulse/releases/latest) 下载最新的 **`Pulse-x.y.z.dmg`**。
2. 打开安装镜像，将 **Pulse** 拖拽至「应用程序（Applications）」文件夹即可。
3. 首次启动先选择要监控的服务，默认都不勾选。点 **「完成」** 后，Pulse 才会读取所选服务的凭据并查询用量。关掉向导会保持未开启监控；也可以在设置里开启任意服务。升级会保留原有选择，对新支持且本机检测到的服务只询问一次。
4. Pulse 常驻菜单栏。若菜单栏过于拥挤，右键浮动栏（或收起后的细线）并选择 **「设置…」**；也可在 **设置 › 通用 › 快捷键** 中为它分配一个全局快捷键。

> [!NOTE]
> **macOS 首次启动拦截处理**：<br>
> Pulse 是未使用 Apple 开发者证书签名的开源项目，首次启动时 macOS 可能阻止应用：
> - **图形界面方式**：启动 Pulse，关闭拦截弹窗，打开 **系统设置 → 隐私与安全性**，点击 **“仍要打开”**。
> - **终端方式**：
>   ```bash
>   xattr -cr /Applications/Pulse.app
>   ```
>   *应用内通过 Sparkle 提供更新。更新后，macOS 可能再次请求浏览器钥匙串访问权限。*

---

## 隐私与安全性

Pulse 秉持“本地优先”与最小权限设计原则：
- **无 Pulse 后端**：你的 Mac 用你自己的登录态连接你已在使用的服务商。同时会为 Token 消耗页从 [models.dev](https://models.dev) 获取公开模型价格，并向 GitHub/Sparkle 检查更新。服务商请求、登录时的令牌交换和 models.dev 会使用「设置 › 通用 › 网络」里选择的代理，Pulse 也会把手动代理传给支持的辅助进程。Sparkle 的更新检查始终跟随 macOS 系统代理设置。
- **凭据来源**：在产品本身如此工作时，复用本地开发工具已有的登录态（`~/.claude`、`~/.codex`、Cursor 本地状态等）；部分服务需要在设置中填写密钥或登录。
- **本地加密存储**：手动输入的 API Key 和 Session 均经过加密保存于 Pulse 应用目录内，权限仅限当前系统用户。
- **本地用量记录**：Pulse 从会话日志、数据库与导出文件中读取 token 数量，以及标题、工作目录等会话信息。这些记录可能包含对话文本；处理全程在你的 Mac 上完成，记录也留在本机。Pulse 只读取这些记录，仅此而已。

---

## 从源码构建

Pulse 采用原生 Swift 与 SwiftUI 构建。编译当前源码需要完整的 **Xcode**（而非 Command Line Tools），并需要 **macOS 26 SDK**；运行时支持 **macOS 14+**。

```bash
# 克隆仓库
git clone https://github.com/qunqin24/Pulse.git
cd Pulse

# 打包为 macOS App Bundle
./Scripts/bundle.sh

# 启动
open build.noindex/Pulse.app
```

`swift run Pulse` 可快速编译运行而不打 Bundle，但通知与应用内更新只有打包后的应用才具备。开发环境配置见 [Docs/build-from-source.md](Docs/build-from-source.md)；发版说明见 [Docs/releasing.md](Docs/releasing.md)。

---

## 参与贡献

文档放在哪、哪些行为不能回退、如何改对那一页：见 [CONTRIBUTING.md](CONTRIBUTING.md)。主题文档索引：[Docs/README.md](Docs/README.md)。

---

## 设计来源

Pulse 的灵感来自 [**Vinz**(@hivinz_)](https://x.com/hivinz_/status/2092996055248126353) 2026 年 8 月在 X 上分享的一个 UI 概念。Pulse 是独立的实现，交互、功能、动画和视觉细节均为自有。Vinz 与 Pulse 没有关联，也不为其负责。

---

## 开源许可

本项目遵循 [Apache 2.0 开源许可协议](LICENSE)。附带的第三方资源遵循其各自的许可协议，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

---

## Star 增长曲线

<a href="https://star-history.com/#qunqin24/Pulse&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=qunqin24/Pulse&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=qunqin24/Pulse&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=qunqin24/Pulse&type=Date" />
  </picture>
</a>
