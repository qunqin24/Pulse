import Foundation

/// Antigravity's limits, read from the language server it runs on this Mac.
///
/// The odd one out of the three. There is no account endpoint to ask and no
/// stored login to borrow: Antigravity's editor starts a `language_server`
/// process of its own and talks to it over HTTPS on the loopback interface,
/// and that process is the only thing that knows the quota. So this is the one
/// provider whose figures exist **only while the app is running** — which is
/// what `.antigravityNotRunning` says, rather than dressing it up as a failure.
///
/// Three things have to be found, and not one of them can be assumed:
/// - **the process**, which lives inside the app bundle rather than on `PATH`;
/// - **the port**, because the app starts the server with
///   `--https_server_port 0`, meaning "take any free one" — it is a different
///   port on every launch, so anything hardcoded is wrong by the next restart;
/// - **the CSRF token**, a per-launch UUID passed on the command line. Without
///   it the server answers `unauthenticated`, and it is the reason this can
///   only ever read the quota of the Antigravity running as this same user.
struct AntigravityUsageService: Sendable {
    /// The RPC that carries the quota. Antigravity is built on Codeium's
    /// language server, hence the `exa.` package and the `x-codeium-` header.
    private static let method = "exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"
    private static let csrfHeader = "x-codeium-csrf-token"

    func fetch() async -> ProviderUsage {
        guard let server = Self.locateServer() else {
            return .unavailable(.antigravity, reason: .antigravityNotRunning)
        }

        // The server listens on more than one port and only one of them speaks
        // this. Which is which isn't advertised, so they are simply tried.
        for port in server.ports {
            switch await Self.ask(port: port, token: server.token) {
            case .success(let windows) where !windows.isEmpty:
                return ProviderUsage(
                    provider: .antigravity,
                    windows: windows,
                    observedAt: Date(),
                    state: .live,
                    // The quota server names neither, and a plan invented from
                    // the limits would be a guess wearing a fact's clothes.
                    plan: nil,
                    creditBalance: nil
                )
            case .success:
                return .unavailable(.antigravity, reason: .noLimitsReported)
            case .failure(.wrongPort):
                continue
            case .failure(let reason):
                return .unavailable(.antigravity, reason: reason.unavailability)
            }
        }

        return .unavailable(.antigravity, reason: .unreachable)
    }

    // MARK: - Finding it

    private struct Server {
        let ports: [Int]
        let token: String
    }

    private static func locateServer() -> Server? {
        guard let (pid, token) = languageServerProcess() else { return nil }

        let ports = listeningPorts(of: pid)
        return ports.isEmpty ? nil : Server(ports: ports, token: token)
    }

    /// The language server's pid and CSRF token, from the process list.
    ///
    /// Matched on the app bundle's own path rather than on the executable's
    /// name: `language_server` is Codeium's binary and the same name is used by
    /// its other editors, which would otherwise be asked for Antigravity's
    /// quota and answer for something else.
    private static func languageServerProcess() -> (pid: Int32, token: String)? {
        guard let listing = run("/bin/ps", ["-axww", "-o", "pid=,command="]) else { return nil }

        for line in listing.split(separator: "\n") {
            guard
                line.contains("/Antigravity.app/"),
                line.contains("/language_server")
            else { continue }

            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard
                let pid = fields.first.flatMap({ Int32($0) }),
                let flag = fields.firstIndex(of: "--csrf_token"),
                fields.index(after: flag) < fields.endIndex
            else { continue }

            return (pid, String(fields[fields.index(after: flag)]))
        }

        return nil
    }

    /// Every loopback port the process is listening on.
    ///
    /// `-F n` asks `lsof` for just the names, one per line, which is far
    /// steadier to read than its columns.
    private static func listeningPorts(of pid: Int32) -> [Int] {
        guard let listing = run(
            "/usr/sbin/lsof",
            ["-nP", "-a", "-p", "\(pid)", "-iTCP", "-sTCP:LISTEN", "-F", "n"]
        ) else { return [] }

        return listing
            .split(separator: "\n")
            .compactMap { line in
                guard line.hasPrefix("n") else { return nil }
                return line.split(separator: ":").last.flatMap { Int($0) }
            }
    }

    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Asking it

    private enum Failure: Error {
        /// This port answered, but not with this service — try the next one.
        case wrongPort
        case refused
        case unreadable

        var unavailability: ProviderUsage.Unavailability {
            switch self {
            case .wrongPort, .refused: .antigravityNotRunning
            case .unreadable: .unreadableReply
            }
        }
    }

