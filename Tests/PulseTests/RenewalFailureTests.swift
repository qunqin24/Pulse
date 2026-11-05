import Foundation
import Testing
@testable import Pulse

/// A token renewal that failed for a reason the login did not cause is not a
/// signed-out account: those keep the cached reading and do not ask the user
/// to sign in again.
struct RenewalFailureTests {
    @Test("Only a refused login, or no renewal at all, is signed out")
    func classification() {
        typealias F = OAuthLogin.Failure
        #expect(LiveUsageServices.renewalFailure(F.unreachable) == .unreachable)
        #expect(LiveUsageServices.renewalFailure(F.rejected(status: 429, detail: "")) == .rateLimited)
        #expect(LiveUsageServices.renewalFailure(F.rejected(status: 503, detail: "")) == .serverError)
        #expect(LiveUsageServices.renewalFailure(F.unreadableReply) == .unreadableReply)
        #expect(LiveUsageServices.renewalFailure(F.rejected(status: 400, detail: "invalid_grant")) == .signedOut)
        #expect(LiveUsageServices.renewalFailure(F.rejected(status: 401, detail: "")) == .signedOut)
        #expect(LiveUsageServices.renewalFailure(F.unsupported) == .signedOut)
        #expect(LiveUsageServices.renewalFailure(CancellationError()) == .unreachable)
    }
}
