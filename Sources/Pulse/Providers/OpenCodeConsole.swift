// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// OpenCode's console log of every request on the workspace: the account's own
/// record, across every machine and every client that uses its keys — OpenCode
/// itself, and anything else pointed at the Go endpoint.
///
/// **Read with the console's session, not the Go key.** The key answers the
/// plan's limits (`OpenCodeGoUsageService`); the logs are behind the signed-in
/// console, `GET /console/api/request-logs`. Every console route also wants the
/// workspace in an `x-org-id` header — without it each answers `400
/// {"_tag":"BadRequest"}` — and `GET /console/api/orgs` lists the session's
/// workspaces, so nothing has to be entered (`OpenCodeConsoleWorkspace`). The session is read out of the browser in
/// Settings and kept in its own slot beside the key, so neither replaces the
/// other. Undocumented, like the usage route; it can change without notice.
///
/// **Only what a ledger needs is decoded.** Each entry also carries the city
/// the request came from, the key's id and the request headers; none of it is
/// read, so none of it is ever held.
enum OpenCodeConsole {
    static let host = "opencode.ai"
    /// The `APIKeyStore` slot the session is kept in, beside the Go key.
    static let slot = "console"
    /// The console's session and the account login. Stripe's tracking and
    /// the language preference come along from the browser and are dropped.
    static let cookieNames: Set<String> = ["__Host-console_session", "auth"]

    /// The console keeps 30 days. A day more is asked for so a month's chart
    /// starts on a whole day; the server answers with what it has.
    static let span: TimeInterval = 31 * 86_400
    /// The most the console hands out at once: 100 is answered, 200 is a
    /// `400` (measured).
    static let pageSize = 100
    /// More than six simultaneous requests slowed the console in local probes.
    /// The adaptive pager shares this bound across all time ranges and retries.
    static let concurrentPages = 6
    /// A total budget across the entire scan, not a separate budget per range.
    /// A history needing more is marked partial and resumed on the next read.
    static let pageLimit = 200

    /// Keeps only the cookies that sign in; nil when the console's session is
    /// not among them, which is what "signed out of the console" looks like.
    static func keep(_ header: String) -> String? {
        let pairs = header.split(separator: ";").compactMap { part -> (String, String)? in
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let equals = trimmed.firstIndex(of: "=") else { return nil }
            let name = String(trimmed[..<equals])
            return cookieNames.contains(name) ? (name, String(trimmed[trimmed.index(after: equals)...])) : nil
        }
        guard pairs.contains(where: { $0.0 == "__Host-console_session" && !$0.1.isEmpty }) else { return nil }
        return pairs.map { "\($0.0)=\($0.1)" }.joined(separator: "; ")
    }

    // MARK: - Whether a session is kept

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored = false

    /// Whether a console session is kept, read from memory: the detailed card
    /// asks on every frame which history it has, and the key file is not read
    /// that often. Refreshed with the keys (`UsageStore.loadAPIKeys`).
    static var hasSession: Bool { lock.withLock { stored } }

    static func refreshSession() {
        let present = APIKeyStore.key(for: .openCodeGo, slot: slot) != nil
        lock.withLock { stored = present }
    }

    // MARK: - The reply

    struct Page: Decodable, Sendable {
        let items: [Item]
        let nextCursor: String?
    }

    struct Item: Codable, Sendable, Equatable {
        let id: String
        /// Milliseconds since 1970.
        let startedAt: Double
        /// `go` for the Go plan; the console also logs other products.
        let product: String?
        let model: String?
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheReadTokens: Int?
        let cacheWriteTokens: Int?
        /// What the request cost, in dollars, as OpenCode charged it. Nil for
        /// a request that failed before anything was spent.
        let cost: Double?

        var date: Date { Date(timeIntervalSince1970: startedAt / 1000) }

        /// The four kinds. Input is fresh input: the cache reads are counted
        /// beside it, never inside it — a request reading 294,272 tokens from
        /// the cache logs 184 of input.
        var tally: TokenTally {
            TokenTally(
                input: inputTokens ?? 0,
                cacheWrite: cacheWriteTokens ?? 0,
                cacheRead: cacheReadTokens ?? 0,
                output: outputTokens ?? 0
            )
        }
    }

    enum Read: Sendable {
        case answered(UsageLedger)
        /// The console turned the session away: signed out, or expired.
        case signedOut
        /// Nothing usable came back.
        case failed
    }