    private static func ask(port: Int, token: String) async -> Result<[UsageWindow], Failure> {
        guard let url = URL(string: "https://127.0.0.1:\(port)/\(method)") else {
            return .failure(.wrongPort)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: csrfHeader)
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 6

        let session = URLSession(
            configuration: .ephemeral,
            delegate: LoopbackTrust(),
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }

        guard let (data, response) = try? await session.data(for: request) else {
            return .failure(.wrongPort)
        }

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 401, 403: return .failure(.refused)
        default: return .failure(.wrongPort)
        }

        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return .failure(.unreadable)
        }

        return .success(windows(from: reply))
    }

    // MARK: - Reading the reply

    private struct Reply: Decodable {
        struct Bucket: Decodable {
            let bucketId: String?
            let window: String?
            let remainingFraction: Double?
            let resetTime: String?
        }

        struct Group: Decodable {
            let displayName: String?
            let buckets: [Bucket]?
        }

        struct Response: Decodable {
            let groups: [Group]?
        }

        let response: Response?
    }

    private static func windows(from reply: Reply) -> [UsageWindow] {
        (reply.response?.groups ?? []).flatMap { group -> [UsageWindow] in
            let scope = modelGroup(group.displayName)

            return (group.buckets ?? [])
                .compactMap { window(from: $0, scope: scope) }
                // Shortest window first within a group, which is the order the
                // other two providers' limits arrive in and the order they are
                // useful in: the one about to bite comes first.
                .sorted { $0.windowSeconds < $1.windowSeconds }
        }
    }

    private static func window(from bucket: Reply.Bucket, scope: String?) -> UsageWindow? {
        guard
            let id = bucket.bucketId,
            let remaining = bucket.remainingFraction,
            let (kind, seconds) = length(of: bucket.window)
        else { return nil }

        // The only provider that reports what is *left* rather than what is
        // gone. Everything downstream is in terms of what is gone.
        let used = min(max(1 - remaining, 0), 1)

        return UsageWindow(
            id: id,
            kind: kind,
            scope: scope,
            usedFraction: used,
            windowSeconds: seconds,
            resetsAt: bucket.resetTime.flatMap(Self.date(from:)),
            isExhausted: remaining <= 0
        )
    }

    /// A bucket whose window can't be read is left out rather than guessed at.
    ///
    /// `5h` and `weekly` are what the server sends today; the numbered forms
    /// are there so a new window length is understood rather than dropped. A
    /// window with no length can't be named or sorted, and inventing one would
    /// put a figure under a heading that isn't true.
    private static func length(of window: String?) -> (UsageWindow.Kind, Int)? {
        guard let window = window?.lowercased() else { return nil }

        switch window {
        case "5h": return (.fiveHour, 5 * 3_600)
        case "weekly": return (.weekly, 7 * 86_400)
        case "daily": return (.other(seconds: 86_400), 86_400)
        case "monthly": return (.other(seconds: 30 * 86_400), 30 * 86_400)
        default: break
        }

        guard let unit = window.last, let count = Int(window.dropLast()), count > 0 else { return nil }

        switch unit {
        case "h": return count == 5 ? (.fiveHour, 5 * 3_600) : (.other(seconds: count * 3_600), count * 3_600)
        case "d":
            let seconds = count * 86_400
            return count == 7 ? (.weekly, seconds) : (.other(seconds: seconds), seconds)
        default: return nil
        }
    }

    /// "Gemini Models" → "Gemini". The group's name is what the limit is
    /// scoped to, and it is shown after the window's own name — "5-hour limit ·
    /// Gemini" — where the trailing "models" is a word the row can't spare.
    private static func modelGroup(_ name: String?) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }

        let words = name.split(separator: " ")
        guard words.count > 1, words.last?.lowercased() == "models" else { return name }
        return words.dropLast().joined(separator: " ")
    }

    /// Built per call rather than kept as a shared instance: `ISO8601DateFormatter`
    /// is not `Sendable`, and this parses at most a handful of stamps a refresh.
    private static func date(from text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

/// Trusts the language server's certificate, and nothing else.
///
/// It signs its own, so the system has no way to vouch for it. The exception is
/// held to the loopback address: a certificate offered by anything other than
/// this Mac talking to itself is refused exactly as it would be anywhere else
/// in the app.
private final class LoopbackTrust: NSObject, URLSessionDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            challenge.protectionSpace.host == "127.0.0.1",
            let trust = challenge.protectionSpace.serverTrust
        else {
            return completionHandler(.performDefaultHandling, nil)
        }

        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
