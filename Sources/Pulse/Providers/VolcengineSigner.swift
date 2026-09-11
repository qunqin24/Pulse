import CryptoKit
import Foundation

/// Volcengine's request signature, which is their spelling of AWS SigV4.
///
/// Only one thing in this file is Pulse's opinion — that it returns headers
/// instead of mutating a request. Everything else is Volcengine's published
/// scheme, and it is here rather than in the service because a signature is
/// either exactly right or a 403 with nothing to read: it has to be testable
/// on its own, against a fixed clock and a fixed key, and it is.
///
/// Two details cost more than they look, both of them recorded by CodexBar
/// (MIT) before this was written:
///
/// - The signed header list is **sorted, lower-cased**, and the canonical
///   request has to list them in that same order. The server re-sorts and
///   recomputes; anything else is a signature mismatch, reported as a 403 that
///   says nothing about why.
/// - The credential scope is `<date>/<region>/ark/request`. `request`, not
///   AWS's `aws4_request`, and `ark` for this service.
enum VolcengineSigner {
    struct Credentials: Sendable, Equatable {
        let accessKeyID: String
        let secretAccessKey: String
        /// Where the account lives. Beijing is where the Ark coding plan is
        /// sold; it is a constant here rather than a setting because a wrong
        /// region fails as a signature mismatch, which is the least helpful
        /// error a settings field could produce.
        var region = "cn-beijing"
    }

    private static let algorithm = "HMAC-SHA256"
    private static let service = "ark"
    private static let terminator = "request"
    private static let signedHeaders = "content-type;host;x-content-sha256;x-date"

    /// The headers a signed request needs, `Authorization` among them.
    static func headers(
        method: String,
        url: URL,
        body: Data,
        contentType: String,
        credentials: Credentials,
        date: Date
    ) -> [String: String] {
        let timestamp = stamp(date, format: "yyyyMMdd'T'HHmmss'Z'")
        let day = stamp(date, format: "yyyyMMdd")
        let payloadHash = hex(SHA256.hash(data: body))
        let host = url.host ?? ""

        let canonicalRequest = [
            method,
            canonicalPath(url),
            canonicalQuery(url),
            "content-type:\(contentType)",
            "host:\(host)",
            "x-content-sha256:\(payloadHash)",
            "x-date:\(timestamp)",
            "",
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        let scope = "\(day)/\(credentials.region)/\(service)/\(terminator)"
        let stringToSign = [
            algorithm,
            timestamp,
            scope,
            hex(SHA256.hash(data: Data(canonicalRequest.utf8)))
        ].joined(separator: "\n")

        // The signing key is derived in four steps, each one keyed by the last.
        // Deriving it per-request rather than caching is deliberate: it is
        // scoped to the day and the region, and a cache of it would be a
        // secret with a lifetime nobody is tracking.
        var key = SymmetricKey(data: Data(credentials.secretAccessKey.utf8))
        for step in [day, credentials.region, service, terminator] {
            key = SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(for: Data(step.utf8), using: key)))
        }
        let signature = hex(HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: key))

        return [
            "Content-Type": contentType,
            "Host": host,
            "X-Date": timestamp,
            "X-Content-Sha256": payloadHash,
            "Authorization": "\(algorithm) Credential=\(credentials.accessKeyID)/\(scope), "
                + "SignedHeaders=\(signedHeaders), Signature=\(signature)"
        ]
    }

    // MARK: - Canonical forms

    private static func canonicalPath(_ url: URL) -> String {
        let path = url.path.isEmpty ? "/" : url.path
        return encode(path, keepingSlashes: true)
    }

    /// Sorted by name, then by value, each half encoded separately — the
    /// server rebuilds this string from its own parse of the query, so the
    /// order in the URL is not the order that is signed.
    private static func canonicalQuery(_ url: URL) -> String {
        guard
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
            !items.isEmpty
        else { return "" }

        let pairs: [(name: String, value: String)] = items.map {
            (encode($0.name), encode($0.value ?? ""))
        }
        let sorted = pairs.sorted { lhs, rhs in
            lhs.name == rhs.name ? lhs.value < rhs.value : lhs.name < rhs.name
        }
        return sorted.map { "\($0.name)=\($0.value)" }.joined(separator: "&")
    }

    /// Percent-encoding by the signature's rules, not the URL's: everything
    /// but the unreserved set, and `~` is **not** escaped. `addingPercentEncoding`
    /// with a stock character set gets both of those wrong.
    private static func encode(_ value: String, keepingSlashes: Bool = false) -> String {
        // **Built from ASCII by hand, not from `CharacterSet.alphanumerics`.**
        // That set is Unicode-wide, so a non-ASCII letter in a query value
        // would be left unescaped here and escaped by the server before it
        // recomputed — an unexplainable 403 the first time anything but
        // `Action` and `Version` is signed.
        var allowed = unreserved
        if keepingSlashes { allowed.insert("/") }
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// `A-Z a-z 0-9 - _ . ~`, and nothing else.
    private static let unreserved: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "A"..."Z")
        set.insert(charactersIn: "a"..."z")
        set.insert(charactersIn: "0"..."9")
        set.insert(charactersIn: "-_.~")
        return set
    }()

    private static func hex<D: Sequence>(_ bytes: D) -> String where D.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Built per call: `DateFormatter` is not `Sendable`, and this runs twice
    /// per request rather than in a loop.
    private static func stamp(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
