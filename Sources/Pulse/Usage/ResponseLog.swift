// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// What the servers said during one account's check, for Settings'
/// connection diagnostics: each request's address, status, type and body.
///
/// **Why.** A reading turns a reply into one of a few reasons, and a reason is
/// a guess about what the reply meant: OpenCode Go's "subscription required"
/// was a 403, and every 403 read as a refused key, so a lapsed plan sent
/// someone to replace a key that worked. The reply itself settles it.
///
/// **What is kept, and what never is.** The method, the address without its
/// query (a key can travel in one), the status, the content type and the
/// first `bodyLimit` characters of the body — **never a request header**, so
/// no key, token or cookie Pulse sends; and in the body, every value under a
/// name that sounds like a credential, and every long unbroken run of the
/// characters tokens are made of, replaced by `mask` (`redacted`). A reply can
/// still name the account — an email, a plan, a balance — which is why it is
/// shown to the person and kept out of the shareable report
/// (`ConnectionDiagnostic.report`).
///
/// **Memory only, the last check only.** One check's replies ride on the
/// raw reading into `ConnectionDiagnostic` and are replaced by the next;
/// nothing is written to disk.
///
/// Requests are recorded by `URLSession.recordedData(for:)`, which the
/// providers use for every request they make while their check runs
/// (`capture`), and the status pages while their pane reads them
/// (`capturing`, to say why a read failed). A request made outside either —
/// a sign-in, the background outage check — records nothing.
enum ResponseLog {
    struct Entry: Equatable, Sendable {
        let at: Date
        let method: String
        /// Scheme, host and path; never the query.
        let address: String
        /// Nil when no reply came back.
        let status: Int?
        let contentType: String?
        /// Redacted and cut to `bodyLimit`; the failure, when there was no reply.
        let body: String
        let byteCount: Int
    }

    static let bodyLimit = 4000
    /// The most requests one check keeps: the last ones, which decided it.
    static let entryLimit = 8
    static let mask = "••••"

    /// One check's entries, appended to from whichever task makes a request.
    final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [Entry] = []

        func append(_ entry: Entry) {
            lock.withLock {
                stored.append(entry)
                if stored.count > ResponseLog.entryLimit { stored.removeFirst(stored.count - ResponseLog.entryLimit) }
            }
        }

