// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Money by kind of token, at one model's own rates.
///
/// `TokenTally` says how many tokens of each kind; this says what they cost.
/// The split is kept rather than only a total because a model's input, cache
/// and output rates differ by an order of magnitude, and a per-model figure
/// built from the wrong kind of token is a number nobody can check. It is also
/// the summand a day's or an agent's money is rolled up from, so there is one
/// arithmetic behind every figure on the page.
struct TokenCost: Codable, Equatable, Sendable {
    var input = 0.0
    var cacheWrite = 0.0
    var cacheRead = 0.0
    var output = 0.0

    var total: Double { input + cacheWrite + cacheRead + output }

    static func + (lhs: TokenCost, rhs: TokenCost) -> TokenCost {
        TokenCost(
            input: lhs.input + rhs.input,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            output: lhs.output + rhs.output
        )
    }
}
