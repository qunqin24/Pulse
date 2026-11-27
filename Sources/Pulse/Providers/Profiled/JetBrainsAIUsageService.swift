// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// JetBrains AI: the AI Assistant quota, from the IDE's file on this Mac or,
/// once signed in, from JetBrains.
///
/// **The file first.** Every JetBrains IDE with AI Assistant used to write
/// the quota it last heard from JetBrains into its own settings folder,
/// `~/Library/Application Support/JetBrains/<IDE><version>/options/
/// AIAssistantQuotaManager2.xml` (Android Studio's under `Google/`), as two
/// XML attributes holding JSON. Pulse reads the most recently written one and
/// never writes to it. The shape is second-hand — taken from CodexBar's
/// JetBrains provider and its tests, not from a file on this Mac — and the
/// fixture in the tests says so. It is as fresh as the IDE left it.
///
/// **Then JetBrains, only when signed in.** IDEs from 2026.3 on keep the
/// quota in memory and leave the file without figures (#122). When the file
/// has no real quota and the user has signed in to a JetBrains account in
/// Settings (`JetBrainsLogin`), the quota is asked of JetBrains with that
/// login (`JetBrainsAIOnlineQuota`). Without a sign-in nothing is sent. The
/// IDE's own login, the Keychain and IDE config files are never read.
///
/// The quota is `current` of `maximum`, both stated, by either route. Its
/// length is the refill's stated length (`PT720H` in the file, `millis` in
/// the reply), and is not claimed when there is none.
extension ProviderProfile {
    static let jetBrainsAI = ProviderProfile(
        displayName: "JetBrains AI",
        iconResource: "extension",
        credential: .localLogin,
        accessDescription: {
            .localized("Reads the AI quota your JetBrains IDE saves on this Mac. After you sign in to a JetBrains account, Pulse asks JetBrains for it when the IDE saved none.")
        },
        soleRoute: {
            (String.localized("The IDE's saved quota, or JetBrains once signed in"),
             String.localized("Without a sign-in, only the IDE's file is read."))
        },
        setupSlug: "jetbrains-ai",
        discoveryPaths: ["Library/Application Support/JetBrains"],
        fetch: { await JetBrainsAIUsageService.fetch($0) }
    )
}

enum JetBrainsAIUsageService {
    /// Where the IDEs keep their settings folders, relative to home.
    static let settingsRoots = ["Library/Application Support/JetBrains", "Library/Application Support/Google"]

    /// The settings folders that belong to an IDE with AI Assistant, by the
    /// name each one starts with. Anything else under those roots — JetBrains
    /// Toolbox, Chrome under `Google/` — is not looked in.
    static let ideFolders = [
        "IntelliJIdea", "PyCharm", "WebStorm", "GoLand", "CLion", "DataGrip", "RubyMine", "Rider",
        "PhpStorm", "AppCode", "Fleet", "AndroidStudio", "RustRover", "Aqua", "DataSpell",
    ]

    static let quotaFile = "options/AIAssistantQuotaManager2.xml"

    static func fetch(
        _ context: ProfileContext,
        home: URL = URL(fileURLWithPath: NSHomeDirectory()),
        storedLogin: @Sendable () -> AccountCredentialStore.StoredLogin = {
            AccountCredentialStore.storedLogin(for: JetBrainsLogin.account)
        },
        online: @Sendable (AccountCredentials, ProfileContext) async -> ProviderUsage = { login, context in
            await JetBrainsAIOnlineQuota.usage(login: login, context: context)
        }
    ) async -> ProviderUsage {
        await choose(local: localReading(context, home: home), storedLogin: storedLogin(), context: context, online: online)
    }

    /// The route order, apart from the disk and the network.
    ///
    /// 1. The file, when it holds a real quota that is still current — older
    ///    IDEs; nothing is sent. A file left by an IDE no longer run keeps a
    ///    quota whose reset has passed; taken as an answer, it kept a signed-in
    ///    account off the network, and the cache then dropped the expired
    ///    window, so nothing showed at all (found in review).
    /// 2. Otherwise, signed in: JetBrains.
    /// 3. Otherwise the file's reason (`.localQuotaUnsaved`, `.localAppMissing`,
    ///    …), whose remedy offers the sign-in.
    ///
    /// A login that is refused or has expired comes back from the online
    /// route as `.signedOut` and is never answered from the file instead; a
    /// store that will not open is `.signedOut` too, as Grok Bot's is.
    static func choose(
        local: ProviderUsage,
        storedLogin: AccountCredentialStore.StoredLogin,
        context: ProfileContext,
        online: (AccountCredentials, ProfileContext) async -> ProviderUsage,
        now: Date = Date()
    ) async -> ProviderUsage {
        if local.state == .live, isCurrent(local, at: now) { return local }
        switch storedLogin {
        case .none: return local
        case .unreadable: return context.unavailable(.signedOut)
        case .login(let login): return await online(login, context)
        }
    }

    /// A reading whose every limit has yet to reset. A limit with no reset
    /// stated cannot be shown stale, so it counts as current.
    static func isCurrent(_ usage: ProviderUsage, at now: Date) -> Bool {
        !usage.windows.isEmpty && usage.windows.allSatisfy { ($0.resetsAt ?? .distantFuture) > now }
    }