        var entries: [Entry] { lock.withLock { stored } }
    }

    @TaskLocal static var collector: Collector?

    /// Runs one account's check with its requests recorded, and returns them
    /// with its reading.
    static func capture(_ check: @Sendable () async -> ProviderUsage) async -> ProviderUsage {
        var (reading, entries) = await capturing(check)
        reading.responses = entries
        return reading
    }

    /// Runs `work` with its requests recorded, and returns them with its
    /// result — a status page's read, for saying why it failed.
    static func capturing<Value: Sendable>(_ work: @Sendable () async -> Value) async -> (Value, [Entry]) {
        let collector = Collector()
        let value = await $collector.withValue(collector) { await work() }
        return (value, collector.entries)
    }

    /// Why a read came back with nothing, in one line: the last request that
    /// got no 200 — its status, or its failure — or, when every request was
    /// answered, that the answer was not one Pulse could use.
    static func failure(of entries: [Entry]) -> String {
        guard let failed = entries.last(where: { $0.status != 200 }) else {
            return entries.isEmpty
                ? String.localized("No request was made.")
                : String.localized("The page answered, but not with anything Pulse reads for this provider.")
        }
        guard let status = failed.status else { return failed.body }
        return String.localized("The page answered HTTP \(String(status)).")
    }

    static func record(_ request: URLRequest, response: URLResponse?, data: Data?, error: (any Error)?, at date: Date = Date()) {
        guard let collector else { return }
        collector.append(entry(request, response: response, data: data, error: error, at: date))
    }

    static func entry(_ request: URLRequest, response: URLResponse?, data: Data?, error: (any Error)?, at date: Date) -> Entry {
        let http = response as? HTTPURLResponse
        var body: String
        if let error {
            let failure = error as NSError
            body = "\(failure.domain) \(failure.code): \(failure.localizedDescription)"
        } else {
            body = text(of: data ?? Data(), contentType: http?.value(forHTTPHeaderField: "Content-Type"))
        }
        // A redirect's whole meaning is where it points: a sign-in host, or
        // the same site. **The site only**, never the path: the body's
        // redaction has already run, and a path can carry a token it would
        // have caught (a review found one copied out through Copy replies).
        if let http, (300..<400).contains(http.statusCode),
           let location = http.value(forHTTPHeaderField: "Location"),
           let target = URL(string: location, relativeTo: response?.url ?? request.url)?.absoluteURL,
           let scheme = target.scheme, let host = target.host() {
            body = "Location: \(scheme)://\(host)" + (body.isEmpty ? "" : "\n\(body)")
        }
        // Whatever this request carried, wherever the reply echoes it back.
        body = masking(credentials(in: request), in: body)
        return Entry(
            at: date,
            method: request.httpMethod ?? "GET",
            address: address(of: response?.url ?? request.url),
            status: http?.statusCode,
            contentType: http?.value(forHTTPHeaderField: "Content-Type"),
            body: body,
            byteCount: data?.count ?? 0
        )
    }

    static func address(of url: URL?) -> String {
        guard let url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "" }
        parts.query = nil
        parts.fragment = nil
        parts.user = nil
        parts.password = nil
        return parts.string ?? ""
    }

    /// The credentials a request carries — the Authorization value and the
    /// token after its scheme, API-key headers, each cookie's value, every
    /// query value — for masking wherever a reply repeats them. Used while
    /// one entry is built and never kept.
    static func credentials(in request: URLRequest) -> [String] {
        var found: [String] = []
        let headers = request.allHTTPHeaderFields ?? [:]
        for (name, value) in headers {
            switch name.lowercased() {
            case "authorization", "proxy-authorization":
                found.append(value)
                if let space = value.firstIndex(of: " ") {
                    found.append(String(value[value.index(after: space)...]).trimmingCharacters(in: .whitespaces))
                }
            case "cookie":
                for pair in value.split(separator: ";") {
                    if let equals = pair.firstIndex(of: "=") {
                        found.append(String(pair[pair.index(after: equals)...]).trimmingCharacters(in: .whitespaces))
                    }
                }
            // `jwt` for JetBrains AI's `Grazie-Authenticate-JWT`.
            case let header where header.contains("key") || header.contains("token") || header.contains("secret")
                || header.contains("jwt"):
                found.append(value)
            default:
                break
            }
        }
        if let url = request.url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            found += items.compactMap(\.value)
        }
        // Short values ("1", "true") would mask ordinary words.
        return Array(Set(found.filter { $0.count >= 8 })).sorted { $0.count > $1.count }
    }

    static func masking(_ values: [String], in text: String) -> String {
        values.reduce(text) { $0.replacingOccurrences(of: $1, with: mask) }
    }

    /// The body as text, redacted and cut. JSON comes back laid out with its
    /// keys sorted; anything else as it came.
    static func text(of data: Data, contentType: String?) -> String {
        guard !data.isEmpty else { return "" }
        if let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let laidOut = try? JSONSerialization.data(
               withJSONObject: redacted(object), options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
           ) {
            return cut(String(decoding: laidOut, as: UTF8.self))
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return String.localized("\(String(data.count)) bytes, not text")
        }
        return cut(redacted(text))
    }

    /// A name that sounds like a credential: its value is never kept.
    static func isSecretName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return ["token", "secret", "password", "passwd", "cookie", "session", "credential", "signature",
                "authorization", "apikey", "api_key", "api-key", "private", "jwt", "bearer", "otp"]
            .contains { lowered.contains($0) }
            || lowered == "key" || lowered.hasSuffix("_key") || lowered.hasSuffix("key") && lowered.count <= 12
    }

    /// Masks the values under credential names — and everything inside them:
    /// `"tokens": ["…"]` and `"session": {"id": "…"}` hide what they hold.
    /// Text only, at any depth: `"input_tokens": 1200` is a count, not a
    /// credential.
    static func redacted(_ object: Any, underSecret: Bool = false) -> Any {
        if let dictionary = object as? [String: Any] {
            var result: [String: Any] = [:]
            for (name, value) in dictionary {
                result[name] = redacted(value, underSecret: underSecret || isSecretName(name))
            }
            return result
        }
        if let array = object as? [Any] { return array.map { redacted($0, underSecret: underSecret) } }
        if let text = object as? String { return underSecret ? mask : redacted(text) }
        return object
    }

    /// A run of the characters keys and tokens are made of — letters,
    /// digits, `-_.~+/=` — that looks like one:
    /// - 40 or more with a digit in it;
    /// - 24 or more mixing capitals, small letters and digits;
    /// - 16 or more starting the way keys do (`sk-`, `ghp_`, `AIza`, a JWT's
    ///   `eyJ`, `xai-`…);
    /// - or holding one piece, between separators, of 16 or more letters and
    ///   digits mixed — `sk-` and 32 hex digits, a hex session id.
    ///
    /// A long model name ("claude-opus-4-6-20260101") or a UUID survives:
    /// its pieces are short. Pulse's own guess at a format is the second line
    /// of defence; the first is `credentials(in:)`, the values the request
    /// really carried.
    static func redacted(_ text: String) -> String {
        guard let pattern = try? Regex(#"[A-Za-z0-9\-_.~+/=]{16,}"#) else { return text }
        return text.replacing(pattern) { match in
            let run = String(text[match.range])
            return looksLikeCredential(run) ? mask : run
        }
    }

    static let credentialPrefixes = [
        "sk-", "sk_", "pk_", "rk_", "oc_sk", "xai-", "gsk_", "ghp_", "gho_", "ghu_", "ghs_", "ghr_",
        "github_pat_", "glpat-", "hf_", "AIza", "eyJ", "xoxb-", "xoxp-", "xoxa-", "xoxs-", "ya29.",
    ]

    static func looksLikeCredential(_ run: String) -> Bool {
        let digits = run.contains(where: \.isNumber)
        if run.count >= 40, digits { return true }
        if run.count >= 24, digits, run.contains(where: \.isUppercase), run.contains(where: \.isLowercase) { return true }
        if credentialPrefixes.contains(where: { run.hasPrefix($0) }) { return true }
        return run.split(whereSeparator: { "-_.~+/=".contains($0) }).contains { piece in
            piece.count >= 16 && piece.contains(where: \.isNumber) && piece.contains(where: \.isLetter)
        }
    }

    private static func cut(_ text: String) -> String {
        guard text.count > bodyLimit else { return text }
        return String(text.prefix(bodyLimit)) + "\n…"
    }
}

extension URLSession {
    /// `data(for:delegate:)`, with the reply kept for the connection
    /// diagnostics while an account's check is running (`ResponseLog`).
    func recordedData(
        for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil
    ) async throws -> (Data, URLResponse) {
        do {
            let (data, response) = try await data(for: request, delegate: delegate)
            ResponseLog.record(request, response: response, data: data, error: nil)
            return (data, response)
        } catch {
            ResponseLog.record(request, response: nil, data: nil, error: error)
            throw error
        }
    }
}
