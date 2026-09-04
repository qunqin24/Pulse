# Grok Bot Usage Investigation

## Objective

- 查明 Grok Bot（Cursor 内部名 “Sand”）额度的读取方式，包括端点、认证、请求头、响应字段和凭据落盘位置。
- 明确其与 Grok Build/SuperGrok 配额的区别，并评估 Pulse 应采用的实现路径。

## Important Details

- Grok Bot 不是 Grok Build；不要使用 `~/.grok/auth.json` 或 `https://cli-chat-proxy.grok.com/v1/billing?format=credits` 读取 Grok Bot。
- Grok Bot 是 Cursor 账户下独立的每周额度，内部协议名为 `Sand`。
- Pulse 当前没有 Grok Bot 实现：
  - `GrokUsageService.swift` 读取的是 Grok/SuperGrok 共享池。
  - `CursorUsageService.swift` 目前只读取 Cursor 月度用量。
- 已确认两条私有接口：
  - REST：`POST https://cursor.com/api/dashboard/get-sand-usage-status`
  - `Cookie: WorkosCursorSessionToken=...`
  - `Accept: application/json`
  - `Content-Type: application/json`
  - `Origin: https://cursor.com`
  - 请求体：`{}`
  - Connect RPC：`POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus`
  - `Authorization: Bearer <Cursor access token>`
  - `Connect-Protocol-Version: 1`
  - `Content-Type: application/json`
  - 请求体：`{}`
- Pulse 已能从 Cursor 本地状态读取 access token：
  - macOS：`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`
  - SQLite key：`cursorAuth/accessToken`
  - 当前代码从 JWT `sub` 构造 `WorkosCursorSessionToken` Cookie。
- OpenUsage 还支持：
  - SQLite key：`cursorAuth/refreshToken`
  - Keychain service：`cursor-access-token`
  - Keychain service：`cursor-refresh-token`
- 已确认主要响应字段：
  - `currentPeriodStart` / `current_period_start`
  - `nextResetTimestampUtc` / `next_reset_timestamp_utc`
  - `usagePercent` / `usage_percent`
  - `includedLimitZero` / `included_limit_zero`
  - `availableBankedResetCount` / `available_banked_reset_count`
  - `usesPooledEnterpriseAllowance` / `uses_pooled_enterprise_allowance`
  - `hasAvailableUsage` / `has_available_usage`
  - `hasNonZeroIncludedLimit` / `has_non_zero_included_limit`
  - `upgradeRecommendation` / `upgrade_recommendation`
  - `sandTrialExpiresAt` / `sand_trial_expires_at`
  - `sandTrialCancelable` / `sand_trial_cancelable`
- 映射规则：
  - `usagePercent` 是已用百分比。
  - `currentPeriodStart` 到 `nextResetTimestampUtc` 通常构成每周窗口。
  - `usesPooledEnterpriseAllowance == true` 时没有独立个人额度条。
  - `hasNonZeroIncludedLimit == false` 或 `includedLimitZero == true` 时应隐藏。
  - 请求失败应 fail-soft，不影响 Cursor 主用量。
- 官方文档确认 Grok Bot 有每周 included usage；同时拥有 Cursor 与 SuperGrok 资格时会使用额度更多的一方：
  - <https://docs.x.ai/grok-bot/faq>
  - <https://docs.x.ai/grok-bot/settings-and-notifications>
- Claude 调查已完成，并写入 `docs/plan.md`。Pulse 当前自动链路为：
  - OAuth 凭据错误：OAuth → 已授权 Desktop → Status Line → Cache → Error
  - OAuth 网络/限流/服务端错误：OAuth → Status Line → Cache → Error

## Work State

### Completed

- 完成 CodexBar Claude 来源审查，确认其无 Claude Status Line JSON/drop-file 接入。
- 核对 Pulse Claude 当前实际回退逻辑，并创建 `docs/plan.md`。
- 克隆并检查官方 `xai-org/grok-build`；确认 Grok Build 配额不是当前 Grok Bot 目标。
- 核对 CodexBar Grok Bot 实现：
  - `POST /api/dashboard/get-sand-usage-status`
  - 使用同一个 Cursor session Cookie。
  - 解析每周额度字段。
- 核对 OpenUsage 的 Connect RPC 实现和 Cursor token 来源。
- 从恢复的 Grok Bot protobuf 描述中确认 `GetSandUsageStatusResponse` 完整字段编号及类型。
- 确认本机安装 `/Applications/Grok Bot.app`。

### Remaining Investigation

- 查明独立安装 Grok Bot、但未安装或未登录 Cursor 时，其 access token 的准确落盘目录、数据库/keychain 名称及字段。
- 比较 Pulse 应优先采用 Cookie REST 还是 Bearer Connect RPC；现有代码条件下 RPC 更直接，但尚需核对 Grok Bot 原生客户端实际使用的附加请求头。
- 已定位应用数据目录 `~/Library/Application Support/Grok Bot`，但未读取其中的凭据内容。

## Recommended Direction

