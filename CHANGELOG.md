# Changelog

What each release changed, written for somebody deciding whether to install it.

This file is the source for both the GitHub release page and the text Sparkle
shows in the update window — see [Scripts/changelog.py](Scripts/changelog.py).
Add the entry **before** tagging, in the small grammar the converter knows:
bullets, `**bold**`, `` `code` `` and `[links](https://example.com)`.

## 1.12.5

**中文**

**新功能**

- **圆环中的小机器人换成了 Agent Robot Avatar。** 小机器人现在是 CX ArtLab 的原创作品，在「设置」中对应账号的「圆环中显示小机器人」开启，并可选择颜色、性格和外形；默认关闭，之前开启过的需要重新开启。
- **支持 DimAgent。** 通过已登录的 `dim` 命令行读取 DimAgent 的套餐额度、加油包和 token 窗口，在「设置」中启用。感谢 [@sunny0826](https://github.com/qunqin24/Pulse/pull/99) 贡献。

**改进与修复**

- **Devin 卡片显示经 Oh My Pi 产生的用量。** 只通过 Oh My Pi 使用 Devin 时，详细卡片的「本机」历史不再为空。感谢 [@Edfghdrtxxx](https://github.com/qunqin24/Pulse/pull/104) 贡献。
- **Codex 固定的圆环不再失效。** Pulse 改用 `codex app-server` 读取时，「圆环显示」中选择的额度仍然生效。感谢 [@tyrival](https://github.com/qunqin24/Pulse/issues/102) 反馈。
- **浏览器 Cookie 被系统拒绝读取时给出正确提示。** 设置中会提示在「完全磁盘访问权限」中重新添加 Pulse，不再提示重新登录。感谢 [@momusticks](https://github.com/qunqin24/Pulse/issues/101) 反馈。
- **圆环中的图标更大。** 服务商图标填满中间的圆盘，更容易辨认。

**English**

**New**

- **The robot in the rings is now Agent Robot Avatar.** The robot is an original character by CX ArtLab, turned on with Robot in the ring in an account's settings, where its colour, personality and shape can be chosen; off by default, and it needs turning on again where it was on before.
- **DimAgent support.** DimAgent's plan credits, add-on packs and token windows are read through the signed-in `dim` CLI; turn it on in Settings. Thanks to [@sunny0826](https://github.com/qunqin24/Pulse/pull/99) for the contribution.

**Changed and fixed**

- **The Devin card shows usage made through Oh My Pi.** Where Devin is used only through Oh My Pi, the detailed card's On this Mac history is no longer empty. Thanks to [@Edfghdrtxxx](https://github.com/qunqin24/Pulse/pull/104) for the contribution.
- **A Codex ring pinned to a limit stays pinned.** The limit chosen in Ring shows still applies when Pulse reads Codex through `codex app-server`. Thanks to [@tyrival](https://github.com/qunqin24/Pulse/issues/102) for reporting it.
- **A browser cookie store macOS refuses is reported as such.** Settings asks to add Pulse again under Full Disk Access instead of asking to sign in again. Thanks to [@momusticks](https://github.com/qunqin24/Pulse/issues/101) for reporting it.
- **Larger icons in the rings.** A provider's icon fills the disc in the middle of its ring, so it is easier to recognise.

## 1.12.4

**中文**

**新功能**

- **实验性功能：水滴式吸附。** 在「设置 → 实验性功能」中开启后，从屏幕边缘拉开胶囊时，它会像水滴一样被拉长再断开，拖近边缘时会被吸过去；默认关闭。
- **测试通知。** 在「设置 → 通知」中点「发送」，立即收到一条测试通知，确认通知能正常送达。

**改进与修复**

- **Cursor 加密保存登录后仍能读取用量。** Pulse 向钥匙串请求 Cursor 的密钥来读取登录，被拒绝后只在下次启动或手动刷新时再次询问。感谢 [@Hill-1024](https://github.com/qunqin24/Pulse/pull/93) 贡献。
- **显示 Cursor 企业账号的额度。** 只报告一个总额度的企业账号，卡片显示为月度额度，金额以美元显示。感谢 [@lexleizou](https://github.com/qunqin24/Pulse/pull/97) 贡献。
- **Kimi Code 的用量记录包含新版 Kimi Code。** 「Token 消耗」和 Kimi Code 设置页同时读取新版 Kimi Code 的会话记录，能识别模型时按公开价格估算。
- **Codex 会话不再重复计算。** 同一会话同时出现在 `sessions` 和 `archived_sessions` 中时只计算一次。感谢 [@Drswith](https://github.com/qunqin24/Pulse/issues/95) 发现。
- **刘海处的胶囊与刘海对齐。** 胶囊按屏幕居中，过渡到屏幕边缘的圆角与刘海一致；尺寸为「小」且服务商较少时，顶部圆角不再被截成直角。
- **详细卡片不再显示「按 API 价格估算」的说明行。** 估算说明保留在「设置 → Token 消耗」中。

**English**

**New**

- **Experimental: liquid docking.** Turned on in Settings → Experimental, the rail stretches and parts like a drop when pulled off a screen edge, and is drawn in when brought near one; off by default.
- **Test notification.** Press Send in Settings → Notifications to receive a test notification and check that notifications reach you.

**Changed and fixed**

- **Cursor usage is read again when Cursor encrypts its saved login.** Pulse asks the keychain for Cursor's key, and after a refusal asks again only at the next launch or on a manual refresh. Thanks to [@Hill-1024](https://github.com/qunqin24/Pulse/pull/93) for the contribution.
- **Cursor Enterprise allowances are shown.** An Enterprise account that reports a single allowance shows it as the monthly limit, with amounts in dollars. Thanks to [@lexleizou](https://github.com/qunqin24/Pulse/pull/97) for the contribution.
- **Kimi Code's usage records include the new Kimi Code.** Token spend and the Kimi Code pane also read the new Kimi Code's session store, estimating money at published prices where the model is known.
- **Codex sessions are no longer counted twice.** A session found in both `sessions` and `archived_sessions` is counted once. Thanks to [@Drswith](https://github.com/qunqin24/Pulse/issues/95) for finding it.
- **The rail at the notch lines up with the notch.** It is centred on the display and its corners into the screen edge match the notch's; at the small size with few providers, its top corners are no longer cut off square.
- **The detailed card no longer shows the "estimated at API prices" line.** The explanation stays in Settings → Token spend.

## 1.12.3

**中文**

**改进与修复**

- **Antigravity 的 Gemini 3.8 Flash 按公开价格估算。** 记录中的 `-n`、`-control`、`-xpe` 变体与基础型号使用同一价格，不再显示为无公开价格。感谢 [@1206-skittle](https://github.com/qunqin24/Pulse/issues/90) 报告。

**English**

**Changed and fixed**

- **Antigravity's Gemini 3.8 Flash is estimated at its published price.** The `-n`, `-control` and `-xpe` variants in its records use the base model's rate instead of showing as having no public price. Thanks to [@1206-skittle](https://github.com/qunqin24/Pulse/issues/90) for reporting it.

## 1.12.2

**中文**

**新功能**

- **日报和周报。** 在「设置 → Token 消耗 → 用量报告」中打开，在窗口顶部切换日、周、月、年，生成可以分享的卡片。
- **Token 消耗可以自定义统计区间。** 「统计方式」新增本月、上月、今年和自定义范围，自定义范围可以选择开始和结束日期。
- **Qoder 显示积分数值和积分消耗记录。** 在 Qoder 设置页打开「显示积分数值」，卡片每一行同时显示积分数，例如 5,843 / 6,000；Qoder 的详细卡片和设置页显示整个账号今天、7 天和 31 天消耗与扣除的积分，以及按天的柱状图。感谢 [@momusticks](https://github.com/qunqin24/Pulse/issues/88) 提议。

**改进与修复**

- **Grok 的缓存和推理 token 不再重复计算。** 缓存命中率、token 总数和估算金额改为与 Grok Build 自身的记录一致。感谢 [@Edfghdrtxxx](https://github.com/qunqin24/Pulse/issues/91) 报告。
- **Antigravity 的金额估算更完整。** Gemini 3.1 Pro 和 Gemini 3.5 Flash (Low) 按公开价格估算；仍有模型没有公开价格时，卡片上的金额后标注 *。感谢 [@1206-skittle](https://github.com/qunqin24/Pulse/issues/90) 报告。
- **Qoder 圆环固定在「积分额度」上后，重启不再被重置。** 感谢 [@momusticks](https://github.com/qunqin24/Pulse/issues/89) 报告。
- **设置窗口的侧栏图标改为黑色，设置项中的选项改为弹出菜单。** 深色模式下图标为白色。
- **缩短俄文的 Token 活动视图名称。** 切换按钮不再被截断。感谢 [@winstik13](https://github.com/qunqin24/Pulse/pull/92) 贡献。

**English**

**New**

- **Daily and weekly recaps.** Open them from Settings › Token spend › Usage recaps and switch between day, week, month and year at the top of the window to make shareable cards.
- **Token spend over a span of your own.** Counting adds this month, last month, this year and a custom range with its own first and last day.
- **Qoder shows credit amounts and credit history.** Show credit amounts in Qoder's settings adds each row's credits to the card, such as 5,843 / 6,000, and Qoder's detailed card and settings pane show the whole account's credits used and charged today, over 7 and 31 days, and day by day. Thanks to [@momusticks](https://github.com/qunqin24/Pulse/issues/88) for the suggestion.

**Changed and fixed**

- **Grok's cached and reasoning tokens are counted once.** The cache hit rate, token totals and estimated cost now match Grok Build's own records. Thanks to [@Edfghdrtxxx](https://github.com/qunqin24/Pulse/issues/91) for the report.
- **Antigravity's cost estimate is more complete.** Gemini 3.1 Pro and Gemini 3.5 Flash (Low) are priced at their published rates, and an amount that still leaves out a model with no published price is marked with *. Thanks to [@1206-skittle](https://github.com/qunqin24/Pulse/issues/90) for the report.
- **A Qoder ring pinned to Credit allowance stays pinned after a restart.** Thanks to [@momusticks](https://github.com/qunqin24/Pulse/issues/89) for the report.
- **Settings' sidebar icons are black, and choices in settings rows are pop-up menus.** The icons are white in dark mode.
- **Shorter Russian names for the Token activity views.** The switcher no longer cuts them off. Thanks to [@winstik13](https://github.com/qunqin24/Pulse/pull/92) for the contribution.

## 1.12.1

**中文**

**改进与修复**

- **Cursor 显示每周用量上限。** 在 Premium 等按周计算额度的套餐上，Cursor 的圆环显示每周用量和重置时间，取代一直显示 0% 的两个月度用量池。感谢 [@HesionBlack](https://github.com/qunqin24/Pulse/issues/87) 报告。

**English**

**Changed and fixed**

- **Cursor shows the weekly usage limit.** On Premium and other plans with weekly included usage, Cursor's ring shows the week's usage and reset in place of the two monthly pools that always read 0%. Thanks to [@HesionBlack](https://github.com/qunqin24/Pulse/issues/87) for the report.

## 1.12.0

**中文**

**新功能**

- **44 个服务商的服务状态。** Copilot、Devin、Windsurf、Hugging Face、Gemini 等服务商的设置页显示官方状态页公布的状态和历史，可以随时刷新，在「设置 → 通知 → 服务出故障时」打开故障提醒，[对照表](https://github.com/qunqin24/Pulse/blob/main/Docs/providers/README.md#service-status)见文档。
- **估算金额可以换成你用的货币。** 在「设置 → 通用 → 货币」中选择人民币、港元、新台币、日元、韩元或卢布，按当日汇率或你填写的汇率换算，服务商自己报告的余额不换算。
- **连接诊断显示服务器的原始回应。** 在服务商设置页的「连接诊断」中展开「服务器原始回应」，查看每个请求的状态码和返回内容，凭证会被隐藏。
- **Antigravity 支持 agy CLI。** 编辑器没有运行时改用 `agy` CLI 读取额度，在 Antigravity 设置页的「用量来源」中选择自动、CLI 或桌面端。
- **MiniMax Code 的用量记录。** 打开 Token 消耗后，MiniMax 的卡片和设置页显示本机 MiniMax Code 的用量记录。感谢 [@Eileenes](https://github.com/qunqin24/Pulse/issues/86) 提议。
- **可以关闭自动吸附到屏幕边缘。** 在「设置 → 位置与行为」中关闭后，拖动只移动面板，可以放在屏幕任何位置，包括菜单栏和程序坞上方。感谢 [@GinWU05](https://github.com/qunqin24/Pulse/issues/85) 提议。
- **进度条样式。** 在「设置 → 外观 → 进度条」中选择连续或分段。

**改进与修复**

- **MiniMax 与 MiniMax CN 合并为一个服务商。** 在 MiniMax 设置页选择国际站或国内站，两个站点各自保存 key，原 MiniMax CN 的 key 和设置会在启动时自动迁移。
- **设置窗口改为系统设置的样式。** 侧栏延伸到窗口顶部，标题栏显示当前页面名称，并有后退和前进按钮（⌘[ 和 ⌘]）。
- **程序坞菜单里的「退出」只关闭窗口。** Pulse 继续留在菜单栏，⌘Q 和菜单栏图标中的「退出 Pulse」仍会退出整个 app。
- **金额不再显示「US$」。** 美元统一写作「$」，估算金额前也不再加「≈」。
- **OpenCode Go 订阅到期时提示没有套餐。** 不再误报「key 被拒绝」。
- **改进 Codex 的「较弱模型迹象」。** max 和 ultra 推理强度纳入比较，上下文窗口不再算作降级，推理在固定位置停下的比例只显示数字、不下结论。感谢 [@frankliness](https://github.com/qunqin24/Pulse/pull/83) 贡献。[#84](https://github.com/qunqin24/Pulse/pull/84)
- **刘海处的面板不会被路过的指针展开。** 指针停留片刻才展开，展开后立即按下的点击也不会误刷新圆环。
- **指针离开后，详情卡可靠收起。** 修复了偶尔要把指针移回去再移开才收起的问题。
- **液态玻璃调得更透明时，文字仍然清晰。** 透明度滑块越过默认值后，文字从白色逐渐变为黑色。
- **更省电，读取更快。** 面板收起时小机器人停止动画，读取本机用量记录更快、占用内存更少。
- **「读取途径检查」整行都可以点击展开。** 不必再点右侧的箭头。

**English**

**New**

- **Service status for 44 providers.** Copilot, Devin, Windsurf, Hugging Face, Gemini and others show their own status page's state and history in their settings, with Refresh; turn on outage alerts under Settings → Notifications → When a service is down, and see [which pages](https://github.com/qunqin24/Pulse/blob/main/Docs/providers/README.md#service-status).
- **Estimates in your own currency.** Choose yuan, Hong Kong or New Taiwan dollars, yen, won or roubles under Settings → General → Currency, converted at the day's rate or one you type; balances a provider reports are not converted.
- **Connection diagnostics show the servers' own replies.** Expand Server replies under Connection diagnostics in a provider's settings to see each request's status and what came back, with credentials hidden.
- **Antigravity through the agy CLI.** With the editor closed, Pulse reads the quota through the `agy` CLI; choose Automatic, CLI or Desktop app under Read usage from in Antigravity's settings.
- **MiniMax Code usage history.** With Token spend on, MiniMax's card and settings show this Mac's MiniMax Code usage. Thanks to [@Eileenes](https://github.com/qunqin24/Pulse/issues/86) for the suggestion.
- **Snap to screen edges can be turned off.** Turn it off under Settings → Position and behavior and a drag only moves the panel, anywhere on screen, over the menu bar and the Dock included. Thanks to [@GinWU05](https://github.com/qunqin24/Pulse/issues/85) for the suggestion.
- **Progress bar styles.** Choose Continuous or Segmented under Settings → Appearance → Progress bars.

**Changed and fixed**

- **MiniMax and MiniMax CN are one provider.** Choose the international or mainland site in MiniMax's settings, each keeping its own key; MiniMax CN's key and settings move over at launch.
- **Settings looks like System Settings.** The sidebar runs to the top of the window, and the title bar shows the current pane with back and forward buttons (⌘[ and ⌘]).
- **Quit in the Dock icon's menu closes the windows only.** Pulse stays in the menu bar; ⌘Q and Quit Pulse in the menu bar icon still quit the app.
- **No more "US$".** Dollars are written "$" everywhere, and estimated amounts no longer carry "≈".
- **An expired OpenCode Go subscription says there is no plan.** It is no longer reported as a refused key.
- **Better Codex weaker-model signs.** Max and ultra reasoning effort are ranked, the context window no longer counts as a downgrade, and the share of reasoning stopped at fixed points is shown as a figure with no verdict. Thanks to [@frankliness](https://github.com/qunqin24/Pulse/pull/83) for the contribution. [#84](https://github.com/qunqin24/Pulse/pull/84)
- **The panel at the notch no longer opens for a passing pointer.** It opens once the pointer rests there, and a click right after it opens no longer refreshes a ring by accident.
- **The detailed card closes reliably once the pointer leaves.** It no longer sometimes waits for the pointer to come back and leave again.
- **Text stays readable on clearer Liquid Glass.** Past the default transparency, the text turns gradually from white to black.
- **Less power, faster reading.** The animated marks stop while the panel is collapsed, and this Mac's usage records are read faster with less memory.
- **The whole Route checks row opens the list.** The arrow on the right is no longer the only target.

## 1.11.0

**中文**

**新功能**

- **俄语界面。** 在「设置 → 通用 → 语言」中选择。感谢 [@winstik13](https://github.com/qunqin24/Pulse/pull/77) 贡献翻译。
- **扩展可以上报自定义指标。** 例如首字时间和输出速率，显示在卡片上并画出趋势线，[写法](https://github.com/qunqin24/Pulse/blob/main/Docs/extensions.md#metrics)见文档。感谢 [@xkaaaaaa](https://github.com/qunqin24/Pulse/issues/80) 提议。
- **新增「不使用代理」和「使用代理」。** 在「设置 → 网络与刷新 → 代理」中选择，「使用代理」在系统代理未开启时不联网，默认仍为「跟随系统」。
- **截图时隐藏悬浮面板。** 在「设置 → 位置与行为」中打开「截图时隐藏」，支持此设置的截图工具不会再截到悬浮面板。

**改进与修复**

- **服务商确认没有套餐后，不再显示旧额度。** 适用于 z.ai、Xiaomi Coding Plan、Grok Bot 等。
- **清除 Xiaomi Coding Plan 的登录后，卡片提示重新登录。** 不再显示过期的旧额度。
- **重新登录的账号不会被旧登录的续期覆盖。** 适用于在 Pulse 中添加的 Claude Code 和 Grok 账号。
- **Qoder 分项显示时，到期说明不再重复。** 合计行不再显示到期，整行一起到期时写作「11月7日全部到期」。感谢 [@momusticks](https://github.com/qunqin24/Pulse/issues/76) 反馈。
- **Qoder 积分分多天到期时，卡片说明全部批次。** 例如「11月8日起分 4 批全部到期」。[#76](https://github.com/qunqin24/Pulse/issues/76)
- **打开「分项显示积分」后，圆环跟随最接近用完的一项。** 原来固定在合计上的圆环会改回自动。[#76](https://github.com/qunqin24/Pulse/issues/76)

**English**

**New**

- **Russian interface.** Choose it under Settings → General → Language. Thanks to [@winstik13](https://github.com/qunqin24/Pulse/pull/77) for the translation.
- **Extensions can report metrics of their own.** Figures such as time to first token and output rate appear on the card with a trend line; see [how to report them](https://github.com/qunqin24/Pulse/blob/main/Docs/extensions.md#metrics). Thanks to [@xkaaaaaa](https://github.com/qunqin24/Pulse/issues/80) for the suggestion.
- **No Proxy and System Proxy Only.** Choose them under Settings → Network and refresh → Proxy; System Proxy Only connects nowhere while macOS has no proxy switched on, and Follow System stays the default.
- **Hide the floating panel from screenshots.** Turn on Hide from screenshots under Settings → Position and behavior, and screenshot tools that support it leave the panel out.

**Changed and fixed**

- **Old figures are no longer shown once a provider confirms there is no plan.** This covers z.ai, Xiaomi Coding Plan, Grok Bot and others.
- **Clearing Xiaomi Coding Plan's sign-in asks you to sign in again.** The card no longer shows the old figures instead.
- **An account signed in to again is no longer replaced by the old login's renewal.** This covers Claude Code and Grok accounts added in Pulse.
- **Qoder's expiry lines no longer repeat when its credits are shown part by part.** The total no longer shows one, and a row whose credits all lapse together reads "All expire Nov 7". Thanks to [@momusticks](https://github.com/qunqin24/Pulse/issues/76) for the report.
- **Qoder credits lapsing over several days are described in full.** For example, "All expire from Nov 8, in 4 lots". [#76](https://github.com/qunqin24/Pulse/issues/76)
- **Turning on Show each part of the credits lets the ring follow the part closest to spent.** A ring pinned to the total returns to automatic. [#76](https://github.com/qunqin24/Pulse/issues/76)

## 1.10.0

**中文**

**新功能**

- **Qoder 积分可以分项显示。** 在 Qoder 设置的「面板」中打开「分项显示积分」，卡片会分别列出套餐积分、加油包和专属积分。感谢 [@momusticks](https://github.com/qunqin24/Pulse/issues/76) 提议。

**改进与修复**

- **开启剩余时间弧后，圆环不再贴着面板下边。** 停靠在屏幕顶部时，圆环一侧多留 10pt。感谢 [@cybershape](https://github.com/qunqin24/Pulse/issues/78) 反馈。
- **积分到期的说明不再被误读为剩余总量。** 卡片改为「其中 1,989 积分 11月7日 到期」。

**English**

**New**

- **Qoder's credits can be shown part by part.** Turn on Show each part of the credits in the Panel group of Qoder's settings to list plan credits, the top-up pack and dedicated credits on the card. Thanks to [@momusticks](https://github.com/qunqin24/Pulse/issues/76) for the suggestion.

**Changed and fixed**

- **The rings no longer sit against the panel's bottom edge with the time-until-reset arc on.** Docked at the top of the screen, the ring's side now has 10pt more room. Thanks to [@cybershape](https://github.com/qunqin24/Pulse/issues/78) for the report.
- **Expiring credits are no longer read as everything that is left.** In Chinese, Japanese and Korean, the card now says the expiring credits are part of the total.

## 1.9.0

**中文**

**新功能**

- **浅色面板。** 在「设置 → 外观 → 面板颜色」中选择「浅色」，面板改为浅灰底色和深色文字，停靠在刘海处时同样适用。感谢 [@brianzheng2024](https://github.com/qunqin24/Pulse/issues/74) 提议。

**改进与修复**

- **工具删除旧记录后，过去的用量不再减少。** Pulse 会保存已经读到的用量，Claude Code 等工具清理旧会话记录后，过去的 token、金额和回顾保持不变。
- **刘海处的面板与刘海更贴合。** 停靠在刘海处时，面板宽度与自由放置时一致，与屏幕顶边相接处的圆角也与刘海一致。
- **「一天的节奏」按实际用量说明时段。** 月度和年度回顾中的这张卡片改为显示用量最集中的连续 4 小时。
- **部分用量没有公开价格时也生成「订阅回本」卡片。** 卡片照常生成，并注明部分用量没有公开价格。
- **回顾从这台 Mac 最早有记录的那天算起。** 活跃天数、日均用量等统计不再计入记录开始之前的月份，卡片底部注明记录开始的日期。
- **回顾中的几处说明更准确。** 「通常开工」改为「最早开工」，月历中没有用量的日子统一显示为虚线框，开头改为「有 N 个 AI 工具和你一起写代码」。
- **回顾里的数字更准确。** 金额、缓存、同期对比、「最晚收工」和「一周七天」的计算均已修正，某一天或某个工具缺少数据时只留空该部分，不再整张卡片消失。
- **回顾的每张卡片都带上说明。** 月份未结束或记录从中途开始时，日历、开头、作息和月份卡片会注明。
- **菜单中用量面板的颜色随菜单外观调整。** 菜单显示为浅色时，用量条改用与浅色面板相同的较深颜色。

**English**

**New**

- **A light panel.** Choose Light under Settings → Appearance → Panel colour for a light grey panel with dark text, including when it is docked at the camera notch. Thanks to [@brianzheng2024](https://github.com/qunqin24/Pulse/issues/74) for the suggestion.

**Changed and fixed**

- **Past usage no longer shrinks when a tool deletes its old records.** Pulse now keeps the usage it has already read, so past days' tokens, money and recaps stay the same after Claude Code or another tool clears old sessions.
- **The panel fits the camera notch more closely.** Docked at the notch, the panel is as wide as it is when placed freely, and the curve where it meets the top of the screen matches the notch's own.
- **Rhythm of the day names your own busiest hours.** The card in the monthly and yearly recaps now shows the four hours in a row with the most usage.
- **The payback card appears when some usage has no published price.** The card is now generated and notes that some usage had no published price.
- **Recaps count from this Mac's first record.** Active days, the daily average and the other totals no longer count the months before records began, and the card footer gives the date records begin.
- **Clearer wording in the recaps.** "Usually starts" is now "Earliest start", days without usage in the month calendar are drawn as dashed outlines, and the opener counts "AI tools".
- **More accurate figures in the recaps.** Money, cache, period comparisons, Finishes latest and the days of the week are now calculated correctly, and a day or tool with missing data is left blank instead of removing the whole card.
- **Every recap card carries its notes.** The calendar, opener, timetable and months cards note when the period is still running or when records begin partway through.
- **Usage colours in the menu's usage panel follow the menu's appearance.** When the menu is drawn light, the usage bars use the same deeper colours as the light panel.

## 1.8.3

**中文**

**改进与修复**

- **修复每日用量图表遮挡详情卡片的问题。** 本机记录只有一天时，每日图表不再显示为覆盖卡片的大圆，设置和菜单栏中的每日图表也不再显示为宽色块。
- **Codex 额度余额按数字显示。** 设置中的「额度余额」按当前语言的数字格式显示，最多保留两位小数。

**English**

**Changed and fixed**

- **Fix the daily usage chart covering the detail card.** With only one day of local records, the daily chart on the hover card is no longer drawn as a large circle over the rows below, and the charts in Settings and the menu bar no longer draw wide blocks.
- **Show Codex's credit balance as a number.** The Credit balance row in Settings uses the number format of the current language, with at most two decimal places.

## 1.8.2

**中文**

**改进与修复**

- **保留不完整记录中的已知 Token 分类。** 只记录了总量或部分分类的来源，已记录的输入、缓存命中和输出照常显示，其余部分列为「未分类」。
- **每日明细支持查看未分类用量。** Token 消耗与模型详情的每日明细新增可排序的「未分类」列，没有未分类用量时自动隐藏。
- **统一 Token 分类展示。** 「新内容」改为「输入」，缓存命中单独统计，未记录的分类标注为「未记录」。
- **修复明细表的排序与表头显示。** 超大 Token 数量可以正确排序，表头保持单行显示。
- **优化界面与更新说明文案。** 简体中文、繁体中文、日文和韩文的界面文案统一了术语，历史版本的中文更新说明也已同步更新。

**English**

**Changed and fixed**

- **Keep known token categories when records are incomplete.** For sources that report only a total or some of the categories, recorded input, cache hits and output are shown, and the rest is listed as Unclassified.
- **Show unclassified usage in daily tables.** Daily tables in Token spend and model details gain a sortable Unclassified column, hidden when there is no unclassified usage.
- **Use consistent token categories.** Fresh input is now labelled Input, cache hits are counted separately, and missing categories are labelled Not reported.
- **Fix table sorting and headers.** Very large token counts now sort correctly, and column headers stay on one line.
- **Improve interface copy and release notes.** Simplified Chinese, Traditional Chinese, Japanese and Korean interface text now uses consistent terminology, and earlier Chinese release notes have been updated to match.

## 1.8.1

**中文**

**改进与修复**

- **自动更新支持备用下载通道。** GitHub 无法连接时，检查和下载更新会自动改用 update.qunqin.org，Pulse 只安装签名校验通过的更新。
- **更新说明只显示一种语言。** 中文界面显示中文更新说明，其他语言显示英文。
- **调整面板外观时不再重新拉取用量。** 修改大小、间距、玻璃效果等外观设置时，只重新排版面板。
- **修复保存的密钥可能被覆盖的问题。** 在设置中保存密钥与 DeepSeek 控制台登录的后台续期同时发生时，两者不再互相覆盖，已删除的 DeepSeek 登录也不会被重新写回。
- **修复钥匙串授权弹窗阻塞刷新的问题。** 读取 Claude Code 登录信息最多等待 60 秒，超时后改用其他方式读取。
- **修复月报大数字显示不完整的问题。** 9、5 等数字的右侧不再被裁切。
- **设置页布局优化。** 窗口较窄时，「位置」一行的选项自动换行，月报窗口的订阅价格输入框也改为与价格长度相称的宽度。

**English**

**Changed and fixed**

- **Updates arrive even where GitHub is out of reach.** When GitHub does not answer, checks and downloads go through update.qunqin.org, and Pulse installs only updates that carry its signature.
- **Update notes in one language.** They are shown in Chinese when Pulse's language is Chinese, and in English for every other language.
- **Changing how the panel looks no longer refetches usage.** Size, spacing, glass and the other appearance settings now only lay the panel out again.
- **Saved keys no longer overwrite each other.** Saving a key in Settings while DeepSeek's console sign-in is renewed in the background no longer loses either one, and a removed DeepSeek sign-in is no longer written back.
- **A Keychain prompt no longer holds up refreshing.** Reading Claude Code's sign-in waits at most 60 seconds before falling back to the other routes.
- **The recap's big numbers are no longer clipped.** The right side of a 9 or a 5 is no longer cut off.
- **Settings layout.** The Position row wraps its choices when the window is narrow, and the recap window's price field is now the width of a price.

## 1.8.0

**中文**

**新功能**

- **月报与年报。** 在「设置 › Token 消耗」中点击「查看九月的月报」或「查看 2026 年报」，即可把一个月或一年的 AI 编程记录生成为一组可保存、拷贝和分享的卡片。
- **回本卡支持自定义订阅价格。** 在月报窗口中填写每月订阅价格，即可查看订阅的用出倍数，不填写则不显示该卡片。
- **月报生成提醒。** 在「设置 › 通知」中开启「月报生成时」，每月初会提醒一次上个月的月报。
- **Token 活动图。** Token 消耗面板新增最近十二个月的用量图，可按天、按周或按累计总量查看。

**改进与修复**

- **会话列表更整洁。** Claude Code 的子代理记录并入所属会话，Codex 会话改用首条实际输入作为标题。
- **项目名更准确。** 在仓库工作树中进行的工作计入仓库名下，Codex 桌面版与 DeepSeek 的临时目录不再被识别为项目。
- **修复 Gemini CLI 等十个图标的显示问题。** 这些图标现在可以完整显示。
- **月报窗口打开时也显示 Dock 图标。** 与设置窗口一致，月报窗口可从 Dock 或 ⌘-Tab 找回。

**English**

**New**

- **Monthly and yearly recaps.** Open View September recap or View 2026 recap in Settings › Token spend to turn a month or a year of AI coding into a set of cards you can save, copy or share.
- **A payback card at your price.** Type your monthly plan price in the recap window to see how many times over you used it, or leave it empty to leave the card out.
- **A note when the recap is ready.** Turn on When a recap is ready in Settings › Notifications to be reminded of last month's recap early each month.
- **Token activity.** The Token spend pane charts the last twelve months by day, by week or as a running total.

**Changed and fixed**

- **Cleaner session lists.** Claude Code's subagent transcripts join the session they belong to, and Codex sessions are titled from the first thing you actually said.
- **Better project names.** Work in a repository's worktree counts under the repository, and Codex Desktop's and DeepSeek's scratch folders are no longer taken for projects.
- **Gemini CLI and nine other icons draw properly.** These icons are now drawn in full.
- **The Dock icon also shows while the recap window is open.** As with Settings, the recap window can be found again from the Dock or with ⌘-Tab.

## 1.7.3

**中文**

**新功能**

- **设置打开时显示 Dock 图标。** 被其他窗口遮挡的设置窗口可通过 Dock 或 ⌘-Tab 找回，该选项位于「设置 › 通用」的「应用」分组，默认开启。

**改进与修复**

- **Token 消耗统计更准确。** Codex 子任务不再重复计入主任务的历史，Claude Code 的一小时缓存写入和 OpenAI 的长上下文请求按官方价格计算，Devin CLI、OpenCode、Codebuff 和 Copilot 的重复计算也已修正。
- **Token 分类更清晰。** 用量分为「新内容」「缓存命中」「输出」三类，工具未记录缓存信息时显示「未记录」。
- **卡片统计按自然日计算。** 「最近 7 天」「最近 31 天」严格对应日历日期，无价格信息的模型显示「—」。
- **其他修复。** 修正了登录续期、OpenCode 控制台账号切换、登录失效提示、额外账号的刷新间隔、窗口启动器频繁唤醒、OpenCode Go 的月度区间，以及服务商返回异常数据导致崩溃的问题。
- **中文文案优化。** 简体和繁体中文统一使用「服务商」「账号」，诊断、集成和刷新设置中的语句也已修订。

**English**

**New**

- **A Dock icon while Settings is open.** A covered settings window can be found again from the Dock or with ⌘-Tab, set in Settings › General under Application and on by default.

**Changed and fixed**

- **More accurate token spend.** Codex sub-agents no longer count their parent's history again, Claude Code's one-hour cache writes and OpenAI's long-context requests are priced at the published rates, and double counting in Devin CLI, OpenCode, Codebuff and Copilot is fixed.
- **Token kinds that read plainly.** Usage is split into Fresh input, Cache hits and Output, and a tool that records no cache shows Not reported.
- **Card figures follow the calendar.** Last 7 days and Last 31 days now cover those calendar days, and a model with no price shows a dash rather than $0.00.
- **Other fixes.** Fixes cover sign-in renewal, switching OpenCode console accounts, lost sign-ins, the refresh interval for added accounts, the window starter's wake-ups, OpenCode Go's monthly window and crashes on malformed provider replies.
- **More natural Chinese.** Simplified and Traditional Chinese use one word each for provider and account, with plainer sentences across diagnostics, integrations and refresh settings.

## 1.7.2

**中文**

**新功能**

- **服务状态。** Codex、Claude Code 和 DeepSeek 的设置页新增「服务状态」，按官方状态页的样式显示各项当前状态、过去 90 天的记录和可用率。
- **服务故障通知。** 在「设置 › 通知」中开启「服务出故障时」，已启用的 Codex、Claude Code 和 DeepSeek 出现故障或恢复时会通知一次。

**改进与修复**

- **打开「关于」页时立即检查更新。** 版本行显示的是本次检查的结果。
- **降低资源占用。** 读取用量记录、汇总 Token 消耗和面板跟随鼠标时的重复计算大幅减少。

**English**

**New**

- **Service status.** Codex's, Claude Code's and DeepSeek's settings gain a Service status section showing each part's current state, the last 90 days and the uptime, as on each provider's status page.
- **Notifications when a service is down.** Turn on When a service is down in Settings › Notifications to be notified once when the Codex, Claude Code or DeepSeek you have switched on goes down or comes back.

**Changed and fixed**

- **Opening About checks for an update right away.** The version row shows the result of that check.
- **Lighter on your Mac.** Reading usage records, adding up token spend and following the pointer on the panel do much less repeated work.

## 1.7.1

**中文**

**新功能**

- **Codex 降智迹象检测。** 「设置 › Codex」底部新增「降智迹象」，根据本机的 Codex 记录统计推理被截断，以及模型、推理强度或上下文被更换的迹象。
- **DeepSeek 控制台用量读取。** 在 DeepSeek 设置的「DeepSeek 控制台」中点击「读取」，Pulse 会通过浏览器的登录状态读取整个账号最近 30 天的用量。

**改进与修复**

- **修复横放面板时百分比和数字的位置问题。** 同时开启「百分比放在圆环右边」和「数字显示在圆环上方」时，百分比不再显示到圆环左侧，数字也不再紧贴「距离重置的时间」的外圈。感谢 [@tyrival](https://github.com/qunqin24/Pulse/issues/73) 反馈。
- **卡片在屏幕空间不足时可滚动。** 面板横放在屏幕中部附近时，展开的卡片不再被屏幕边缘截断。

**English**

**New**

- **Signs of a weaker Codex model.** A new Signs of a weaker model section at the bottom of Codex's settings reads this Mac's Codex records for reasoning that was cut short and for turns that ran on a different model, lower reasoning or a smaller context.
- **DeepSeek usage from its console.** Press Read under DeepSeek console in DeepSeek's settings and Pulse uses your browser's sign-in to read the whole account's last 30 days.

**Changed and fixed**

- **The percentage and figures sit correctly on a panel lying across.** With Figures beside the rings and Figure above the ring both on, the percentage no longer jumps to the left of the ring, and figures no longer crowd the Time until reset arc. Thanks to [@tyrival](https://github.com/qunqin24/Pulse/issues/73) for the report.
- **A card scrolls when the screen cannot hold it.** With the panel lying across near the middle of the screen, an open card is no longer cut off at the screen's edge.

## 1.7.0

**中文**

**新功能**

- **详细卡片。** 在账号设置中开启「详细卡片」后，悬停卡片会额外显示套餐、更新时间、近期用量、缓存命中率和额度对应的大致金额。
- **按模型查看用量。** 「设置 › Claude Code / Codex」的「用量记录」下新增「模型」卡片，显示各模型的用量占比、缓存命中率和输出速度。
- **提示缓存列表。** Claude Code 和 Codex 的设置页列出所有仍持有缓存的对话及缓存的剩余时间。
- **OpenCode Go 读取官网记录。** 在 OpenCode Go 的设置中读取浏览器登录状态后，Pulse 会直接从官网控制台读取额度和每次请求的记录。
- **面板支持横向自由摆放，也可吸附屏幕底部。** 在「位置」中选择「自由（横向）」或吸附屏幕底部，面板可放在程序坞两侧的空白区域。感谢 [@GinWU05](https://github.com/qunqin24/Pulse/issues/70) 提议并参与实现横向自由摆放。

**改进与修复**

- **修复 Claude Code 用量重复计算的问题。** 继续或分叉对话时携带的历史副本不再计入用量。
- **修复 Claude Code 输出 token 少算的问题。** 分多行写入的回复现在完整计入输出量。
- **额度价值估算更稳定、更准确。** 估算只统计到读取额度的时刻，用量不足 5% 或账号在其他设备上同时使用时不显示估算。
- **支持 OpenCode 2 的记录。** 升级到 OpenCode 2 后的用量会计入 Token 消耗。
- **Token 消耗改为后台读取。** 开启后，Pulse 在后台保持数据更新，打开页面时直接显示。
- **菜单栏图标更换为 Pulse 标志。** 菜单中的用量面板改为开关，默认关闭。

**English**

**New**

- **A detailed card.** Turn on Detailed card in an account's settings and its hover card adds the plan, when it was updated, recent usage, the cache hit rate and roughly what each limit is worth.
- **Usage by model.** Under Usage history in Claude Code's and Codex's settings, a new Models card shows each model's share, cache hit rate and output speed.
- **Prompt cache list.** Claude Code's and Codex's settings list every conversation still holding a cache, and how long it has left.
- **OpenCode Go from its own console.** Read the browser sign-in in OpenCode Go's settings and Pulse reads the limits and every request straight from the console.
- **Float the panel lying across, or dock it to the bottom of the screen.** Choose Free across or the bottom edge under Position to place the panel in the empty space either side of the Dock. Thanks to [@GinWU05](https://github.com/qunqin24/Pulse/issues/70) for proposing and building the lying-across placement.

**Changed and fixed**

- **Claude Code's usage is no longer counted twice.** The copy of the old history that a resumed or forked conversation carries is no longer counted.
- **Claude Code's output tokens are no longer undercounted.** Replies written over several lines are now counted in full.
- **Steadier, more accurate value estimates.** Estimates count only up to when the limit was read, and none is shown under 5% used or while the account is in use on another device.
- **OpenCode 2's usage is read.** Usage after upgrading to OpenCode 2 now appears in Token spend.
- **Token spend reads in the background.** With it on, Pulse keeps the figures up to date, so the page opens on them.
- **The menu bar shows Pulse's own mark.** The usage panel in its menu is now a switch, off by default.

## 1.6.1

**中文**

**新功能**

- **额度重置后自动开始新窗口（可选）。** 在 Claude Code 或 Codex 的账号设置中开启「自动开始新窗口」，Pulse 会在每次重置后、你设定的时间段内，通过服务商自带的命令行工具发送一条「hi」，此功能默认关闭，开启前需要确认。

**改进与修复**

- **全新应用图标。** 一笔画成的 P，在 macOS 26 上支持液态玻璃效果，并跟随深色、透明和着色图标样式。
- **开启液态玻璃且面板吸附屏幕边缘时，圆环之间的空白区域也可拖动。** 设置中「开启后只能按住圆环拖动」的提示也已移除。感谢 [@annsyun](https://github.com/qunqin24/Pulse/issues/68) 反馈。

**English**

**New**

- **Start usage windows after a reset (optional).** Turn on Start windows automatically in a Claude Code or Codex account's settings and Pulse sends a single "hi" through the provider's own command-line tool after each reset, within the hours you choose; it is off by default and asks you to confirm first.

**Changed and fixed**

- **A new icon.** A P drawn in one stroke, in Liquid Glass on macOS 26 and following the dark, clear and tinted icon styles.
- **A docked Liquid Glass panel can be dragged from between its rings.** The settings caption saying only the rings can be dragged is gone. Thanks to [@annsyun](https://github.com/qunqin24/Pulse/issues/68) for reporting it.

## 1.6.0

**中文**

**新功能**

- **菜单栏用量显示。** 在「设置 › 通用」开启「在菜单栏显示用量」，菜单栏图标旁会以数字、迷你圆环或「分项」样式显示用量最高的圆环或指定账号。
- **菜单栏用量面板。** 点击菜单栏图标即可查看「概览」和各账号的额度、套餐、重置时间与 Token 消耗，并可按 ⌘R 立即刷新。
- **仅用菜单栏。** 关闭菜单中的「显示悬浮面板」，即可隐藏屏幕边缘的悬浮面板。
- **再次打开 Pulse 时弹出设置。** Pulse 在后台运行时，从「应用程序」或聚焦搜索再次打开会直接弹出设置窗口。

**改进与修复**

- **液态玻璃模式下，卡片尾部与卡片融为一体。** 复杂背景上的卡片尾部不再显示为独立的一块。
- **Grok 额度达到 100% 时视为已用完。** 与其他服务商一致，此时会发出「额度用完」通知。
- **删除额外账号时清除其全部设置。** 小机器人外观、余额提醒等设置不再残留。

**English**

**New**

- **Usage in the menu bar.** Turn on Show usage in the menu bar in Settings › General to show the fullest ring, or an account you pick, beside the menu bar icon as a figure, a small ring or Split.
- **A dashboard in the menu bar menu.** Click the menu bar icon for an Overview and a tab per account with each limit, the plan, resets and token spend, and press ⌘R to refresh.
- **Menu bar only.** Turn off Show floating panel in the menu to hide the floating panel at the screen edge.
- **Opening Pulse again opens Settings.** Opening Pulse from Applications or Spotlight while it runs brings up the settings window.

**Changed and fixed**

- **With Liquid Glass, the card's tail is part of the card.** Over a busy backdrop the tail no longer reads as a separate piece.
- **Grok's pool counts as spent at 100%.** As with every other provider, the spent notification is sent.
- **Removing an added account clears all of its settings.** Its animated mark, low-balance alert and other settings are no longer left behind.

## 1.5.2

**中文**

**改进与修复**

- **支持通过新版 ChatGPT 桌面应用读取 Codex 额度重置券。** Pulse 会同时在 ChatGPT 26.924 前后两个版本存放内置 codex 的位置查找。感谢 [@sanziliu](https://github.com/qunqin24/Pulse/issues/67) 定位问题。
- **卡片显示最近一张重置券的到期时间。** 到期时间精确到分钟，显示在券数量的下方。

**English**

**Changed and fixed**

- **Codex's limit reset credits are read with the newer ChatGPT desktop app too.** Pulse looks for the bundled codex where ChatGPT 26.924 puts it as well as where earlier versions did. Thanks to [@sanziliu](https://github.com/qunqin24/Pulse/issues/67) for tracking it down.
- **The card shows when the next reset credit expires.** The time is shown to the minute, under the count.

## 1.5.1

**中文**

**新功能**

- **扩展支持上报余额。** 扩展可上报账号余额和币种，圆环可选「自上次充值」「只看余额」或「我的预算」并设置低余额提醒，中转站示例见 [Docs/extensions.md](https://github.com/qunqin24/Pulse/blob/main/Docs/extensions.md)。感谢 [@Zoltan-code](https://github.com/qunqin24/Pulse/issues/40) 提议。

**改进与修复**

- **密钥输入框旁新增显示按钮。** 点击眼睛图标可查看输入的内容，切换到其他服务商时自动重新隐藏。
- **修复 API 服务设置页「圆环计算方式」遮挡说明文字的问题。** 该项原名「环上显示」，现已更名，避免与面板组中的同名设置混淆。
- **仅安装 ChatGPT 桌面应用时也能读取 Codex 额度重置券。** Pulse 会在 ChatGPT 应用内查找内置的 codex，完全找不到时显示「找不到 codex」。感谢 [@sanziliu](https://github.com/qunqin24/Pulse/issues/67) 反馈。

**English**

**New**

- **Extensions can report a balance.** An extension can report an account's balance and currency, with the same Since top-up, Balance only and My budget ring choices as an API account and a low-balance alert; a relay example is in [Docs/extensions.md](https://github.com/qunqin24/Pulse/blob/main/Docs/extensions.md). Thanks to [@Zoltan-code](https://github.com/qunqin24/Pulse/issues/40) for asking.

**Changed and fixed**

- **The key field has a show button.** Click the eye to see what you typed, and the key hides again when you open another provider.
- **Ring measures no longer covers its own description.** On an API account's settings page, the setting formerly called Ring shows has been renamed so it is no longer confused with the Panel group's row of the same name.
- **Codex's limit reset credits are read when only the ChatGPT desktop app is installed.** Pulse looks for the codex the app ships, and says so when no codex can be found at all. Thanks to [@sanziliu](https://github.com/qunqin24/Pulse/issues/67) for the report.

## 1.5.0

**中文**

**新功能**

- **新增 53 个服务商，共 77 个。** 新增阶跃星辰的 Step Plan，以及参考 [CodexBar](https://github.com/steipete/CodexBar) 移植、尚未用真实账号验证的 ClinePass、阿里云百炼、Gemini 等 52 个服务商，完整列表见 README。
- **扩展系统。** 将自编的小程序放入扩展文件夹，即可让 Pulse 显示某个账号的用量，编写方法见 [Docs/extensions.md](https://github.com/qunqin24/Pulse/blob/main/Docs/extensions.md)。感谢 [@guanbear](https://github.com/qunqin24/Pulse/issues/51) 提议。
- **订阅与 API 分组显示。** 设置侧边栏和首次启动的服务商选择窗口分为「订阅」和「API 与按量付费」两组，「已启用」的服务商排在顶部。
- **每个 API 服务均可选择圆环计算方式。** OpenAI API、Moonshot、New API 等上报余额的服务商均可分别选择「自上次充值」「只看余额」或「我的预算」。
- **Codex 卡片可显示额度重置券。** 在「设置 → Codex」开启「在卡片上显示额度重置券」，悬浮卡片会显示剩余数量。感谢 [@sanziliu](https://github.com/qunqin24/Pulse/issues/67) 提议。

**改进与修复**

- **支持读取通过 npm 或 nvm 安装的 Codex 的 app server。** 从 Finder 启动的 Pulse 现在也能找到 `node`，Kiro、arkcli 等命令行工具同样适用。
- **未选择服务商时，菜单栏菜单第一项会给出提示。** 关闭首次启动的选择窗口后，菜单会提示选择服务商。感谢 [@Drswith](https://github.com/qunqin24/Pulse/issues/66) 反馈。
- **面板窗口仅按已启用的服务商预留大小。** 服务商较多时，透明窗口不再远高于屏幕。
- **「顺序」列表仅显示已启用的服务商。** 未启用的服务商不再出现在列表中。
- **设置侧边栏加宽。** 较长的服务商名称不再被截断。

**English**

**New**

- **53 new providers, 77 in all.** StepFun's Step Plan joins 52 more ported from [CodexBar](https://github.com/steipete/CodexBar)'s providers and not yet checked against a live account, including ClinePass, Alibaba Cloud Model Studio and Gemini; the full list is in the README.
- **Extensions.** A small program of your own, put in the extensions folder, can report one account's usage for Pulse to draw as a ring; how to write one is in [Docs/extensions.md](https://github.com/qunqin24/Pulse/blob/main/Docs/extensions.md). Thanks to [@guanbear](https://github.com/qunqin24/Pulse/issues/51) for proposing it.
- **Subscriptions and API accounts are listed apart.** The Settings sidebar and the first-run chooser group providers under Subscriptions and API and pay-as-you-go, with Enabled at the top.
- **Every API account chooses what its ring measures.** OpenAI API, Moonshot, New API and every other account that reports a balance can each choose Since top-up, Balance only or My budget.
- **Codex's card can show limit reset credits.** Turn on Reset credits on the card in Settings → Codex, and the hover card shows how many are left. Thanks to [@sanziliu](https://github.com/qunqin24/Pulse/issues/67) for asking.

**Changed and fixed**

- **A Codex installed with npm or nvm now reaches its app server.** Pulse launched from Finder now finds `node`, and Kiro, arkcli and the other command-line tools are started the same way.
- **The menu bar menu says to choose providers when none are chosen.** After the first-run chooser is dismissed, the menu's first item asks you to choose providers. Thanks to [@Drswith](https://github.com/qunqin24/Pulse/issues/66) for reporting it.
- **The panel window is sized for the rings switched on.** With many providers, the transparent window is no longer far taller than the screen.
- **Order lists only the accounts switched on.** Accounts that are switched off no longer appear in the list.
- **A wider Settings sidebar.** Long provider names are no longer cut short.

## 1.4.1

**中文**

**新功能**

- **Qoder 显示积分包到期日。** 卡片显示最早到期的一批积分，例如「10月18日 86 积分到期」，`--json` 新增 `expiresAt` 和 `expiringAmount` 字段。感谢 [@momusticks](https://github.com/qunqin24/Pulse/issues/59) 提议。

**改进与修复**

- **修复 Qoder 体验版账号显示「未返回任何限额」的问题。** 大陆站体验版账号现在会正常显示剩余积分。感谢 [@momusticks](https://github.com/qunqin24/Pulse/issues/59) 查明原因。
- **购买 Qoder 积分包不再被误判为额度重置。** 只有 Qoder 的重置时间后移时，Pulse 才视为额度重置。
- **修复 Qoder 确认账号无积分时仍显示旧百分比的问题。** 缓存不再把上一次的读数带回面板和 `--json` 输出。感谢 [@tech-zjf](https://github.com/qunqin24/Pulse/pull/61)。
- **模型价格无需重启即可更新。** 价格表过期后会在下次读取时重新下载，下载失败时继续使用旧表。感谢 [@tech-zjf](https://github.com/qunqin24/Pulse/pull/60)。
- **小机器人的眼神和动作恢复原版幅度。** 眼神、手势和大幅动作按原版动画播放，不再额外压缩。
- **鼠标悬停胶囊时，小机器人依次转向。** 各圆环依次响应，约 0.4 秒内平滑转向指针。

**English**

**New**

- **Qoder shows when your credit packs lapse.** The card shows the soonest batch to expire, such as "Oct 18: 86 credits expire", and `--json` gains `expiresAt` and `expiringAmount`. Thanks to [@momusticks](https://github.com/qunqin24/Pulse/issues/59) for asking.

**Changed and fixed**

- **A Qoder trial no longer shows "no limits reported".** Trial accounts on the mainland site now show their remaining credits. Thanks to [@momusticks](https://github.com/qunqin24/Pulse/issues/59) for tracking down the cause.
- **Buying a Qoder pack is no longer read as a reset.** Only Qoder's reset date moving forward counts as a reset.
- **An old percentage no longer covers Qoder saying an account has no credits.** The cache no longer brings the previous reading back on the panel or in `--json`. Thanks to [@tech-zjf](https://github.com/qunqin24/Pulse/pull/61).
- **Model prices refresh without restarting Pulse.** An expired price table is downloaded again on the next read, and a failed download keeps the old one. Thanks to [@tech-zjf](https://github.com/qunqin24/Pulse/pull/60).
- **The bot moves as the original animation does.** Glances, gestures and larger moves play at full size, without extra damping.
- **The bots turn to an arriving pointer one after another.** Each ring responds in turn and faces the pointer over about 0.4 seconds.

## 1.4.0

**中文**

**新功能**

- **新增 Sub2API、New API、V2EX 和 Qoder，服务商增至二十四个。** 两个自建网关填入服务器地址和密钥即可读取余额或额度，V2EX 使用个人访问令牌读取 AI Chat 额度，Qoder 通过浏览器的登录状态显示积分额度。感谢 [@momusticks](https://github.com/qunqin24/Pulse/issues/59) 提议。
- **真实液态玻璃。** 开启「液态玻璃」后，面板为透明、带折射效果的 macOS 26 液态玻璃，并可用「透明度」滑块调节明暗。
- **时间圆环支持倒数。** 「距离重置的时间」的外圈可选「已过去」或「剩余」。感谢 [@Steven-oyjb](https://github.com/qunqin24/Pulse/pull/44)。
- **Kiro 与 ZCode 显示工作动画。** Pulse 读取这两个工具在本机写入的会话记录，判断任务是否正在进行。感谢 [@guanbear](https://github.com/qunqin24/Pulse/pull/56)。
- **设置按主题拆分为多个页面。** 外观、圆环与数字、位置与行为、通用、通知、网络与刷新各自独立，侧边栏搜索可按设置项名称定位页面。
- **每个服务商均提供配置指南。** 设置中的「配置帮助」会打开对应的页面，说明密钥或登录信息的获取位置、填写位置和常见错误。

**改进与修复**

- **修复贴边时鼠标推至屏幕最边缘被误判为离开的问题。** 开启自动收起时，胶囊不再反复展开和收起。
- **卡片切换更流畅。** 高度不同的卡片切换时，新增的行不再出现在卡片外部，快速扫过圆环时也不再显示空卡片。
- **修复小机器人偶发瞬移的问题。** 动作被中途打断时，身体会平滑过渡到下一状态。
- **Token 消耗：同名项目分开统计，无定价用量不再显示 $0.00。** 不同路径下的同名目录不再合并，无法定价的会话和项目显示「—」或带 `*` 的小计。感谢 [@tech-zjf](https://github.com/qunqin24/Pulse/pull/57)（[#58](https://github.com/qunqin24/Pulse/pull/58)）。

**English**

**New**

- **Sub2API, New API, V2EX and Qoder bring the count to twenty-four providers.** The two self-hosted gateways read a balance or allowance from a server address and key, V2EX reads its AI Chat allowance with a Personal Access Token, and Qoder reads your credits through your browser's sign-in. Thanks to [@momusticks](https://github.com/qunqin24/Pulse/issues/59) for asking.
- **Real Liquid Glass.** With Liquid Glass on, the panel is clear, refracting macOS 26 Liquid Glass, and a new Transparency slider sets how much it is dimmed.
- **The window clock can count down.** The outer arc of Time until reset can show time elapsed or time remaining. Thanks to [@Steven-oyjb](https://github.com/qunqin24/Pulse/pull/44).
- **Kiro and ZCode show activity too.** Pulse reads the session records these tools leave on this Mac to tell whether a turn is in flight. Thanks to [@guanbear](https://github.com/qunqin24/Pulse/pull/56).
- **Settings are split by subject.** Appearance, Rings and figures, Position and behavior, General, Notifications, and Network and refresh each have their own pane, and the sidebar search finds a pane by the names of its settings.
- **Every provider has a setup guide.** Setup help opens a page that explains where the key or login comes from, where it goes in Pulse and what each error means.

**Changed and fixed**

- **A pointer pushed against the screen edge no longer counts as leaving a docked rail.** With auto-collapse on, the rail no longer opens and closes over and over.
- **Switching cards is smoother.** An added row no longer appears outside the card, and sweeping across the rings no longer shows an empty card.
- **The animated mark no longer jumps.** An interrupted motion now eases into the next state.
- **Token spend keeps same-name projects apart and stops showing unpriced use as $0.00.** Directories with the same name at different paths are no longer merged, and usage that cannot be priced shows `—` or a subtotal marked `*`. Thanks to [@tech-zjf](https://github.com/qunqin24/Pulse/pull/57) ([#58](https://github.com/qunqin24/Pulse/pull/58)).

## 1.3.1

**中文**

**新功能**

- **Kiro 成为第二十个服务商。** Pulse 通过 Kiro CLI 内置的 ACP 接口读取当前账号的方案与额度，无需额外登录。
- **面板支持贴合刘海。** 停靠在屏幕顶部时，面板围绕刘海并延伸至屏幕边缘。
- **菜单栏图标可隐藏。** 隐藏后可通过面板或全局快捷键使用 Pulse，按 `Command-,` 也可直接打开设置。
- **更多外观与动画开关。** 面板警报颜色、CLI 活动动画和刷新动画均可关闭，面板两端也可保持与圆环一致的柔和曲线。

**改进与修复**

- **未选择显示的服务商不再被读取。** Pulse 仅扫描已监控服务商的本机 CLI 活动，未显示的服务商在设置中标注为「未显示」。
- **修复 Kiro 额度顺序变化打乱账号的问题。** 额度改按 Kiro 返回的资源类型识别，顺序变化后仍保留各自的显示设置和历史。
- **修复辅助进程重启后的错误超时。** Codex 和 Kiro 的旧请求计时器不再终止新的请求或报告延迟错误。
- **修复隐藏菜单栏图标导致无法进入应用的问题。** 面板不可用且快捷键注册失败时，Pulse 会自动恢复菜单栏图标。
- **修正 GLM 服务商图标与发布构建检查。** 两个 GLM 区域使用一致的服务商标识，发布构建不再因多余的警告而失败。

**English**

**New**

- **Kiro is the twentieth provider.** Pulse reads the current plan and allowances through the ACP service built into Kiro CLI, with no extra sign-in.
- **The rail can berth around the notch.** Docked at the top, the rail wraps the notch and reaches the screen edge.
- **The menu bar icon can be hidden.** Pulse can then be reached through the floating rail or global shortcuts, and `Command-,` opens Settings directly.
- **More appearance and motion controls.** The docked alert colour, CLI activity animation and refresh animation can each be turned off, and the rail's ends can follow the rings' own curve.

**Changed and fixed**

- **Providers that are not selected are no longer read.** Pulse scans local CLI activity only for watched providers, and a hidden provider is labelled “Not shown” in Settings.
- **Kiro allowance ordering no longer changes account identity.** Allowances are identified by the resource type Kiro returns, so display choices and history survive a reordered response.
- **Fixed false timeouts after helper restarts.** Old Codex and Kiro request timers no longer end a newer request or report a late failure.
- **Hiding the menu bar icon cannot lock the user out.** Pulse restores the menu bar icon if the rail is unavailable and no shortcut is registered.
- **Corrected the GLM provider marks and the release build check.** Both GLM regions use a consistent provider identity, and release builds no longer fail on a redundant warning.

## 1.3.0

**中文**

**新功能**

- **首次启动时先选择要监控的服务商。** 选择完成前，Pulse 不读取任何凭据，也不开始监控。
- **代理设置。** 网络可继续跟随 macOS，也可在设置中指定 HTTP、HTTPS 或 SOCKS5 代理，服务商请求、登录和辅助进程都使用同一配置。

**改进与修复**

- **Token 消耗改为明确开启后才读取。** 新安装默认关闭，开启后仅在查看该页面时扫描本机会话。
- **八种小机器人配备完整的动作编排。** 日常、工作、刷新、鼠标响应和完成反馈按顺序完整播放。
- **修复连续工作动画中小机器人眼睛被裁切的问题。** 眼睛不再在旋转和瞥视时被裁掉一半，Kimi 机器人的蓝色也已调亮。

**English**

**New**

- **Choose what Pulse may monitor before it starts.** Pulse reads no credentials and starts no monitoring until the first-run choice is saved.
- **Proxy settings.** Network traffic can follow macOS or use an HTTP, HTTPS or SOCKS5 proxy set in Settings, for provider requests, sign-ins and helper processes alike.

**Changed and fixed**

- **Token spend is read only after an explicit opt-in.** It is off on new installs, and once on it scans local sessions only while its Settings pane is open.
- **Each of the eight bots now has a complete authored choreography.** Everyday, working, fetching, pointer-attention and completion scenes play every beat in order.
- **Eyes remain whole through sustained work animation.** Turns and glances no longer clip half an eye, and Kimi's bot blue is lighter.

## 1.2.1

**中文**

**修复**

- **修复 Codex 导致 CPU 空转的问题。** `codex app-server` 退出后，Pulse 不再持续读取已关闭的管道而占满一个 CPU 核心。感谢 [@ethan-ji](https://github.com/qunqin24/Pulse/issues/25) 查明了原因、堆栈和触发条件。

**新功能**

- **小米 Coding Plan 成为第十九个服务商。** Pulse 通过浏览器中已登录的会话，读取小米 MiMo 控制台上按月购买的 token 额度和预付余额。
- **更新检查频率改为每两小时一次。** 仍仅提示更新，不会自动安装。

**改进**

- **小机器人现在朝向屏幕内侧。** 胶囊贴在右侧时看向左侧，贴在左侧时看向右侧，鼠标位于面板上时优先看向鼠标。
- **修复小机器人眼睛超出面部轮廓的问题。** 眼睛不再被推出轮廓而被裁切。
- **重写设置中小机器人相关的中文文案。** 新文案按中文表达撰写，不再逐字翻译英文。

**English**

**Fixed**

- **Codex no longer spins the CPU.** After `codex app-server` exits, Pulse no longer keeps reading its closed pipe and holding one core at full load. Reported by [@ethan-ji](https://github.com/qunqin24/Pulse/issues/25), with the cause, the stack and the conditions already worked out.

**New**

- **Xiaomi Coding Plan is the nineteenth provider.** Pulse reads the monthly token allowance and prepaid balance on Xiaomi's MiMo console through your signed-in browser session.
- **Updates are checked every two hours.** They are still offered, never installed on their own.

**Changed**

- **The bot now faces into the screen.** A rail docked right looks left, docked left looks right, and a pointer on the panel takes precedence.
- **The bot's eyes stay inside its face.** An eye is no longer pushed past the silhouette and clipped.
- **Rewrote the Chinese copy for the bot settings.** The new copy is written in Chinese rather than translated word by word.

## 1.2.0

**中文**

**新功能**

- **圆环可显示小机器人。** 在账号设置中可将圆环中的服务商图标替换为一个动态小机器人，反映 CLI 运行、读取和额度状态，默认关闭。
- **人格、形状与颜色。** 每个账号可分别选择小机器人的人格、身体形状和颜色，共有八种人格和十八种形状。
- **小机器人会对状态变化作出反应。** 眼睛跟随鼠标，工作时切换动作，额度重置和一轮工作完成时会庆祝。
- **关于页新增项目地址。** 关于页同时注明小机器人动画的移植来源。

**English**

**New**

- **Animated marks.** A ring's provider logo can be replaced, per account in its settings, by a small animated bot that shows whether the CLI is running, Pulse is fetching or the limit is spent; off by default.
- **Personality, shape and colour.** Each account can choose its mark's personality, body shape and colour, from eight personalities and eighteen shapes.
- **The bot reacts to what is happening.** The eyes follow the pointer, motions change while work is under way, and resets and finished turns are celebrated.
- **The project's address in About.** The About pane also credits the project the animated marks were ported from.

## 1.1.2

**中文**

**新功能**

- **更多 Token 消耗来源。** 新增 Gemini CLI、Cline、Roo Code、OpenClaw、GitHub Copilot 等本地记录，以及 Cursor、Trae 等导出数据，支持的格式见[来源说明](https://github.com/qunqin24/Pulse/blob/main/Docs/token-spend-sources.md)。
- **模型用量详情。** 点击模型可查看输入、输出、缓存读写、每日与每小时用量，以及各 Agent 的贡献。
- **图表悬停读数。** 悬停在历史图表上即可查看对应日期或小时的 token 数量。
- **面板右键菜单与全局快捷键。** 右键面板即可打开设置，也可自定义打开设置或显示、隐藏面板的快捷键。
- **繁体中文、日语和韩语。** 界面与 README 新增三种语言。

**改进与修复**

- **补全计价。** 仅由套餐商公布价格的模型已补全计价，Kilo CLI 的价格来源也已修正。
- **修复来源读取。** Antigravity IDE 读取自身的会话存储，Devin 记录不再误标为仅来自 CLI，已匹配的会话只统计一次。
- **修正区间统计。** 跨天汇总记录仅计入所选区间，Command Code 回退对话后仍保留已发生的消耗。
- **优化默认区间。** Token 消耗默认显示最近一周，并记住所选区间。
- **修复切换语言后设置侧栏变窄的问题。** 同时补充了 Agent 图标并更新了界面截图。

**English**

**New**

- **More token-spend sources.** Local records from Gemini CLI, Cline, Roo Code, OpenClaw, GitHub Copilot and more, plus exports from Cursor, Trae and others, are now read; see [sources and validation coverage](https://github.com/qunqin24/Pulse/blob/main/Docs/token-spend-sources.md) for supported formats.
- **Model usage details.** Open a model to see input, output, cache reads and writes, daily and hourly usage, and each agent's contribution.
- **Chart hover values.** Point at a history chart to see the token count for a date or hour.
- **Rail menu and global shortcuts.** Right-click the floating rail to open Settings, or set shortcuts that open Settings or show and hide the rail.
- **Traditional Chinese, Japanese and Korean.** The interface and README are now available in three more languages.

**Changed and fixed**

- **More complete pricing.** Models priced only by their plan vendor now have prices, and Kilo CLI's price source is corrected.
- **Source reading fixes.** Antigravity IDE reads its own conversation store, Devin records are no longer labelled CLI-only, and matched sessions count once.
- **Correct span totals.** Cross-day aggregate records count only their in-range usage, and Command Code rewinds keep consumption that already occurred.
- **A better default span.** Token spend defaults to the last week and remembers the span you choose.
- **The Settings sidebar no longer narrows after a language change.** Agent icons were also added and screenshots updated.

## 1.1.1

**中文**

**新功能**

- **Devin 成为第十八个服务商。** Pulse 从 Chromium 浏览器会话读取每日和每周额度，无需钥匙串授权。
- **Token 消耗统计。** 汇总 Claude Code、Codex、OpenCode、Kilo CLI、Grok Build、Kimi CLI 和 Devin CLI 的本机会话，可按区间、Agent、模型、项目、会话和 token 类型查看。
- **开发者集成。** 在设置中可导出 Raycast 扩展及 tmux、sketchybar、终端脚本，详见[配置指南](https://github.com/qunqin24/Pulse/blob/main/Docs/integrations.md)。
- **连接诊断。** 在设置中可查看最近的检查、读数来源和缓存，并复制不含账号详情或凭据的诊断信息。
- **变红阈值可调。** 在「变红阈值」中可选 60%–90%，默认 75%。

**改进与修复**

- **修复额度误报与凭据串写。** Claude Code 的 warning 不再被误判为额度耗尽，切换页面也不再覆盖另一服务商的凭据。
- **修复详情卡片展开、收起时沿胶囊漂移的问题。** 详情卡片在展开和收起时保持在原位。
- **修正区间与缓存。** 跨天会话仅计入所选区间，日志与数据库缓存更新、模型别名计价和自定义会话标题的读取也已修正。
- **修复 Devin 快照问题。** 旧快照按实际时间标注，过期窗口和超龄快照不再显示。

**English**

**New**

- **Devin is the eighteenth provider.** Pulse reads daily and weekly quota from your Chromium browser session without a keychain prompt.
- **Token spend.** Local sessions from Claude Code, Codex, OpenCode, Kilo CLI, Grok Build, Kimi CLI and Devin CLI are brought together by span, agent, model, project, session and token kind.
- **Developer integrations.** Export a Raycast extension and tmux, sketchybar and shell scripts from Settings; see the [setup guide](https://github.com/qunqin24/Pulse/blob/main/Docs/integrations.md).
- **Connection diagnostics.** Settings shows recent checks, sources and cache use, and copies diagnostics without account details or credentials.
- **Configurable warning colour.** Choose where rings turn red under Turn red at, from 60% to 90%, with 75% as the default.

**Changed and fixed**

- **Fewer false alarms and crossed credentials.** Claude Code warnings no longer read as exhausted, and switching panes no longer overwrites another provider's credential.
- **Detail cards stay in place.** Detail cards no longer drift along the rail as they open and close.
- **Correct spans and caches.** Cross-midnight sessions count only their in-range work, and log and database cache updates, model aliases and custom session titles are corrected.
- **Devin snapshot fixes.** Snapshots show their actual age, and expired windows and over-age snapshots are no longer shown.

## 1.1.0

- **A large balance no longer overflows the ring.** The rail shows ¥5k, ¥123k or $1.2M, always rounded down, with the exact balance on the card and in Settings.

- **The rail no longer sits slightly too low until you touch something.** The rail is drawn in the right place from launch instead of about 76pt too low.

- **API balances are checked more often.** DeepSeek and Command Code are now checked at least every five minutes.

- **The provider list starts in alphabetical order.** A rail you have arranged yourself keeps your order.

- **Tell me when the credit runs low.** Set Warn below in DeepSeek's or Command Code's settings, and Pulse notifies you once when the balance falls under it.

- **Notifications about a prepaid balance say less, and say it correctly.** Changing what the ring measures no longer announces a reset, and only the provider can declare a balance spent.

- **DeepSeek is the seventeenth provider.** Its ring measures the balance Since top-up, shows the Balance only, or measures against My budget, chosen in DeepSeek's settings.

- **智谱's row is now called "Zhipu".** Only the row's name has changed; the company, the storefront and the key it takes are the same.

## 1.0.9

- **Command Code is the sixteenth provider.** Its rings show the five-hour and weekly limits, your organisation's spend limits and an estimate of this month's plan, signed in with a pasted key or the one `cmd auth login` saved.

- **The panel can follow you between displays.** Turn on Follow the active display and the rail moves to the screen your pointer is on, keeping the same corner and distance.

## 1.0.8

- **The interface follows your Mac's language.** A Mac set to Chinese now gets Pulse in Chinese, and Settings › Language still overrides it.

- **Antigravity can show its two allowances as two rings.** Turn on A ring for each model group in Antigravity's settings to give the Gemini and the Claude-and-GPT allowances a ring each.

- **智谱 and z.ai get a usage history.** The token history comes from the account's own statistics, so it covers every machine you use.

- **A second limit on the ring.** Turn on Second limit inside the ring in Settings to show the next-fullest limit of the same kind as a thinner inner ring.

- **The panel no longer slides out from under you as you pick it up.** The rail now tracks the pointer exactly from the first frame of a drag.

- **The two GLM Coding Plan rows are now named for the shops.** They are called **z.ai** and **智谱**, so each key goes to the service that issued it.
- **A refused key now says the key was refused.** A key from the other one of the two shops is reported as refused rather than as a service error.

## 1.0.7

- **Pulse can tell you, instead of waiting to be looked at.** Three notifications in Settings, Warn at, When a limit comes back and When a reading stops arriving, stay off until you turn them on.
- **Each thing is said once.** A limit already past the line is announced once when the setting goes on, and again only after it resets or gets worse.
- **Antigravity reads from the IDE too.** Antigravity IDE now shows the same Gemini and Claude-and-GPT limits as the desktop app.
- **Antigravity no longer stops at the wrong helper.** Pulse asks each of Antigravity's helpers until one answers.
- **Reorder the rail by dragging.** Drag providers in Settings to reorder them, with Reset order under the list.
- **Volcengine is the fifteenth provider.** Its Ark Coding Plan and Agent Plan are read through `arkcli` or a Volcengine access key pair.
- **Usage as JSON with `Pulse --json`.** The command prints the figures the app last read, without fetching, for a tmux status line, sketchybar, Raycast or a shell prompt.
- **Settings has a search field.** The field matches provider names and your own account labels.
- **The Settings window opens bigger.** The window now fits its sidebar without opening already scrolled.
- **Notifications use the standard sound.** Change how they arrive in System Settings › Notifications › Pulse.

## 1.0.6

- **Grok joins the providers.** Pulse reads the weekly pool shared by every Grok product from the login Grok Build's CLI already stores.
- **Grok Bot joins the providers.** Its limit comes with a Cursor plan and is read with the login the Cursor editor already stores.
- **A second Grok or Grok Bot account.** Grok signs in with a device code and Grok Bot through Cursor's sign-in page, each asking only for access to read a limit.
- **Cards no longer show a window length the provider never reported.** A length used only to sort the rows is no longer printed when there is no reset time.
- **Single-route providers name the right route in Settings.** They are no longer described as "Antigravity's language server".

## 1.0.5

- **Claude Code read through the Claude desktop app.** Choose Desktop app under Read usage from, or let `Automatic` fall back to it, to read your limits from the session the desktop app is signed in with.
- **The new route says why it can't answer.** The card says whether the desktop app is signed out or the keychain was refused.
- **A reading no longer goes backwards.** A newer figure is no longer replaced by an older one that arrives late.
- **GitHub Copilot no longer shows a red ring for paid overage.** Going past the included allowance with overage permitted is no longer drawn as blocked.
- **Codex no longer marks the wrong model group as spent.** A group reporting "limit reached" marks only its own window.
- **Removing your only added account no longer empties the rail.** The rail goes on showing the providers that remain.

## 1.0.4

- **GitHub Copilot is the twelfth provider.** It signs in with a device code that asks only to read your profile, and shows your plan's completions, chat and premium-request allowances.
- **Whether a limit will last.** A switch in Settings adds a line under each limit on the card saying whether it will outlast its window.
- **Show what's left instead of what's spent.** Turn on Show what's left to read a limit as "88% left" rather than "12% used".
- **Claude Code's card names the plan.** The card shows "Max 5x", "Pro" or "Team", as other providers' cards already did.
- **The panel no longer stops refreshing after running a long time.** Pulse notices stale readings, recovers from a fetch that never returned, and refreshes when the Mac wakes.

## 1.0.3

- **The panel can go on a second display.** Drag the panel across, and Pulse remembers the screen and brings the panel home if that screen is unplugged.
- **Four more providers.** The GLM Coding Plan and MiniMax are added, each with separate international and mainland entries.
- **A second arc can show how far through the window the clock is.** Turn it on in Settings to read "80% used" against how much of the window is left.
- **The figure can sit above the ring.** Turn on Figure above the ring in Settings.
- **Providers that need an API key wait in Settings.** They are no longer switched on by themselves to ask for a key on the rail.
- **A provider without a key says so.** It no longer shows "Reading…" for ever.
- **Claude Code no longer shows a limit that has already reset.** A stale window from an expired login is dropped rather than shown with an old reset time.
- **The update window shows the release notes itself.** It no longer loads the GitHub page inside the window.

## 1.0.2

- **Multiple accounts.** Sign in to a second Claude Code or Codex subscription to watch both, each with its own ring.
- **Cursor joins the providers.** It is reported as the two pools its own account page shows.
- **Ollama Cloud joins the providers.** Its session is read from your browser rather than copied by hand, from PcOffeeP's pull request.
- **The rail can dock along the top of the screen.** It sits above the menu bar.
- **A colour of your own for any ring.** The gap between rings can be adjusted as well.
- **Percentages can be switched off.** They can be hidden on either rail.
- **The rail opens with the last reading.** It no longer sits blank at launch.
- **The activity mark stops when a turn ends.** It no longer keeps turning for a minute afterwards.
- **The API-key field lets go when you click away.** Clicking elsewhere in Settings ends editing of the field.
- **A used limit no longer reads as 0%.** A limit with any usage on it now shows a figure above zero.
- **Quitting Codex no longer quits Pulse.** Pulse keeps running when Codex exits.
- **A new app icon.** The icon is drawn on Apple's icon grid.

## 1.0.1

- **OpenCode Go and Kimi Code join the providers.** That brings the count to five agents.
- **Put the rings in your own order.** Set the order in Settings.
- **A refresh button on every provider's pane.** The age of the reading is shown beside it.
- **A new install starts with the agents you actually have.** It no longer shows five rings that say "not configured".
- **Drag the panel by any part of the capsule.** Dragging is no longer limited to the rings.
- **Clicking a ring refreshes that ring.** The provider you clicked is refreshed whatever order the rail is in.
- **The detail card fits at every size.** It no longer truncates itself at Small or sits half empty at Large.

## 1.0.0

- **The first release.** A floating rail of rings against the edge of the screen shows how much of each coding agent's limit is left.
