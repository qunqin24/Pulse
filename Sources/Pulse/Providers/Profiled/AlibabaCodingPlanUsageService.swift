// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Alibaba Cloud's Coding Plan (Model Studio / Bailian): a five-hour, a weekly
/// and a billing-month allowance, each reported as an amount used out of an
/// amount the plan grants.
///
/// Read with the plan's API key, sent to the console route the Model Studio
/// page itself asks: `POST /data/api.json?action=…queryCodingPlanInstanceInfoV2`
/// on the international console first and, when that one does not know the
/// key or the plan, on the China mainland console. Nothing is chosen in
/// Settings: the key belongs to one site, and whichever site answers for it is
/// the one read. The shape is second-hand — taken from CodexBar's Alibaba
/// provider and its tests, not from a captured reply.
///
/// **Only figures the console states.** A window needs both its used amount
/// and its total; a missing or non-positive total leaves that window off
/// rather than drawn at zero. A reset time already in the past is dropped
/// rather than moved forward by five hours, which would be a guess.
///
/// Some accounts get `ConsoleNeedLogin` for a key: the route wants a console
/// session instead. That is said as a refused key, the nearest shared reason,
/// and is not retried on the other site, which would refuse it the same way.
extension ProviderProfile {
    static let alibabaCodingPlan = ProviderProfile(
        displayName: "Alibaba Coding Plan",
        iconResource: "alibabacloud",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the API key you enter in Settings. No Keychain prompt.") },
        keySubtitle: { .localized("From the Coding Plan page in Model Studio. Stored encrypted on this Mac.") },
        brandColor: 0xFF6A00,
        setupSlug: "alibaba-coding-plan",
        fetch: { await AlibabaCodingPlanUsageService.fetch($0) }
    )
}

enum AlibabaCodingPlanUsageService {
    /// One of the two consoles the plan is sold on. The key is sent to the
    /// console's own host and nowhere else.
    struct Site: Sendable, Equatable {
        let origin: String
        let regionID: String
        let commodityCode: String
        let page: String

        static let international = Site(
            origin: "https://modelstudio.console.alibabacloud.com",
            regionID: "ap-southeast-1",
            commodityCode: "sfm_codingplan_public_intl",
            page: "https://modelstudio.console.alibabacloud.com/ap-southeast-1/?tab=coding-plan#/efm/coding_plan"
        )
        static let chinaMainland = Site(
            origin: "https://bailian.console.aliyun.com",
            regionID: "cn-beijing",
            commodityCode: "sfm_codingplan_public_cn",
            page: "https://bailian.console.aliyun.com/cn-beijing/?tab=model#/efm/coding_plan"
        )

        var endpoint: URL {
            var components = URLComponents(string: origin)!
            components.path = "/data/api.json"
            components.queryItems = [
                URLQueryItem(name: "action", value: "zeldaEasy.broadscope-bailian.codingPlan.queryCodingPlanInstanceInfoV2"),
                URLQueryItem(name: "product", value: "broadscope-bailian"),
                URLQueryItem(name: "api", value: "queryCodingPlanInstanceInfoV2"),
                URLQueryItem(name: "currentRegionId", value: regionID),
            ]
            return components.url!
        }
    }

    /// What one site's answer means: a reading, a reason worth asking the
    /// other site about, or a reason that ends it.
    enum Answer: Equatable {
        case usage(ProviderUsage)
        case askOtherSite(ProviderUsage.Unavailability)
        case final(ProviderUsage.Unavailability)
    }

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let key = context.trimmedCredential else { return context.unavailable(.apiKeyMissing) }

        let first = await ask(.international, key: key, context: context, session: session)
        let firstReason: ProviderUsage.Unavailability
        switch first {
        case .usage(let usage): return usage
        case .final(let reason): return context.unavailable(reason)
        case .askOtherSite(let reason): firstReason = reason
        }

