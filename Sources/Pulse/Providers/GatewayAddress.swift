// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import CryptoKit
import Foundation

/// Where a self-hosted gateway lives, as the reader typed it.
///
/// **A trust boundary, not a convenience.** Every other provider in this
/// directory knows where to go; these are *told*, which means Pulse can be
/// pointed at any host on the internet with a credential attached. Whatever
/// comes back from here gets a bearer token put on it, so the checks below are
/// about where that token may go rather than about whether a string parses.
///
/// Shared rather than copied per provider. Two gateways already ask the same
/// question and differ only in the path they end at, and a second copy of a
/// rule like this is a second copy to forget to tighten.
enum GatewayAddress {
    /// A checked URL for `path` on the gateway the reader named, or nil if the
    /// address may not be used.
    ///
    /// - A scheme is assumed when none is typed, because `gateway.example.com`
    ///   is what people paste. It is assumed **https**, never http.
    /// - Plain http only where there is nothing between Pulse and the server to
    ///   intercept it: loopback, a private network, or `.local`. On a public
    ///   host it is **refused rather than upgraded**, because silently
    ///   rewriting somebody's address is how a credential ends up somewhere
    ///   they never looked.
    /// - No user info and no fragment. Both are ways of writing a URL whose
    ///   host is not the part a reader's eye lands on.
    /// - No query either: the path built here is the whole request, and a query
    ///   pasted out of a dashboard link would be forwarded with the key.
    ///
    /// - Parameters:
    ///   - typed: the address as entered.
    ///   - path: the route to reach, beginning with `/`.
    ///   - trimming: suffixes to drop off whatever the reader typed before the
    ///     route is appended. People paste a gateway's root and people paste
    ///     the base URL out of their client's config, which usually ends in
    ///     `/v1`; appending blindly makes `/v1/v1/…`.
    static func url(from typed: String, path: String, trimming: [String] = []) -> URL? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let text = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var parts = URLComponents(string: text) else { return nil }

        let scheme = (parts.scheme ?? "").lowercased()
        guard scheme == "https" || scheme == "http" else { return nil }
        guard let host = parts.host, !host.isEmpty else { return nil }
        guard parts.user == nil, parts.password == nil else { return nil }
        guard parts.fragment == nil, parts.query == nil else { return nil }
        guard scheme == "https" || allowsPlainHTTP(host) else { return nil }

        parts.path = root(of: parts.path, trimming: trimming) + path
        return parts.url
    }

    /// Which deployment and which key a reading came from, for the cache.
    ///
    /// The deployment is the gateway's root as it will actually be asked, so
    /// `host`, `https://host/` and `https://host/v1` are one server; the key is
    /// named by its SHA-256, never by itself — a different key on the same
    /// server is a different account. Nil without a usable address or a key,
    /// which never matches anything.
    static func scope(of typed: String?, key: String?) -> UsageScope? {
        guard let typed, let key, !key.isEmpty,
              let root = url(from: typed, path: "", trimming: ["/v1"])
        else { return nil }
        let fingerprint = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return UsageScope(route: .endpoint, organization: root.absoluteString.lowercased(), identity: fingerprint)
    }

    /// Whether an address could be used at all, without naming a route.
    ///
    /// What Settings checks on Save, so a reader is told the address is wrong
    /// once rather than per endpoint.
    static func isUsable(_ typed: String) -> Bool {
        url(from: typed, path: "/") != nil
    }

    /// The gateway's root: trailing slashes gone, and any suffix the reader
    /// already typed that the route is about to repeat.
    ///
    /// Longest suffix first, so `/v1/usage` is not left as `/usage` by a rule
    /// meant to strip `/v1`.
    static func root(of typed: String, trimming: [String]) -> String {
        var path = typed
        while path.hasSuffix("/") { path.removeLast() }

        for suffix in trimming.sorted(by: { $0.count > $1.count }) where path.hasSuffix(suffix) {
            path.removeLast(suffix.count)
            while path.hasSuffix("/") { path.removeLast() }
            break
        }
        return path
    }

    /// Whether http is safe for this host because nothing routable sits
    /// between here and it.
    ///
    /// Loopback, the three RFC 1918 ranges, IPv4 link-local, IPv6 loopback,
    /// unique-local and link-local, and the `.local` names Bonjour hands out.
    /// Demanding a certificate on those would rule out the ordinary way people
    /// run a gateway at home.
    static func allowsPlainHTTP(_ host: String) -> Bool {
        let name = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))

        if name == "localhost" || name.hasSuffix(".localhost") { return true }
        if name == "::1" { return true }
        if name.hasSuffix(".local") { return true }
        // Unique-local (fc00::/7) and link-local (fe80::/10). The colon test is
        // what keeps a *name* beginning "fd" out of this.
        if name.contains(":"),
           name.hasPrefix("fc") || name.hasPrefix("fd") || name.hasPrefix("fe80:") {
            return true
        }

        let octets = name.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return false }
        let numbers = octets.compactMap { UInt8($0) }
        guard numbers.count == 4 else { return false }

        switch (numbers[0], numbers[1]) {
        case (127, _), (10, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        default: return false
        }
    }
}
