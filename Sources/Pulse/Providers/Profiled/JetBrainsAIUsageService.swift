// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// JetBrains AI: the AI Assistant quota a JetBrains IDE keeps on this Mac.
///
/// Nothing is asked of any server. Every JetBrains IDE with AI Assistant
/// writes the quota it last heard from JetBrains into its own settings folder,
/// `~/Library/Application Support/JetBrains/<IDE><version>/options/
/// AIAssistantQuotaManager2.xml` (Android Studio's under `Google/`), as two
/// XML attributes holding JSON. Pulse reads the most recently written one and
/// never writes to it. The shape is second-hand — taken from CodexBar's
/// JetBrains provider and its tests, not from a file on this Mac — and the
/// fixture in the tests says so.
///
/// **As fresh as the IDE left it.** The file changes only while an IDE is
/// running and talking to JetBrains; with every IDE closed the figure is the
/// last one any of them saw. The pane says so rather than pretending to be
/// live in a way it is not.
///
/// The quota is `current` of `maximum`, both stated. Its length is the refill
/// tariff's `duration` when that is an ISO 8601 length (`PT720H`), and is not
/// claimed when it isn't.
extension ProviderProfile {
    static let jetBrainsAI = ProviderProfile(
        displayName: "JetBrains AI",
        iconResource: "extension",
        credential: .localLogin,
        accessDescription: {
            .localized("Reads the AI Assistant quota your JetBrains IDE saves on this Mac. Nothing is sent anywhere.")
        },
        soleRoute: {
            (String.localized("The quota your JetBrains IDE saved"),
             String.localized("As current as the IDE last left it."))
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
        home: URL = URL(fileURLWithPath: NSHomeDirectory())
    ) async -> ProviderUsage {
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

        guard let used = number(quota["current"]), used >= 0,
              let maximum = number(quota["maximum"]), maximum > 0
        else { return context.unavailable(.noLimitsReported) }

        let refill = option("nextRefill")
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
        let total = parts.reduce(0) { sum, part in sum + (part.0.flatMap { Int($0) } ?? 0) * part.1 }
        return total > 0 ? total : nil
    }
}