        switch await ask(.chinaMainland, key: key, context: context, session: session) {
        case .usage(let usage):
            return usage
        // A site that refused the key says less than one that took it and
        // found nothing, so the refusal is only reported when both refused.
        case .final(let reason), .askOtherSite(let reason):
            return context.unavailable(reason == .apiKeyRefused ? firstReason : reason)
        }
    }

    static func request(_ site: Site, key: String) -> URLRequest {
        var request = URLRequest(url: site.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        let body = ["queryCodingPlanInstanceInfoRequest": ["commodityCode": site.commodityCode]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // The three places the console looks for a key, as the page's own
        // request carries it.
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(key, forHTTPHeaderField: "X-DashScope-API-Key")
        request.setValue(site.origin, forHTTPHeaderField: "Origin")
        request.setValue(site.page, forHTTPHeaderField: "Referer")
        return request
    }

    private static func ask(
        _ site: Site, key: String, context: ProfileContext, session: URLSession?
    ) async -> Answer {
        switch await ProfileHTTP.reply(for: request(site, key: key), session: session) {
        case .failure(let reason):
            return .final(reason)
        case .success(let reply):
            // Not this site's key, or not this site's route: the other one
            // may know it.
            if [401, 403, 404].contains(reply.status) {
                return .askOtherSite(reply.status == 404 ? .serverError : .apiKeyRefused)
            }
            switch ProfileHTTP.classify(reply) {
            case .failure(let reason): return .final(reason)
            case .success(let data): return answer(from: data, context: context)
            }
        }
    }

    // MARK: - Reading the reply

    /// The reading, for anything that only wants the result.
    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        switch answer(from: data, context: context, now: now) {
        case .usage(let usage): usage
        case .askOtherSite(let reason), .final(let reason): context.unavailable(reason)
        }
    }

    /// The three allowances the console names, each with the keys it has
    /// used for them. A billing month is not a stated length, so its thirty
    /// days are a sort key only.
    private static let allowances: [(id: String, kind: UsageWindow.Kind, seconds: Int, reportsLength: Bool,
                                      used: [String], total: [String], reset: [String])] = [
        ("fiveHour", .fiveHour, 5 * 3_600, true,
         ["per5HourUsedQuota", "perFiveHourUsedQuota"], ["per5HourTotalQuota", "perFiveHourTotalQuota"],
         ["per5HourQuotaNextRefreshTime", "perFiveHourQuotaNextRefreshTime"]),
        ("weekly", .weekly, 7 * 86_400, true,
         ["perWeekUsedQuota"], ["perWeekTotalQuota"], ["perWeekQuotaNextRefreshTime"]),
        ("monthly", .monthly, 30 * 86_400, false,
         ["perBillMonthUsedQuota", "perMonthUsedQuota"], ["perBillMonthTotalQuota", "perMonthTotalQuota"],
         ["perBillMonthQuotaNextRefreshTime", "perMonthQuotaNextRefreshTime"]),
    ]

    private static let quotaKeys: Set<String> = [
        "per5HourUsedQuota", "per5HourTotalQuota", "perWeekUsedQuota",
        "perWeekTotalQuota", "perBillMonthUsedQuota", "perBillMonthTotalQuota",
    ]

    static func answer(from data: Data, context: ProfileContext, now: Date = Date()) -> Answer {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let tree = AlibabaConsoleJSON.expanded(object) as? [String: Any]
        else { return .final(.unreadableReply) }

        if let refusal = refusal(in: tree) { return refusal }

        let instances = (AlibabaConsoleJSON.first(["codingPlanInstanceInfos", "coding_plan_instance_infos"], in: tree)
            as? [Any])?.compactMap { $0 as? [String: Any] }
        let chosen = instances.flatMap { activeInstance($0, now: now) }
        let chosenIsActive = chosen.map { activity(of: $0, now: now) > 0 } ?? false

        // Several plans on one account: the active one's figures, and never
        // an expired one's standing in for them.
        let quota: [String: Any]? = if let chosen, let own = quotaInfo(in: chosen) {
            own
        } else if (instances?.count ?? 0) > 1, chosenIsActive {
            nil
        } else {
            quotaInfo(in: tree)
        }

        let windows = quota.map { Self.windows(from: $0, now: now) } ?? []
        guard !windows.isEmpty else {
            // A list of plans that is empty, or holds only lapsed ones, is the
            // console saying there is no plan — not that its figures are missing.
            if let instances, instances.allSatisfy({ Self.activity(of: $0, now: now) < 0 }) {
                return .askOtherSite(.noPlan)
            }
            return .askOtherSite(.noLimitsReported)
        }

        let plan = chosen.flatMap(instancePlanName) ?? planName(in: tree)
        return .usage(context.reading(windows, plan: plan, at: now))
    }

    /// A failure the console reports inside a 200.
    private static func refusal(in tree: [String: Any]) -> Answer? {
        let message = AlibabaConsoleJSON.firstString(["statusMessage", "status_msg", "message", "msg"], in: tree)?
            .lowercased() ?? ""

        if let status = AlibabaConsoleJSON.firstInt(["statusCode", "status_code", "code"], in: tree),
           status != 0, status != 200 {
            if status == 401 || status == 403 || message.contains("api key") || message.contains("unauthorized") {
                return .askOtherSite(.apiKeyRefused)
            }
            return .final(.serverError)
        }

        // `ConsoleNeedLogin`: this route wants a signed-in console, not a key.
        let code = AlibabaConsoleJSON.firstString(["code", "status", "statusCode"], in: tree)?.lowercased() ?? ""
        if code.contains("login") || message.contains("login") || message.contains("log in") {
            return .final(.apiKeyRefused)
        }
        return nil
    }

    private static func windows(from quota: [String: Any], now: Date) -> [UsageWindow] {
        allowances.compactMap { allowance -> UsageWindow? in
            guard let used = AlibabaConsoleJSON.number(firstValue(allowance.used, in: quota)),
                  let total = AlibabaConsoleJSON.number(firstValue(allowance.total, in: quota)),
                  used >= 0, total > 0
            else { return nil }
            let reset = AlibabaConsoleJSON.date(firstValue(allowance.reset, in: quota)).flatMap { $0 > now ? $0 : nil }
            return UsageWindow(
                id: "alibabaCodingPlan.\(allowance.id)",
                kind: allowance.kind,
                scope: nil,
                usedFraction: used / total,
                windowSeconds: allowance.seconds,
                resetsAt: reset,
                reportsLength: allowance.reportsLength,
                isExhausted: used >= total
            )
        }
    }

    private static func firstValue(_ keys: [String], in object: [String: Any]) -> Any? {
        keys.lazy.compactMap { object[$0] }.first
    }

    private static func quotaInfo(in value: Any) -> [String: Any]? {
        if let named = AlibabaConsoleJSON.first(["codingPlanQuotaInfo", "coding_plan_quota_info"], in: value,
                                         intoArrays: false) as? [String: Any] {
            return named
        }
        return AlibabaConsoleJSON.firstObject(in: value) { !quotaKeys.isDisjoint(with: $0.keys) }
    }

    /// The instance that is running, or the first when none says either way.
    private static func activeInstance(_ instances: [[String: Any]], now: Date) -> [String: Any]? {
        guard let best = instances.max(by: { activity(of: $0, now: now) < activity(of: $1, now: now) }),
              activity(of: best, now: now) > 0
        else { return instances.first }
        return best
    }

    /// How sure the instance is about being active: stated outright, implied
    /// by an end date still ahead, or said to have lapsed.
    private static func activity(of instance: [String: Any], now: Date) -> Int {
        if let status = AlibabaConsoleJSON.string(instance["status"] ?? instance["instanceStatus"])?.uppercased() {
            if ["VALID", "ACTIVE"].contains(status) { return 3 }
            if ["EXPIRED", "INVALID", "INACTIVE", "DISABLED", "TERMINATED", "STOPPED"].contains(status) { return -1 }
        }
        if let active = (instance["isActive"] ?? instance["active"]) as? Bool { return active ? 3 : -1 }
        let end = ["endTime", "periodEndTime", "expireTime", "expirationTime"]
            .lazy.compactMap { AlibabaConsoleJSON.date(instance[$0]) }.first
        return (end.map { $0 > now } ?? false) ? 1 : 0
    }

    private static func instancePlanName(_ instance: [String: Any]) -> String? {
        ["planName", "plan_name", "instanceName", "instance_name", "packageName", "package_name"]
            .lazy.compactMap { AlibabaConsoleJSON.string(instance[$0]) }.first
    }

    private static func planName(in tree: [String: Any]) -> String? {
        AlibabaConsoleJSON.firstString(["planName", "plan_name", "packageName", "package_name"], in: tree)
    }
}