    /// What the IDE's file says, or why it says nothing.
    static func localReading(_ context: ProfileContext, home: URL) -> ProviderUsage {
        guard let file = newestQuotaFile(home: home) else { return context.unavailable(.localAppMissing) }
        guard let data = try? Data(contentsOf: file) else { return context.unavailable(.unreadableReply) }
        return reading(from: data, context: context)
    }

    /// The quota file written last, across every IDE that has one.
    static func newestQuotaFile(home: URL) -> URL? {
        let files = FileManager.default
        let candidates = settingsRoots.flatMap { root -> [URL] in
            let folder = home.appending(path: root)
            let names = (try? files.contentsOfDirectory(atPath: folder.path)) ?? []
            return names
                .filter { name in ideFolders.contains { name.lowercased().hasPrefix($0.lowercased()) } }
                .map { folder.appending(path: $0).appending(path: quotaFile) }
                .filter { files.fileExists(atPath: $0.path) }
        }
        func modified(_ url: URL) -> Date {
            (try? files.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
        }
        return candidates.max { modified($0) < modified($1) }
    }

    // MARK: - Reading the file

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let document = try? XMLDocument(data: data) else { return context.unavailable(.unreadableReply) }
        func option(_ name: String) -> [String: Any]? {
            let path = "//component[@name='AIAssistantQuotaManager2']/option[@name='\(name)']/@value"
            guard let text = (try? document.nodes(forXPath: path))?.first?.stringValue,
                  let object = try? JSONSerialization.jsonObject(with: Data(text.utf8))
            else { return nil }
            return object as? [String: Any]
        }
        // The IDE writes the component once AI Assistant has asked for a
        // quota; a file without it has nothing in it yet.
        guard let quota = option("quotaInfo") else { return context.unavailable(.localAppMissing) }

        let refill = option("nextRefill")
        guard let used = number(quota["current"]), used >= 0,
              let maximum = number(quota["maximum"]), maximum > 0
        else { return context.unavailable(withoutFigures(quota: quota, refill: refill)) }

        let tariff = refill?["tariff"] as? [String: Any]
        let stated = seconds(fromISODuration: (refill?["duration"] ?? tariff?["duration"]) as? String)
        let fraction = used / maximum
        let window = UsageWindow(
            id: "jetbrains.quota",
            kind: stated.map { .other(seconds: $0) } ?? .credits,
            scope: nil,
            usedFraction: fraction,
            windowSeconds: stated ?? 30 * 86_400,
            resetsAt: ProfileHTTP.date(refill?["next"] as? String),
            reportsLength: stated != nil,
            isExhausted: fraction >= 1
        )
        return context.reading([window], at: now)
    }

    /// Why a quota with no usable figures has none. IDEs from 2026.3 on fetch
    /// the quota online and keep it in memory (issue #122): the file stays,
    /// with `quotaInfo.type` `Unknown` and `nextRefill.type` `Error`, and no
    /// `current` or `maximum`. That is the IDE not saving a quota, not a quota
    /// without a size, so it is not called `noLimitsReported`.
    static func withoutFigures(quota: [String: Any], refill: [String: Any]?) -> ProviderUsage.Unavailability {
        let stated = quota["current"] != nil || quota["maximum"] != nil
        let unknown = (quota["type"] as? String)?.caseInsensitiveCompare("Unknown") == .orderedSame
        let failed = (refill?["type"] as? String)?.caseInsensitiveCompare("Error") == .orderedSame
        return !stated && (unknown || failed) ? .localQuotaUnsaved : .noLimitsReported
    }

    /// The IDE writes its figures as strings; a number is taken as well.
    static func number(_ value: Any?) -> Double? {
        let parsed: Double? = switch value {
        case let text as String: Double(text.trimmingCharacters(in: .whitespaces))
        case let number as NSNumber: number.doubleValue
        default: nil
        }
        return parsed.flatMap { $0.isFinite ? $0 : nil }
    }

    /// `PT720H`, `P30D`, `P1DT12H` — the lengths an ISO 8601 duration can
    /// state exactly. Months and years are not a fixed number of seconds, and
    /// anything that is not a duration at all (`monthly`) is not guessed at.
    static func seconds(fromISODuration text: String?) -> Int? {
        guard let text,
              let match = text.wholeMatch(of: #/P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?/#)
        else { return nil }
        let parts = [(match.1, 7 * 86_400), (match.2, 86_400), (match.3, 3_600), (match.4, 60), (match.5, 1)]
        var total = 0
        for (digits, unit) in parts {
            guard let digits else { continue }
            // Digits past `Int` do not parse; a count that does but overflows
            // its unit, or the sum, is not a length either.
            guard let count = Int(digits) else { return nil }
            guard count > 0 else { continue }
            guard let seconds = UsageWindow.length(count, unitSeconds: unit) else { return nil }
            let (sum, overflow) = total.addingReportingOverflow(seconds)
            guard !overflow, sum <= UsageWindow.longestLength else { return nil }
            total = sum
        }
        return total > 0 ? total : nil
    }
}
