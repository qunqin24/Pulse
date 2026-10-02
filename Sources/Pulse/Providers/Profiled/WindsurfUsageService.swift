// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Windsurf's daily and weekly quota, each a percentage remaining that
/// Windsurf states, read from the endpoint its own profile page calls:
/// `POST https://windsurf.com/_backend/exa.seat_management_pb.SeatManagementService/GetPlanStatus`,
/// Connect over protobuf.
///
/// **Not Devin's route, and deliberately so.** Windsurf now belongs to
/// Cognition, and Devin's provider already reads both of the other ways to
/// this plan: the Devin/Windsurf app's saved plan in `state.vscdb`, and
/// `app.devin.ai`'s quota endpoint with a session read out of the browser.
/// Reading either again here would be the same account counted twice under
/// two names. This one is windsurf.com's own endpoint.
///
/// **The credential is read from the browser's `localStorage`**, where
/// windsurf.com keeps its session as four `devin_*` values rather than in a
/// cookie: Read in Settings finds them in a Chromium browser and saves them as
/// one JSON object. They are sent only to windsurf.com.
///
/// The shape is second-hand — field numbers from CodexBar's Windsurf provider
/// and its tests, which took them from Windsurf's bundled protobuf metadata —
/// and the fixture in the tests says so.
extension ProviderProfile {
    static let windsurf = ProviderProfile(
        displayName: "Windsurf",
        iconResource: "windsurf",
        credential: .browserStorage(origin: "https://windsurf.com", keys: WindsurfUsageService.storageKeys),
        accessDescription: { .localized("Reads windsurf.com's sign-in from a Chromium browser when you press Read. No Keychain prompt.") },
        setupSlug: "windsurf",
        discoveryPaths: ["/Applications/Windsurf.app"],
        fetch: { await WindsurfUsageService.fetch($0) }
    )
}

enum WindsurfUsageService {
    static let storageKeys = ["devin_session_token", "devin_auth1_token", "devin_account_id", "devin_primary_org_id"]

    static let endpoint =
        URL(string: "https://windsurf.com/_backend/exa.seat_management_pb.SeatManagementService/GetPlanStatus")!

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let text = context.trimmedCredential, let bundle = Session(pasted: text) else {
            return context.unavailable(.sessionMissing)
        }
        switch await ProfileHTTP.data(for: request(bundle), refused: .sessionExpired, session: session) {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let data):
            return reading(from: data, context: context)
        }
    }

    // MARK: - The session

    /// The four values windsurf.com keeps in `localStorage`, all of which the
    /// endpoint is sent.
    struct Session: Equatable {
        let token: String
        let auth1: String
        let accountID: String
        let organizationID: String

        /// `{"devin_session_token": …, "devin_auth1_token": …,
        /// "devin_account_id": …, "devin_primary_org_id": …}`, which is what
        /// `ProviderProfile.storageCredential` saves. Any of the four missing
        /// and there is no session.
        init?(pasted text: String) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
            else { return nil }
            func value(_ key: String) -> String? {
                (object[key] as? String)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .flatMap { $0.isEmpty ? nil : $0 }
            }
            guard let token = value("devin_session_token"),
                  let auth1 = value("devin_auth1_token"),
                  let accountID = value("devin_account_id"),
                  let organizationID = value("devin_primary_org_id")
            else { return nil }
            self.token = token
            self.auth1 = auth1
            self.accountID = accountID
            self.organizationID = organizationID
        }
    }

    /// The headers windsurf.com's profile page sends, and a body of two
    /// fields: the session token (1) and "include top-up status" (2), which
    /// the page always sets.
    static func request(_ session: Session) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/proto", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("https://windsurf.com", forHTTPHeaderField: "Origin")
        request.setValue("https://windsurf.com/profile", forHTTPHeaderField: "Referer")
        request.setValue(session.token, forHTTPHeaderField: "x-auth-token")
        request.setValue(session.token, forHTTPHeaderField: "x-devin-session-token")
        request.setValue(session.auth1, forHTTPHeaderField: "x-devin-auth1-token")
        request.setValue(session.accountID, forHTTPHeaderField: "x-devin-account-id")
        request.setValue(session.organizationID, forHTTPHeaderField: "x-devin-primary-org-id")

        var body = Data()
        WindsurfProtobuf.appendKey(1, wire: 2, to: &body)
        WindsurfProtobuf.appendVarint(UInt64(session.token.utf8.count), to: &body)
        body.append(Data(session.token.utf8))
        WindsurfProtobuf.appendKey(2, wire: 0, to: &body)
        WindsurfProtobuf.appendVarint(1, to: &body)
        request.httpBody = body
        return request
    }

    // MARK: - Reading the reply

    /// What is read out of `plan_status` (field 1 of the reply).
    struct PlanStatus: Equatable {
        var planName: String?
        var dailyRemaining: UInt64?
        var weeklyRemaining: UInt64?
        var dailyResetAt: UInt64?
        var weeklyResetAt: UInt64?
    }

    /// `plan_status` fields: 1 `plan_info` (whose 2 is the plan's name),
    /// 14 and 15 the daily and weekly percentage **remaining**, 17 and 18
    /// their resets in Unix seconds. Everything else is skipped.
    static func planStatus(from data: Data) -> PlanStatus? {
        var reply = WindsurfProtobuf.Reader(data)
        var found: Data?
        while let field = reply.next() {
            guard case .bytes(let bytes) = field.value, field.number == 1 else { continue }
            found = bytes
        }
        guard reply.isComplete, let found else { return nil }

        var status = PlanStatus()
        var reader = WindsurfProtobuf.Reader(found)
        while let field = reader.next() {
            switch (field.number, field.value) {
            case (1, .bytes(let info)):
                var plan = WindsurfProtobuf.Reader(info)
                while let inner = plan.next() {
                    if inner.number == 2, case .bytes(let name) = inner.value {
                        status.planName = String(data: name, encoding: .utf8)
                    }
                }
            case (14, .varint(let value)): status.dailyRemaining = value
            case (15, .varint(let value)): status.weeklyRemaining = value
            case (17, .varint(let value)): status.dailyResetAt = value
            case (18, .varint(let value)): status.weeklyResetAt = value
            default: continue
            }
        }
        return reader.isComplete ? status : nil
    }

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let status = planStatus(from: data) else { return context.unavailable(.unreadableReply) }

        // WindsurfProtobuf does not write a zero, so a quota at 0% remaining and a
        // quota the plan does not have look the same: absent. CodexBar leaves
        // an absent one off, and so does this — a spent quota is not drawn
        // rather than drawn as a guess. Unverified against a spent account.
        let windows: [UsageWindow] = [
            ("daily", UsageWindow.Kind.daily, 86_400, status.dailyRemaining, status.dailyResetAt),
            ("weekly", .weekly, 7 * 86_400, status.weeklyRemaining, status.weeklyResetAt),
        ].compactMap { id, kind, seconds, remaining, reset in
            guard let remaining, remaining <= 100 else { return nil }
            let used = Double(100 - remaining) / 100
            return UsageWindow(
                id: "windsurf.\(id)",
                kind: kind,
                scope: nil,
                usedFraction: used,
                windowSeconds: seconds,
                resetsAt: reset.flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil },
                isExhausted: remaining == 0
            )
        }

        let plan = status.planName.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        guard !windows.isEmpty else { return context.unavailable(.noLimitsReported) }
        return context.reading(windows, plan: plan, at: now)
    }
}

