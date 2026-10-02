// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Prime Agent: the Pi RLM format plus a parent/child accounting problem.
///
/// A parent assistant message can persist a **cumulative** `aggregateUsage`
/// that already includes the usage of a child invocation, and a
/// `child_usage_attributed` record states which child and how much. The child
/// transcript is also scanned directly as its own usage, so adding the parent's
/// aggregate unchanged would count the child twice. The fix is not a guess: the
/// parent message whose own tally **equals** the stated aggregate is the one
/// injected, and it is reduced by exactly the stated child usage, clamped at
/// zero.
///
/// **When the child is not present, the parent keeps its aggregate.** Subtracting
/// a child Pulse cannot find would silently drop tokens nobody else accounts
/// for; keeping them is the conservative, checkable choice.
///
/// Attribution ids are eight hex characters that are unique only inside one
/// session, and a fork copies a session's records into a new file. Pairing the
/// id with the resolved fork-lineage root collapses copies of one attribution
/// while keeping two unrelated sessions' collisions apart. A `parentSession`
/// cycle resolves every member to the lexicographically smallest path, so the
/// lineage is deterministic rather than traversal-order dependent.
enum PrimeAgentSessionReader {
    static func records(roots: [URL]) -> [AgentUsageRecord] {
        let files = AgentLogIO.files(in: roots, extensions: ["jsonl"]).map { PiTranscript.parse($0) }

        var parentOf: [String: String] = [:]
        for file in files {
            guard let parent = file.header.parentSession else { continue }
            parentOf[file.path] = URL(fileURLWithPath: parent).standardizedFileURL.path
        }

        /// The top of a fork lineage, collapsing a cycle to its smallest path.
        func lineageRoot(_ start: String) -> String {
            var chain: [String] = []
            var current = start
            while true {
                if let index = chain.firstIndex(of: current) {
                    return chain[index...].min() ?? current
                }
                chain.append(current)
                guard let parent = parentOf[current] else { return current }
                current = parent
            }
        }

        func isDescendant(_ child: String, of ancestor: String) -> Bool {
            var current: String? = child
            var visited: Set<String> = []
            while let path = current {
                if path == ancestor { return true }
                guard visited.insert(path).inserted else { return false }
                current = parentOf[path]
            }
            return false
        }

        // Every child transcript's total, for matching a stated child usage. A
        // fork's `parentSession` names the file it copied (not a child); only a
        // positive `rlmDepth` is a child.
        let childTotals: [(path: String, tally: TokenTally)] = files
            .filter { ($0.header.rlmDepth ?? 0) > 0 }
            .map { ($0.path, $0.messages.reduce(TokenTally()) { $0 + $1.tally }) }

        var consumedChildren: Set<String> = []
        var seenAttributions: Set<String> = []
        // Keyed by the parent message's stable identity so a fork copy of the
        // same message is reduced identically.
        var reductions: [String: TokenTally] = [:]

        for file in files {
            for attribution in file.attributions {
                guard let id = attribution.id, let target = attribution.targetId else { continue }

                let key = "\(lineageRoot(file.path))#\(id)"
                guard seenAttributions.insert(key).inserted else { continue }
                guard attribution.aggregateUsage.total > 0, attribution.childUsage.total > 0 else { continue }

                guard let message = file.messages.first(where: {
                    $0.id == target && $0.tally == attribution.aggregateUsage
                }) else { continue }

                guard let index = childTotals.firstIndex(where: {
                    !consumedChildren.contains($0.path)
                        && $0.tally == attribution.childUsage
                        && isDescendant($0.path, of: lineageRoot(file.path))
                }) else { continue }
                consumedChildren.insert(childTotals[index].path)

                let identity = deduplicationID(message: message)
                reductions[identity] = (reductions[identity] ?? TokenTally()) + attribution.childUsage
            }
        }

        var records: [AgentUsageRecord] = []
        var incomplete = false
        for file in files {
            let sessionID = file.isValid ? file.header.id : nil
            for message in file.messages {
                var tally = message.tally
                if let subtract = reductions[deduplicationID(message: message)] {
                    tally = TokenTally(
                        input: max(0, tally.input - subtract.input),
                        cacheWrite: max(0, tally.cacheWrite - subtract.cacheWrite),
                        cacheRead: max(0, tally.cacheRead - subtract.cacheRead),
                        output: max(0, tally.output - subtract.output)
                    )
                }
                guard tally.total > 0 || message.unclassified > 0 else { continue }
                guard let sessionID, let timestamp = message.timestamp, let model = message.model else {
                    incomplete = true
                    continue
                }

                records.append(
                    AgentUsageRecord(
                        timestamp: timestamp,
                        model: model,
                        tally: tally,
                        sessionID: sessionID,
                        sessionName: nil,
                        title: nil,
                        project: file.header.cwd,
                        deduplicationID: deduplicationID(message: message),
                        unclassifiedTokens: message.unclassified
                    )
                )
            }
        }
        return incomplete ? records.map(markedPartial) : records
    }

    private static func markedPartial(_ record: AgentUsageRecord) -> AgentUsageRecord {
        var copy = record
        copy.isPartial = true
        return copy
    }

    /// A fork copy must fold onto its original, so the key is session-independent.
    private static func deduplicationID(message: PiTranscript.Message) -> String {
        if let responseId = message.responseId {
            return "prime-agent:response:\(responseId)"
        }
        let milliseconds = message.timestamp.map { Int(($0.timeIntervalSince1970 * 1000).rounded()) } ?? 0
        let tally = message.tally
        return "prime-agent:message:\(message.id ?? ""):\(milliseconds):\(message.provider ?? ""):"
            + "\(message.model ?? ""):\(tally.input):\(tally.output):\(tally.cacheRead):\(tally.cacheWrite)"
    }
}