/// Alibaba's console replies nest, and sometimes carry the real reply as a
/// JSON string inside a field. Unwrapped here so a reading sees one tree.
///
/// Shared with Alibaba Token Plan and Qwen Cloud, which answer through the
/// same console gateway in the same envelopes.
enum AlibabaConsoleJSON {
    static func expanded(_ value: Any) -> Any {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
                  let inner = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))
            else { return value }
            return expanded(inner)
        }
        if let object = value as? [String: Any] { return object.mapValues(expanded) }
        if let array = value as? [Any] { return array.map(expanded) }
        return value
    }

    /// The first object, the outer one before what it holds, that `matches`.
    static func firstObject(in value: Any, intoArrays: Bool = true,
                            where matches: ([String: Any]) -> Bool) -> [String: Any]? {
        if let object = value as? [String: Any] {
            if matches(object) { return object }
            for nested in object.values {
                if let found = firstObject(in: nested, intoArrays: intoArrays, where: matches) { return found }
            }
        } else if intoArrays, let array = value as? [Any] {
            for nested in array {
                if let found = firstObject(in: nested, intoArrays: intoArrays, where: matches) { return found }
            }
        }
        return nil
    }

    static func first(_ keys: [String], in value: Any, intoArrays: Bool = true) -> Any? {
        var result: Any?
        _ = firstObject(in: value, intoArrays: intoArrays) { object in
            result = keys.lazy.compactMap { object[$0] }.first
            return result != nil
        }
        return result
    }

    static func firstInt(_ keys: [String], in value: Any) -> Int? {
        var result: Int?
        _ = firstObject(in: value) { object in
            result = keys.lazy.compactMap { number(object[$0]).flatMap { Int(exactly: $0) } }.first
            return result != nil
        }
        return result
    }

    static func firstString(_ keys: [String], in value: Any) -> String? {
        var result: String?
        _ = firstObject(in: value) { object in
            result = keys.lazy.compactMap { string(object[$0]) }.first
            return result != nil
        }
        return result
    }

    /// What a reply that is not a reading says went wrong, read the way the
    /// console's own page reads it: a frame that says it did not succeed, a
    /// code or message about signing in, or a status that is not a success.
    enum Failure: Equatable {
        /// The console wants a sign-in, or refused the one it was given.
        case signedOut
        /// Anything else the console says failed.
        case failed
    }

    static func failure(in tree: [String: Any]) -> Failure? {
        let frame = firstObject(in: tree) { object in
            ["successResponse", "success", "Success"].contains { (object[$0] as? Bool) == false }
        }
        let codeKeys = ["errorCode", "code", "Code", "status", "statusCode"]
        let messageKeys = ["errorMsg", "message", "Message", "msg", "statusMessage"]
        let code = frame.flatMap { firstString(codeKeys, in: $0) } ?? firstString(codeKeys, in: tree)
        let message = frame.flatMap { firstString(messageKeys, in: $0) } ?? firstString(messageKeys, in: tree)
        let said = [code, message].compactMap { $0?.lowercased() }.joined(separator: " ")

        let signIn = ["needlogin", "login", "tokenerror", "request has expired", "refresh page", "请求已经过期"]
        // A workspace the account may not use is a permission, not a session:
        // signing in again would change nothing.
        let refused = ["notauthorised", "notauthorized", "not authorised", "not authorized",
                       "unauthorised", "unauthorized", "access denied", "forbidden"]
        if signIn.contains(where: said.contains) { return .signedOut }
        if !said.contains("workspace.notauthori"), refused.contains(where: said.contains) { return .signedOut }
        if frame != nil { return .failed }

        if let status = firstInt(["statusCode", "status_code", "code", "httpStatusCode"], in: tree),
           status != 0, status != 200 {
            return status == 401 || status == 403 ? .signedOut : .failed
        }
        return nil
    }

    /// A number, or a string that is one. Never a boolean, which Foundation
    /// would otherwise hand over as 0 or 1.
    static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number.doubleValue.isFinite ? number.doubleValue : nil
        }
        if let text = value as? String {
            return Double(text.trimmingCharacters(in: .whitespaces)).flatMap { $0.isFinite ? $0 : nil }
        }
        return nil
    }

    static func string(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return text.isEmpty ? nil : text
    }

    /// Epoch seconds or milliseconds, ISO 8601, or the console's own
    /// `yyyy-MM-dd HH:mm[:ss]`.
    static func date(_ value: Any?) -> Date? {
        if let epoch = number(value), epoch > 0 {
            return Date(timeIntervalSince1970: epoch >= 1_000_000_000_000 ? epoch / 1_000 : epoch)
        }
        guard let text = string(value) else { return nil }
        if let date = ProfileHTTP.date(text) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}
