<p align="center">
  <img src="AppIcon/pulse-icon-1024.png" width="112" alt="Pulse">
</p>

<h1 align="center">Pulse</h1>

<p align="center">
  <b>不用挨个打开用量页面，就知道 Claude Code、Codex、Cursor 还剩多少额度。</b><br>
  免费开源的 macOS 小工具，贴在屏幕边上，所有 AI 编程额度一眼看完。
</p>

<p align="center">
  <a href="https://github.com/qunqin24/Pulse/releases/latest"><img src="https://img.shields.io/badge/%E4%B8%8B%E8%BD%BD-000000?style=for-the-badge&logo=apple&logoColor=white" alt="下载 macOS 版 Pulse"></a>
</p>

<p align="center">
  <a href="https://github.com/qunqin24/Pulse/releases/latest"><img src="https://img.shields.io/github/v/release/qunqin24/Pulse?label=%E6%9C%80%E6%96%B0%E7%89%88%E6%9C%AC&color=black" alt="最新版本"></a>
  <a href="https://github.com/qunqin24/Pulse/releases"><img src="https://img.shields.io/github/downloads/qunqin24/Pulse/total?label=%E4%B8%8B%E8%BD%BD%E9%87%8F&color=black" alt="下载量"></a>
  <a href="https://github.com/qunqin24/Pulse/stargazers"><img src="https://img.shields.io/github/stars/qunqin24/Pulse?label=%E6%98%9F%E6%A0%87&color=black" alt="GitHub 星标"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/%E8%AE%B8%E5%8F%AF-Apache%202.0-blue" alt="Apache 2.0 许可"></a>
</p>

<p align="center">
  <sub><b>macOS 14 Sonoma 或更高版本</b> · Apple 芯片与 Intel 通用 · <a href="README.md"><b>English</b></a> · <b>简体中文</b> · <a href="README.zh-Hant.md"><b>繁體中文</b></a> · <a href="README.ja.md"><b>日本語</b></a> · <a href="README.ko.md"><b>한국어</b></a> · <a href="README.ru.md"><b>Русский</b></a></sub>
</p>

<p align="center">
  <img src="Docs/images/demo.gif" height="400" alt="贴在屏幕边缘的 Pulse 悬浮胶囊">
  &nbsp;&nbsp;
  <img src="Docs/images/panel.webp" height="400" alt="指针移到圆环上，会打开一张卡片，列出每项额度和重置时间">
</p>

- **77 个服务，一眼看完**——Claude Code、Codex、Cursor、GitHub Copilot、Antigravity、Kiro、Grok、DeepSeek、Kimi Code 等等，每个都有自己的圆环。
- **没有 Pulse 账号，也没有 Pulse 服务器**——直接用你已有的登录，不回传任何东西。
- **只显示真实数字**——每个用量百分比都是服务商自己报告的。少数估算会明确标出；服务商没给数字时，Pulse 会直说，不去猜。
- **原生、安静**——用 Swift 和 SwiftUI 写成，macOS 26 上是液态玻璃。可以停靠在左边、右边、顶部，或底部程序坞旁边，闲置时收成一条细线，也可以只待在菜单栏里。

**最近新增：** 菜单栏显示用量，并带每个账号的面板；额度重置后自动开始新窗口；会动的小机器人标记。[更新说明](https://github.com/qunqin24/Pulse/releases/latest)。

<p align="center">
  <img src="Docs/images/bot-mark.gif" width="300" alt="Pulse 动画标记：每个环里的小机器人会随该账号的状态反应">
</p>

<p align="center">
  <sub>如果 Pulse 帮你躲过了一次突如其来的限额，点个 ⭐ 能让更多人发现它。</sub>
</p>

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

## 核心特性

### 一眼看清的圆环
- **颜色随用量变化**——从绿到琥珀再到红，也可以给每个账号设一种自己的颜色。
- **已用或剩余**——显示 `75% 已用` 或 `25% 剩余`，可加一圈时钟弧，表示当前窗口已经过去多少。
- **实时动态**——agent 工作时圆环上有转动的小点；可选的小机器人会随每个账号的状态做动作。

### 指向圆环就能看细节
- **每条限额和它的重置时间**，都在一张卡片上，进度条可选连续或分段。
- **详细卡片**——套餐、读取时间、每条限额值多少钱，以及本机记录里最近的用量。
- **消耗速度预测**——按现在的速度会在窗口重置前用完时提醒你。
- **菜单栏**——把用得最多的圆环显示成数字、小圆环或并排的限额，可选打开用量面板。

<p align="center">
  <img src="Docs/images/detailed-card.webp" width="620" alt="同一个 Codex 账号的简洁额度卡与详细额度卡">
</p>

### 不打扰你
- **停在哪都行**——左、右、顶部、程序坞旁边，或任意位置；闲置时收成一条细线。
- **自己选的通知**——限额越线、用尽、重置、连续读取失败、余额不足、服务商故障。
- **六种界面语言**——英语、简体中文、繁体中文、日语、韩语和俄语。
- **可选功能**——全局快捷键、跟随当前显示器、截图时隐藏。

### 消耗、状态及其他
- **Token 消耗**——54 种本机客户端用了多少，按公开 API 价格估算，可按天、模型和 agent 查看，统计区间可以自己选。
- **用你的货币显示估算**——美元、人民币、港元、新台币、日元、韩元或卢布。
- **用量报告**——用同一份记录生成、适合分享的日报、周报、月报和年报卡片。
- **服务状态**——44 个服务商的官方状态页，出故障时可以通知你。
- **连接诊断**——每个数字从哪来，以及服务器的原始回应。
- **进阶**——同一服务商多个账号、接入自己数据源的扩展、供脚本使用的 `Pulse --json`。

<p align="center">
  <img src="Docs/images/spend.webp" height="290" alt="Token 消费：合计、按类型的用量与每日规律">
  &nbsp;&nbsp;
  <img src="Docs/images/spend-history.webp" height="290" alt="按天、按月、按 agent 的 Token 消费">
</p>

**完整说明**（英文）：[Docs/features.md](Docs/features.md)。

---

## 支持的服务商与读取方式

77 个服务，每个都按产品本身的方式读取——它自己的用量接口、编辑器的登录态、本地 Language Server，或你粘贴的 key；每个百分比都是服务商自己报告的。[完整列表和各自的读取方式](Docs/supported-services.md)（英文）。

---

## 隐私与安全性

- **没有 Pulse 账号，也没有 Pulse 服务器**——你的 Mac 用你自己的登录态连接你在用的服务。
- **只有五类连接，全列在这里**——这些服务、它们的公开状态页、取模型价格的 [models.dev](https://models.dev)、仅在你选了美元以外的货币时才用的 [ExchangeRate-API](https://www.exchangerate-api.com)，以及检查更新的 GitHub/Sparkle。
- **你的 key 加密保存在本机**，Pulse 读取的本机用量记录也不会离开你的 Mac。

[详细说明](Docs/features.md#privacy-and-security)（英文）。

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

## 支持 Pulse

<p align="center">
  <sub>Pulse 是免费开源的，用爱发电、抽空更新。<br>如果它帮你躲过了一次突如其来的限流，欢迎请作者喝杯咖啡。</sub>
</p>

<p align="center">
  <a href="https://afdian.com/a/qunqin"><img src="https://img.shields.io/badge/%E7%88%B1%E5%8F%91%E7%94%B5-%E8%AF%B7%E4%BD%9C%E8%80%85%E5%96%9D%E6%9D%AF%E5%92%96%E5%95%A1-946CE6?style=for-the-badge" alt="在爱发电支持 Pulse"></a>
</p>

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
