<p align="center">
  <img src="AppIcon/pulse-icon-1024.png" width="112" alt="Pulse">
</p>

<h1 align="center">Pulse</h1>

<p align="center">
  <b>不用离开手头的事，就知道 Claude Code、Codex、Antigravity 还剩多少额度。</b>
</p>

<p align="center">
  <sub><b>macOS 14 Sonoma 或更高</b> · Apple 芯片与 Intel 通用 · <a href="README.md">English</a></sub>
</p>

<p align="center">
  <img src="Docs/panel.png" width="440" alt="Pulse 吸附在屏幕右侧，旁边展开着某个供应商的额度卡">
</p>

Pulse 是一个贴在屏幕边缘的小浮窗。扫一眼圆环就知道自己在什么位置；你不在附近时它缩成一条细线，凑近了再回来。不用切到某个后台页面去查，也不会在任务干到一半时才发现限流了。

## 安装

从 [Releases](https://github.com/qunqin24/Pulse/releases/latest) 下载最新的 **`Pulse-x.y.z.dmg`**，打开后把 Pulse 拖进「应用程序」。

Pulse 还没有 Apple 开发者签名，所以首次启动会被 macOS 拦下——而且 macOS 15 之后，右键 →「打开」这个老办法已经被 Apple 去掉了。只需一次：

1. 打开 Pulse，被拒绝后关掉那个弹窗。
2. 进入 **系统设置 → 隐私与安全性**，滚到 **安全性**，点 **仍要打开**。
3. 再打开一次，确认。

之后就能正常启动了，后续版本会自己更新。

## 它能做什么

<img src="Docs/rail.png" width="150" align="right" alt="胶囊上的三个圆环">

**三个 agent，一条胶囊。** Claude Code、Codex、Antigravity 各占一个圆环。颜色在你读数字之前就告诉你还有多少余地——绿、黄、红。点某个圆环可以只刷新它。

**是真实额度，不是估算。** 每个数字都来自供应商自己的账号。Pulse 从不根据本地 token 数反推百分比；供应商不给答案时，它就说不知道，而不是编一个看起来合理的。

**它知道你在干活。** 某个 CLI 正在处理一轮对话时，对应圆环里会有一段标记在转——依据是对话记录里真实的回合边界，而不是「最近写过文件」，所以一个跑得慢的工具调用不会被误判成已经结束。

**不碍事。** 可以吸附到屏幕左右任一边，也可以在桌面上自由放置；你不在附近时缩成 6pt 的细线；默认不进入其他应用的全屏空间。额度快用完时那条细线仍然会变红——一个会自己藏起来的监视器，总得留一种方式说「看我一眼」。

**花了多少钱。** 设置里会根据 CLI 自己的会话记录还原出一份消费历史，按各家公布的 API 价格计算——另外还有一个明确标注为「推算」的数字：当前这个额度窗口大概值多少钱。这个没有任何供应商会告诉你。

**自适应刷新。** 2 到 30 分钟之间浮动，没有变化时自动放慢，而不是全天候按固定频率轮询。

支持简体中文和英文，切换无需重启。三档整体尺寸。macOS 26 上可选液态玻璃材质。

<p align="center">
  <img src="Docs/settings.png" width="620" alt="Pulse 设置窗口的「通用」页">
</p>

## 这些数字是怎么来的

三家各自提供的读取方式完全不同，各有各的代价：

| | 读取方式 | 注意 |
|---|---|---|
| **Claude Code** | 账号的用量接口，用 Claude Code 已保存的登录信息；失败时回退到状态栏，Pulse 可以把自己注册上去 | 保存的令牌几小时就过期，且没有任何东西替 Pulse 续期，所以才需要回退 |
| **Codex** | Codex 自家客户端用的同一个接口，失败时回退到 `codex app-server` | 不是公开 API，随时可能变 |
| **Antigravity** | 编辑器在本机回环地址上跑的 language server | 只在 Antigravity 开着时才有数据——额度就存在那个进程里 |

某次读取失败时，会退回上一次成功的读数，并标注它是什么时候取的，而不是当成当前值糊弄过去。

## 隐私

Pulse 没有自己的后端。它只访问你的 CLI 本来就在访问的接口，用的是它们已经存在这台 Mac 上的凭据；消费历史完全在本机从已有的日志文件算出来。没有任何数据被上传。

## 从源码构建

```bash
swift run Pulse              # 构建并运行
swift build                  # 全量类型检查，含 preview
./Scripts/bundle.sh          # → build/Pulse.app
./Scripts/dmg.sh             # → build/Pulse-<版本>.dmg
```

`xcode-select` 必须指向 Xcode 而不是 CommandLineTools——`#Preview` 宏是由 Xcode 自带的插件展开的。如果构建报 `PreviewsMacros plugin not found`：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Swift tools 6.0；用 `Package.swift` 可以直接在 Xcode 里打开。没有测试目标，也没有配 linter。

## 代码结构

源码都在 `Sources/Pulse`，一个 SwiftUI 视图一个文件，供应商图标在 `Sources/Pulse/Resources`。[CLAUDE.md](CLAUDE.md) 是更深入的说明（英文）——AppKit 浮窗与 SwiftUI 的分界、为什么拖拽归窗口管、三家各自的读取路径实际付出了什么代价。

## 许可

[Apache 2.0](LICENSE)。内置的第三方素材保留各自的许可，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
