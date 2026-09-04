<p align="center">
  <img src="AppIcon/pulse-icon-1024.png" width="112" alt="Pulse">
</p>

<h1 align="center">Pulse</h1>

<p align="center">
  <b>Claude Code、Codex、Antigravity、Cursor、OpenCode Go、Kimi Code、Ollama Cloud、<br>Z.ai、GLM、MiniMax、Grok、Grok Bot 或 GitHub Copilot 还剩多少额度。</b>
</p>

<p align="center">
  <sub><b>macOS 14 Sonoma 或更高</b> · Apple 芯片与 Intel 通用 · <a href="README.md">English</a></sub>
</p>

<p align="center">
  <a href="https://github.com/qunqin24/Pulse/releases/latest"><img src="https://img.shields.io/github/v/release/qunqin24/Pulse?color=black" alt="最新版本"></a>
  <a href="https://github.com/qunqin24/Pulse/actions/workflows/ci.yml"><img src="https://github.com/qunqin24/Pulse/actions/workflows/ci.yml/badge.svg" alt="构建"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue" alt="许可"></a>
</p>

<p align="center">
  <img src="Docs/demo.gif" width="330" alt="Pulse 贴在屏幕左侧的胶囊">
</p>

Pulse 是一个贴在屏幕边缘的小型悬浮监视器，用各服务商为你的账号上报的限额，显示你剩多少 AI 编码额度。它没有后端，也没有自己的账号。

## 安装

从 [Releases](https://github.com/qunqin24/Pulse/releases/latest) 下载最新的 **`Pulse-x.y.z.dmg`**，打开后把 Pulse 拖进「应用程序」。

Pulse 未经 Apple 公证，macOS 会阻止首次启动。先打开 Pulse 并关闭警告，然后前往 **系统设置 → 隐私与安全性**，点击**仍要打开**。只需一次，后续版本会自行更新。

## 功能

- 每个 Agent 一个圆环，颜色按用量变化：绿、琥珀、红，用尽后更深——也可以按账号自选颜色（用尽的限额仍会变红）。点击圆环刷新该服务。
- 指向圆环会展开一张卡片，列出该服务上报的每一项限额：已用多少、各窗口何时重置，以及可选的消耗速率预测（限额能否撑到本轮重置）。可以把某个窗口钉到圆环上；默认显示最接近用尽的那个。
- 可停靠屏幕左右两侧或顶部（菜单栏之上），也可悬浮在任意位置，包括拖到第二台显示器，并记住所在屏幕。离开时收成一条细线；额度快用完时细线变红。默认不进入其他应用的全屏空间。
- 圆环上的标记表示该 Agent 此刻是否正在工作（仅 Claude Code 和 Codex，其余几家本机没有会话记录）。
- 启动时先显示上次读数，并标注读取时间；读取失败时退回上一次成功的读数，而不是只报一个错误。
- 设置中根据 Claude Code 和 Codex 的会话记录生成消费历史，按公开 API 价格计算，另有一项明确标注的限额窗口价值估算。
- 支持同一服务的多个账号：登录第二个 Claude Code 或 Codex 订阅即可并排查看。
- 可配置：圆环顺序、间距、面板大小、两种胶囊各自的百分比开关、数字在圆环上方或下方、从正数改为倒数（显示剩余而非已用）、按账号自定义圆环颜色、可选的窗口时间进度弧、刷新间隔、语言（英语和简体中文，切换无需重启）。默认黑色面板；macOS 26 可选 Liquid Glass。
- 默认开机自启——这个决定只做一次，关掉后不会被改回来。通过 Sparkle 自动更新，更新包用 EdDSA 密钥签名。
- 自适应刷新，间隔 2 到 30 分钟；已关闭的服务不会被读取。

<p align="center">
  <img src="Docs/panel.png" height="300" alt="胶囊旁的详情卡片">
  &nbsp;&nbsp;&nbsp;
  <img src="Docs/settings.png" height="300" alt="Pulse 设置">
</p>

## 这些数字是怎么来的

| | 读取方式 | 注意 |
|---|---|---|
| **Claude Code** | 账号的用量接口，用 Claude Code 已保存的登录信息；失败时回退到状态栏 | — |
| **Codex** | Codex 自家客户端用的接口；失败时回退到 `codex app-server` | — |
| **Antigravity** | 编辑器在本机运行的 language server | 只在 Antigravity 打开时报告 |
| **Cursor** | 账号的用量摘要接口，用编辑器已保存的登录信息 | 按其账号页分成两个额度池显示 |
| **OpenCode Go** | 设置中粘贴 API key，或用 OpenCode CLI 已保存的登录信息 | — |
| **Kimi Code** | 设置中粘贴 API key | — |
| **Z.ai** | 设置中粘贴 API key | 国际站，国内 BigModel 的 key 不适用 |
| **GLM 编码套餐** | 设置中粘贴 API key，或读取 GLM 工具已保存的 key | 国内站（`open.bigmodel.cn`） |
| **MiniMax** / **MiniMax CN** | 设置中粘贴 API key | `api.minimax.io` 和 `api.minimaxi.com` |
| **Grok** | Grok Build CLI 自家的代理接口，用 `grok login` 已保存的登录信息 | 一个周额度池，全 Grok 产品共用，不只是 CLI |
| **Grok Bot** | Cursor 的 dashboard 接口，用 Cursor 编辑器已保存的登录信息 | 和上面的 Grok 是两笔额度：这个随 Cursor 套餐附送，不是 SuperGrok 的 |
| **GitHub Copilot** | 设备码登录 | 只申请 `read:user`，不需要你粘贴令牌 |
| **Ollama Cloud** | 登录后的设置页，会话从浏览器读取 | 没有额度 API。详见 [Docs/ollama-cloud.md](Docs/ollama-cloud.md) |

每个数字都是服务商上报的；Pulse 不根据本地 token 数估算百分比，服务商不回答时会直接说明。读取失败时退回上一次成功的读数并标注时间；已过重置时间的窗口会被丢弃。

## 隐私

Pulse 没有后端。多数服务用你自己的工具已保存在这台 Mac 上的登录信息读取；其余几家需要你粘贴 API key；Ollama Cloud 的会话从浏览器读取（仅限 `ollama.com` 及其登录 cookie）。key 和会话加密保存在 Pulse 自己的文件夹中，仅本人可读。消费历史完全在本机计算。没有任何数据被上传。

## 从源码构建

见 [Docs/build-from-source.md](Docs/build-from-source.md)（英文）。

## 代码结构

源码都在 `Sources/Pulse`，一个 SwiftUI 视图一个文件，供应商图标在 `Sources/Pulse/Resources`。更深入的说明见 [CLAUDE.md](CLAUDE.md)。

## 设计来源

感谢 [**Vinz**(@hivinz_)](https://x.com/hivinz_/status/2092996055248126353)。

Pulse 是照着他 2026 年 8 月在 X 上发的一个概念做出来的：一条贴在屏幕边缘的圆环胶囊，该知道的一眼就有，多余的一个都没有。那个想法是他的；这里大部分的工夫，其实是在尽量别把它做糟。他没有参与开发，也不为它负责。

## 许可

[Apache 2.0](LICENSE)。内置的第三方素材保留各自的许可，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
