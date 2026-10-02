// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Freebuff, which shares Codebuff's `manicode*` trees but persists no usage.
///
/// A Freebuff chat is one whose `metadata.runState.sessionState.mainAgentState
/// .agentType` starts with `base2-free`; the Codebuff agent types (`base2`,
/// `base2-lite`, `base2-max`, `base2-plan`) are the other product. A chat that
/// carries authoritative usage is Codebuff's even when its agent type says
/// otherwise, so `CodebuffUsageReader` claims it and this reader never does.
///
/// **Nothing is emitted, and that is the whole reader.** The only figures
/// Freebuff leaves are estimates from message character counts — roughly four
/// characters to a token. Pulse does not show an inferred count as if it were
/// reported, and a "0 tokens" from a store that persisted none is a fabricated
/// zero. So this reader answers with no records and says why, and the token
/// spend pane reports no Freebuff usage rather than an estimate dressed as a
/// reading.
enum FreebuffUsageReader {
    /// The line a caller shows in place of a figure: no counters are persisted.
    static let limitation =
        "Freebuff stores no token counters; only character-based estimates exist, "
        + "which Pulse does not report as usage."

    /// Whether a chat belongs to Freebuff by its agent type.
    static func isFreebuff(_ message: [String: Any]) -> Bool {
        guard
            let metadata = AgentLogIO.object(message["metadata"]),
            let runState = AgentLogIO.object(metadata["runState"]),
            let sessionState = AgentLogIO.object(runState["sessionState"]),
            let mainAgent = AgentLogIO.object(sessionState["mainAgentState"]),
            let agentType = AgentLogIO.text(mainAgent["agentType"])
        else { return false }
        return agentType.lowercased().hasPrefix("base2-free")
    }

    /// Always empty: the store has no reported counters to hand over.
    static func records(roots: [URL]) -> [AgentUsageRecord] { [] }
}
