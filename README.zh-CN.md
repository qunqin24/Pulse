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
</p>

<p align="center">
  <sub><b>macOS 14 Sonoma 或更高版本</b> · Apple 芯片与 Intel 通用 · <a href="README.md"><b>English</b></a></sub>
</p>

<p align="center">
  <img src="Docs/demo.gif" width="340" alt="贴在屏幕边缘的 Pulse 悬浮胶囊">
</p>

Pulse 是一个停靠在屏幕边缘的小巧悬浮监视器。它展示各服务自己上报的剩余额度——走的是该产品自己的客户端通道，而不是 Pulse 的服务器——无 Pulse 账号、无遥测。Pulse 不会自行编造用量百分比。

---

## 核心特性

### 一目了然的用量圆环
- **智能用量着色**：环形进度随使用率平滑变色（绿 → 琥珀 → 红 → 用尽深红），亦可按账号自定义专属高亮色。
- **实时工作状态灯**：圆环边缘带动态旋转光点，实时指示 Agent 是否正在生成或执行任务（支持 Claude Code 与 Codex）。
- **时间窗口进度弧**：可选的外层时钟副弧线，直观呈现当前限额窗口的时间流逝比例。
- **正数 / 倒数自由切换**：支持在“已消耗百分比（如 80% used）”与“剩余可用额度（如 20% left）”之间一键切换。

### 悬停详情卡与智能消耗预测
- **完整配额清单**：鼠标悬停在圆环上即可弹出详情卡，列出该平台的所有用量池、重置倒计时与生效状态。
- **消耗速率与耗尽预测**：智能分析当前使用节奏是否足以撑到本轮周期重置；存在耗尽风险时，自动预测大致枯竭时间。
- **置顶核心配额**：可自由指定将关注的配额钉在圆环主视图，或由系统默认展示最临近用尽的配额。

### 原生丝滑、静默无扰
- **多位置随心停靠**：可吸附停靠在屏幕左边缘、右边缘或顶部（菜单栏之上），亦可在屏幕任意位置自由悬浮。
- **多显示器支持**：随心拖拽到外接屏幕，自动记忆所在显示器位置；拔掉副屏后自适应回归主屏。
- **边缘微光收起**：闲置时自动折叠为一条极窄细线，不遮挡代码与工作视线；仅在额度见底预警时细线泛红提醒。
- **全屏空间避让**：默认不在其他全屏应用（Spaces）中弹出干扰。
- **原生质感**：提供沉稳耐看的纯黑底板，macOS 26+ 更可选原生 **Liquid Glass（流动玻璃）** 材质。

### 多账号管理与本地消费账本
- **多账号并行**：支持同一服务绑定多个订阅（Claude Code、Codex、Grok、Grok Bot），并排查看并自定义标签。
- **本地消费历史**：直接解析本地 CLI 会话日志，基于官方公开 API 价格折算历史总消费，并估算限额窗口的实际价值。
- **本地优先**：无 Pulse 服务器、无 Pulse 账号、无遥测。请求发往你已在使用的服务商（并遵循 macOS 系统代理设置）。

<p align="center">
  <img src="Docs/panel.png" height="300" alt="详情卡片">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="Docs/settings.png" height="300" alt="Pulse 设置界面">
</p>

---

## 支持的服务商与读取方式

Pulse 仅呈现各服务上报的数字，绝不依靠本地 Token 粗略估算。各产品的读取通道不同（已文档化的客户端接口、编辑器登录态、本地 language server、粘贴的密钥），并不是每一行都有公开的官方配额 API。贡献者细节见 [Docs/providers/README.md](Docs/providers/README.md)。

