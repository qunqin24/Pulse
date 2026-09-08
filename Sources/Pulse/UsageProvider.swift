import Foundation

/// The coding agents Pulse tracks.
///
/// Each reports its own usage, by routes that have almost nothing in common —
/// see `ClaudeCodeUsageService`, `CodexUsageService`, `AntigravityUsageService`,
/// `CursorUsageService` and the two key-based ones.
enum Provider: String, CaseIterable, Identifiable, Codable, Sendable {
    case claudeCode
    case codex
    case antigravity
    case cursor
    case openCodeGo
    case kimiCode
    case ollamaCloud
    case zai
    case glmCoding
    case minimax
    case minimaxCN
    case copilot
    case grok
    case grokBot
    case volcengine

    var id: String { rawValue }

    /// Product names, left untranslated.
    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .antigravity: "Antigravity"
        case .cursor: "Cursor"
        case .openCodeGo: "OpenCode Go"
        case .kimiCode: "Kimi Code"
        case .ollamaCloud: "Ollama Cloud"
        // Two entries rather than one with a region switch, because they are
        // two accounts on two services: a key for one is refused by the other,
        // and plenty of people have only one of them.
        // **Named for the two shops, not for the product.** Both sell the
        // same thing under the same name — "GLM Coding Plan" — so a row
        // called that is a row half the buyers will pick wrongly: an
        // international subscriber chose it, pasted a z.ai key, and had it
        // sent to the mainland service, which refused it (issue #13). The
        // company is the one thing that differs and the one thing a buyer
        // knows, so it is the whole name.
        case .zai: "z.ai"
        case .glmCoding: "智谱"
        // Same product, two storefronts and two accounts. There is no separate
        // brand name for the mainland one, so the region is the distinction.
        case .minimax: "MiniMax"
        case .minimaxCN: "MiniMax CN"
        case .copilot: "GitHub Copilot"
        // The account's pool is spent across every Grok product, not just
        // Grok Build's CLI, so the ring is about the account and the name
        // says so. See `GrokUsageService`.
        case .grok: "Grok"
        // xAI's, sold through Cursor and billed against that account — a
        // different bill from the SuperGrok pool above, under a name people
        // already use for it. See `GrokBotUsageService`.
        case .grokBot: "Grok Bot"
        // The official name. Volcengine is the platform, Ark (方舟) the model
        // service on it, and Doubao the model — the plan is sold as the Ark
        // Coding Plan, and the account, the keys and the CLI are all
        // Volcengine's. Naming it for the model would name the one part of
        // that chain the ring is not about.
        case .volcengine: "Volcengine"
        }
    }

    /// The parent brand's mark rather than the CLI-specific one — these read
    /// better at ring size and are what people recognise.
    var iconResource: String {
        switch self {
        case .claudeCode: "claude"
        case .codex: "openai"
        case .antigravity: "antigravity"
        case .cursor: "cursor"
        case .openCodeGo: "opencode"
        case .kimiCode: "kimi"
        case .ollamaCloud: "ollama"
        case .zai: "zai"
        // 清言's mark, not the corporate Zhipu one. Both rows are the same
        // company's two storefronts, so the mark is the only thing telling
        // them apart on the rail — and the corporate logo is a wordmark-ish
        // glyph that reads as "the same company as the other row" rather than
        // as a different row.
        case .glmCoding: "qingyan"
        // One mark for both, since there is only one brand. Two accounts of one
        // provider already share a mark on the rail; this is the same case.
        case .minimax, .minimaxCN: "minimax"
        case .copilot: "github"
        case .grok: "grok"
        // The parent brand's mark rather than Grok's own, which is the one
        // thing that tells the two apart on a rail carrying both.
        case .grokBot: "xai"
        case .volcengine: "volcengine"
        }
    }

    /// Whether this agent leaves transcripts on disk that Pulse can read.
    ///
    /// The two CLIs write one JSONL file per session, carrying both the token
    /// counts every local figure is built from and the turn boundaries the
    /// activity mark is read from. Antigravity is an editor rather than a CLI
    /// and keeps no such record, so anything derived from transcripts — the
    /// spending history, the estimated value of a window, the "working right
    /// now" mark — simply doesn't apply to it and is left out rather than
    /// shown as zero.
    var keepsLocalTranscripts: Bool {
        switch self {
        case .claudeCode, .codex: true
        // Antigravity is an editor and keeps nothing. OpenCode *does* keep
        // sessions with token counts — `opencode stats` adds them up — but in
        // its own store rather than the JSONL both CLIs above write, so the
        // ledger cannot read it yet. False here means "no history shown",
        // which is true today and better than a column of zeroes.
        case .antigravity, .cursor, .openCodeGo, .kimiCode, .ollamaCloud,
             .zai, .glmCoding, .minimax, .minimaxCN, .copilot, .grok, .grokBot,
             .volcengine: false
        }
    }

    /// Whether this provider's limits can be drawn as one ring per model
    /// group.
    ///
    /// Antigravity alone: its plan carries a Gemini allowance and a separate
    /// one for Claude and GPT, reported as two `scope`s of one login. They are
    /// independent budgets — spending one says nothing about the other — so a
    /// single ring can only show the worse of the two and silently drop the
    /// other. Every other provider reports one pool, or several that are
    /// facets of one.
    var splitsByModelGroup: Bool { self == .antigravity }

    /// How many rings a split account can produce. Fixed rather than counted
    /// from a reading, so the rail's own budget does not move when a provider
    /// answers with one group short.
    var modelGroupCount: Int { splitsByModelGroup ? 2 : 1 }

    /// Whether a spending history can be shown for this provider at all.
    ///
    /// **Not the same question as `keepsLocalTranscripts`**, which it used to
    /// be. Two different sources answer it: the CLIs leave session files on
    /// this Mac, and Z.ai and 智谱 publish the account's own statistics — the
    /// endpoint their console draws its charts from. The second is the better
    /// data (it covers every machine) and the poorer (one token total per
    /// model, so nothing can be priced), which is what `UsageLedger.Origin`
    /// exists to keep straight.
    var providesHistory: Bool { keepsLocalTranscripts || self == .zai || self == .glmCoding }

    /// Whether the route to this provider's figures is a choice.
    ///
    /// The two CLIs can each be read two ways, which is a setting. Antigravity
    /// and Cursor have exactly one route each — a server one of them runs
    /// itself, a login the other one stored — so it is stated rather than
    /// offered.
    /// **Not `keepsLocalTranscripts`**, which it used to be. The two happened
    /// to agree while only the CLIs had a choice, and reading one for the other
    /// is the kind of coincidence that breaks silently: Volcengine has two routes
    /// and no transcripts, and would have been given a stated route it does not
    /// have instead of the picker it needs.
    var hasSourceChoice: Bool {
        switch self {
        case .claudeCode, .codex, .volcengine, .kimiCode: true
        case .antigravity, .cursor, .openCodeGo, .ollamaCloud,
             .zai, .glmCoding, .minimax, .minimaxCN, .copilot, .grok, .grokBot: false
        }
    }

    /// The one route this provider has, named for the settings row that
    /// states it rather than offering a picker. Nil where the row is never
    /// drawn — a provider with a choice of routes, or one whose credential is
    /// a key the user pastes.
    ///
    /// **Exhaustive on purpose.** This was a ternary in `SettingsView` that
    /// named Cursor's route and let *everything else* fall through to
    /// Antigravity's words, so Grok's pane read "Antigravity's language
    /// server · Only while Antigravity is open." — about a route it does not
    /// have and an app it has nothing to do with. A switch here means the next
    /// provider added cannot inherit somebody else's sentence in silence.
    var soleRoute: (name: String, note: String)? {
        switch self {
        case .antigravity:
            (String.localized("Antigravity's language server"),
             String.localized("Only while Antigravity is open."))
        case .cursor:
            (String.localized("Cursor's own login"),
             String.localized("Uses the login Cursor already saved."))
        case .grok:
            (String.localized("Grok's own login"),
             String.localized("Uses the login Grok's CLI already saved."))
        // The credential really is Cursor's: Grok Bot is billed against that
        // account, so this names where the login comes from rather than the
        // product it reports on.
        case .grokBot:
            (String.localized("Cursor's own login"),
             String.localized("Grok Bot is billed to your Cursor account."))
        // Either a choice of routes, or a key the user pastes: both are asked
        // about elsewhere, so there is nothing here to state.
        case .claudeCode, .codex, .openCodeGo, .kimiCode, .ollamaCloud,
             .zai, .glmCoding, .minimax, .minimaxCN, .copilot, .volcengine:
            nil
        }
    }

    /// Whether Pulse needs an API key from the user for this one.
    ///
    /// The others borrow a login their own CLI stored. OpenCode stores one too,
    /// and that is the route taken first — but a key can also be pasted in for
    /// anyone on the plan who doesn't run the CLI on this Mac.
    var usesAPIKey: Bool {
        [.openCodeGo, .kimiCode, .ollamaCloud, .zai, .glmCoding, .minimax, .minimaxCN, .volcengine].contains(self)
    }

    /// Whether the pasted credential is a **pair** rather than one token.
    ///
    /// Volcengine signs with an access key id and a secret, so Volcengine's field
    /// takes `AccessKeyID:SecretAccessKey`. One field rather than two because
    /// the whole store, the whole settings row and the whole "is it set" test
    /// are built around one string per provider — and because it is optional
    /// anyway: `arkcli` is the other route and needs nothing pasted at all.
    var usesKeyPair: Bool { self == .volcengine }

    /// Whether what the user pastes is a browser session rather than an API
    /// key. Ollama has no quota API at all — the figures are read from its
    /// signed-in settings page — so a session is the only credential there is,
    /// and calling it an API key in Settings would send people looking for one
    /// that does not exist.
    var usesSessionCookie: Bool { self == .ollamaCloud }

    /// Whether this provider can report anything at all without being set up.
    ///
    /// The key-based ones cannot: with no key they draw a ring that says
    /// "enter an API key in Settings" and nothing else, for a service the
    /// person may well not have an account with. Switching those on
    /// uninvited — which is what the offer-once rule did — spends a slot on
    /// the rail to advertise a plan, and with eleven providers that is most
    /// of the rail.
    ///
    /// So a new provider appears by itself only when it has something to say.
    /// The rest wait in Settings, where they can be switched on deliberately.
    /// Whether Pulse holds a credential of its own for this provider.
    ///
    /// **Not the same question as `usesAPIKey`**, which asks whether the user
    /// pastes one and so decides what Settings draws. Copilot is signed in to
    /// rather than pasted, but its token lives in the same encrypted store —
    /// and reading `usesAPIKey` where the *storage* was meant is what left a
    /// signed-in account reporting "sign in again": the token was saved and
    /// then never loaded back for the fetch.
    var keepsOwnCredential: Bool { usesAPIKey || self == .copilot }

    var canReportWithoutSetup: Bool {
        guard keepsOwnCredential else { return borrowsAnExistingLogin }
        if APIKeyStore.key(for: self) != nil { return true }
        if self == .kimiCode, AccountCredentialStore.credentials(for: AccountKey(self)) != nil {
            return true
        }

        // Two of them can find a credential another tool already saved, which
        // counts: nothing has to be pasted for those to work.
        return switch self {
        case .openCodeGo: OpenCodeGoUsageService.storedKey() != nil
        case .glmCoding: ZaiUsageService.storedKey(for: .glmCoding) != nil
        default: false
        }
    }

    /// For a provider that borrows another tool's login: whether there is one
    /// on this Mac to borrow.
    ///
    /// **Needing no key is not the same as having something to say**, and
    /// reading it that way is what the offer-once rule above would otherwise
    /// do with a new provider. Grok borrows what `grok login` stored and Grok
    /// Bot what the Cursor editor stored; with neither installed they would be
    /// switched on at the next update for everyone, and the rail would grow
    /// two rings reading "sign in to something you have never heard of" — the
    /// exact greyed-out rail the rule exists to prevent, arriving as an
    /// upgrade rather than on a first run.
    ///
    /// Only the two added here are gated. The others were offered before this
    /// question was asked of anything, so they are stamped in every stored
    /// list already and their answer cannot change what anyone sees; the rule
    /// is for what comes next.
    private var borrowsAnExistingLogin: Bool {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return switch self {
        case .grok: FileManager.default.fileExists(atPath: home.appending(path: ".grok").path)
        case .grokBot: CursorAppLogin.hasStoredLogin()
        default: true
        }
    }

    /// Whether this agent looks installed, for the **first run only**.
    ///
    /// Showing all four to someone who uses one is three quarters of a rail
    /// greyed out, reading as broken rather than as not-yet-configured — and a
    /// rail half again as tall as it needs to be. So the first launch starts
    /// with what is actually here, and the rest are a switch away in Settings.
    ///
    /// Only the presence of a directory is checked, never its contents: this
    /// is "has this agent ever run here", not anything about the account.
    /// Kimi Code is absent by design: it has nothing to install and Pulse
    /// never goes looking for its key, so there is nothing to find.
    static func installedOnThisMac() -> Set<Provider> {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let manager = FileManager.default

        var found: Set<Provider> = []
        if manager.fileExists(atPath: home.appending(path: ".claude").path) {
            found.insert(.claudeCode)
        }
        if manager.fileExists(atPath: home.appending(path: ".codex").path) {
            found.insert(.codex)
        }
        if manager.fileExists(atPath: home.appending(path: ".grok").path) {
            found.insert(.grok)
        }
        // The standalone app only. Grok Bot can also be used inside Cursor,
        // but a Cursor login is no evidence the plan *includes* it — every
        // Cursor user would get a ring that says "your plan doesn't include
        // this", which is the greyed-out rail this whole function exists to
        // avoid. It is a switch away in Settings for anyone who has it.
        let grokBot = ["/Applications/Grok Bot.app",
                       home.appending(path: "Applications/Grok Bot.app").path]
        if grokBot.contains(where: manager.fileExists(atPath:)) {
            found.insert(.grokBot)
        }
        // Not everyone installs into /Applications.
        let antigravity = ["/Applications/Antigravity.app",
                           home.appending(path: "Applications/Antigravity.app").path]
        if antigravity.contains(where: manager.fileExists(atPath:)) {
            found.insert(.antigravity)
        }

        // Cursor's own store, rather than the bundle: it is the same
        // "has this ever run here" evidence as `~/.claude`, and it does not
        // care where the app was dragged to.
        if CursorAppLogin.hasStoredLogin() {
            found.insert(.cursor)
        }

        // OpenCode Go has nothing to install, but a key OpenCode already saved
        // is the same kind of evidence: this Mac is set up for it. Without
        // this, someone whose only agent is OpenCode Go detects nothing and
        // gets the everything-on fallback.
        if OpenCodeGoUsageService.storedKey() != nil {
            found.insert(.openCodeGo)
        }

        // The same evidence for the mainland GLM plan: its relay and console
        // tools leave the key in a one-line file. z.ai's international route
        // has no such file, so it is never detected — nothing to find.
        if ZaiUsageService.storedKey(for: .glmCoding) != nil {
            found.insert(.glmCoding)
        }

        return found
    }
}
