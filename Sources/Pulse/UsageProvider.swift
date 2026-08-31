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
        case .antigravity, .cursor, .openCodeGo, .kimiCode, .ollamaCloud: false
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
    var usesAPIKey: Bool { self == .openCodeGo || self == .kimiCode || self == .ollamaCloud }

    /// Whether what the user pastes is a browser session rather than an API
    /// key. Ollama has no quota API at all — the figures are read from its
    /// signed-in settings page — so a session is the only credential there is,
    /// and calling it an API key in Settings would send people looking for one
    /// that does not exist.
    var usesSessionCookie: Bool { self == .ollamaCloud }

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

        return found
    }
}
