// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Replicate: the prepaid credit left on the account, read with the signed-in
/// replicate.com session.
///
/// Replicate's API token runs models; the billing figures are only on the
/// website, behind its session. So the credential is a browser session,
/// imported on request and kept to `sessionid` (the one that has to be there)
/// and `csrftoken`.
///
/// Two requests, both to replicate.com:
///
/// 1. `GET /account/billing` as a page. Its server-rendered React props name
///    the account the page is for — a user or an organization — and that is
///    the only way to know whose credit to ask for.
/// 2. `GET /api/{users|organizations}/{name}/unused-credit`, the page's own
///    call for the balance.
///
/// The shapes are second-hand — taken from CodexBar's Replicate plugin and
/// its tests, not from captured replies — and the fixtures in the tests say so.
///
/// **What is left out, and why.** The month's spend (from the invoices the
/// page lists) has no limit to measure it against and nowhere to go yet, so it
/// is not asked for. Replicate reports no allowance and no percentage, and
/// none is drawn: the balance is the reading.
extension ProviderProfile {
    static let replicate = ProviderProfile(
        displayName: "Replicate",
        billing: .api,
        iconResource: "replicate",
        credential: .sessionCookie(host: "replicate.com", cookies: ["sessionid", "csrftoken"]),
        accessDescription: { .localized("Uses a browser session you import in Settings. Importing may ask for browser Keychain access.") },
        reportsSpendableBalance: true,
        spendingIsWatchedLocally: false,
        setupSlug: "replicate",
        fetch: { await ReplicateUsageService.fetch($0) }
    )
}

enum ReplicateUsageService {
    static let billingPage = URL(string: "https://replicate.com/account/billing")!

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let cookie = context.trimmedCredential else { return context.unavailable(.sessionMissing) }

        let page: Data
        switch await ProfileHTTP.data(for: request(billingPage, cookie: cookie, accept: "text/html"),
                                      refused: .sessionExpired, session: session) {
        case .failure(let reason): return context.unavailable(reason)
        case .success(let data): page = data
        }

        let owner: Account
        switch account(inBillingPage: String(decoding: page, as: UTF8.self)) {
        case .signedOut: return context.unavailable(.sessionExpired)
        case .unrecognized: return context.unavailable(.unreadableReply)
        case .found(let found): owner = found
        }

        switch await ProfileHTTP.data(for: request(owner.creditURL, cookie: cookie, accept: "application/json"),
                                      refused: .sessionExpired, session: session) {
        case .failure(let reason): return context.unavailable(reason)
        case .success(let data): return reading(from: data, context: context)
        }
    }

    private static func request(_ url: URL, cookie: String, accept: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        return request
    }

    // MARK: - Whose billing page this is

    struct Account: Equatable {
        let isOrganization: Bool
        let username: String

        var creditURL: URL {
            var allowed = CharacterSet.urlPathAllowed
            allowed.remove("/")
            let name = username.addingPercentEncoding(withAllowedCharacters: allowed) ?? username
            let kind = isOrganization ? "organizations" : "users"
            return URL(string: "https://replicate.com/api/\(kind)/\(name)/unused-credit")!
        }
    }

    enum PageAccount: Equatable {
        case found(Account)
        /// Replicate's public sign-in page, which a lapsed session is sent to.
        case signedOut
        case unrecognized
    }

    /// The account named in the page's `react-component-props` JSON, found
    /// wherever it is nested. Bounded, because the page is not ours.
    static func account(inBillingPage html: String) -> PageAccount {
        let scripts = try! NSRegularExpression(
            pattern: #"<script\b([^>]*)>([\s\S]*?)</script\s*>"#, options: [.caseInsensitive]
        )
        let isProps = try! NSRegularExpression(
            pattern: #"\bid\s*=\s*(["'])react-component-props[^"']*\1"#, options: [.caseInsensitive]
        )
        let isJSON = try! NSRegularExpression(
            pattern: #"\btype\s*=\s*(["'])application/json\1"#, options: [.caseInsensitive]
        )
        let text = html as NSString
        var visited = 0
        for match in scripts.matches(in: html, range: NSRange(location: 0, length: text.length)) {
            let attributes = text.substring(with: match.range(at: 1))
            let whole = NSRange(location: 0, length: (attributes as NSString).length)
            guard isProps.firstMatch(in: attributes, range: whole) != nil,
                  isJSON.firstMatch(in: attributes, range: whole) != nil,
                  let payload = try? JSONSerialization.jsonObject(with: Data(text.substring(with: match.range(at: 2)).utf8))
            else { continue }

            var queue: [Any] = [payload]
            var index = 0
            while index < queue.count, visited < 4_000 {
                let item = queue[index]
                index += 1
                visited += 1
                if let object = item as? [String: Any],
                   let candidate = object["account"] as? [String: Any],
                   let kind = candidate["kind"] as? String, kind == "user" || kind == "organization",
                   let name = (candidate["username"] as? String)?.trimmingCharacters(in: .whitespaces),
                   !name.isEmpty {
                    return .found(Account(isOrganization: kind == "organization", username: name))
                }
                let children: [Any] = (item as? [Any]) ?? ((item as? [String: Any]).map { Array($0.values) } ?? [])
                queue.append(contentsOf: children.filter { $0 is [Any] || $0 is [String: Any] })
            }
        }

        // Both markers of Replicate's own sign-in page, not just the word.
        let signIn = html.range(of: #"<title>\s*Sign in\s*\|\s*Replicate\s*</title>"#,
                                options: [.regularExpression, .caseInsensitive]) != nil
        let github = html.range(of: #"<a\b[^>]*\bhref=["']/login/github/(\?[^"']*)?["']"#,
                                options: [.regularExpression, .caseInsensitive]) != nil
        return signIn && github ? .signedOut : .unrecognized
    }

    // MARK: - Reading the balance

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return context.unavailable(.unreadableReply) }

        let credit: Double
        switch root["unused_credit"] {
        case nil, is NSNull:
            return context.unavailable(.noLimitsReported)
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard trimmed.range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil,
                  let value = Double(trimmed), value.isFinite
            else { return context.unavailable(.unreadableReply) }
            credit = value
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID():
            guard number.doubleValue.isFinite, number.doubleValue >= 0 else { return context.unavailable(.unreadableReply) }
            credit = number.doubleValue
        default:
            return context.unavailable(.unreadableReply)
        }

        return context.reading(
            [],
            creditBalance: money(credit),
            creditRemaining: ProviderUsage.CreditAmount(amount: credit, currency: "USD"),
            at: now
        )
    }

    /// Replicate bills in dollars; the reply carries the figure only.
    static func money(_ amount: Double) -> String {
        amount.formatted(
            .currency(code: "USD")
                .precision(.fractionLength(2))
                .locale(LocalizationSource.locale)
        )
    }
}