    // MARK: - Paging

    /// Every page from the newest back to `since`, asked for one after
    /// another with each page's cursor.
    ///
    /// `complete` is false when the walk stopped for any reason but the
    /// server's own end — the page limit, a cursor handed back twice, a page
    /// that failed after others arrived — so a short history can be said to
    /// be short rather than passed off as the month.
    static func collect(
        retryDelay: Duration = .seconds(1),
        fetch: (_ cursor: String?) async -> PageResult
    ) async -> (items: [Item], complete: Bool, outcome: PageResult?) {
        var items: [Item] = []
        var cursor: String?
        var seen: Set<String> = []
        for _ in 0..<pageLimit {
            let result = await retryPage(retryDelay: retryDelay) { await fetch(cursor) }
            if case .signedOut = result { return (items, false, .signedOut) }
            guard case .page(let page) = result else {
                return (items, false, items.isEmpty ? result : nil)
            }
            items.append(contentsOf: page.items)
            guard let next = page.nextCursor, !next.isEmpty, !page.items.isEmpty else {
                return (items, true, nil)
            }
            guard seen.insert(next).inserted else { return (items, false, nil) }
            cursor = next
        }
        return (items, false, nil)
    }

    /// Retry transient failures twice, but never retry cancellation or a
    /// session the server rejected. Shared by sequential and adaptive walks.
    static func retryPage(
        retryDelay: Duration,
        fetch: () async -> PageResult
    ) async -> PageResult {
        for attempt in 0...2 {
            guard !Task.isCancelled else { return .failed }
            if attempt > 0 {
                do { try await Task.sleep(for: retryDelay * attempt) }
                catch { return .failed }
            }
            let result = await fetch()
            if case .failed = result {
                if attempt == 2 { return result }
            } else { return result }
        }
        return .failed
    }

    enum PageResult: Sendable {
        case page(Page)
        case signedOut
        case failed
    }

    /// Preserve an item's exact millisecond when a Date becomes an inclusive
    /// query boundary. Truncating floating-point round-off can lose the rest
    /// of a page's last timestamp. Also used by the synthetic API fixture.
    static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    static func fetchPage(cookie: String, org: String, since: Date, until: Date? = nil, cursor: String?) async -> PageResult {
        var components = URLComponents(string: "https://\(host)/console/api/request-logs")!
        var query = [
            URLQueryItem(name: "since", value: String(milliseconds(since))),
            URLQueryItem(name: "category", value: "inference"),
            URLQueryItem(name: "limit", value: String(pageSize)),
        ]
        if let until { query.append(URLQueryItem(name: "until", value: String(milliseconds(until)))) }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        components.queryItems = query
        guard let url = components.url else { return .failed }

        var request = URLRequest(url: url)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(org, forHTTPHeaderField: "x-org-id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        guard let (data, response) = try? await NetworkSession.shared.recordedData(for: request, delegate: NoRedirects()) else { return .failed }
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 401, 403: return .signedOut
        default: return .failed
        }
        // A signed-out console answers its sign-in page, not an error code.
        guard let page = try? JSONDecoder().decode(Page.self, from: data) else {
            let text = String(decoding: data.prefix(64), as: UTF8.self)
            return text.contains("<") ? .signedOut : .failed
        }
        return .page(page)
    }

    // MARK: - The workspace

    /// One of the session's workspaces, as `/console/api/orgs` lists them.
    struct Workspace: Decodable, Sendable, Equatable {
        let id: String
        let name: String?
    }

    enum Resolved: Sendable {
        case workspace(Workspace)
        case signedOut
        case failed
    }