1. 在 `CursorUsageService` 中把 Grok Bot 当作 Cursor 账户的独立每周窗口读取，而不是合并到 `GrokUsageService`。
2. 优先复用 Pulse 已有的 Cursor access token 或由它构造的 `WorkosCursorSessionToken` Cookie。
3. 将 Grok Bot 请求作为 Cursor 主用量请求的可选并发分支；失败时忽略该窗口，不使 Cursor 主用量整体失败。
4. 仅在存在有效 `usagePercent` 且账户拥有非零 included allowance 时显示窗口。
5. 将接口视为未公开 API，保持解码字段可选，并为返回结构变化保留 `.unreadableReply` 或静默省略窗口的处理。

## Relevant Files

- `Sources/Pulse/GrokUsageService.swift`：当前 Grok/SuperGrok 共享池实现，不是 Grok Bot。
- `Sources/Pulse/CursorUsageService.swift`：Pulse 当前 Cursor 月度用量请求，可在此并发附加 Grok Bot。
- `Sources/Pulse/CursorAppLogin.swift`：从 `state.vscdb` 读取 `cursorAuth/accessToken` 并构造 Cursor Cookie。
- `docs/plan.md`：Claude 当前来源顺序。
- `CodexBar/Sources/CodexBarCore/Providers/Cursor/CursorSandUsage.swift`：Grok Bot REST 响应模型和周窗口映射。
- `CodexBar/Sources/CodexBarCore/Providers/Cursor/CursorStatusProbe.swift`：Cookie REST 请求、请求头和 fail-soft 并发流程。
- `CodexBar/Tests/CodexBarTests/CursorSandUsageTests.swift`：示例 JSON 和字段语义。
- `OpenUsage/Sources/OpenUsage/Providers/Cursor/CursorUsageClient.swift`：`api2.cursor.sh` Connect RPC URL、方法和请求头。
- `OpenUsage/Sources/OpenUsage/Providers/Cursor/CursorAuthStore.swift`：SQLite 和 Keychain token 来源。
- `OpenUsage/Sources/OpenUsage/Providers/Cursor/CursorUsageMapper.swift`：Grok Bot eligibility 和百分比映射规则。
- `/Applications/Grok Bot.app`：独立 Grok Bot 客户端。

## Outcome

已实现，但**没有**按 Recommended Direction 第 1 条走。最初确实做成了 Cursor 卡片上的第四行，
结果第一反应是「Grok Bot 呢」——问的时候人正看着 Grok 那一页，而那是另一个 Grok。
所以最终拆成了独立 provider `GrokBotUsageService`，在胶囊上单独占一个环，
仍然借 Cursor 的登录读取（凭据确实是 Cursor 账户的），但用 xAI 的图标以便和 Grok 区分。

实测与本文调查结果有一处出入，以实测为准:

- **`nextResetTimestampUtc` 本机账号上不返回。** REST 与 Connect RPC 两条路的响应
  逐字节相同，都只有 `currentPeriodStart`，没有重置时间。所以该字段按可选读取，
  拿不到就不画重置行；七天只作排序用（`reportsLength: false`），不参与任何除法。
- **不要用 `currentPeriodStart + 7 天` 推出重置时间**，Grok Bot 自己的客户端就不这么做。
  `Grok Bot.app/Contents/Resources/app.asar` 里的原文是
  `nextResetMs: n != null && Number.isFinite(n) && n > 0 ? n : null`，取不到就是 null。
  同一个包里带着 schema：两个时间戳都是 proto3 的 **message** 字段（显式存在性），
  所以「没有」就是真的没设，而不是被序列化省掉的零值。
- 「每周」这个定性取自 xAI 官方文档，不是从 `currentPeriodStart` 推出来的。
- 本机账号返回 `usagePercent: 0` + `hasNonZeroIncludedLimit: true`，属于有额度但未使用，
  与「无额度」区分开：后者同样返回 0，但会带升级推广文案，直接画出来就是一个满绿的假环。

另外发现并修复了一个既有缺陷:`UsageDetailCard.resetText` 在没有重置时间时会退回显示
窗口长度，而那个长度对部分窗口只是排序键——等于把没人上报过的数字印在卡片上。已改为不显示。

### 多账号

Grok Bot 支持添加第二个账号，走的**不是 OAuth**——Cursor 没有对第三方开放的
authorize/token 端点。它的实际流程（从 `Grok Bot.app` 的 asar 里读出来的）是：

1. 浏览器打开 `https://cursor.com/loginDeepControl?challenge=…&uuid=…&mode=login&redirectTarget=sand`
2. 轮询 `https://api2.cursor.sh/auth/poll?uuid=…&verifier=…`，404 = 还没好，
   200 返回 `accessToken` / `refreshToken`

proof key 是 PKCE 的算法，注意 hash 的是 **base64url 编码后的 verifier 字符串**，
不是原始随机字节。Cursor 的 token 有效期实测 60 天，且客户端里找不到 refresh 端点，
所以过期后只能重新登录一次，而不是自动续期。

这也回答了本文 Remaining Investigation 里的第一条:Grok Bot 独立客户端把 Cursor 账号存在
`~/Library/Application Support/Grok Bot/sand-secrets.json` 的 `cursor-accounts` 字段里，
用 Electron safeStorage 加密。Pulse 没有去读它——自己登录拿到的 token 更干净，也不必碰钥匙串。
