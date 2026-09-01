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
        case .zai: "Z.ai"
        case .glmCoding: "GLM Coding Plan"
        // Same product, two storefronts and two accounts. There is no separate
        // brand name for the mainland one, so the region is the distinction.
        case .minimax: "MiniMax"
        case .minimaxCN: "MiniMax CN"
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
        // The parent brand's mark, which is also what tells the two apart on
        // the rail — they are one company's two storefronts.
        case .glmCoding: "zhipu"
        // One mark for both, since there is only one brand. Two accounts of one
        // provider already share a mark on the rail; this is the same case.
        case .minimax, .minimaxCN: "minimax"
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
             .zai, .glmCoding, .minimax, .minimaxCN: false
        }
    }

    /// Whether the route to this provider's figures is a choice.
    ///
    /// The two CLIs can each be read two ways, which is a setting. Antigravity
    /// and Cursor have exactly one route each — a server one of them runs
    /// itself, a login the other one stored — so it is stated rather than
    /// offered.
    var hasSourceChoice: Bool { keepsLocalTranscripts }

    /// Whether Pulse needs an API key from the user for this one.
    ///
    /// The others borrow a login their own CLI stored. OpenCode stores one too,
    /// and that is the route taken first — but a key can also be pasted in for
    /// anyone on the plan who doesn't run the CLI on this Mac.
    var usesAPIKey: Bool {
        [.openCodeGo, .kimiCode, .ollamaCloud, .zai, .glmCoding, .minimax, .minimaxCN].contains(self)
    }

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
    var canReportWithoutSetup: Bool {
        guard usesAPIKey else { return true }
        if APIKeyStore.key(for: self) != nil { return true }

        // Two of them can find a credential another tool already saved, which
        // counts: nothing has to be pasted for those to work.
        return switch self {
        case .openCodeGo: OpenCodeGoUsageService.storedKey() != nil
        case .glmCoding: ZaiUsageService.storedKey(for: .glmCoding) != nil
        default: false
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