/// Just enough protobuf to read a reply and write a request: varints and
/// length-delimited fields, with the fixed-width ones skipped.
enum WindsurfProtobuf {
    enum Value: Equatable {
        case varint(UInt64)
        case bytes(Data)
        case skipped
    }

    struct Reader {
        private let bytes: [UInt8]
        private var index = 0
        /// False once anything could not be read; a reader that stopped early
        /// has not read the message.
        private(set) var isComplete = true

        init(_ data: Data) { bytes = Array(data) }

        mutating func next() -> (number: Int, value: Value)? {
            guard isComplete, index < bytes.count else { return nil }
            guard let key = varint(), key >> 3 > 0 else { return fail() }
            let number = Int(key >> 3)
            switch key & 0x07 {
            case 0:
                guard let value = varint() else { return fail() }
                return (number, .varint(value))
            case 1:
                guard advance(8) else { return fail() }
                return (number, .skipped)
            case 2:
                guard let length = varint(), length <= UInt64(bytes.count - index) else { return fail() }
                let start = index
                index += Int(length)
                return (number, .bytes(Data(bytes[start..<index])))
            case 5:
                guard advance(4) else { return fail() }
                return (number, .skipped)
            default:
                return fail()
            }
        }

        private mutating func fail() -> (number: Int, value: Value)? {
            isComplete = false
            return nil
        }

        private mutating func advance(_ count: Int) -> Bool {
            guard bytes.count - index >= count else { return false }
            index += count
            return true
        }

        private mutating func varint() -> UInt64? {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while index < bytes.count, shift < 64 {
                let byte = bytes[index]
                index += 1
                result |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
            }
            return nil
        }
    }

    static func appendKey(_ number: Int, wire: UInt64, to data: inout Data) {
        appendVarint(UInt64(number) << 3 | wire, to: &data)
    }

    static func appendVarint(_ value: UInt64, to data: inout Data) {
        var remaining = value
        while remaining >= 0x80 {
            data.append(UInt8(remaining & 0x7F) | 0x80)
            remaining >>= 7
        }
        data.append(UInt8(remaining))
    }
}
