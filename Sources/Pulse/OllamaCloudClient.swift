import Foundation

/// A read-only adapter for Ollama's signed-in settings page, not a public API.
/// Kept independent of the app so parsing and credential boundaries are testable.
enum OllamaCloudError: Error, Equatable {
    case missingCookie, invalidCookie, signedOut, rateLimited, serverError, invalidPage
}

struct OllamaCloudSnapshot: Equatable, Sendable {
    struct Window: Equatable, Sendable {
        let usedFraction: Double
        let resetsAt: Date?
    }
    let session: Window
    let weekly: Window
}

enum OllamaSessionCookie {
    /// Retain only authentication cookies; analytics and unrelated cookies are
    /// neither saved nor forwarded. Do not accept bare API keys or header injection.
    static func normalize(_ input: String) throws -> String {
        guard !input.unicodeScalars.contains(where: { $0.value < 32 || $0.value > 126 }) else {
            throw OllamaCloudError.invalidCookie
        }
        var header = input.trimmingCharacters(in: .whitespaces)
        if header.lowercased().hasPrefix("cookie:") {
            header = String(header.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        guard !header.isEmpty else { throw OllamaCloudError.missingCookie }
        guard header.utf8.count <= 32_768 else { throw OllamaCloudError.invalidCookie }
        let names = ["wos-session", "__Secure-session", "__Secure-next-auth.session-token", "next-auth.session-token"]
        var found: [String] = []
        var seen = Set<String>()
        for pair in header.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { throw OllamaCloudError.invalidCookie }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            let recognized = names.contains { base in
                name == base || (name.hasPrefix(base + ".")
                    && !name.dropFirst(base.count + 1).isEmpty
                    && name.dropFirst(base.count + 1).allSatisfy(\.isNumber))
            }
            guard recognized else { continue }
            guard !value.isEmpty, !value.contains("\""), !value.contains("\\"),
                  !value.contains(" ") else {
                throw OllamaCloudError.invalidCookie
            }
            // A repeated name is not a malformed cookie. Every browser store
            // routinely holds both a host-only and a domain row for the same
            // session name, and the host match returns both on purpose — so
            // throwing here threw away the whole browser (the call site takes
            // this through `try?`) and moved on to the next one without a
            // word, which is exactly the "a wrong lookup reads as an empty
            // one" failure this feature is prone to. The first wins, as it
            // does in any cookie header.
            guard seen.insert(name).inserted else { continue }
            found.append("\(name)=\(value)")
        }
        guard !found.isEmpty else { throw OllamaCloudError.invalidCookie }
        return found.joined(separator: "; ")
    }
}

enum OllamaCloudPage {
    static let maximumBytes = 2 * 1024 * 1024

    static func parse(_ data: Data) throws -> OllamaCloudSnapshot {
        guard data.count <= maximumBytes,
              let html = String(data: data, encoding: .utf8),
              !html.localizedCaseInsensitiveContains("<!ENTITY") else {
            throw OllamaCloudError.invalidPage
        }
        let document: XMLDocument
        do {
            document = try XMLDocument(data: data, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever])
        } catch { throw OllamaCloudError.invalidPage }
        // Remove non-visible text so embedded scripts cannot masquerade as usage.
        for node in (try? document.nodes(forXPath: "//script | //style | //template")) ?? [] { node.detach() }
        if let forms = try? document.nodes(forXPath: "//form"), forms.contains(where: { node in
            guard let form = node as? XMLElement else { return false }
            let action = form.attribute(forName: "action")?.stringValue?.lowercased() ?? ""
            return action.contains("signin") || action.contains("login")
        }) { throw OllamaCloudError.signedOut }

        // Require both windows. A changed or partially rendered page must never
        // turn the missing window into zero usage or silently omit a higher limit.
        return try OllamaCloudSnapshot(
            session: window("Session usage", in: document),
            weekly: window("Weekly usage", in: document)
        )
    }