    /// The session's workspaces, or why there are none to name.
    static func workspaces(cookie: String) async -> Result<[Workspace], WorkspaceFailure> {
        var request = URLRequest(url: URL(string: "https://\(host)/console/api/orgs")!)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        guard let (data, response) = try? await NetworkSession.shared.recordedData(for: request, delegate: NoRedirects()) else { return .failure(.failed) }
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 401, 403: return .failure(.signedOut)
        default: return .failure(.failed)
        }
        guard let list = try? JSONDecoder().decode([Workspace].self, from: data) else {
            let text = String(decoding: data.prefix(64), as: UTF8.self)
            return .failure(text.contains("<") ? .signedOut : .failed)
        }
        return .success(list.filter { !$0.id.isEmpty })
    }

    enum WorkspaceFailure: Error { case signedOut, failed }

    // MARK: - The ledger

    /// The Go plan's requests as a ledger: days from `span` ago to today, the
    /// gaps closed, with each day's kinds, models and cost, and quarter-hours
    /// for the value estimate.
    ///
    /// **Go only.** The console logs every product on the workspace; the ring
    /// is the Go plan's, so its card counts the Go plan's requests.
    static func ledger(from items: [Item], now: Date = Date(), calendar: Calendar = .current) -> UsageLedger {
        let start = calendar.startOfDay(for: now.addingTimeInterval(-span))
        let go = items.filter { $0.product == "go" && $0.date >= start && $0.date <= now }

        var byDay: [Date: [Item]] = [:]
        var bySlot: [Date: (tokens: Int, cost: Double, unpriced: Int, models: [String: TokenTally])] = [:]
        var unpricedModels: Set<String> = []
        for item in go {
            byDay[calendar.startOfDay(for: item.date), default: []].append(item)
            let quarter = 15.0 * 60
            let slot = Date(timeIntervalSince1970: (item.date.timeIntervalSince1970 / quarter).rounded(.down) * quarter)
            var entry = bySlot[slot] ?? (0, 0, 0, [:])
            let tally = item.tally
            entry.tokens += tally.total
            entry.cost += item.cost ?? 0
            if item.cost == nil, tally.total > 0 {
                entry.unpriced += tally.total
                if let model = item.model { unpricedModels.insert(model) }
            }
            if let model = item.model { entry.models[model] = (entry.models[model] ?? TokenTally()) + tally }
            bySlot[slot] = entry
        }

        var days: [LedgerDay] = []
        var date = start
        let today = calendar.startOfDay(for: now)
        while date <= today {
            let items = byDay[date] ?? []
            var models: [String: Int] = [:]
            var modelTallies: [String: TokenTally] = [:]
            var tally = TokenTally()
            var cost = 0.0
            var unpriced = 0
            for item in items {
                let kinds = item.tally
                tally = tally + kinds
                cost += item.cost ?? 0
                if item.cost == nil { unpriced += kinds.total }
                if let model = item.model {
                    models[model, default: 0] += kinds.total
                    modelTallies[model] = (modelTallies[model] ?? TokenTally()) + kinds
                }
            }
            var day = LedgerDay(date: date, tokens: tally.total, cost: cost, unpricedTokens: unpriced, models: models)
            day.tally = tally
            day.modelTallies = modelTallies
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }

        var ledger = UsageLedger(
            days: days,
            earliest: go.map(\.date).min(),
            unpricedModels: unpricedModels.sorted(),
            modelNames: [:],
            slots: bySlot.keys.sorted().map { start in
                let entry = bySlot[start]!
                return UsageLedger.Slot(start: start, tokens: entry.tokens, cost: entry.cost,
                                        unpricedTokens: entry.unpriced, models: entry.models)
            }
        )
        ledger.origin = .providerLogs
        return ledger
    }
}

/// Which workspace the console's session reads, asked once per session.
///
/// `/console/api/orgs` lists them. One is the usual case and is used as it is;
/// with several, the first that holds a Go subscription is — the ring is the
/// Go plan's — and the first of all when none answers that it does.
actor OpenCodeConsoleWorkspace {
    static let shared = OpenCodeConsoleWorkspace()

    private var cached: (cookie: String, workspace: OpenCodeConsole.Workspace)?

    func resolve(cookie: String) async -> OpenCodeConsole.Resolved {
        if let cached, cached.cookie == cookie { return .workspace(cached.workspace) }
        switch await OpenCodeConsole.workspaces(cookie: cookie) {
        case .failure(.signedOut): return .signedOut
        case .failure(.failed): return .failed
        case .success(let list):
            guard let first = list.first else { return .failed }
            guard list.count > 1 else {
                cached = (cookie, first)
                return .workspace(first)
            }
            for workspace in list where await OpenCodeGoUsageService.hasGoAccess(cookie: cookie, org: workspace.id) {
                cached = (cookie, workspace)
                return .workspace(workspace)
            }
            // No workspace answered with Go — perhaps none has it, perhaps the
            // console was unreachable for a moment. The first is used for now
            // but **not kept**: a blip at launch must not pin the session to
            // the workspace without the plan until Pulse restarts.
            return .workspace(first)
        }
    }

    /// Asked again next time: a workspace that stops answering may be gone.
    func forget() { cached = nil }
}
