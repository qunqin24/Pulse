import Foundation
import Testing
@testable import Pulse

/// What the GLM Coding Plan's refusals mean.
///
/// **Every one of these is an HTTP 200.** The endpoint puts its verdict in the
/// envelope, so the status line says nothing and this mapping is the whole of
/// what the user is told. The bodies below were taken from the live endpoint
/// on 2026-09-07 — `open.bigmodel.cn` answers in Chinese and `api.z.ai` in
/// English, which is what the old English-only keyword list could not see.
@Suite("GLM Coding Plan refusals")
struct ZaiErrorTests {
    private func reply(code: Int?, msg: String?) throws -> ZaiUsageService.Reply {
        let body: [String: Any] = [
            "success": false,
            "code": code as Any,
            "msg": msg as Any
        ].compactMapValues { $0 is NSNull ? nil : $0 }
        return try JSONDecoder().decode(
            ZaiUsageService.Reply.self,
            from: try JSONSerialization.data(withJSONObject: body)
        )
    }

    @Test("A key of the wrong shape: 401, in Chinese")
    func malformedKey() throws {
        #expect(try ZaiUsageService.problem(reply(code: 401, msg: "令牌已过期或验证不正确")) == .apiKeyRefused)
    }

    @Test("A well-formed key the host does not know: 1000")
    func wrongRegionKey() throws {
        // The case that sent people looking for an outage. A z.ai key is the
        // right shape and the wrong account for BigModel, so this is what
        // somebody with the international plan sees on the mainland row.
        #expect(try ZaiUsageService.problem(reply(code: 1000, msg: "身份验证失败。")) == .apiKeyRefused)
    }

    @Test("No Authorization header reached the server: 1001")
    func missingHeader() throws {
        #expect(try ZaiUsageService.problem(
            reply(code: 1001, msg: "Header中未收到Authorization参数，无法进行身份验证。")
        ) == .apiKeyRefused)
    }

    @Test("The international host says the same things in English")
    func englishMessages() throws {
        #expect(try ZaiUsageService.problem(reply(code: 401, msg: "token expired or incorrect")) == .apiKeyRefused)
        #expect(try ZaiUsageService.problem(reply(code: 999, msg: "invalid api key")) == .apiKeyRefused)
    }

    @Test("Chinese wording carries even when the code is unknown")
    func chineseKeywordsWithoutACode() throws {
        // The code list cannot be complete — it is one vendor's private
        // numbering and is not published in full — so the words have to work
        // on their own.
        for said in ["鉴权失败", "认证信息有误", "未授权的请求", "密钥无效", "无权限访问该接口"] {
            #expect(try ZaiUsageService.problem(reply(code: 12_345, msg: said)) == .apiKeyRefused, "missed: \(said)")
        }
    }

    @Test("A key that works on an account with no plan is not a fault")
    func noCodingPlan() throws {
        // Measured against the live endpoint with a real Coding Plan key
        // whose subscription had lapsed — one that still answers a
        // `glm-4-flash` completion. All three hosts reply with this, over an
        // HTTP 200, using the vendor's generic 500: the code says nothing and
        // only the sentence does.
        #expect(try ZaiUsageService.problem(reply(code: 500, msg: "当前用户不存在coding plan"))
            == .zaiNoCodingPlan)
        // And it must outrank the code test: 500 alone would say the service
        // broke, which sends somebody to look for an outage instead of at
        // their subscription.
        #expect(try ZaiUsageService.problem(reply(code: 500, msg: "user has no coding plan"))
            == .zaiNoCodingPlan)
    }

    @Test("Rate limiting and real server faults are still told apart")
    func notEverythingIsTheKey() throws {
        #expect(try ZaiUsageService.problem(reply(code: 429, msg: "too many requests")) == .rateLimited)
        #expect(try ZaiUsageService.problem(reply(code: 500, msg: "内部错误")) == .serverError)
        #expect(try ZaiUsageService.problem(reply(code: nil, msg: nil)) == .serverError)
    }

    @Test("The two rows are named for the shops, not for the product")
    func namesDisambiguate() {
        // Both shops sell the same thing under the same name, so a row called
        // "GLM Coding Plan" is a row half the buyers pick wrongly — issue #13.
        #expect(Provider.zai.displayName == "z.ai")
        #expect(Provider.glmCoding.displayName == "Zhipu")
        for provider in [Provider.zai, .glmCoding] {
            #expect(!provider.displayName.contains("GLM Coding Plan"),
                    "the ambiguous name is what caused the mix-up")
        }
    }
}