    private static func window(_ label: String, in document: XMLDocument) throws -> OllamaCloudSnapshot.Window {
        let labels = (try? document.nodes(forXPath: "//*[normalize-space(text())='\(label)']")) ?? []
        guard labels.count == 1, let labelNode = labels.first else { throw OllamaCloudError.invalidPage }
        var result: OllamaCloudSnapshot.Window?
        var candidate = labelNode.parent
        while let container = candidate as? XMLElement {
            // Stop before crossing into the other window or an unrelated page area.
            let other = label == "Session usage" ? "Weekly usage" : "Session usage"
            if !((try? container.nodes(forXPath: ".//*[normalize-space(text())='\(other)']")) ?? []).isEmpty { break }
            if let percent = try percentage(in: container) {
                let times = ((try? container.nodes(forXPath: ".//*[@data-time]")) ?? [])
                    .compactMap { ($0 as? XMLElement)?.attribute(forName: "data-time")?.stringValue }
                guard times.count <= 1 else { throw OllamaCloudError.invalidPage }
                let reset: Date?
                if let time = times.first {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let fractional = formatter.date(from: time)
                    formatter.formatOptions = [.withInternetDateTime]
                    guard let date = fractional ?? formatter.date(from: time) else { throw OllamaCloudError.invalidPage }
                    reset = date
                } else { reset = nil }
                result = .init(usedFraction: percent / 100, resetsAt: reset)
                if container.attribute(forName: "data-usage-meter") != nil { break }
            }
            candidate = container.parent
        }
        guard let result else { throw OllamaCloudError.invalidPage }
        return result
    }

    private static func percentage(in element: XMLElement) throws -> Double? {
        // Read the provider's explicit total, not a model segment's CSS width.
        // Each text node is tested separately to avoid concatenating unrelated numbers.
        let texts = ((try? element.nodes(forXPath: ".//text()")) ?? []).compactMap(\.stringValue)
        let expression = try NSRegularExpression(pattern: #"^\s*([0-9]+(?:\.[0-9]+)?)\s*%\s*used\s*$"#, options: .caseInsensitive)
        var values: [Double] = []
        for text in texts {
            if let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text), let number = Double(text[range]) {
                guard number.isFinite, (0...100).contains(number) else { throw OllamaCloudError.invalidPage }
                values.append(number)
            }
        }
        guard values.count <= 1 else { throw OllamaCloudError.invalidPage }
        return values.first
    }
}

struct OllamaCloudClient: Sendable {
    static let settingsURL = URL(string: "https://ollama.com/settings")!

    static func request(cookie: String) throws -> URLRequest {
        var request = URLRequest(url: settingsURL)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(try OllamaSessionCookie.normalize(cookie), forHTTPHeaderField: "Cookie")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        return request
    }

    static func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200:
            guard response.url?.scheme == "https", response.url?.host == "ollama.com",
                  response.url?.path == "/settings", response.mimeType == "text/html" else {
                throw OllamaCloudError.invalidPage
            }
        case 300..<400, 401, 403: throw OllamaCloudError.signedOut
        case 429: throw OllamaCloudError.rateLimited
        default: throw OllamaCloudError.serverError
        }
    }

    func fetch(cookie: String) async throws -> OllamaCloudSnapshot {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: Self.request(cookie: cookie))
        guard let http = response as? HTTPURLResponse else { throw OllamaCloudError.invalidPage }
        try Self.validate(http)
        var data = Data()
        for try await byte in bytes {
            guard data.count < OllamaCloudPage.maximumBytes else { throw OllamaCloudError.invalidPage }
            data.append(byte)
        }
        return try OllamaCloudPage.parse(data)
    }
}

/// Never forward a session cookie to a redirect target, including login hosts.
///
/// `URLSession` strips `Authorization` across hosts by itself; a `Cookie`
/// header set by hand it forwards, which is how a redirect off the provider's
/// own domain would carry the user's session with it.
final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
