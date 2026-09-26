import Foundation
import Testing
@testable import Pulse

/// `Provider.handWritten` and `Provider.profile` split every case into
/// exactly one of two answers. A provider counted in both, or in neither,
/// would let a shared switch silently fall back to a `default` somewhere, or
/// leave a case with no profile and no hand-written arm at all.
@Suite("Hand-written / profiled provider split")
struct HandWrittenProviderCoverageTests {
    @Test("Every provider is answered by exactly one of handWritten or profile")
    func exactlyOne() {
        for provider in Provider.allCases {
            let written = provider.handWritten != nil
            let profiled = provider.profile != nil
            #expect(written != profiled, "\(provider.rawValue) is \(written ? "both" : "neither")")
        }
    }

    @Test("Every HandWrittenProvider case maps back to the Provider it names")
    func mapsBack() {
        for written in Provider.HandWrittenProvider.allCases {
            let provider = Provider(rawValue: written.rawValue)
            #expect(provider != nil, "no Provider case named \(written.rawValue)")
            #expect(provider?.handWritten == written)
        }
    }
}