/// The success path, at last held against a real payload.
///
/// Captured from `open.bigmodel.cn` on 2026-09-07 with a live Coding Plan key
/// (a Lite subscription, freshly bought and untouched). Until this existed the
/// mapping from `limits[]` to rings had never been run against anything but
/// invented JSON — the refusals were measured and the answer was not.
///
/// The payload carries no secret: quota counts, a reset stamp and a tier name.
@Suite("GLM Coding Plan quota")
struct ZaiQuotaTests {
    private static func windows() throws -> [UsageWindow] {
        let url = try #require(
            Bundle.module.url(forResource: "glm-coding-plan-quota", withExtension: "json", subdirectory: "Fixtures")
        )
        let reply = try JSONDecoder().decode(ZaiUsageService.Reply.self, from: try Data(contentsOf: url))
        return ZaiUsageService.windows(from: try #require(reply.data?.limits), provider: .glmCoding)
    }

    @Test("Both limits are read, shortest first")
    func twoWindows() throws {
        let windows: [UsageWindow] = try Self.windows()
        #expect(windows.count == 2)
        #expect(windows.map(\.kind) == [.fiveHour, .weekly])
    }

    @Test("`unit` and `number` are a real duration, not a sort key")
    func durations() throws {
        let windows: [UsageWindow] = try Self.windows()
        // unit 3 is hours, unit 6 is weeks — 5 hours and 1 week, both stated
        // by the service, so the window clock and the forecast may divide.
        #expect(windows[0].windowSeconds == 5 * 3_600)
        #expect(windows[1].windowSeconds == 7 * 86_400)
        let statedLengths = windows.allSatisfy(\.reportsLength)
        #expect(statedLengths)
    }

    @Test("An untouched plan reads as nothing used, not as no reading")
    func freshPlanIsZero() throws {
        let windows: [UsageWindow] = try Self.windows()
        // `usage` and `remaining` are equal, so the spend is zero — and zero
        // is a reading. The distinction matters: a missing figure has to stay
        // nil rather than draw a full green ring.
        let allZero = windows.allSatisfy { $0.usedFraction == 0 }
        let noneSpent = windows.allSatisfy { !$0.isExhausted }
        #expect(allZero)
        #expect(noneSpent)
    }

    @Test("The reset stamp is milliseconds, and only one limit has one")
    func resetTimes() throws {
        let windows: [UsageWindow] = try Self.windows()
        #expect(windows[0].resetsAt == nil)
        #expect(windows[1].resetsAt == Date(timeIntervalSince1970: 1_789_373_585.999))
    }

    @Test("The tier is named from `level`, which is the key this account uses")
    func planName() throws {
        let url = try #require(
            Bundle.module.url(forResource: "glm-coding-plan-quota", withExtension: "json", subdirectory: "Fixtures")
        )
        let reply = try JSONDecoder().decode(ZaiUsageService.Reply.self, from: try Data(contentsOf: url))
        // Five keys are accepted because different tiers use different ones.
        #expect(reply.data?.planLabel == "lite")
    }

    @Test("Ids are unique, so a pinned window stays resolvable")
    func idsAreUnique() throws {
        let windows: [UsageWindow] = try Self.windows()
        let ids = windows.map(\.id)
        // Two limits of the same type differing only in duration — the index
        // is in the id because a collision leaves a pin unresolvable.
        #expect(Set(ids).count == ids.count)
    }
}
