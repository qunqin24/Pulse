<p align="center">
  <img src="AppIcon/pulse-icon-1024.png" width="112" alt="Pulse">
</p>

<h1 align="center">Pulse</h1>

<p align="center">
  <b>Claude Code、Codex、Antigravity、Cursor、OpenCode Go、Kimi Code 或 Ollama Cloud 还剩多少额度。</b>
</p>

<p align="center">
  <sub><b>macOS 14 Sonoma 或更高</b> · Apple 芯片与 Intel 通用 · <a href="README.md">English</a></sub>
</p>

<p align="center">
  <img src="Docs/demo.gif" width="330" alt="Pulse 贴在屏幕左侧的胶囊">
</p>

Pulse 是一个贴在屏幕边缘的小型悬浮监视器，用来追踪你剩多少 AI 编码额度。它读取 Claude Code、Codex、Antigravity、Cursor、OpenCode Go、Kimi Code 和 Ollama Cloud 各自为你的账号真实上报的限额，显示成一条扫一眼就能看到、不用切回编辑器的胶囊。它没有后端，也没有自己的账号；每一个数字都来自对应 Agent 自己提供的读取方式。

## 安装

从 [Releases](https://github.com/qunqin24/Pulse/releases/latest) 下载最新的 **`Pulse-x.y.z.dmg`**，打开后把 Pulse 拖进「应用程序」。

Pulse 尚未使用 Apple 开发者签名，所以首次启动会被 macOS 拦下——而 macOS 15 之后，右键 → **打开** 这个老办法也被去掉了。只需一次：

1. 打开 Pulse。macOS 会拒绝，关掉那个弹窗。
2. 进入 **系统设置 → 隐私与安全性**，滚到 **安全性**，点 **仍要打开**。
3. 再打开一次，确认。

之后就能正常启动。后续版本会自己覆盖安装。

## 它能做什么

胶囊可以吸附到屏幕左右任一边，也可以吸附到顶部（在菜单栏之上），还可以在桌面上自由放置。每个 Agent 占一个圆环。你不在附近时，胶囊收成一条 6pt 的细线；额度快用完时，细线会变红。默认不会进入其他应用的全屏空间。

颜色就是读数本身，不是身份：低于警告阈值是绿色，到阈值是琥珀色，超过是红色，额度用尽后是更深的红色。点某个圆环，就现在重新取那一家的数据。胶囊启动时直接显示上一次的读数并标注取数时间，而不是空着等最慢的那家回应。

部分 Agent 用的是你自己的 CLI 或客户端已经存在这台 Mac 上的登录信息；两家需要你在设置里粘贴 API key；Ollama Cloud 根本没有额度 API，所以从你的浏览器里读出登录会话。已关闭的 Agent 不会被读取，也就不会为一个没人看的数字而花掉它的限额。

圆环还会告诉你那一家的 Agent 此刻是不是正在干活，依据是对话记录里真实的回合边界，而不是「最近写过文件」——所以一个跑得慢的工具调用不会被误判成已经结束。只有 Claude Code 和 Codex 有这个功能；其余几家没有留在本机的对话记录可读。

设置里会根据 Claude Code 和 Codex 自己的会话记录还原出一份消费历史，按各家公布的 API 价格计算，另外还有一个 Pulse 自己算出来的数字：明确标注为「推算」的某个额度窗口值多少钱。没有任何供应商会告诉你这个，其余几家也没有留本机日志可算。

胶囊按你的意思来：圆环顺序自己排，间距分三档，两种吸附方式下的百分比都可以关掉，也可以给某个账号指定一个固定颜色。默认仍按用量上色，因为选一个固定色等于主动放弃了这个读数；供应商判定为「已用尽」的额度，无论你选了什么颜色都保持用尽的颜色。被监控的账号按账号区分，而不是按供应商，所以你可以让第二个 Claude Code 或 Codex 订阅与第一个并排查看。

刷新是自适应的，在 2 到 30 分钟之间，空闲的机器会自动停止询问。刷新间隔、面板大小、圆环间距、百分比和语言都是设置项；英语和简体中文切换无需重启。

## 这些数字是怎么来的

每个数字都是对应 Agent 自己上报的。Pulse 从不根据本地 token 数反推百分比；供应商不给答案时，它会直说，而不是编一个看起来合理的。各家读取方式不同，代价也不同：

| | 读取方式 | 注意 |
|---|---|---|
| **Claude Code** | 账号的用量接口，用 Claude Code 已保存的登录信息——失败时回退到状态栏，Pulse 可以把自己注册上去 | 保存的令牌几小时就过期，且没有任何东西替它续期，所以才需要回退 |
| **Codex** | Codex 自家客户端用的同一个接口，失败时回退到 `codex app-server` | 不是公开 API，随时可能变 |
| **Antigravity** | 编辑器在本机回环地址上跑的 language server | 只在 Antigravity 打开时才有数据——额度就存在那个进程里 |
| **Cursor** | 账号的用量摘要接口，用编辑器已保存的登录信息拼出所需的 cookie | 不是公开 API。按 Cursor 自己账号页的口径分成两个额度池，而不是合成一个数 |
| **OpenCode Go** | 在设置里粘贴一个 API key——如果你已经在 OpenCode 自己的 CLI 里登录过，也会用它保存的登录信息 | 不是公开 API，随时可能变。这是 Pulse 唯一替自己持有的凭据 |
| **Kimi Code** | 在设置里粘贴一个 API key | 九家里唯一一个有公开文档的接口——但也不保证永远不变 |
| **Z.ai** | 在设置里粘贴一个 API key | 不是公开 API。国际站，用国内 BigModel 的 key 会被拒绝 |
| **GLM 编码套餐** | 在设置里粘贴一个 API key，或读取 GLM 工具已经存在本机的那个 | 不是公开 API。国内站（`open.bigmodel.cn`） |
| **Ollama Cloud** | 登录后的设置页，会话由 Pulse 从浏览器里读出 | 根本没有额度 API，网页是唯一来源。详见 [Docs/ollama-cloud.md](Docs/ollama-cloud.md) |

自己添加的账号是通过 Pulse 走一遍登录的，用的是对应 CLI 那个公开客户端，并持有自己的刷新令牌——不碰 CLI 自己的任何东西。

某次读取失败时，会退回上一次成功的读数，并标注它是什么时候取的。已经过了重置时间的窗口会被丢掉而不是继续变旧：它不是过期了，是已经重置了。

## 隐私

Pulse 没有后端。多数供应商用的是你自己的 CLI 或客户端已经存在这台 Mac 上的登录信息。例外是 OpenCode Go 和 Kimi Code，要你自己粘贴 API key；以及 Ollama Cloud，它的会话由 Pulse 从浏览器读出——这个读取只针对 `ollama.com`、只取用于认证的那几个 cookie 名，浏览器里其余的东西一概不看。这些凭据都加密存在 Pulse 自己的文件夹里，仅本人可读，密钥由这台 Mac 推导而来；不写进 `UserDefaults`，那是个任何以你的身份运行的进程都能读的 plist。

自己添加的账号的登录信息也是同样存法。消费历史完全在本机从已有的日志文件算出来。没有任何数据被上传。

## 从源码构建

见 [Docs/build-from-source.md](Docs/build-from-source.md)（英文）。

## 代码结构

源码都在 `Sources/Pulse`，一个 SwiftUI 视图一个文件，供应商图标在 `Sources/Pulse/Resources`。[CLAUDE.md](CLAUDE.md) 是更深入的说明——AppKit 浮窗与 SwiftUI 的分界、为什么拖拽归窗口管、九家各自的读取路径实际付出了什么代价。其中一家单独有一页：[Docs/ollama-cloud.md](Docs/ollama-cloud.md)，因为从浏览器里读会话这件事值得完整写下来。

## 设计来源

感谢 [**Vinz**(@hivinz_)](https://x.com/hivinz_/status/2092996055248126353)。

Pulse 是照着他 2026 年 8 月在 X 上发的一个概念做出来的：一条贴在屏幕边缘的圆环胶囊，该知道的一眼就有，多余的一个都没有。那个想法是他的；这里大部分的工夫，其实是在尽量别把它做糟。他没有参与开发，也不为它负责。

## 许可

[Apache 2.0](LICENSE)。内置的第三方素材保留各自的许可，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
