# Changelog

What each release changed, written for somebody deciding whether to install it.

This file is the source for both the GitHub release page and the text Sparkle
shows in the update window — see [Scripts/changelog.py](Scripts/changelog.py).
Add the entry **before** tagging, in the small grammar the converter knows:
bullets, `**bold**`, `` `code` `` and `[links](https://example.com)`.

## 1.9.0

**中文**

**新功能**

- **浅色面板。** 在「设置 → 外观 → 面板颜色」中选择「浅色」，面板改为浅灰底色和深色文字，适合明亮的屏幕；停靠在刘海处时同样为浅色。浅色下用量的绿色、黄色和红色改用更深的颜色，以保证可读性。开启液态玻璃时此选项不可用。感谢 [@brianzheng2024](https://github.com/qunqin24/Pulse/issues/74) 提议。

**改进与修复**

- **工具删除旧记录后，过去的用量不再减少。** Claude Code 等工具会清理旧的会话记录，此前 Pulse 下次读取时会随之去掉这部分用量，过去日子的 token、金额和回顾都会变小。现在 Pulse 会保存已经读到的用量，原记录被删除后仍然保留。在此版本之前已被删除的记录无法找回。
- **刘海处的面板与刘海更贴合。** 停靠在刘海处时，面板宽度与自由放置时一致，不再两端多出一截；面板与屏幕顶边之间的过渡圆角缩小，与刘海本身的圆角一致。
- **「一天的节奏」按实际用量说明时段。** 月度和年度回顾中，这张卡片此前固定统计晚上 9 点到凌晨 5 点的用量占比，每个人看到的时段都一样。现在改为找出用量最集中的连续 4 小时，例如「45% 的用量集中在 10:00 到 14:00 之间」；表盘上高亮的时段和作息表中的数字也随之改为这段时间。
- **部分用量没有公开价格时也生成「订阅回本」卡片。** 此前只要没有公开价格的用量达到 1%，月度和年度回顾就不生成这张卡片，界面上也没有说明原因；用量较大、又使用了未公开价格的模型时，几乎每个月都会被跳过。现在照常生成，并注明部分用量没有公开价格、金额只会偏低。
- **回顾从这台 Mac 最早有记录的那天算起。** 此前年度回顾把记录开始之前的月份显示为 0，并计入活跃天数、日均用量、工作日与周末的天数和订阅回本的折算，例如记录从 5 月开始时显示「活跃 88 / 282 天」。现在这些都从最早有记录的那天算起，此前的月份和日子显示为虚线，卡片底部注明记录开始的日期。
- **回顾中的几处说明更准确。** 「通常开工」改为「最早开工」，说明改为「凌晨 5 点以后最早有记录的时刻」；月历中没有用量的日子统一显示为虚线框，图例随之更新；开头改为「有 N 个 AI 工具和你一起写代码」；去掉「比九月同期」「九月的每一天」「十月见」等处多余的空格。
- **回顾里的数字更准确。** 有一天的用量没有公开价格时，按天的金额图、「最贵的一天」和花费曲线不再整体消失，那一天留空显示；缓存相关的金额改称「缓存让 API 价格少了」，不再写成「实际花了」「帮你省下」，「不用缓存」的估算也不再计入缓存写入的溢价；「比上月同期」按日均比较，已结束的月份与上个月整月相比；「最晚收工」按每段连续工作的结束时间计算，通宵到早上也能显示，晚上 12 点前收工也有数字；「一周七天」按每个星期几的平均值比较；某个工具不记录时间或计数不完整时，作息和缓存命中率改为不计入这部分并在卡片底部说明，不再整张消失；「全天型」改为「不定时型」。
- **回顾的每张卡片都带上说明。** 日历、年历、开头、作息和月份卡片在月份未结束或记录从中途开始时注明；开头卡片列出前 5 个工具之外的其余工具；年度海报中还没到的月份显示为虚线；进行中的月份不再写「这就是你的十月」「十一月见」。
- **菜单中用量面板的颜色随菜单外观调整。** 菜单显示为浅色时，用量条改用与浅色面板相同的较深颜色。

**English**

**New**

- **A light panel.** Choose Light under Settings → Appearance → Panel colour for a light grey surface with dark text, suited to a bright screen; it stays light when docked at the camera notch. On it, the green, yellow and red usage colours are deepened so they remain readable. The option is unavailable while Liquid Glass is on. Thanks to [@brianzheng2024](https://github.com/qunqin24/Pulse/issues/74) for the suggestion.

**Changed and fixed**

- **Past usage no longer shrinks when a tool deletes its old records.** Claude Code and other tools clean up old session records, and Pulse used to drop that usage the next time it read them, so past days' tokens, money and recaps grew smaller. Pulse now keeps the usage it has already read after the original records are deleted. Records deleted before this version cannot be recovered.
- **The panel fits the camera notch more closely.** Docked at the notch, the panel is now as wide as it is when placed freely, without the extra length at each end, and the curve where it meets the top of the screen is smaller, matching the notch's own.
- **Rhythm of the day names your own busiest hours.** In the monthly and yearly recaps, this card reported the share of usage between 9 PM and 5 AM, the same hours for everyone. It now finds the four hours in a row with the most usage, for example "45% of it came between 10 AM and 2 PM"; the highlighted hours on the clock and the figure in the timetable follow the same window.
- **The payback card appears when some usage has no published price.** The monthly and yearly recaps left this card out as soon as 1% of the usage had no published price, without saying why; with heavy use of a model whose price is not published, that was nearly every month. It now appears, noting that some usage had no published price, so the money is a floor.
- **Recaps count from this Mac's first record.** The yearly recap showed the months before records began as zeros and counted them in active days, the average per day, the weekday and weekend split, and the prorated plan price, for example "Active 88 of 282 days" when records began in May. These now count from the first recorded day; earlier months and days are drawn as dashed outlines, and the card footer gives the date records begin.
- **Clearer wording in the recaps.** "Usually starts" is now "Earliest start", described as the earliest hour after 5 AM with any work; days without usage in the month calendar are all drawn as dashed outlines, with the legend updated to match; and the opener counts "AI tools".
- **More accurate figures in the recaps.** A day whose usage has no published price no longer removes the daily money chart, the most expensive day and the cost line; that day is left blank. Cache figures are described as reductions in the API price rather than money spent or saved, and the no-cache estimate no longer includes the cache-write premium. The change against the previous period is compared per day, and a finished month is compared with the whole previous month. Finishes latest is read from the end of each stretch of work, so an all-nighter and an evening that ends before midnight both have a figure. Days of the week are compared by their average. A tool that records no time of day, or whose counts are incomplete, is left out of the hours and the cache hit rate, with a note on the card, instead of removing them. "All day" is now "No set hours".
- **Every recap card carries its notes.** The calendar, year calendar, opener, timetable and months cards note when the period is still running or when records begin partway through; the opener names the tools beyond its first five; months still to come are dashed on the yearly poster; and a running month no longer reads "That was your October" or "See you in November".
- **Usage colours in the menu's usage panel follow the menu's appearance.** When the menu is drawn light, the usage bars use the same deeper colours as the light panel.

## 1.8.3

**中文**

**改进与修复**

- **修复每日用量图表遮挡详情卡片的问题。** 本机用量记录只有一天时，悬浮详情卡片中的每日图表会显示为一个覆盖卡片下方内容的大圆。现在图表的柱宽始终按 31 天计算，记录较少时从左侧开始显示；设置和菜单栏中的每日图表也按同样方式显示，不再显示为宽色块。
- **Codex 额度余额按数字显示。** 设置中的「额度余额」此前显示为「2500.0000000000」这类带十位小数的原始数值，现在按当前语言的数字格式显示，最多保留两位小数。

**English**

**Changed and fixed**

- **Fix the daily usage chart covering the detail card.** When local usage records covered only one day, the daily chart on the hover detail card was drawn as a large circle over the rows below it. Bars are now always sized for 31 days, and a short history starts at the left. The daily charts in Settings and the menu bar follow the same rule and no longer draw wide blocks.
- **Show Codex's credit balance as a number.** The Credit balance row in Settings showed the raw value with ten decimal places, such as "2500.0000000000". It now uses the number format of the current language, with at most two decimal places.

## 1.8.2

**中文**

**改进与修复**

- **保留不完整记录中的已知 Token 分类。** 部分来源只记录总用量，或仅记录部分分类。现在会保留已记录的输入、缓存命中和输出，并将来源明确记录的未分类用量单独列出；分类占比按包含未分类用量的总量计算。未分类部分不估算费用，分类与总量不一致时也不会自动补数。
- **每日明细支持查看未分类用量。** Token 消耗与模型详情的每日明细新增「未分类」列，支持排序，无未分类用量时自动隐藏。只有未分类数据的记录，输入、缓存命中和输出不再显示为 0。
- **统一 Token 分类展示。** 「新内容」改为「输入」，包含已记录的缓存写入；缓存命中单独统计，未记录的分类明确标注为「未记录」。
- **修复明细表的排序与表头显示。** 超大 Token 数量排序时不再因精度损失将不同数值视为相同；表头保持单行显示。
- **优化界面与更新说明文案。** 修订简体中文、繁体中文、日文和韩文的界面文案，统一术语并修正表达与排版问题；历史版本的中文更新说明同步更新至 GitHub 发布页和应用内更新窗口。

**English**

**Changed and fixed**

- **Keep known token categories when records are incomplete.** Some sources report only a total or provide only partial category detail. Recorded input, cache hits and output now remain visible alongside any explicitly recorded unclassified usage. Category shares include unclassified tokens in the total. Unclassified tokens are not priced, and inconsistent totals are not filled in by inference.
- **Show unclassified usage in daily tables.** Daily tables in Token spend and model details now include a sortable Unclassified column, hidden when there is no unclassified usage. Records containing only unclassified tokens no longer show zeroes for input, cache hits or output.
- **Use consistent token categories.** Fresh input is now labelled Input and includes recorded cache writes. Cache hits remain separate, and missing category data is labelled Not reported.
- **Fix table sorting and headers.** Sorting very large token counts no longer treats distinct values as equal due to precision loss. Column headers stay on one line.
- **Improve interface copy and release notes.** Revised Simplified Chinese, Traditional Chinese, Japanese and Korean interface text for consistent terminology, clearer wording and corrected typography. Historical Chinese release notes are also updated on GitHub and in the in-app update window.

## 1.8.1

**中文**

**改进与修复**

- **自动更新支持备用下载通道。** 检查更新时优先访问 GitHub；无法连接时自动改用 update.qunqin.org 中转服务。检查或下载失败后，会立即通过另一条线路重试。所有安装包均带有签名，Pulse 只安装签名校验通过的更新，中转服务无法篡改更新内容。
- **更新说明只显示一种语言。** 语言跟随 Pulse 当前的界面语言（跟随系统时以系统语言为准）：中文界面显示中文，其他语言显示英文。
- **调整面板外观时不再重新拉取用量。** 修改面板大小、间距、玻璃效果等外观设置时，仅重新排版界面，不再向各服务商重新请求数据。
- **修复保存的密钥可能被覆盖的问题。** 在设置页保存密钥时，若恰好与 DeepSeek 控制台登录的后台续期同时发生，可能丢失其中一项；已删除的 DeepSeek 登录也可能被续期重新写回。两个问题均已修复。
- **修复钥匙串授权弹窗阻塞刷新的问题。** 读取 Claude Code 登录信息时最多等待 60 秒，超时后自动改用其他方式，不再导致所有服务商的刷新长时间等待。
- **修复月报大数字显示不完整的问题。** 此前 9、5 等数字的右侧可能被裁切。
- **设置页布局优化。** 「位置」一行在窗口较窄时，选项自动换行显示，不再把说明文字挤压成一行一字；月报窗口的订阅价格输入框调整为合适的宽度。

**English**

**Changed and fixed**

- **Updates arrive even where GitHub is out of reach.** Pulse tries GitHub before each check and goes through update.qunqin.org when it does not answer; a check or download that fails is tried again at once the other way. Every update is signed and Pulse installs only what carries its signature, so the relay cannot change it.
- **Update notes in one language.** They follow Pulse's language (the system's, when Pulse follows it): Chinese in Chinese, English for every other language.
- **Changing how the panel looks no longer refetches usage.** Size, spacing, glass and the other look settings now only lay the panel out again instead of asking every provider afresh.
- **Saved keys no longer overwrite each other.** Saving a key in Settings while DeepSeek's console sign-in was being renewed in the background could lose one of them, and a renewal could bring back a DeepSeek sign-in you had just removed. Both fixed.
- **A Keychain prompt no longer holds up refreshing.** Reading Claude Code's sign-in waits at most 60 seconds, then falls back to the other routes instead of keeping every provider waiting.
- **The recap's big numbers are no longer clipped.** The right side of a 9 or a 5 was cut off flat.
- **Settings layout.** The Position row puts its choices under the label when the window is too narrow for both, instead of squeezing the description to a character a line; the recap window's price field is now the width of a price.

## 1.8.0

**中文**

**新功能**

- **月报与年报。** 将一个月或一年的 AI 编程记录整理为一组可分享的卡片：总览海报、常用工具、日历、每日时段分布、订阅回本情况，以及一张总结成绩单。年报额外包含十二个月的日历和逐月对比。在「设置 › Token 消耗」中点击「查看九月的月报」或「查看 2026 年报」即可打开，支持保存、拷贝和分享图片。数据仅来自本机记录；缺失的数据不绘制，不会以 0 填充。
- **回本卡支持自定义订阅价格。** 在月报窗口中填写每月订阅价格，即可查看订阅的用出倍数；不填写则不显示该卡片。项目名称默认显示，可一键隐藏。
- **月报生成提醒。** 每月初提醒一次上个月的月报，点击通知即可查看。位于「设置 › 通知」中的「月报生成时」，默认关闭。
- **Token 活动图。** Token 消耗面板新增最近十二个月的用量图，可按天（一格一天）、按周或按累计总量查看，悬停时显示对应日期或周的具体数值。

**改进与修复**

- **会话列表更整洁。** Claude Code 的子代理记录已并入所属会话，同一会话不再重复出现；Codex 会话改用首条实际输入作为标题，自动审查的会话标注为「Codex 自动审查」，标题不再包含链接，也不会误用文件名。
- **项目名更准确。** 在仓库工作树中进行的工作计入仓库名下；Codex 桌面版与 DeepSeek 的临时目录不再被识别为项目。
- **修复 Gemini CLI 等十个图标的显示问题。** 此前 macOS 无法完整绘制这些图标，Gemini CLI 仅显示为一个点。
- **月报窗口打开时也显示 Dock 图标**，与设置窗口一致。

**English**

**New**

- **Monthly and yearly recaps.** A month or a year of AI coding as a set of cards to share: an overview poster, the tools that worked with you, the calendar, your hours, whether your plan paid for itself, and a closing scorecard. The yearly recap adds twelve small calendars and a month-by-month comparison. Open it from Settings › Token spend with View September recap or View 2026 recap, then save, copy or share the images. Everything comes from this Mac's own records; what is missing is left out, never drawn as zero.
- **A payback card at your price.** Type your monthly plan price in the recap window to see how many times over you used it; leave it empty and the card is left out. Project names are shown by default and can be hidden in one click.
- **A note when the recap is ready.** Once a month, early in the month, for the month that ended; clicking it opens that recap. In Settings › Notifications, off by default.
- **Token activity.** The Token spend pane charts the last twelve months by day (a square per day), by week or as a running total, with the day's or week's figure under the pointer.

**Changed and fixed**

- **Cleaner session lists.** Claude Code's subagent transcripts join the session they belong to, so one session no longer appears several times; Codex sessions are titled from the first thing you actually said, automatic reviews are marked Codex review, and titles no longer show links or fall back to a file name.
- **Better project names.** Work in a repository's worktree counts under the repository; Codex Desktop's and DeepSeek's scratch folders are no longer taken for projects.
- **Gemini CLI and nine other icons draw properly.** macOS drew them incompletely, Gemini CLI as a single dot.
- **The Dock icon also shows while the recap window is open**, as it does for Settings.

## 1.7.3

**中文**

**新功能**

- **设置打开时显示 Dock 图标。** 设置窗口被其他窗口遮挡后，可通过 Dock 或 ⌘-Tab 找回；窗口关闭后图标随之消失。位于「设置 › 通用」的「应用」分组，默认开启。

**改进与修复**

- **Token 消耗统计更准确。** Codex 桌面版的子任务记录包含主任务的全部历史数据，此前被重复计入子任务自身用量，导致 Codex 的数值明显偏高，现已排除；已归档的 Codex 会话也已计入统计。Claude Code 的一小时缓存写入按官方的双倍输入价格计算，OpenAI 的长上下文请求按长上下文价格计算。Devin CLI、OpenCode、Codebuff 和 Copilot 各存在一处重复计算，均已修正。更新后首次打开时会重新读取一遍本机记录。
- **Token 分类更清晰。** 分为「新内容」「缓存命中」「输出」三类，缓存写入计入新内容。工具未记录缓存信息时显示「未记录」，不再显示 0 或 0%。
- **卡片统计按自然日计算。** 「最近 7 天」「最近 31 天」严格对应日历日期，间歇使用后不再显示间歇前的数据。无价格信息的模型显示「—」，不再显示 $0.00。连续使用天数按全部记录计算，当天尚未使用时不会清零。「最常用模型」更名为「用量最多的模型」。
- **其他修复。** 删除账号后，进行中的登录续期不再把登录信息写回；OpenCode 更换控制台账号后，卡片不再显示旧账号的记录；登录或会话失效时提示重新登录，不再持续显示旧数据；仅有额外账号时同样按设定的刷新间隔刷新；关闭窗口启动器后不再频繁唤醒；OpenCode Go 的月度区间不再固定按 30 天计算；服务商返回异常数据时不再导致 Pulse 崩溃。
- **中文文案优化。** 简体和繁体中文统一使用「服务商」「账号」，并顺滑了诊断、集成和刷新设置中的语句。

**English**

**New**

- **A Dock icon while Settings is open.** A settings window another app has covered can be found again from the Dock or with ⌘-Tab; the icon goes when the window closes. In Settings › General, under Application, on by default.

**Changed and fixed**

- **More accurate token spend.** Codex Desktop's sub-agents start with their parent's whole history, which was counted again as their own work and made Codex's figures far too high; that copy is now left out, and archived Codex sessions are counted. Claude Code's one-hour cache writes are priced at twice the input rate, as Anthropic bills them, and OpenAI's long-context requests at the long-context rate. Devin CLI, OpenCode, Codebuff and Copilot each counted something twice; fixed. The first launch after updating reads this Mac's records again.
- **Token kinds that read plainly.** Fresh input, cache hits and output, with cache writes counted as fresh input. A tool that records no cache shows Not reported rather than 0 or 0%.
- **Card figures follow the calendar.** Last 7 days and Last 31 days are those calendar days, so coming back from a break no longer shows the days before it. A model with no price shows a dash rather than $0.00. Streaks count your whole history and no longer drop to zero before you have worked today. Favourite model is now Most tokens.
- **Other fixes.** Removing an account no longer lets a renewal still in flight write its login back; switching OpenCode console accounts no longer leaves the card on the old account's history; a lost sign-in asks you to sign in again instead of showing the last figures; a rail of added accounts alone follows the refresh interval you set; a switched-off window starter no longer wakes the app every few seconds; OpenCode Go's monthly window is no longer taken as 30 days; and a malformed reply from a provider can no longer crash Pulse.
- **More natural Chinese.** Simplified and Traditional Chinese settle on one word each for provider and account, with plainer sentences across diagnostics, integrations and refresh settings.

## 1.7.2

**中文**

**新功能**

- **服务状态。** Codex、Claude Code 和 DeepSeek 的设置页新增「服务状态」，按照各自官方状态页的样式显示：各项当前是否正常、过去 90 天每日一条记录，以及状态页公布的可用率。Codex 显示 status.openai.com 的 Codex 分组，Claude Code 和 DeepSeek 显示各自状态页上的全部项目。打开设置页时读取，页面保持打开时每 5 分钟更新一次。
- **服务故障通知。** 「设置 › 通知」新增「服务出故障时」，默认关闭。开启后每 5 分钟检查一次已启用的 Codex、Claude Code 和 DeepSeek，仅在工具相关项目（Codex 分组、Claude Code 与 Claude API、DeepSeek 的 API 服务）出现故障、升级严重程度或恢复时通知一次。以各自状态页公布的信息为准。

**改进与修复**

- **打开「关于」页时立即检查更新。** 版本行显示的是当前检查结果，而非上一次定时检查的结果。
- **降低资源占用。** 读取各工具的用量记录、汇总 Token 消耗以及面板跟随鼠标等操作，减少了大量重复计算。

**English**

**New**

- **Service status.** Codex's, Claude Code's and DeepSeek's settings gain a Service status section drawn the way each provider's own status page draws it: whether each part is up now, a bar a day for the last 90 days, and the uptime the page reports. Codex shows status.openai.com's Codex group; Claude Code and DeepSeek show everything on their pages. It is read when the pane opens and every five minutes while it stays open.
- **Notifications when a service is down.** Settings › Notifications gains When a service is down, off by default. Once on, it checks the Codex, Claude Code and DeepSeek you have switched on every five minutes and notifies once when what the tool runs on (the Codex group, Claude Code and the Claude API, DeepSeek's API services) goes down, gets worse or comes back — as each provider's status page reports it.

**Changed and fixed**

- **Opening About checks for an update right away.** The version row shows the answer now, not whatever the last scheduled check said.
- **Lighter on your Mac.** Reading each tool's usage records, adding up token spend and following the pointer on the panel all do much less repeated work.

## 1.7.1

**中文**

**新功能**

- **Codex 降智迹象检测。** 「设置 › Codex」底部新增「降智迹象」，仅读取本机的 Codex 记录，不发送任何请求：统计每个模型有多少长回复的推理恰好终止于 516、1,034、1,552 等位置（疑似被强制截断，超过 5% 时标记为「疑似降智」），以及是否存在未经设置变更即被更换模型、调低推理强度或缩短上下文的情况。这些仅为迹象，并非定论——Codex 不会记录服务器实际使用的模型。
- **DeepSeek 控制台用量读取。** 在 DeepSeek 设置的「DeepSeek 控制台」中点击「读取」，Pulse 会通过浏览器（Chrome、Edge、Brave、Arc 等）的登录状态读取整个账号最近 30 天的用量：每日花费和 Token、各模型占比及缓存命中率，金额以账号自身的币种显示。未填写 API Key 时也可用于读取余额。

**改进与修复**

- **修复横放面板时百分比和数字的位置问题。** 同时开启「百分比放在圆环右边」和「数字显示在圆环上方」时，百分比不再显示到圆环左侧；开启「距离重置的时间」时，数字也不再紧贴外圈。感谢 [@tyrival](https://github.com/qunqin24/Pulse/issues/73) 反馈。
- **卡片在屏幕空间不足时可滚动。** 面板横放在屏幕中部附近时，展开的卡片不再被屏幕边缘截断。

**English**

**New**

- **Signs of a weaker Codex model.** A new Signs of a weaker model section at the bottom of Codex's settings reads this Mac's Codex records and sends nothing: for each model, how many long replies had their reasoning stop at exactly 516, 1,034, 1,552 and so on — as if cut off; over 5% is marked Possibly weakened — and whether any turn ran on a different model, lower reasoning or a smaller context without you changing the settings. These are signs, not proof: Codex doesn't record which model the server actually used.
- **DeepSeek usage from its console.** Press Read under DeepSeek console in DeepSeek's settings and Pulse uses your browser's sign-in (Chrome, Edge, Brave, Arc and other Chromium browsers) to read the whole account's last 30 days: spend and tokens per day, each model's share and cache hit rate, in the account's own currency. It also reads the balance when no API key is set.

**Changed and fixed**

- **Lying across, with Figures beside the rings and Figure above the ring both on, the percentage no longer jumps to the left of the ring; with Time until reset on, figures no longer crowd the outer arc.** Thanks to [@tyrival](https://github.com/qunqin24/Pulse/issues/73) for the report.
- **A card scrolls when the screen cannot hold it.** With the panel lying across near the middle of the screen, an open card is no longer cut off at the screen's edge.

## 1.7.0

**中文**

**新功能**

- **详细卡片。** 在账号设置中为某个账号开启「详细卡片」后，悬停在圆环上时卡片会额外显示套餐、更新时间、近期用量和缓存命中率，以及额度对应的大致金额。Claude Code 和 Codex 还会显示提示缓存的剩余时间；多个对话同时进行时，显示最紧急的一个。
- **按模型查看用量。** 「设置 › Claude Code / Codex」的「用量记录」下新增「模型」卡片：各模型的用量占比、缓存命中率，以及最近 24 小时的每秒输出 token 数；Codex 还显示首字延迟。
- **提示缓存列表。** Claude Code 和 Codex 的设置页列出所有仍持有缓存的对话，以及缓存的剩余时间。
- **OpenCode Go 读取官网记录。** 在 OpenCode Go 的设置中读取浏览器登录状态后，Pulse 会直接从官网控制台读取额度和每次请求的记录，覆盖所有设备，金额为实际扣费金额。
- **面板支持横向自由摆放，也可吸附屏幕底部。** 原「自由」更名为「竖向自由」，新增「横向自由」；吸附底部时面板贴合屏幕最底边，可放置在程序坞两侧的空白区域。感谢 [@GinWU05](https://github.com/qunqin24/Pulse/issues/70) 提议并参与实现横向自由摆放。

**改进与修复**

- **修复 Claude Code 用量重复计算的问题。** 继续或分叉对话时，新记录会携带一份此前的历史数据，此前该副本也被计入用量，导致用量和花费偏高，最大可达约三成。
- **修复 Claude Code 输出 token 少算的问题。** 一条回复会分多行写入记录，此前仅读取第一行，输出量少算约四分之一，额度价值也因此偏低。
- **额度价值估算更稳定、更准确。** 仅统计至读取额度的时刻；不再遗漏周期起始阶段；用量不足 5% 时不显示，避免整数百分比造成的大幅波动；检测到账号在其他设备上同时使用时，本周期不再估算，并显示原因。
- **支持 OpenCode 2 的记录。** 升级到 OpenCode 2 后，Token 消耗中看不到新增用量的问题已修复。
- **Token 消耗改为后台读取。** 开启开关后，Pulse 会在后台自动读取并保持更新，打开页面时直接显示，关闭设置窗口也不会中断。
- **菜单栏图标更换为 Pulse 标志，菜单中的用量面板改为开关，默认关闭。**

**English**

**New**

- **A detailed card.** Turn on Detailed card for an account in its settings and its hover card adds the plan, when it was updated, recent usage and cache hit rate, and roughly what each limit is worth. Claude Code and Codex also show how long the prompt cache has left — the most urgent conversation when several are running.
- **Usage by model.** Under Usage history in Claude Code's and Codex's settings, a new Models card shows each model's share, cache hit rate and output tokens per second over the last 24 hours; Codex also shows the wait for the first token.
- **Prompt cache list.** Claude Code's and Codex's settings list every conversation still holding a cache, and how long it has left.
- **OpenCode Go from its own console.** Read the browser sign-in in OpenCode Go's settings and Pulse reads the limits and every request straight from the console — every device, with what each request was charged.
- **Float the panel lying across, or dock it to the bottom of the screen.** Free is now Free upright, beside a new Free across; docked to the bottom the panel sits on the screen's very edge, in the empty space either side of the Dock. Thanks to [@GinWU05](https://github.com/qunqin24/Pulse/issues/70) for proposing and building the lying-across placement.

**Changed and fixed**

- **Claude Code's usage is no longer counted twice.** Resuming or forking a conversation starts a new transcript with a copy of the old history, and Pulse counted the copy too — usage and cost read high, by as much as about a third.
- **Claude Code's output tokens are no longer undercounted.** A reply is written over several lines and only the first was read, missing about a quarter of the output — and of what each limit is worth.
- **Steadier, more accurate value estimates.** Spending counts up to when the limit was read; the start of a window is no longer dropped; nothing is shown under 5% used, where whole-number percentages made it swing; and a window being used on another device is not estimated, with the reason shown.
- **OpenCode 2's usage is read.** After upgrading to OpenCode 2, its new usage was missing from Token spend.
- **Token spend reads in the background.** With it on, Pulse keeps it up to date and the page opens on figures, even after the settings window was closed.
- **The menu bar shows Pulse's own mark, and the usage panel in its menu is now a switch, off by default.**

## 1.6.1

**中文**

**新功能**

- **额度重置后自动开始新窗口（可选）。** Claude Code 和 Codex 的用量窗口，需要在重置后等你发出第一条消息才开始计时。在账号设置中开启「自动开始新窗口」后，Pulse 会在每次重置后、你设定的时间段内，通过服务商自带的命令行工具发送一条「hi」，使窗口从该时刻开始计时。默认关闭；此功能并非 Anthropic 或 OpenAI 提供，可能被视为绕过用量限制，开启前会要求确认。

**改进与修复**

- **全新应用图标。** 一笔画成的 P：竖笔是面板贴合的屏幕边缘，荧光绿的圆弧是一枚未闭合的用量环。在 macOS 26 上支持液态玻璃效果，并跟随深色、透明和着色图标样式。
- **开启液态玻璃且面板吸附屏幕边缘时，圆环之间的空白区域也可拖动。** 此前仅能按住圆环拖动。设置中「开启后只能按住圆环拖动」的提示已相应移除。感谢 [@annsyun](https://github.com/qunqin24/Pulse/issues/68) 反馈。

**English**

**New**

- **Start usage windows after a reset (optional).** Claude Code's and Codex's windows only start at your first message after a reset. Turn on Start windows automatically in the account's settings and Pulse sends a single "hi" through the provider's own command-line tool just after each reset, within the hours you choose, so the window starts then. Off by default. It is not a feature of Anthropic or OpenAI and may be treated as getting around usage limits, so it asks you to confirm first.

**Changed and fixed**

- **A new icon.** A P drawn in one stroke: the stem is the screen edge the panel docks to, the lime bowl a usage ring not yet closed. On macOS 26 it is Liquid Glass and follows the dark, clear and tinted icon styles.
- **With Liquid Glass on and the panel docked to an edge, it can be dragged from between its rings**, not only by a ring. The settings caption saying so is gone. Thanks to [@annsyun](https://github.com/qunqin24/Pulse/issues/68) for reporting it.

## 1.6.0

**中文**

**新功能**

- **菜单栏用量显示。** 在「设置 › 通用」开启「在菜单栏显示用量」后，菜单栏图标旁显示用量最高的圆环，也可指定某个账号。样式可选数字、迷你圆环，或「分项」并列显示 5 小时与每周额度（`5h/9%  周/15%`）；超过警示线时变红。默认关闭。
- **菜单栏用量面板。** 点击菜单栏图标，顶部为「概览」和各账号标签：概览列出所有账号的用量与重置时间；账号标签中包含各项额度的进度条、套餐、更新时间、Codex 重置券与额度余额；开启「Token 消耗」后，还提供今日、最近 31 天、单日最高和累计的花费估算及每日柱状图。支持一键打开服务商的官方用量页，或按 ⌘R 立即刷新。
- **仅用菜单栏。** 菜单中新增「显示悬浮面板」开关，不需要屏幕边缘悬浮栏的用户可以直接关闭。
- **再次打开 Pulse 时弹出设置。** Pulse 在后台运行时，从「应用程序」或聚焦搜索再次打开会直接弹出设置窗口；即使面板和菜单栏图标均已隐藏，也不会失去入口。

**改进与修复**

- **液态玻璃模式下，卡片尾部与卡片融为一体。** 此前尾巴在复杂背景上会呈现为独立的一块水晶。
- **Grok 额度达到 100% 时视为已用完**，与其他服务一致，会发出「额度用完」通知。
- **删除额外账号时清除其全部设置**（小机器人外观、余额提醒等），不再残留。

**English**

**New**

- **Usage in the menu bar.** Turn on Show usage in the menu bar in Settings › General, and the menu bar icon shows the fullest ring — or an account you pick — as a figure, a small ring, or Split: the five-hour and weekly limits side by side (`5h/9%  Wk/15%`), red past the warning line. Off by default.
- **A dashboard in the menu bar menu.** Tabs across the top: an Overview of every account's figure and reset, and one tab per account with each limit's bar, the plan, how fresh the reading is, Codex's reset credits and credits left, and — with Token spend on — today, the last 31 days, the busiest day and all time as estimated cost, with a daily chart. Plus a link to the provider's own usage page and Refresh (⌘R).
- **Menu bar only.** Show floating panel is now in the menu, so the rail can be switched off in one click.
- **Opening Pulse again opens Settings.** A double-click in Applications or Spotlight while Pulse runs brings up Settings, so hiding both the panel and the menu bar icon is never a dead end.

**Changed and fixed**

- **With Liquid Glass, the card's tail is part of the card.** It used to read as a separate crystal over a busy backdrop.
- **Grok's pool counts as spent at 100%**, like every other provider, so the spent notification fires.
- **Removing an added account clears all of its settings**, including its animated mark and low-balance alert.

## 1.5.2

**中文**

**改进与修复**

- **支持通过新版 ChatGPT 桌面应用读取 Codex 额度重置券。** ChatGPT 26.924 更改了内置 codex 的位置，导致 1.5.1 无法找到；现在会同时检查新旧两个位置。感谢 [@sanziliu](https://github.com/qunqin24/Pulse/issues/67) 定位问题。
- **卡片显示最近一张重置券的到期时间**，精确到分钟，显示在券数量的下方。

**English**

**Changed and fixed**

- **Codex's limit reset credits are read with the newer ChatGPT desktop app too.** ChatGPT 26.924 moved the codex it ships, and 1.5.1 didn't find it; both places are looked in now. Thanks to [@sanziliu](https://github.com/qunqin24/Pulse/issues/67) for tracking it down.
- **The card shows when the next reset credit expires**, to the minute, under the count.

## 1.5.1

**中文**

**新功能**

- **扩展支持上报余额。** 扩展除上报额度外，还可上报账户余额（金额和币种），适用于 API 中转站。其圆环可与 API 服务一样选择「自上次充值起 / 只看余额 / 我的预算」，也可设置低余额提醒。中转站示例见 [Docs/extensions.md](https://github.com/qunqin24/Pulse/blob/main/Docs/extensions.md)。感谢 [@Zoltan-code](https://github.com/qunqin24/Pulse/issues/40) 提议。

**改进与修复**

- **密钥输入框旁新增显示按钮。** 点击眼睛图标可查看输入的内容，便于核对；切换到其他服务时自动重新隐藏。
- **修复 API 服务设置页「圆环计算方式」遮挡说明文字的问题。** 该项原名「环上显示」，与面板组中的同名设置容易混淆，现已更名。
- **仅安装 ChatGPT 桌面应用时也能读取 Codex 额度重置券。** 此前 Pulse 不会在应用内查找内置的 codex，卡片一直显示「不可用」；完全找不到 codex 时，现在会明确显示「找不到 codex」。感谢 [@sanziliu](https://github.com/qunqin24/Pulse/issues/67) 反馈。

**English**

**New**

- **Extensions can report a balance.** Besides limits, an extension can now report the money left in an account, as an amount and a currency, which suits API relays. Its ring takes the same three choices as an API account's — since top-up, balance only, my budget — and it can warn when the balance runs low. A relay example is in [Docs/extensions.md](https://github.com/qunqin24/Pulse/blob/main/Docs/extensions.md). Thanks to [@Zoltan-code](https://github.com/qunqin24/Pulse/issues/40) for asking.

**Changed and fixed**

- **The key field has a show button.** Click the eye to see what you typed and check it; it hides again when you open another provider.
- **Ring measures no longer covers its own description** on an API account's settings page. It was also called Ring shows, the same as the Panel group's row for a different setting; it has a name of its own now.
- **Codex's limit reset credits are read when only the ChatGPT desktop app is installed.** Pulse never looked for the codex the app ships, so the card said Not available. When no codex can be found at all, it now says so. Thanks to [@sanziliu](https://github.com/qunqin24/Pulse/issues/67) for the report.

## 1.5.0

**中文**

**新功能**

- **新增 53 个服务商，共 77 个。** 包括阶跃星辰的 Step Plan，以及 ClinePass、阿里云百炼 Coding Plan 与 Token Plan、Qwen Cloud、美团 LongCat、Gemini、Kilo Code、Factory、Augment Code、Windsurf、Amp、Mistral、Moonshot、OpenAI API、xAI API 等 52 个。这 52 个参考 [CodexBar](https://github.com/steipete/CodexBar) 的实现移植，尚未用真实账号验证；如遇到不可用的情况，欢迎提交 issue。完整列表见 README。
- **扩展系统。** 将自编的小程序放入扩展文件夹，即可让 Pulse 显示某个账号的用量，例如公司内部的额度接口。开启之前不会运行，Pulse 也不会向其提供任何凭据。编写方法见 [Docs/extensions.md](https://github.com/qunqin24/Pulse/blob/main/Docs/extensions.md)。感谢 [@guanbear](https://github.com/qunqin24/Pulse/issues/51) 提议。
- **订阅与 API 分组显示。** 设置侧边栏和首次启动的服务选择窗口分为「订阅」和「API 与按量付费」两组，顶部为「已启用」，无需再在数十个服务中翻找。
- **每个 API 服务均可选择圆环显示方式。** 此前仅 DeepSeek 支持：自上次充值起、只看余额、我的预算。现在 OpenAI API、Moonshot、New API 等上报余额的服务均可分别设置。
- **Codex 卡片可显示额度重置券。** 在「设置 → Codex」开启「在卡片上显示额度重置券」后，悬浮卡片会显示剩余数量；Codex 未返回数据时显示「不可用」。默认关闭。感谢 [@sanziliu](https://github.com/qunqin24/Pulse/issues/67) 提议。

**改进与修复**

- **支持读取通过 npm 或 nvm 安装的 Codex 的 app server。** 从 Finder 或开机启动的 Pulse 找不到 `node`，导致 app server 启动即退出，重置券等数据始终无法读取。Kiro、arkcli 等命令行工具也已一并处理。
- **未选择服务时，菜单栏菜单第一项会给出提示。** 此前点击「以后再说」后，面板消失且没有任何说明。感谢 [@Drswith](https://github.com/qunqin24/Pulse/issues/66) 反馈。
- **面板窗口仅按已启用的服务预留大小。** 此前按所有服务预留，服务较多时，透明窗口的高度会远超屏幕。
- **「顺序」列表仅显示已启用的服务。**
- **设置侧边栏加宽**，较长的名称不再被截断。

**English**

**New**

- **53 new providers, 77 in all.** StepFun's Step Plan, and 52 more including ClinePass, Alibaba Cloud Model Studio's Coding Plan and Token Plan, Qwen Cloud, LongCat, Gemini, Kilo Code, Factory, Augment Code, Windsurf, Amp, Mistral, Moonshot, OpenAI API and xAI API. Those 52 were ported by reading [CodexBar](https://github.com/steipete/CodexBar)'s providers and have not been checked against a live account yet; if one doesn't work for you, please open an issue. The full list is in the README.
- **Extensions.** A small program of your own, put in the extensions folder, can report one account's usage — an internal quota endpoint, say — and Pulse draws it as a ring. Nothing runs until you switch it on, and Pulse hands it no credentials. How to write one: [Docs/extensions.md](https://github.com/qunqin24/Pulse/blob/main/Docs/extensions.md). Thanks to [@guanbear](https://github.com/qunqin24/Pulse/issues/51) for proposing it.
- **Subscriptions and API accounts are listed apart.** The Settings sidebar and the first-run chooser group providers under Subscriptions and API and pay-as-you-go, with the ones you use under Enabled at the top.
- **Every API account chooses what its ring measures.** DeepSeek's three modes — since top-up, balance only, my budget — now apply to OpenAI API, Moonshot, New API and every other account that reports a balance, each set on its own.
- **Codex's card can show limit reset credits.** Turn on Reset credits on the card in Settings → Codex, and the hover card says how many are left, or Not available when Codex reports none. Off by default. Thanks to [@sanziliu](https://github.com/qunqin24/Pulse/issues/67) for asking.

**Changed and fixed**

- **A Codex installed with npm or nvm now reaches its app server.** Pulse launched from Finder had no `node` on its path, so the app server quit at once and reset credits never arrived. Kiro, arkcli and the other command-line tools are started the same way now.
- **The menu bar menu says to choose services when none are.** Dismissing the first-run chooser left no panel and nothing saying why. Thanks to [@Drswith](https://github.com/qunqin24/Pulse/issues/66) for reporting it.
- **The panel window is sized for the rings switched on.** It reserved room for every provider, which with dozens of them made the transparent window far taller than the screen.
- **Order lists only the accounts switched on.**
- **A wider Settings sidebar**, so long provider names are no longer cut short.

## 1.4.1

**中文**

**新功能**

- **Qoder 显示积分包到期日。** 每个积分包有独立的到期时间，卡片显示最早到期的一批，例如「10月18日 86 积分到期」，同日到期的合并显示；`--json` 新增 `expiresAt` 和 `expiringAmount` 字段。感谢 [@momusticks](https://github.com/qunqin24/Pulse/issues/59) 提议。

**改进与修复**

- **修复 Qoder 体验版账号显示「未返回任何限额」的问题。** 大陆站体验版会返回一个早已过期的重置时间，Pulse 据此将整份读数视为过期丢弃；现已忽略该日期，正常显示剩余积分。感谢 [@momusticks](https://github.com/qunqin24/Pulse/issues/59) 查明原因。
- **购买 Qoder 积分包不再被误判为额度重置。** 购买后上限增大、用量比例骤降，此前会误发重置通知，小机器人也会播放庆祝动画；现在仅当 Qoder 的重置时间后移时才视为重置。
- **修复 Qoder 确认账号无积分时仍显示旧百分比的问题。** 此前缓存会把上一次的读数顶回，重启后及 `--json` 输出中同样存在。感谢 [@tech-zjf](https://github.com/qunqin24/Pulse/pull/61)。
- **模型价格无需重启即可更新。** 价格表过期后，会在下次读取时重新下载；下载失败时继续使用旧表，五分钟后可重试。感谢 [@tech-zjf](https://github.com/qunqin24/Pulse/pull/60)。
- **小机器人的眼神和动作恢复原版幅度。** 此前为避免眼睛贴边、身体超出圆环，Pulse 额外压缩了眼神、手势和大幅动作，摇头幅度仅剩一半；现在按原版动画播放，动作较大时眼睛可能贴近边缘，头顶可能短暂超出圆环。
- **鼠标悬停胶囊时，小机器人依次转向。** 不再所有圆环在同一帧同时转向指针；各环依次响应，约 0.4 秒内平滑转向。

**English**

**New**

- **Qoder shows when your credit packs lapse.** Each pack has its own end date; the card now shows the soonest, such as "Oct 18: 86 credits expire", with packs ending the same day added together. `--json` gains `expiresAt` and `expiringAmount`. Thanks to [@momusticks](https://github.com/qunqin24/Pulse/issues/59) for asking.

**Changed and fixed**

- **A Qoder trial no longer shows "no limits reported".** The mainland site's trial replies with a reset date long past, and Pulse discarded the whole reading as expired. The date is now ignored and the remaining credits are shown. Thanks to [@momusticks](https://github.com/qunqin24/Pulse/issues/59) for tracking down the cause.
- **Buying a Qoder pack is no longer read as a reset.** The larger limit made the used fraction drop, which sent a reset notification and set the bot celebrating. Only Qoder's reset date moving forward counts now.
- **An old percentage no longer covers Qoder saying an account has no credits.** The cache brought the previous reading back, after relaunch and in `--json` too. Thanks to [@tech-zjf](https://github.com/qunqin24/Pulse/pull/61).
- **Model prices refresh without restarting Pulse.** An expired price table is downloaded again on the next read; a failed download keeps the old one and may retry after five minutes. Thanks to [@tech-zjf](https://github.com/qunqin24/Pulse/pull/60).
- **The bot moves as the original animation does.** Pulse had been damping its glances, gestures and larger moves to keep the eyes off the edge and the body inside the ring, so a head shake lost half its sweep. They play at full size again: an eye may touch the edge, and the top of the head may briefly leave the ring.
- **The bots turn to an arriving pointer one after another.** Instead of every ring snapping to it in the same frame, each notices a moment later and turns over about 0.4 seconds.

## 1.4.0

**中文**

**新功能**

- **新增 Sub2API、New API、V2EX 和 Qoder，服务商增至二十四个。** 两个自建网关填入服务器地址和密钥即可读取余额或额度；V2EX 使用个人访问令牌读取 AI Chat 额度；Qoder 通过浏览器读取 qoder.com 或 qoder.com.cn 的登录状态并显示积分额度，团队套餐的共享积分单独显示一个圆环。感谢 [@momusticks](https://github.com/qunqin24/Pulse/issues/59) 提议。
- **真实液态玻璃。** 开启后，面板为透明、带折射效果的 macOS 26 液态玻璃，不再是磨砂层；文字改为白色，并新增「透明度」滑块，可根据常用背景调节玻璃明暗。设置中的名称也已改回「液态玻璃」。
- **时间圆环支持倒数。** 「距离重置的时间」的外圈可选「已过去」或「剩余」，剩余模式从满圈逐渐缩短至重置时刻。感谢 [@Steven-oyjb](https://github.com/qunqin24/Pulse/pull/44)。
- **Kiro 与 ZCode 显示工作动画。** Pulse 读取它们在本机写入的会话记录，判断任务是否进行中；ZCode 仅在配置的接口属于智谱或 z.ai 时驱动对应圆环。感谢 [@guanbear](https://github.com/qunqin24/Pulse/pull/56)。
- **设置按主题拆分为多个页面。** 外观、圆环与数字、位置与行为、通用、通知、网络与刷新各自独立；侧边栏搜索可根据设置项名称定位所在页面。
- **每个服务均提供配置指南。** 设置中的「配置帮助」现在打开专门撰写的页面：密钥或登录信息的获取位置、填写位置，以及常见错误的处理方法。

**改进与修复**

- **修复贴边时鼠标推至屏幕最边缘被误判为离开的问题。** 此前开启自动收起时，指针贴边会导致胶囊反复展开和收起。
- **卡片切换更流畅。** 高度不同的卡片切换时，新增的行不再先于卡片出现在外部；快速扫过圆环时也不再显示空卡片。
- **修复小机器人偶发瞬移的问题。** 庆祝转圈或变形动作被中途打断时，身体会平滑过渡到下一状态，不再在单帧内跳转。
- **Token 消耗：同名项目分开统计，无定价用量不再显示 $0.00。** 不同路径下的同名目录不再合并；无法定价的会话和项目显示「—」或带 `*` 的小计。感谢 [@tech-zjf](https://github.com/qunqin24/Pulse/pull/57)（[#58](https://github.com/qunqin24/Pulse/pull/58)）。

**English**

**New**

- **Sub2API, New API, V2EX and Qoder bring the count to twenty-four providers.** Both self-hosted gateways read a balance or allowance from a server address and key you enter; V2EX reads its AI Chat allowance with a Personal Access Token; Qoder reads your qoder.com or qoder.com.cn sign-in from the browser and shows your credits, with a team plan's shared credits as a ring of their own. Thanks to [@momusticks](https://github.com/qunqin24/Pulse/issues/59) for asking.
- **Real Liquid Glass.** With glass on, the panel is clear, refracting macOS 26 Liquid Glass rather than a frosted layer. Text is drawn white, and a new **Transparency** slider sets how much the glass is dimmed for the backgrounds you usually work over. The setting is called Liquid Glass again in every language.
- **The window clock can count down.** The outer arc of **Time until reset** can show time elapsed or time remaining; remaining starts full and empties toward the reset. Thanks to [@Steven-oyjb](https://github.com/qunqin24/Pulse/pull/44).
- **Kiro and ZCode show activity too.** Pulse reads the session records they leave on this Mac to tell whether a turn is in flight; ZCode drives a ring only when its configured endpoint belongs to Zhipu or z.ai. Thanks to [@guanbear](https://github.com/qunqin24/Pulse/pull/56).
- **Settings are split by subject.** Appearance, Rings and figures, Position and behavior, General, Notifications, and Network and refresh each have their own pane, and the sidebar search finds a pane by the names of its settings.
- **Every provider has a setup guide.** **Setup help** now opens a page written for users: where the key or login comes from, where it goes in Pulse, and what each error means.

**Changed and fixed**

- **A pointer pushed against the screen edge no longer counts as leaving a docked rail.** With auto-collapse on, it used to open and close the rail over and over.
- **Switching cards is smoother.** An added row no longer appears outside a card that has not grown yet, and sweeping across the rings no longer shows an empty card.
- **The animated mark no longer jumps.** A celebration spin or a shape change interrupted mid-motion now eases into the next state instead of snapping in one frame.
- **Token spend keeps same-name projects apart and stops showing unpriced use as $0.00.** Directories with the same name at different paths are no longer merged, and sessions or projects that cannot be priced show `—` or a subtotal marked `*`. Thanks to [@tech-zjf](https://github.com/qunqin24/Pulse/pull/57) ([#58](https://github.com/qunqin24/Pulse/pull/58)).

## 1.3.1

**中文**

**新功能**

- **Kiro 成为第二十个服务商。** Pulse 通过 Kiro CLI 内置的 ACP 接口读取当前账号的方案与额度，无需额外登录或复制凭据；同一响应中的多个额度分别显示，并保持稳定的账号身份。
- **浮动栏支持贴合刘海。** 顶部停靠时围绕刘海并延伸至屏幕边缘，在有刘海和无刘海屏幕之间移动时自动切换形状；警报提示改画在刘海下方，不再被屏幕缺口遮挡。
- **菜单栏图标可隐藏。** 可仅通过浮动栏或全局快捷键使用 Pulse。设置会确保始终保留至少一个可用入口；`Command-,` 也可直接打开设置。
- **更多外观与动画开关。** 可关闭浮动栏警报颜色、CLI 活动动画和刷新动画，并可使浮动栏两端保持与圆环一致的柔和曲线。

**改进与修复**

- **未选择显示的服务不再被读取。** Pulse 仅扫描已监控服务的本机 CLI 活动；关闭显示的服务在设置中明确标注为「未显示」，且无法从诊断页触发刷新。
- **修复 Kiro 额度顺序变化打乱账号的问题。** 额度身份改用 Kiro 返回的资源类型，不再依赖数组位置，重排后仍会保留各自的显示设置和历史。
- **修复辅助进程重启后的错误超时。** Codex 和 Kiro 的旧请求计时器不会再终止新一轮同编号请求，也不会为已完成的请求留下延迟报错。
- **修复隐藏菜单栏图标导致无法进入应用的问题。** 若浮动栏不可用且快捷键注册失败，Pulse 会自动恢复菜单栏入口；首次选择服务前，也不允许隐藏唯一入口。
- **修正 GLM 服务图标与发布构建检查。** 两个 GLM 区域使用一致的服务标识；构建命令不再重复覆盖 Swift 语言模式，避免把无效警告当作发布失败。

**English**

**New**

- **Kiro is the twentieth provider.** Pulse reads the current plan and allowances through the ACP service built into Kiro CLI, with no extra sign-in or copied credential. Multiple allowances in one response remain separate and keep stable account identities.
- **The rail can berth around the notch.** A top-docked rail wraps the notch and reaches the screen edge, adapting as it moves between displays with and without a notch. Its alert cue is drawn below the cutout where it remains visible.
- **The menu bar icon can be hidden.** Pulse can be reached through the floating rail or global shortcuts alone. Settings always preserve at least one working entry point, and `Command-,` opens Settings directly.
- **More appearance and motion controls.** The docked alert colour, CLI activity animation and refresh animation can each be disabled, while the rail can keep ends softened to the rings' own curve.

**Changed and fixed**

- **Providers that are not selected are no longer read.** Pulse scans local CLI activity only for watched providers. A hidden provider is labelled “Not shown” in Settings and cannot be refreshed from diagnostics.
- **Kiro allowance ordering no longer changes account identity.** Allowances use the resource type returned by Kiro instead of their array position, preserving display choices and history when the response is reordered.
- **Fixed false timeouts after helper restarts.** Old Codex and Kiro request timers can no longer finish a newer request that reused the same identifier, or report a late failure after a request already completed.
- **Hiding the menu bar icon cannot lock the user out.** Pulse restores the menu bar entry if the rail is unavailable and no shortcut registered successfully, and keeps the sole entry visible until the first provider selection is complete.
- **Corrected the GLM provider marks and the release build check.** Both GLM regions now use a consistent provider identity, and build commands no longer override the package's Swift language mode and turn a redundant warning into a failed release.

## 1.3.0

**中文**

**新功能**

- **首次启动时先选择要监控的服务。** Pulse 在选择完成前不读取任何凭据，也不会开始监控。后续升级发现新的本机服务时仅提示，不会擅自开启；已有选择保持不变。
- **代理设置。** 网络可继续跟随 macOS，也可在设置中指定 HTTP、HTTPS 或 SOCKS5 代理。服务商请求、登录流程以及 Codex、arkcli 等辅助进程使用同一配置。

**改进与修复**

- **Token 消耗改为明确开启后才读取。** 新安装默认关闭；开启后也仅在查看该页面时扫描本机会话，离开页面或关闭设置会取消进行中的读取并释放结果。大型 JSONL 日志改为流式解析，避免为一次统计将整份文件载入内存；返回页面时会复用已完成的结果，手动重新扫描除外。
- **八种小机器人配备完整的动作编排。** 日常、工作、刷新、鼠标响应和完成反馈按顺序播放，不再随机跳过标志性动作。日常动作与工作动作明确区分，空闲转圈不再出现代表工作的彩带；仅「迟缓」会在深夜打瞌睡。
- **修复连续工作动画中小机器人眼睛被裁切的问题。** 最终轮廓约束留出适合圆环尺寸的微小内边距，旋转和随机瞥视叠加时眼睛不再被裁掉一半。Kimi 机器人的蓝色也已调亮，在小尺寸下更清晰。

**English**

**New**

- **Choose what Pulse may monitor before it starts.** A first-run picker makes the choice explicit. Pulse reads no credentials and starts no monitoring until it is saved. Later upgrades only suggest newly detected services; they never enable one on their own or disturb an existing choice.
- **Proxy settings.** Network traffic can keep following macOS or use a manually configured HTTP, HTTPS or SOCKS5 proxy. Provider requests, sign-in flows and helper processes such as Codex and arkcli all use the same selection.

**Changed and fixed**

- **Token spend is read only after an explicit opt-in.** It is off on new installs and scans local sessions only while its Settings pane is open. Leaving the pane or closing Settings cancels an unfinished read and releases its result. Large JSONL logs are streamed instead of loaded whole, while a completed result is reused when returning to the pane unless Rescan is requested.
- **Each of the eight bots now has a complete authored choreography.** Everyday, working, fetching, pointer-attention and completion scenes play every beat in order rather than randomly skipping signatures. Everyday and work vocabularies are separate across the whole cast, an idle spin no longer throws work ribbons, and only Sleepy may doze at night.
- **Eyes remain whole through sustained work animation.** The final silhouette bound reserves a small ring-sized inset, so stacked turns and glances no longer clip half an eye. Kimi's bot blue is lighter as well, keeping its face readable at this size.

## 1.2.1

**中文**

**修复**

- **修复 Codex 导致 CPU 空转的问题。** `codex app-server` 退出后，Pulse 仍在读取其已关闭的管道。该状态下的管道永远「可读」，读取回调因此被反复调用——单个核心持续满载，直到退出 Pulse 为止；且 helper 每重启一次，都会残留一条空转线程。感谢 [@ethan-ji](https://github.com/qunqin24/Pulse/issues/25) 查明了原因、堆栈和触发条件。

**新功能**

- **小米 Coding Plan 成为第十九个服务商。** 读取小米 MiMo 控制台上按月购买的 token 额度，有周期结束时间时一并显示，预付余额作为一行金额显示在卡片上。凭据为浏览器中已登录的会话，而非 API key——平台签发的 key 用于购买推理服务，控制台的账户接口均不认可。账号未购买 Coding Plan 时会明确提示，而不是显示 0%。
- **更新检查频率改为每两小时一次**，此前为每日一次。仍仅提示更新，不会自动安装。

**改进**

- **小机器人现在朝向屏幕内侧。** 胶囊贴在右侧时看向左侧，贴在左侧时看向右侧，拖至另一侧时视线平滑移动而非瞬间跳转。此前的偏移量远小于表情自带的朝向，因此大部分时间都在盯着屏幕边框。鼠标位于面板上时，优先看向鼠标。
- **修复小机器人眼睛超出面部轮廓的问题。** 表情自带的朝向、贴边偏移和随机瞥视叠加后，会把眼睛推出轮廓，被裁切后看起来像少了一只眼睛。
- **重写设置中小机器人相关的中文文案。** 此前为英文直译。

**English**

**Fixed**

- **Codex no longer spins the CPU.** After `codex app-server` exits, Pulse went on reading its closed pipe. A pipe in that state is readable for ever, so the read callback was called again and again — one core, flat out, until Pulse was quit — and every restart of the helper left another spinning thread behind. Reported by [@ethan-ji](https://github.com/qunqin24/Pulse/issues/25), with the cause, the stack and the conditions already worked out.

**New**

- **Xiaomi Coding Plan is the nineteenth provider.** Reads the monthly token allowance bought on Xiaomi's MiMo console, with the period's end where it reports one, and the prepaid balance as a line on the card. The credential is your signed-in browser session rather than an API key — the platform's keys buy inference and answer none of the console's account routes. An account with no plan says so instead of drawing 0%.
- **Updates are checked every two hours** rather than once a day. Still offered, never installed on their own.

**Changed**

- **The bot now faces into the screen.** A rail docked right looks left, docked left looks right, and dragging it across sends the eyes over rather than snapping them. The old lean was far smaller than the glance drawn into each expression, so a mark spent much of its time staring at the screen edge. A pointer on the panel outranks all of it.
- **The bot's eyes stay inside its face.** The expression's own glance, the edge lean and the random glances stacked up and pushed an eye past the silhouette, where it was clipped — which read as a mark with one eye.
- **Rewrote the Chinese copy for the bot settings**, which had been translated word by word from the English.

## 1.2.0

**中文**

**新功能**

- **动画标记。** 可将某个账号圆环中的服务商图标替换为一个动态小机器人，默认关闭，在该账号的设置页中单独开启。它仅反映面板已知的信息：该服务商的 CLI 正在运行、Pulse 正在获取新读数、额度已用满、尚无读数，或当前无活动。开启动画标记的圆环不再绘制白色活动弧——旋转的白弧与一个明显正在工作的小机器人是同一信息，无需重复绘制。
- **人格、形状与颜色。** 八种人格决定其播放的动作和节奏，默认自动分配，确保相邻圆环的角色不同；十八种身体形状可选，默认为圆形；颜色默认采用服务商品牌色，无品牌色的会自动分配一个与相邻圆环区分的色相，也可自行指定。三项均按账号设置。
- **对状态变化作出反应。** 眼睛跟随面板上的鼠标，被指向的圆环会停下倾听；工作时在「工作、生成、书写」之间切换，非工作时间会一边生气一边工作；长时间没有任何 CLI 写入会感到无聊，深夜则犯困；额度重置时庆祝，一轮工作完成时兴奋。重置判定与通知系统使用同一规则，与通知是否开启无关。
- **关于页新增项目地址。** 同时注明动画标记的移植来源。

**English**

**New**

- **Animated marks.** A ring's provider logo can be replaced by a small animated bot. Off by default, switched on per account in that account's settings pane. It says only what the panel already knows: that provider's CLI is running, Pulse is fetching a reading, the limit is spent, there is no reading yet, or nothing is happening. A ring drawing a mark no longer draws the white activity arc — a travelling arc and a bot that visibly gets to work are one fact drawn twice.
- **Personality, shape and colour.** Eight personalities decide which motions a mark plays and at what pace, dealt automatically so the ring beside it is a different character. Eighteen body shapes, round by default. Colour is the provider's brand where it has one, otherwise dealt to stand apart from its neighbours' hues, or chosen outright. All three are per account.
- **It reacts to what is happening.** The eyes follow the pointer across the panel, and the ring being pointed at stops to listen. Work alternates between working, generating and writing, with anger added out of hours. A machine that has been quiet for twenty minutes gets bored, and sleepy about it at night. A limit that resets is celebrated; a finished turn gets a cheer. The reset is recognised by the same rule the reset notification uses, whether or not notifications are on.
- **The project's address in About**, alongside credit for the animated marks' origin.

## 1.1.2

**中文**

**新功能**

- **更多 Token 消耗来源。** 新增 Gemini CLI、Cline、Roo Code、OpenClaw、GitHub Copilot 等本地记录读取，并支持 Cursor、Trae 等导出数据。部分来源需先导出或捕获记录；支持的格式与验证范围见[来源说明](https://github.com/qunqin24/Pulse/blob/main/Docs/token-spend-sources.md)。
- **模型用量详情。** 点击模型可查看输入、输出、缓存读写、每日与每小时用量，以及各 Agent 的贡献；明细表支持排序和分页。费用按公开 API 价格折算，并非订阅账单。
- **图表悬停读数。** 悬停历史图表即可查看对应日期或小时的 token 数量，较短的柱形和零用量时段也可选中。
- **浮动栏菜单与全局快捷键。** 右键浮动栏即可打开设置；可自定义快捷键，用于打开设置或显示、隐藏浮动栏。默认未绑定按键。
- **繁体中文、日语和韩语。** 界面与 README 新增三种语言，大数缩写采用各语言对应的单位。

**改进与修复**

- **补全计价。** 为仅由套餐商公布价格的模型补全计价，修正 Kilo CLI 的价格来源；日汇总、模型详情和会话金额保持一致。
- **修复来源读取。** Antigravity IDE 读取自身的会话存储；Devin 记录不再误标为仅来自 CLI；已匹配的数据库与 Desktop 捕获只统计一次。
- **修正区间统计。** 跨天汇总记录仅计入所选区间；Command Code 回退对话后仍保留已发生的消耗，重复记录不会重复计数。
- **优化默认区间。** Token 消耗默认显示最近一周，并记住所选区间；缺失价格、不完整计数和不可用的小时明细会明确标注，旧缓存自动重读。
- **修复切换语言后设置侧栏变窄的问题**，补充 Agent 图标并更新界面截图。

**English**

**New**

- **More token-spend sources.** Added local-record readers for Gemini CLI, Cline, Roo Code, OpenClaw, GitHub Copilot and more, plus exports from Cursor, Trae and others. Some sources require a prior export or capture. See [sources and validation coverage](https://github.com/qunqin24/Pulse/blob/main/Docs/token-spend-sources.md) for supported formats.
- **Model usage details.** Open a model to inspect input, output, cache reads and writes, daily and hourly usage, and contributions by agent. Detail tables support sorting and paging. Costs use published API rates and are not a subscription bill.
- **Chart hover values.** Point at a history chart to see the token count for a date or hour, including short bars and periods with no usage.
- **Rail menu and global shortcuts.** Right-click the floating rail to open Settings. Optional shortcuts open Settings or show and hide the rail; both are unassigned by default.
- **Traditional Chinese, Japanese and Korean.** Added three interface and README translations, with large-number abbreviations using each language's own units.

**Changed and fixed**

- Added pricing for models listed only by their plan vendor and corrected Kilo CLI's price source. Day, model and session amounts agree.
- Antigravity IDE reads its own conversation store. Devin records are no longer labelled CLI-only, and matched database sessions and Desktop captures count once.
- Cross-day aggregate records contribute only their in-range usage. Command Code rewinds retain consumption that already occurred, and replayed records are not counted twice.
- Token spend defaults to the last week and remembers the selected span. Missing prices, incomplete counts and unavailable hourly detail are identified; older caches are reread automatically.
- Fixed the Settings sidebar narrowing after a language change, added agent icons and updated screenshots.

## 1.1.1

**中文**

**新功能**

- **Devin 成为第十八个服务商。** 从 Chromium 浏览器会话读取每日和每周额度，无需钥匙串授权；无登录凭据时读取应用保存的带日期套餐。不同账户和组织的读数相互隔离。
- **Token 消耗统计。** 汇总 Claude Code、Codex、OpenCode、Kilo CLI、Grok Build、Kimi CLI 和 Devin CLI 的本机会话，按区间、Agent、模型、项目、会话和 token 类型查看。费用按公开 API 价格折算，并非订阅账单。
- **开发者集成。** 在设置中导出 Raycast 扩展及 tmux、sketchybar、终端脚本；`Pulse --json` 新增读数来源和账户设置链接。集成仅读取缓存。[配置指南](https://github.com/qunqin24/Pulse/blob/main/Docs/integrations.md)。
- **连接诊断。** 查看最近的检查、读数来源、缓存和回退结果，按原因修复连接；额外账户可原位重新登录。可复制不含账户详情或凭据的诊断信息。
- **变红阈值可调。** 可选 60%–90%，默认 75%；圆环、详情条和收起的胶囊保持一致，已耗尽状态仍优先显示。

**改进与修复**

- **修复额度误报与凭据串写。** Claude Code 的 warning 不再被误判为额度耗尽；登录码、取消按钮和错误信息归属到正确的服务商页面，切换页面不再覆盖另一服务商的凭据。
- **修复详情卡片展开、收起时沿胶囊漂移的问题。**
- **修正区间与缓存。** 跨天会话仅计入所选区间；修正日志与数据库缓存更新、模型别名计价和自定义会话标题的读取。
- **修复 Devin 快照问题。** 旧快照按实际时间标注，过期窗口和超龄快照不再显示；额度变化纳入自适应刷新，异常长度的浏览器存储数据不再导致崩溃。

**English**

**New**

- **Devin is the eighteenth provider.** Read daily and weekly quota from your Chromium browser session without a keychain prompt. With no credential, Pulse reads the app's dated saved plan. Account and organization boundaries are preserved.
- **Token spend.** Bring together local sessions from Claude Code, Codex, OpenCode, Kilo CLI, Grok Build, Kimi CLI and Devin CLI, grouped by span, agent, model, project, session and token kind. Costs use published API rates and are not a subscription bill.
- **Developer integrations.** Export a Raycast extension and tmux, sketchybar and shell scripts from Settings. `Pulse --json` now includes reading sources and account links; integrations only read the cache. [Setup guide](https://github.com/qunqin24/Pulse/blob/main/Docs/integrations.md).
- **Connection diagnostics.** Inspect checks, sources, cache use and fallback outcomes, with relevant repair actions and in-place reauthentication for added accounts. Copied diagnostics omit account details and credentials.
- **Configurable warning colour.** Choose where rings turn red, from 60% to 90% (default 75%). Rings, detail bars and the collapsed rail agree; exhausted limits still take precedence.

**Changed and fixed**

- Claude Code warnings no longer mean exhausted. Device codes, Cancel and errors stay with their provider; switching panes no longer lets login completion overwrite another provider's credential field.
- Fixed detail cards drifting along the rail as they open and close.
- Cross-midnight sessions count only their in-range work. Corrected log and database cache updates, model aliases and custom session titles.
- Devin snapshots retain their actual age; expired windows and over-age snapshots disappear. Quota changes participate in adaptive refresh, and malformed browser-storage lengths no longer crash Pulse.

## 1.1.0

- **A large balance no longer overflows the ring.** The rail shows ¥5k, ¥123k, $1.2M rather than the full figure, which did not fit and was being cut off — the exact balance is on the card and in Settings. It is always rounded **down**, so the ring never claims you have more than you do.

- **The rail no longer sits slightly too low until you touch something.** On most displays the panel is taller than the space macOS will grant it, and Pulse works out where to draw the rail from the position the window actually got. It was asking that question a moment too early — before the window was on screen, when the answer was still the position it had **requested** — so the rail was drawn about 76pt below where it belonged, and then jumped into place the first time any setting changed.

- **API balances are checked more often.** Pulse paces itself by watching this Mac — an agent writing to its transcripts, a figure that moved, you glancing at the rail — which is why it can be quick when you are working and quiet when you are not. But money spent through an API leaves no trace here, so DeepSeek and Command Code were always being left the full half hour: it waited because nothing had changed, and nothing appeared to change because it waited. Those two are now checked at least every five minutes. Everything else is unaffected, a Mac in low power or with the panel hidden still goes quiet, and a fixed interval you chose yourself still means what it says.

- **The provider list starts in alphabetical order.** It was in the order providers had been added over the months, which meant nothing to anyone reading it. If you have arranged the rail yourself, your arrangement is untouched.

- **Tell me when the credit runs low.** Providers that sell prepaid credit — DeepSeek and Command Code — get a **Warn below** figure in their own settings, and Pulse says so once when the balance falls under it. Money rather than a percentage, because these two report no allowance to take a percentage of; per provider rather than one figure, because ¥20 and $20 are not the same line. Off until you set one, like every other notification here. It is said once and not again until you top up — or until you move the line, which is a new question and gets a new answer.

- **Notifications about a prepaid balance say less, and say it correctly.** Credit that is bought does not reset and cannot be declared spent by arithmetic, so changing what the ring measures against no longer announces a reset, and a balance reaching 100% of a figure **you** set no longer claims the provider says you are out. Only the provider saying so does that.

- **DeepSeek is the seventeenth provider**, and the first one Pulse carries that reports no allowance at all — `GET /user/balance` says how much prepaid credit is left and nothing else. There is no quota, no window and no spend history to read, so the ring needs a denominator from somewhere and you choose which in DeepSeek's settings. **Since top-up** is the default and needs nothing from you: Pulse remembers the highest balance it has watched, and a balance that goes up can only be a top-up, so the ring starts again from full when you add credit. **Balance only** draws no ring at all and puts the money itself on the rail. **My budget** measures against a figure you type. The first two days on "since top-up" will read low — Pulse can only measure from the moment it started watching, and the card says which date that is.

- **智谱's row is now called "Zhipu".** The rail and the settings list are otherwise all Latin script, and one row in Chinese characters read as a different kind of thing rather than as another shop. The company, the storefront and the key it takes are unchanged — this is the name on the row, nothing else. Its sibling stays **z.ai**, which is that company's own spelling.

## 1.0.9

- **Command Code is the sixteenth provider.** It bills a credit balance in dollars rather than a token allowance, so the rings are money: the rolling 5-hour and weekly limits, your organisation's spend limits, and how much of this month's plan is gone. That last one is marked **estimated** on the card, and it is the one thing here Pulse has to infer — Command Code reports what is **left** of a plan's monthly credit but never what the plan grants, which is published on its pricing page instead. A plan Pulse cannot size shows no monthly row at all rather than a reassuring zero. Sign in by pasting a key, or let Pulse borrow the one `cmd auth login` already saved.

- **The panel can follow you between displays.** Switch on "Follow the active display" and the rail moves to whichever screen your pointer is on, keeping the same corner and the same distance down it. There is still only one rail — it is carried across, not copied onto every monitor — and it stays where you last dragged it if you leave the setting off, which is how it ships. "Active" means the display the pointer is on and nothing else: it does not chase other apps' windows around, and it asks for no extra permission to work out where you are.

## 1.0.8

- **The interface follows your Mac's language.** Pulse now declares that it speaks Chinese, which it always did — the translations shipped, macOS just was not told they existed, so a Mac set to 简体中文 got an English app. If that was you, this update switches over on its own; if you preferred it in English, Settings › Language still overrides. The Chinese copy has been rewritten throughout while we were in there.

- **Antigravity can show its two allowances as two rings.** The plan carries one budget for Gemini and a separate one for Claude and GPT, and until now a single ring could only follow whichever was busier — the other went unmentioned unless you hovered. Switch on "A ring for each model group" in Antigravity's settings and each gets its own ring, both under the Antigravity icon, both refreshing the one login. Off by default: an extra ring takes room on the rail, and most people want the one number.

- **智谱 and z.ai get a usage history**, read from the same statistics the console draws its own charts from. Unlike the history Pulse builds for Claude Code and Codex — which it works out by reading session files on this Mac — this one comes from the account, so it covers every machine you use it on. It counts tokens only: the figures behind it cannot be turned into money, and the card says so rather than printing a confident zero.

- **A second limit on the ring.** A thinner ring inside the first shows the next-fullest limit *of the same kind* — the 5-hour beside the weekly it belongs with — so both are readable without hovering. Where a provider splits its allowance by model, the two arcs come from the same allowance wherever it has a second limit to show: pairing one model's weekly with another's 5-hour would put two unrelated budgets on one mark. Off by default and switched on in Settings; the ring is the thing you read without stopping, and two arcs is twice as much to take in. Where a provider reports only one limit nothing is added.

- **The panel no longer slides out from under you as you pick it up.** On a display where the panel is taller than the space under the menu bar — which is most laptops — macOS quietly refuses the position Pulse asks for, and Pulse was then drawing the rail relative to a position the window never had. It jumped about one ring's worth on the first frame of a drag. It tracks the pointer exactly now.

- **The two GLM Coding Plan rows are now named for the shops** — **z.ai** and **智谱**. They were "Z.ai" and "GLM Coding Plan", which was a trap: both shops sell the plan under that same name, so anyone on the international plan picked the row named after their product and had their key sent to the mainland service, which of course refused it.
- **A refused key now says the key was refused.** These services answer with an ordinary HTTP 200 and put the verdict inside, and Pulse only recognised the English wording and two of the numbers — so the most common mistake of all, a key from the other one of the two shops, came out as "the service returned an error" and sent people looking for an outage that was not happening.

## 1.0.7

- **Pulse can tell you, instead of waiting to be looked at.** Three switches in Settings, all off until you turn them on. **Warn at** posts a notification when a limit passes 75, 80, 90 or 95% — whichever you pick — and again when the provider says it is spent. **When a limit comes back** says so once the window you were warned about has turned over, which is the moment you can start again. **When a reading stops arriving** is the one that is about Pulse rather than about usage: a failed check falls back to the last good figures, which is the right thing to show and also the reason the fault is invisible — the panel goes on displaying perfectly plausible numbers with only a "last read" time to give it away. It waits for three failures in a row and then says it once, with the same sentence the card would have shown you.
- **It says each thing once.** A limit already past the line when you switch this on is mentioned straight away — silence followed by a wall is not restraint — and then never again until it resets or gets worse. "Spent" is the provider's own word, never a rounding of ours. A reset is announced only on unambiguous evidence, so a rolling weekly allowance sliding down a few points is not mistaken for a window turning over. And a provider you have never set up, or an app that simply is not running, is not a failure to be reminded of on a timer.
- **Antigravity reads from the IDE too**, not only the desktop app. If Antigravity IDE is the one you have open, its ring said “Open Antigravity to see its usage” while the figures were sitting there for the asking. Both report the same thing — the Gemini and the Claude-and-GPT group, weekly and five-hour each.
- **Antigravity could pick the wrong helper and give up.** It runs more than one of these, only one of them answers, and Pulse asked the first it found and stopped.
- **Reorder the rail by dragging.** The arrows are still there — they are the precise way to move one place, and the only way that works from the keyboard — but with fifteen providers, moving the bottom one to the top was fourteen clicks. There is a Reset order button under the list for when a drag goes somewhere you didn't mean.
- **Volcengine**, bringing it to fifteen. The Ark Coding Plan and Agent Plan, personal and team, each with its five-hour, weekly and monthly windows. Two ways in: `arkcli`, using the login it already saved so there is nothing to paste, or a Volcengine access key pair for anyone who has keys but doesn't run the CLI here. With both set up it prefers the keys — the CLI carries a sign-in that can belong to a different account, and quietly showing the wrong account's limits is worse than either answer.
- **`Pulse --json`**, so the figures can go somewhere other than the panel — a tmux status line, sketchybar, Raycast, a shell prompt. It prints what the app last read rather than fetching, so polling it every second costs nothing and asks no provider anything; every account says when its figures were taken and how old they are. Nothing in the output is translated, so a script parsing it does not break when you change the interface language.
- **Settings has a search field**, since the sidebar now lists fifteen providers plus whatever accounts you have added. It matches the provider's name as well as your own label, so a second Claude subscription you called "work" is still found by typing Claude.
- **The Settings window opens bigger.** It was sized when the sidebar held four rows and had got to the point of appearing already scrolled in both columns.
- Notifications come with the standard notification sound. Silence them, or change anything else about how they arrive, in System Settings › Notifications › Pulse — the same place as every other app.

## 1.0.6

- **Grok**, read from the login Grok Build's CLI already stores — nothing to paste. One thing worth knowing before the ring confuses you: since June 2026 a paid Grok plan spends **one weekly pool across every Grok product** — the web chat, Imagine, voice, the API and the CLI alike — so this is what the account has spent this week, not what the CLI has. That is why it is called Grok rather than Grok Build.
- **Grok Bot**, which is a different limit despite the name. It comes with a Cursor plan rather than a SuperGrok one, so it is read with the login the Cursor editor already stores and carries the xAI mark to tell the two apart on the rail. It appears by itself only if the standalone app is installed; otherwise switch it on in Settings.
- **A second account of either.** Grok signs in with a device code, Grok Bot through Cursor's own sign-in page. Both ask for the narrowest access that can read a limit — never for permission to read or write your conversations.
- A card could print a window length the provider never reported. Some limits carry a length that only exists to sort the rows — a rolling week, a billing cycle — and when there was no reset time to show, that length was printed as though it were one.
- A provider with a single route named the wrong one in Settings. Every such provider but Cursor was described as "Antigravity's language server", about an app it had nothing to do with.

## 1.0.5

- **Claude Code read through the Claude desktop app.** If you work in the desktop app rather than a terminal, Pulse had no way to see your limits: the desktop app hands the CLI a token through its own environment and renews it itself, so the login Pulse was reading went stale and never came back, and it never renders a status line either. Pulse can now read the session the desktop app is signed in with — a new "Desktop app" choice under Read usage from, and the route `Automatic` falls back to once you have allowed it. It asks for the keychain once, at launch, so there is nothing to go and find in Settings.
- **The new route says why it can't answer**, rather than leaving the last reading in place with nothing but its "Last read" time to give it away — which is what makes a refresh look as though it did nothing. It says whether the desktop app is signed out, or whether it was the keychain that was refused.
- **A reading could go backwards.** A newer figure already on file could be replaced on screen by an older one that had just arrived, and a refresh that had been given up on could still overwrite the one that replaced it — including, for an added account, the renewed login itself.
- **GitHub Copilot no longer shows a red ring for paid overage.** Going past the included allowance with overage permitted is not being blocked, and it was being drawn as though it were.
- **Codex no longer marks the wrong model group as spent.** A group reporting "limit reached" could put the mark on another group's window entirely.
- Removing your only added account no longer leaves the rail empty.

## 1.0.4

- **GitHub Copilot**, bringing it to twelve. Signs in with a device code, so there is no token to paste — Pulse asks GitHub for permission to read your profile and nothing else, and never for access to your repositories. Shows the completions, chat and premium-request allowances your plan actually has.
- **Whether a limit will last.** A switch in Settings puts one line under each limit on the card: whether it is on course to outlast its window, and roughly when it runs out if it isn't. Off by default, and it stays quiet when the figures can't carry it — the time only appears when it falls before the reset, and it is rounded, because usage comes in bursts and a figure to the minute would be made up.
- **Show what's left instead of what's spent.** Another switch, which turns the figure and the ring over together so a limit reads "88% left" rather than "12% used". The colour still means how close you are, so a nearly empty ring is still red.
- **Claude Code's card names the plan** — "Max 5x", "Pro", "Team" — as every other provider's already did. The multiplier is part of it, since a Max 5x and a Max 20x are different products.
- **The panel could quietly stop refreshing** after running a long time, and only come back when you next started Claude Code in a terminal. It notices when its own readings have gone stale and asks again, recovers from a fetch that never returned, and refreshes when the Mac wakes as well as when the display does.

## 1.0.3

- **The panel can go on a second display.** Drag it across; it remembers which screen you left it on, and comes home if that screen is unplugged.
- **Four more providers**: the GLM Coding Plan and MiniMax, each with a separate entry for the international and the mainland service, since they are separate accounts with separate keys.
- **A second arc can show how far through the window the clock is**, so "80% used" can be read against how much of the window is left. Off by default, in Settings.
- **The figure can sit above the ring** instead of below it. Also in Settings.
- A provider that needs an API key is no longer switched on by itself — it waits in Settings rather than taking a place on the rail to ask for a key.
- One that has no key says so, instead of saying "Reading…" for ever.
- Claude Code no longer shows a limit that has already reset. If its saved login has expired and no session has run for a while, the stale window is dropped rather than shown with an old reset time.
- The update window now shows the release notes itself, rather than loading the GitHub page inside it.

## 1.0.2

- **Multiple accounts.** Sign in to a second Claude Code or Codex subscription and watch both at once, each with its own ring.
- **Cursor**, reported as the two pools its own account page shows.
- **Ollama Cloud**, from PcOffeeP's pull request — with the session read out of your browser rather than copied by hand.
- **The rail can dock along the top of the screen**, above the menu bar.
- **A colour of your own for any ring**, and the gap between rings is now adjustable.
- **Percentages can be switched off** on either rail.
- The rail opens with the last reading instead of sitting blank.
- The activity mark no longer keeps turning for a minute after a turn has ended.
- The API-key field in Settings lets go when you click away from it.
- A limit you have used never reads as 0% any more.
- Quitting Codex no longer takes Pulse down with it.
- A new app icon, drawn on Apple's icon grid.

## 1.0.1

- **OpenCode Go** and **Kimi Code**, bringing it to five agents.
- **Put the rings in your own order**, in Settings.
- **A refresh button on every provider's pane**, with the age of the reading beside it.
- A new install starts with the agents you actually have, rather than five rings that say "not configured".
- The panel can be dragged by any part of the capsule, not only by its rings.
- Clicking a ring refreshes the one you clicked, whatever order the rail is in.
- The detail card no longer truncates itself at Small or sit half empty at Large.

## 1.0.0

- The first release. A floating rail of rings against the edge of the screen, one per coding agent, showing how much of each limit is left.
