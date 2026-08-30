import Foundation

/// The coding agents Pulse tracks.
///
/// Both report their own usage, by very different routes — see
/// `CodexUsageService` and `ClaudeCodeUsageService`.
enum Provider: String, CaseIterable, Identifiable, Sendable {
    case claudeCode
    case codex

    var id: String { rawValue }

    /// Product names, left untranslated.
    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// The parent brand's mark rather than the CLI-specific one — these read
    /// better at ring size and are what people recognise.
    var iconResource: String {
        switch self {
        case .claudeCode: "claude"
        case .codex: "openai"
        }
    }

}