| 服务商 | 读取通道与鉴权方式 | 说明与特性 |
|---|---|---|
| **Claude Code** | 账号 OAuth 用量接口；自动回退至 Claude 桌面端 Web 会话及状态栏 | 优先复用本机已存凭据，支持终端及桌面端混合无缝切换 |
| **Codex** | 客户端用量接口；回退至 `codex app-server` | 自动复用本地 Codex 登录凭证 |
| **Antigravity** | 编辑器本地运行的 Language Server (LSP) | 在 Antigravity 编辑器运行期间实时报告 |
| **Cursor** | Cursor 账号用量摘要接口 | 读取编辑器已保存凭据，分别展示 Fast / Slow 两个额度池 |
| **Grok** | Grok Build CLI 代理接口 | 一个统一的周额度池，与网页/CLI/API 全线 Grok 共享 |
| **Grok Bot** | Cursor 仪表盘接口 | Cursor 套餐内包含的 xAI 专属额度 |
| **GitHub Copilot** | GitHub 设备码（Device Code）登录 | 仅申请极窄的 `read:user` 权限，绝不触碰你的仓库代码 |
| **OpenCode Go** | 设置中填入 API Key，或读取 OpenCode CLI 登录信息 | — |
| **Kimi Code** | 设置中填入 API Key | — |
| **Z.ai** | 设置中填入 API Key | 智谱国际站（`api.z.ai`），与国内账号独立 |
| **GLM 编码套餐** | 设置中填入 API Key，或读取本地 GLM 工具已保存密钥 | 智谱国内站（`open.bigmodel.cn`） |
| **MiniMax / MiniMax CN** | 设置中填入 API Key | 同时支持国际站（`minimax.io`）与国内站（`minimaxi.com`） |
| **Ollama Cloud** | 本地读取浏览器登录会话 Cookies | 官方无配额 API。详见 [Docs/ollama-cloud.md](Docs/ollama-cloud.md) |

---

## 安装与快速上手

1. 前往 [Releases](https://github.com/qunqin24/Pulse/releases/latest) 下载最新的 **`Pulse-x.y.z.dmg`**。
2. 打开安装镜像，将 **Pulse** 拖拽至「应用程序（Applications）」文件夹即可。

> [!NOTE]
> **macOS 首次启动拦截处理**：  
> Pulse 是开源项目且未参与 Apple 付费公证，macOS 首次启动会触发安全拦截：
> - **图形界面方式**：启动 Pulse，关闭拦截弹窗，打开 **系统设置 → 隐私与安全性**，点击 **“仍要打开”**。
> - **终端快速放行（推荐）**：
>   ```bash
>   xattr -cr /Applications/Pulse.app
>   ```
> *(后续通过内置的 Sparkle 进行静默更新，无需再次授权)*。

---

## 隐私与安全性

Pulse 秉持“本地优先”与最小权限设计原则：
- **无 Pulse 后端**：没有 Pulse 服务器、账号或遥测。应用直接请求你已在使用的服务商，不插入自有代理；macOS 系统代理设置仍然生效。
- **凭据来源**：在产品本身如此工作时，复用本地开发工具已有的登录态（`~/.claude`、`~/.codex`、Cursor 本地状态等）；部分服务需要在设置中填写密钥或登录。
- **本地加密存储**：手动输入的 API Key 和 Session 均经过加密保存于 Pulse 应用目录内，权限仅限当前系统用户。
- **代码与对话**：Pulse 绝不读取或上传你的源码、终端上下文、Prompt 或模型生成内容。

---

## 从源码构建

Pulse 采用现代化 Swift 6 和原生 SwiftUI 构建，无沉重依赖。

```bash
# 克隆仓库
git clone https://github.com/qunqin24/Pulse.git
cd Pulse

# 直接编译并运行
swift run Pulse

# 或打包为标准的 macOS App Bundle
./Scripts/bundle.sh
```

更多开发环境配置，请参阅 [Docs/build-from-source.md](Docs/build-from-source.md)。发版说明见 [Docs/releasing.md](Docs/releasing.md)。

---

## 参与贡献

文档放在哪、哪些行为不能回退、如何改对那一页：见 [CONTRIBUTING.md](CONTRIBUTING.md)。主题文档索引：[Docs/README.md](Docs/README.md)。

---

## 设计来源

Pulse 的灵感来自 [**Vinz**(@hivinz_)](https://x.com/hivinz_/status/2092996055248126353) 2026 年 8 月在 X 上分享的一个 UI 概念。Pulse 是独立的实现，交互、功能、动画和视觉细节均为自有。Vinz 与 Pulse 没有关联，也不为其负责。

---

## 开源许可

本项目遵循 [Apache 2.0 开源许可协议](LICENSE)。附带的第三方资源遵循其各自的许可协议，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
