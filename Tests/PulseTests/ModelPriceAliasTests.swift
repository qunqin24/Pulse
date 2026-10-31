import Foundation
import Testing
@testable import Pulse

/// The agents do not all spell a model the same way, and a name that misses
/// the price list is not a free model — it is a bill that silently reads zero.
@Suite("Model price aliases")
struct ModelPriceAliasTests {
    private static let table: [String: ModelPrice] = [
        "grok-4.6": ModelPrice(input: 1, output: 1, cacheRead: nil, cacheWrite: nil, name: "Grok 4.6"),
        "grok-build-0.1": ModelPrice(input: 9, output: 9, cacheRead: nil, cacheWrite: nil, name: "Grok Build"),
        "kimi-k3": ModelPrice(input: 2, output: 2, cacheRead: nil, cacheWrite: nil, name: "Kimi K3"),
        "kimi-k2.6": ModelPrice(input: 3, output: 3, cacheRead: nil, cacheWrite: nil, name: "Kimi K2.6"),
        "gpt-5.6-sol": ModelPrice(input: 4, output: 4, cacheRead: nil, cacheWrite: nil, name: "GPT-5.6 Sol"),
        "MiniMax-M3": ModelPrice(input: 5, output: 5, cacheRead: nil, cacheWrite: nil, name: "MiniMax-M3"),
        "gemini-3.5-flash": ModelPrice(input: 6, output: 6, cacheRead: nil, cacheWrite: nil, name: "Gemini 3.5 Flash"),
        "gemini-3.8-flash": ModelPrice(input: 7, output: 7, cacheRead: nil, cacheWrite: nil, name: "Gemini 3.8 Flash"),
        "gemini-3.1-pro-preview": ModelPrice(input: 8, output: 8, cacheRead: nil, cacheWrite: nil, name: "Gemini 3.1 Pro Preview"),
    ]

    private static func name(_ id: String) -> String? {
        ModelPrices.price(for: id, in: table)?.name
    }

    @Test("Grok Build tags its own build of a model")
    func buildSuffixIsDropped() {
        #expect(Self.name("grok-4.6-build") == "Grok 4.6")
        // Its own model really is called that, and must not be stripped into
        // something else.
        #expect(Self.name("grok-build-0.1") == "Grok Build")
    }

    @Test("Antigravity's lowest Flash effort is priced as the Flash (#90)")
    func extraLowEffortIsDropped() {
        #expect(Self.name("gemini-3.5-flash-extra-low") == "Gemini 3.5 Flash")
        #expect(Self.name("gemini-3.5-flash-medium") == "Gemini 3.5 Flash")
    }

    @Test("Antigravity's `-n`, `-control` and `-xpe` Flash is priced as the Flash (#90)")
    func nSuffixIsDropped() {
        #expect(Self.name("gemini-3.8-flash-n") == "Gemini 3.8 Flash")
        #expect(Self.name("gemini-3.8-flash-control") == "Gemini 3.8 Flash")
        #expect(Self.name("gemini-3.8-flash-xpe") == "Gemini 3.8 Flash")
        // Only on a Gemini id, and only when the base is priced.
        #expect(Self.name("kimi-k3-n") == nil)
        #expect(Self.name("gemini-9-flash-n") == nil)
    }

    @Test("A context window on the end is the same model with more room")
    func contextTagsAreDropped() {
        #expect(Self.name("kimi-k3-256k") == "Kimi K3")
        // And it composes with the abbreviation below.
        #expect(Self.name("k3-256k") == "Kimi K3")
        #expect(Self.name("k3-1m") == "Kimi K3")
    }

    @Test("Kimi's CLI abbreviates the version")
    func kimiShorthandIsExpanded() {
        #expect(Self.name("k3") == "Kimi K3")
        #expect(Self.name("k2p6") == "Kimi K2.6")
    }

    @Test("Devin writes the version with dashes and an effort on the end")
    func dashedVersionsAndEffortsResolve() {
        #expect(Self.name("gpt-5-6-sol-medium") == "GPT-5.6 Sol")
        #expect(Self.name("gpt-5-6-sol") == "GPT-5.6 Sol")
        // A dash between two words is not a version separator.
        #expect(ModelPrices.aliases(for: "gpt-sol").contains("gpt.sol") == false)
    }

    @Test("Devin spells a Gemini preview with dashes, no suffix")
    func dashedGeminiPreviewResolves() {
        #expect(Self.name("gemini-3-1-pro") == "Gemini 3.1 Pro Preview")
        // Only a Gemini id picks up the preview spelling.
        #expect(ModelPrices.aliases(for: "kimi-k3").contains("kimi-k3-preview") == false)
        // The preview build itself still resolves directly.
        #expect(Self.name("gemini-3.1-pro-preview") == "Gemini 3.1 Pro Preview")
    }

    @Test("Case is the only difference for MiniMax")
    func caseIsFolded() {
        #expect(Self.name("minimax-m3") == "MiniMax-M3")
        #expect(Self.name("MINIMAX-M3") == "MiniMax-M3")
    }

    @Test("A model nobody publishes a price for stays unpriced")
    func unknownModelsAreNotGuessed() {
        // The failure mode of a loose match is a model billed at another
        // model's rate, which is a wrong number that looks right.
        #expect(Self.name("swe-2-high") == nil)
        #expect(Self.name("codex-auto-review") == nil)
        #expect(Self.name("") == nil)
    }
}
