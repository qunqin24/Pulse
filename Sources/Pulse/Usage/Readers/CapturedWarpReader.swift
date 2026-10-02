// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Warp's synced account snapshot.
///
/// **This reader returns no records, ever, and that is the point.** A Warp
/// snapshot carries a request count and money — `requestsUsed` and
/// `spendCents` — and **no tokens of any kind**. `TokenTally` is the boundary
/// here, and a request is not a token: fabricating one, or dividing the spend
/// by a price to arrive at a token count, would put a number on the page that
/// nobody measured.
///
/// `CapturedUsageReaders.inputs` still names the Warp cache, so a UI can see
/// that the snapshot exists and say plainly that Warp reports requests and cost
/// but no token usage, rather than showing a silent zero.
enum CapturedWarpReader {
    /// Always empty. The snapshot is a real source; it simply has no tokens to
    /// contribute to a token ledger.
    static func records(roots: [URL]) -> [AgentUsageRecord] {
        []
    }
}
