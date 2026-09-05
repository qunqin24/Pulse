# Claude usage reading plan

This file is a **compatibility pointer**. The current Claude Code source order, Desktop Keychain rules, Status Line freshness, added-account isolation, and the reasons those branches exist live in [providers/claude-code.md](providers/claude-code.md). Shared cache rules: [providers/README.md](providers/README.md).

Grok (account weekly pool / Grok Build CLI login) is not a Claude topic: [providers/grok.md](providers/grok.md). Grok Bot is a third provider: [providers/grok-bot.md](providers/grok-bot.md). The pre-shipping Grok Bot investigation is historical: [grok-bot-usage.md](grok-bot-usage.md).

## Compact primary-account flow (current)

Pulse currently resolves the **primary** Claude Code account in this order:

1. OAuth usage endpoint
2. Claude Desktop web session (only when already permitted, live, and compatible)
3. Status Line capture
4. Last successful usage cache
5. An actionable unavailable reason

```text
OAuth -> permitted Desktop session -> Status Line -> valid cache -> error
```

OAuth network, rate-limit, or server failures currently skip Desktop:

```text
OAuth network failure -> Status Line -> valid cache -> error
```

A successful OAuth reading wins immediately. An expired or refused OAuth credential falls through to Desktop. Explicitly pinning Endpoint, Provider Tooling, or Desktop App disables the normal cross-source fallback; cache reconciliation still happens afterwards where its error rules allow it.

Added Claude accounts use their own OAuth credentials only. The primary CLI Status Line and Desktop session are never substituted for an added account.

Source: [`Sources/Pulse/ClaudeCodeUsageService.swift`](../Sources/Pulse/ClaudeCodeUsageService.swift), [`Sources/Pulse/ClaudeDesktopSession.swift`](../Sources/Pulse/ClaudeDesktopSession.swift), [`Sources/Pulse/UsageCache.swift`](../Sources/Pulse/UsageCache.swift), [`Sources/Pulse/UsageStore.swift`](../Sources/Pulse/UsageStore.swift), [`Sources/Pulse/AppDelegate.swift`](../Sources/Pulse/AppDelegate.swift).
