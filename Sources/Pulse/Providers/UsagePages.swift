// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

extension Provider {
    /// The provider's own page for an account's usage or billing, where one is
    /// known — what the menu's "Open usage page" goes to.
    ///
    /// **Only pages somebody opens.** Several providers' services send a
    /// `Referer` or call an endpoint whose address looks like a page; those are
    /// not listed unless they are also where a person looks at their usage.
    /// A provider missing here gets no menu item rather than a guessed link.
    ///
    /// A table, not a switch, so a new provider adds a line only if it has one.
    var usagePage: URL? {
        Self.usagePages[self].flatMap(URL.init(string:))
    }

    private static let usagePages: [Provider: String] = [
        .claudeCode: "https://claude.ai/settings/usage",
        .codex: "https://chatgpt.com/codex/settings/usage",
        .cursor: "https://cursor.com/dashboard?tab=usage",
        .copilot: "https://github.com/settings/copilot",
        .deepSeek: "https://platform.deepseek.com/usage",
        .openAIPlatform: "https://platform.openai.com/usage",
        .kimiCode: "https://www.kimi.com/code/console",
        .ollamaCloud: OllamaCloudClient.settingsURL.absoluteString,
        .xiaomiMiMo: XiaomiMiMoClient.consoleURL.absoluteString,
        .replicate: ReplicateUsageService.billingPage.absoluteString,
        .qwenCloud: QwenCloudUsageService.page.absoluteString,
        .perplexity: "https://www.perplexity.ai/account/usage",
        .gitKraken: "https://gitkraken.dev/account#ai-usage",
        .neuralwatt: "https://portal.neuralwatt.com/dashboard",
        .amp: "https://ampcode.com/settings",
        .typeSafe: "https://console.typesafe.ai/settings/billing",
        .mistral: "https://admin.mistral.ai/organization/usage",
        .xaiAPI: "https://console.x.ai",
    ]
}
