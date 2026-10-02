// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// A coding agent that leaves a record of its work on this Mac.
///
/// **Not a `Provider`, deliberately.** A provider is something Pulse can draw a
/// ring for: it reports a quota, it has a pane, it can be signed in to. An
/// agent is something that has *spent* tokens here. The two overlap and are
/// not the same list — Kimi's CLI and Kilo keep transcripts and sell no plan
/// Pulse watches, while Cursor and Copilot report quota and leave nothing here
/// to read. Folding these into `Provider` would put four rings on the rail for
/// products nobody can check a limit for.
///
/// **This is the whole catalogue, not only the stores Pulse was measured
/// against.** The first seven were read off a real machine and remain the only
/// ones whose native formats Pulse asserts it has verified. The rest are the
/// remaining clients of the reference inventory, each with an independently
/// written reader behind `AgentRecordReaders`; a reader that cannot decode its
/// store contributes no record rather than a guessed number, and the format
/// facts and caveats live in the readers' own files.
///
/// **A source ID is not a case name.** `rawValue` is the Swift case written as
/// one word and is what `AgentCache` keys its files by; `sourceID` is the
/// canonical string the reader families dispatch on. The seven legacy cases
/// keep the raw values they were persisted with, so their cache files stay
/// readable.
///
/// **Distinguish "recognised" from "counted".** A client can be part of the
/// catalogue and still have nothing to add up: Warp reports requests and money
/// and no tokens at all, Crush reports cost only, and Freebuff has no persisted
/// counters. `requiresUsageExport` says the store is an export/capture rather
/// than a native log; `reportsTokenCounts` says whether a token figure from it
/// is a measurement. Neither is inferred from the other.
enum SpendAgent: String, CaseIterable, Identifiable, Sendable {
    // MARK: - The seven readers verified on a real machine

    case claudeCode
    case codex
    case openCode
    case kiloCLI
    case grok
    case kimiCLI
    case devinCLI

    // MARK: - Group A: session-log readers

    case pi
    case omp
    case senpi
    case kimchi
    case primeAgent
    case gemini
    case qwen
    case amp
    case droid
    case openClaw

    // MARK: - Group B: editor-log readers

    case rooCode
    case kiloCode
    case cline
    case codeBuddy
    case workBuddy
    case cherryStudio
    case commandCode
    case openCodeReview
    case zcode

    // MARK: - Group C: database readers

    case hermes
    case goose
    case zed
    case kiro
    case crush
    case unsloth
    case antigravityCLI
    case antigravityIDE
    case micode
    case devinDesktop

    // MARK: - Group D: structured-log readers

    case mux
    case codebuff
    case freebuff
    case jcode
    case augment
    case gjc
    case junie
    case dsh
    case fx
    case lmStudio
    case reasonix

    // MARK: - Group E: explicit local exports and captures

    case cursor
    case antigravity
    case trae
    case warp
    case hindsight
    case mcode

    // MARK: - Group F: Copilot

    case copilot

    var id: String { rawValue }

    /// The canonical id this client has in the reference inventory, which is
    /// also what the reader families dispatch on.
    ///
    /// The seven legacy cases have no entry in a family — they are read by
    /// `UsageLedgerReader` and the store readers that predate the catalogue —
    /// so their spellings are the inventory's own (`claude`, `kimi`,
    /// `devin-cli`, …) rather than a conversion of the Swift case. Everything
    /// else is exactly the string in the owning family's `supportedClients`.
    var sourceID: String {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        case .openCode: "opencode"
        case .kiloCLI: "kilo"
        case .grok: "grok"
        case .kimiCLI: "kimi"
        case .devinCLI: "devin-cli"
        case .pi: "pi"
        case .omp: "omp"
        case .senpi: "senpi"
        case .kimchi: "kimchi"
        case .primeAgent: "prime-agent"
        case .gemini: "gemini"
        case .qwen: "qwen"
        case .amp: "amp"
        case .droid: "droid"
        case .openClaw: "openclaw"
        case .rooCode: "roocode"
        case .kiloCode: "kilocode"
        case .cline: "cline"
        case .codeBuddy: "codebuddy"
        case .workBuddy: "workbuddy"
        case .cherryStudio: "cherrystudio"
        case .commandCode: "commandcode"
        case .openCodeReview: "opencodereview"
        case .zcode: "zcode"
        case .hermes: "hermes"
        case .goose: "goose"
        case .zed: "zed"
        case .kiro: "kiro"
        case .crush: "crush"
        case .unsloth: "unsloth"
        case .antigravityCLI: "antigravity-cli"
        case .antigravityIDE: "antigravity-ide"
        case .micode: "micode"
        case .devinDesktop: "devin-desktop"
        case .mux: "mux"
        case .codebuff: "codebuff"
        case .freebuff: "freebuff"
        case .jcode: "jcode"
        case .augment: "augment"
        case .gjc: "gjc"
        case .junie: "junie"
        case .dsh: "dsh"
        case .fx: "fx"
        case .lmStudio: "lmstudio"
        case .reasonix: "reasonix"
        case .cursor: "cursor"
        case .antigravity: "antigravity"
        case .trae: "trae"
        case .warp: "warp"
        case .hindsight: "hindsight"
        case .mcode: "mcode"
        case .copilot: "copilot"
        }
    }

    /// Product names, left untranslated.
    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .openCode: "OpenCode"
        // A fork of OpenCode, down to the database schema — which is why one
        // reader serves both.
        case .kiloCLI: "Kilo CLI"
        case .grok: "Grok Build"
        case .kimiCLI: "Kimi CLI"
        // **"Devin", not "Devin CLI".** The store is `.../devin/cli/sessions.db`,
        // but that `cli` is Devin's own directory layout, not a product
        // marker: measured on a Mac with only Devin **Desktop** installed and
        // no `devin` on PATH, that database was being written all the same —
        // Desktop embeds the same core (its logs say `init_cli`,
        // `binary=devin`) and drives it. Calling the rows CLI usage told
        // somebody they had used a program they had never installed.
        //
        // The database cannot settle which client drove it, so this name does
        // not try to. `devinDesktop` stays separate and keeps its qualifier,
        // because its evidence — an `acp-events` capture tree — is Desktop's
        // alone.
        case .devinCLI: "Devin"
        case .pi: "Pi"
        case .omp: "Oh My Pi"
        case .senpi: "OmO Native"
        case .kimchi: "Kimchi"
        case .primeAgent: "Prime Agent"
        case .gemini: "Gemini CLI"
        case .qwen: "Qwen Code"
        case .amp: "Amp"
        case .droid: "Droid"
        case .openClaw: "OpenClaw"
        case .rooCode: "Roo Code"
        case .kiloCode: "Kilo Code"
        case .cline: "Cline"
        case .codeBuddy: "CodeBuddy"
        case .workBuddy: "WorkBuddy"
        case .cherryStudio: "Cherry Studio"
        case .commandCode: "Command Code"
        case .openCodeReview: "OpenCodeReview"
        case .zcode: "ZCode"
        case .hermes: "Hermes"
        case .goose: "Goose"
        case .zed: "Zed"
        case .kiro: "Kiro"
        case .crush: "Crush"
        case .unsloth: "Unsloth"
        // Three Antigravity entries, and the qualifiers are load-bearing: the
        // CLI and the IDE write separate stores for separate products and are
        // never pooled, and the third is fed by an export rather than by
        // Antigravity itself.
        case .antigravityCLI: "Antigravity CLI"
        case .antigravityIDE: "Antigravity IDE"
        case .micode: "MiMo Code"
        case .devinDesktop: "Devin Desktop"
        case .mux: "Mux"
        case .codebuff: "Codebuff"
        case .freebuff: "Freebuff"
        case .jcode: "JCode"
        case .augment: "Augment"
        case .gjc: "Gajae Code"
        case .junie: "Junie"
        case .dsh: "DeepSeek Harness"
        case .fx: "FX"
        case .lmStudio: "LM Studio"
        case .reasonix: "Reasonix"
        case .cursor: "Cursor"
        // Qualified, and the qualifier is the whole difference: this one is
        // fed by a Tokscale export of the IDE cache, not by Antigravity's own
        // store. Nothing appears under it until that export exists.
        case .antigravity: "Antigravity (export)"
        case .trae: "Trae"
        case .warp: "Warp"
        case .hindsight: "Hindsight"
        case .mcode: "MiniMax Code"
        case .copilot: "GitHub Copilot"
        }
    }

    /// The provider whose mark this agent is recognised by, where Pulse
    /// carries one. Nil where the agent is not a provider at all and there is
    /// no mark to borrow.
    ///
    /// **Only an existing `Provider` case is ever returned.** An agent does not
    /// get a ring, a pane or a rail slot by appearing here; it borrows a mark
    /// that already exists. Most of the catalogue has no mark and stays nil.
    var iconProvider: Provider? {
        switch self {
        case .claudeCode: .claudeCode
        case .codex: .codex
        case .openCode: .openCodeGo
        case .kiloCLI: nil
        case .grok: .grok
        case .kimiCLI: .kimiCode
        case .devinCLI: .devin
        case .cursor: .cursor
        case .antigravity, .antigravityCLI, .antigravityIDE: .antigravity
        case .commandCode: .commandCode
        case .devinDesktop: .devin
        case .copilot: .copilot
        default: nil
        }
    }

    /// The models.dev vendor whose published rates this agent's plan is sold
    /// at, consulted **only** when no first-party provider prices the model.
    ///
    /// Nil for an agent that calls the model vendors directly — its models are
    /// already in the first-party list, and a plan price there would be a
    /// second answer to a question that already has one.
    var priceVendor: String? {
        switch self {
        case .openCode, .openCodeReview: "opencode-go"
        case .kiloCLI, .kiloCode: "kilo"
        case .cline: "cline-pass"
        default: nil
        }
    }

    /// The SVG in `Resources` this agent is drawn with, or nil where nothing
    /// in the icon set stands for it.
    ///
    /// **Separate from `iconProvider`, and the split is the point.** A
    /// provider is something Pulse can put a ring and a settings pane behind;
    /// most of this catalogue is a client, not a provider, and must be able to
    /// carry a mark without being promoted to one to get it. Where an agent
    /// *is* a provider Pulse already draws, it reuses that exact file rather
    /// than shipping a second copy.
    ///
    /// **Nil is a real answer.** The icon set has no mark for a good number of
    /// these clients, and a borrowed or approximated one would say the wrong
    /// company made the tool. Those rows draw no mark at all.
    var iconResource: String? {
        if let iconProvider { return iconProvider.iconResource }

        return switch self {
        case .kiloCLI, .kiloCode: "kilocode"
        case .pi: "pi"
        case .gemini: "gemini"
        case .qwen: "qwen"
        case .amp: "amp"
        case .cline: "cline"
        // CodeBuddy and WorkBuddy are both Tencent's.
        case .codeBuddy, .workBuddy: "tencent"
        case .cherryStudio: "cherrystudio"
        case .hermes: "hermesagent"
        case .goose: "goose"
        case .kiro: "kiro"
        case .unsloth: "unsloth"
        case .micode: "xiaomimimo"
        case .junie: "junie"
        case .dsh: "deepseek"
        case .lmStudio: "lmstudio"
        case .trae: "trae"
        case .rooCode: "roocode"
        case .mcode: "minimax"
        case .openCodeReview: "opencode"
        case .openClaw: "openclaw"
        // No mark in the set: Oh My Pi, OmO Native, Kimchi, Prime Agent,
        // Droid, Crush, Zed, Warp, Hindsight, Mux, Codebuff, Freebuff, JCode,
        // Augment, Gajae Code, FX, Reasonix, ZCode. Checked name by name
        // against the whole set, not by a pattern — the first pass missed
        // OpenClaw, which was there all along. Left blank rather than
        // approximated: `zenmux` is not Mux.
        default: nil
        }
    }

    /// Whether its history comes from `UsageLedgerReader`, which already reads
    /// these two for the per-provider card.
    ///
    /// **The only two that keep a provider.** Everything else, including the
    /// agents that borrow a mark above, is read here and nowhere else.
    var provider: Provider? {
        switch self {
        case .claudeCode: .claudeCode
        case .codex: .codex
        default: nil
        }
    }

    /// Whether this agent's store is an export, cache or capture produced by a
    /// separate step, rather than a log the product writes as it runs.
    ///
    /// True for the six Group E clients, all of which need a prior sync,
    /// export or capture before there is anything to read. It decides the
    /// ledger's `origin`: imported records may still be priced, but they are
    /// not claimed as a native transcript.
    var requiresUsageExport: Bool {
        switch self {
        case .cursor, .antigravity, .trae, .warp, .hindsight, .mcode: true
        default: false
        }
    }

    /// Whether a token count from this agent is a measurement.
    ///
    /// False for the three whose stores expose no usable token counters:
    /// Crush reports per-session cost only, Warp reports requests and money and
    /// no tokens, and Freebuff persists no counters at all. **A false here
    /// does not mean the client was not recognised** — it is in the catalogue
    /// and its records are built — only that a token figure must not be
    /// presented as if it had been measured.
    var reportsTokenCounts: Bool {
        switch self {
        case .crush, .warp, .freebuff: false
        default: true
        }
    }

    /// Whether this agent's native reader was checked against a real store on a
    /// real machine.
    ///
    /// True only for the seven Pulse started with. It is a statement about the
    /// evidence behind the format, not about whether the reader runs; it is
    /// carried so a future surface can be honest without a second list.
    var hasCapturedValidation: Bool {
        switch self {
        case .claudeCode, .codex, .openCode, .kiloCLI, .grok, .kimiCLI, .devinCLI: true
        default: false
        }
    }

    private static var home: URL { URL(fileURLWithPath: NSHomeDirectory()) }

    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// Every file or directory this agent is read from, **whether or not it
    /// exists**.
    ///
    /// A missing root is named so the multi-root cache can watch the real
    /// sources: a store that appears later invalidates exactly the agent it
    /// belongs to. `home` and `environment` are injected rather than read, so a
    /// test never touches the machine it runs on.
    ///
    /// The seven legacy agents keep the exact home-relative paths they have
    /// always used and do not honour an environment override; the rest are
    /// resolved by their family, which does.
    func inputs(home: URL, environment: [String: String]) -> [URL] {
        guard !Task.isCancelled else { return [] }
        return switch self {
        case .claudeCode: [home.appending(path: ".claude/projects")]
        case .codex: [home.appending(path: ".codex/sessions")]
        case .openCode: [home.appending(path: ".local/share/opencode/opencode.db")]
        case .kiloCLI: [home.appending(path: ".local/share/kilo/kilo.db")]
        case .grok: [home.appending(path: ".grok/sessions")]
        case .kimiCLI: [home.appending(path: ".kimi/sessions")]
        case .devinCLI: [home.appending(path: ".local/share/devin/cli/sessions.db")]
        // Every other case is a catalog client, routed by its canonical id.
        default: AgentRecordReaders.inputs(client: sourceID, home: home, environment: environment)
        }
    }

    /// The inputs that actually exist now, which is what `present` is decided
    /// by and what the cache fingerprints.
    func stores(home: URL, environment: [String: String]) -> [URL] {
        let existing = inputs(home: home, environment: environment)
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        // **Devin Desktop is the one client whose inputs include a store it
        // does not own.** It borrows the Devin CLI database to resolve a
        // Desktop event file's session id, model and workspace by title and
        // exclude a mirror of usage the native route counts, so
        // that database is read and watched once Desktop is present — but its
        // existence alone is not evidence of Desktop. Without this gate a
        // machine with only the CLI would report a desktop agent with nothing
        // to show. Presence is proved by an `acp-events` tree; once it is, the
        // CLI database stays in the watched set.
        if self == .devinDesktop, !existing.contains(where: Self.isDevinDesktopEventInput) {
            return []
        }

        return existing
    }

    /// Whether an input is one of Devin Desktop's own `acp-events` trees, as
    /// opposed to the Devin CLI database it borrows for a lookup.
    ///
    /// A pure rule rather than a path spelled out again, so the presence gate
    /// cannot drift from the roots the reader declares.
    static func isDevinDesktopEventInput(_ url: URL) -> Bool {
        url.lastPathComponent == "acp-events"
    }

    /// The existing input roots, resolved against this machine.
    var stores: [URL] { stores(home: Self.home, environment: Self.environment) }

    /// The single root this agent has always had, where it has one.
    ///
    /// **A compatibility shim.** It is how the pre-catalogue readers name the
    /// one store they take; the multi-root callers use `stores`.
    var store: URL? { stores.first }

    /// The agents with something to read here. Everything downstream works
    /// from this rather than from `allCases`, so a machine with two agents on
    /// it never sees a row for the other fifty-one.
    static var present: [SpendAgent] { present(home: home, environment: environment) }

    /// The agents whose roots exist under an injected home and environment.
    static func present(home: URL, environment: [String: String]) -> [SpendAgent] {
        allCases.filter { !$0.stores(home: home, environment: environment).isEmpty }
    }
}
