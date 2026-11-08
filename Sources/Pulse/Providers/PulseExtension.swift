// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import ImageIO

/// A program in the extensions folder that reports one account's usage.
///
/// **Out of process, and host-drawn.** Pulse starts the program, reads one
/// JSON object from its standard output and draws that with its own ring and
/// card. Nothing is loaded into Pulse, nothing the program sends is drawn as it
/// sent it, and Pulse hands it no credential: the program owns its own login.
/// The contract is Docs/extensions.md; this file is its one implementation.
///
/// Each extension is an account of `Provider.pulseExtension`, with the
/// manifest's `id` as its slot, so the rail, the cache and `--json` carry it
/// the way they carry an added account.
struct PulseExtension: Identifiable, Equatable, Sendable {
    /// From the manifest. Also the account's slot, so it has to survive being
    /// written into an account id: see `ExtensionCatalog.isValidID`.
    let id: String
    /// What the rail's card and Settings call it. The program's own word for
    /// itself, so it is never translated.
    let name: String
    /// The folder the manifest was found in.
    let directory: URL
    /// The program, resolved, and known to be inside `directory`.
    let executable: URL
    /// How long a run may take before it is stopped.
    let timeout: TimeInterval
    /// Validated PNG bytes from this extension's folder. Capturing the bytes
    /// makes a same-path icon replacement observable on the next scan.
    let iconData: Data?

    init(id: String, name: String, directory: URL, executable: URL,
         timeout: TimeInterval, iconData: Data? = nil) {
        self.id = id
        self.name = name
        self.directory = directory
        self.executable = executable
        self.timeout = timeout
        self.iconData = iconData
    }

    var account: AccountKey { AccountKey(.pulseExtension, slot: id) }
}

/// Finding extensions: which folders hold a manifest, and whether it can be
/// used.
///
/// **Reading a manifest never runs anything.** A folder dropped into the
/// extensions directory is listed in Settings and does nothing else until it is
/// switched on there — the same rule as every built-in provider, which is not
/// fetched while it is off.
enum ExtensionCatalog {
    static let manifestName = "pulse-extension.json"
    /// The only schema this build reads, for the manifest and the report both.
    static let schemaVersion = 1

    /// Where extensions live. Pulse's own Application Support folder, so it
    /// is somewhere nothing else writes to and a user who asks can be told
    /// exactly where to look.
    static var folder: URL { PulseStorage.directory.appending(path: "Extensions") }

    static let defaultTimeout: TimeInterval = 20
    /// A pass waits for every extension it asks, so the ceiling is a ceiling on
    /// how late every other ring can be.
    static let timeoutRange: ClosedRange<TimeInterval> = 1...60

    /// What a scan found: the extensions that can be used, and why each folder
    /// that could not be was turned away.
    struct Scan: Equatable, Sendable {
        var extensions: [PulseExtension] = []
        var problems: [Problem] = []
    }

    struct Problem: Equatable, Sendable, Identifiable {
        /// The folder's name, which is all the reader needs to find it.
        let folder: String
        let reason: Reason
        var id: String { folder }
    }

    enum Reason: Equatable, Sendable {
        case noManifest
        case unreadableManifest
        case unsupportedSchema(Int)
        case invalidID
        case missingName
        case executableOutsideFolder
        case executableMissing
        case duplicateID(String)

        var message: String {
            switch self {
            case .noManifest:
                .localized("No pulse-extension.json in this folder.")
            case .unreadableManifest:
                .localized("pulse-extension.json isn't valid JSON, or is missing a field.")
            case .unsupportedSchema(let version):
                .localized("Written for extension schema \(String(version)), which this version of Pulse doesn't read.")
            case .invalidID:
                .localized("Its id must be lowercase letters, digits, dots, dashes or underscores, 64 at most.")
            case .missingName:
                .localized("Its name is empty.")
            case .executableOutsideFolder:
                .localized("Its program has to be inside its own folder.")
            case .executableMissing:
                .localized("Its program isn't there, or isn't executable.")
            case .duplicateID(let id):
                .localized("Another extension already uses the id \(id).")
            }
        }
    }

    private struct Manifest: Decodable {
        let schemaVersion: Int
        let id: String
        let name: String
        let executable: String
        let timeoutSeconds: Double?
        let icon: IconPath?
    }

    /// An optional presentation field must not disable a working program if
    /// its value has the wrong type.
    private struct IconPath: Decodable {
        let value: String?

        init(from decoder: Decoder) throws {
            value = try? decoder.singleValueContainer().decode(String.self)
        }
    }

    static let iconByteCeiling = 256 * 1024
    static let iconDimensionCeiling = 1024

    /// Read a bounded local PNG during discovery, never during drawing. An
    /// unavailable or invalid icon leaves the program and its readings intact.
    private static func iconData(at path: String?, in root: URL) -> Data? {
        guard let path, !path.isEmpty, !path.hasPrefix("/") else { return nil }
        let file = root.appending(path: path).resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"),
              let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize, (1...iconByteCeiling).contains(size),
              let handle = try? FileHandle(forReadingFrom: file)
        else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: iconByteCeiling + 1),
              !data.isEmpty, data.count <= iconByteCeiling,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == "public.png",
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              (1...iconDimensionCeiling).contains(width),
              (1...iconDimensionCeiling).contains(height),
              CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil
        else { return nil }
        return data
    }

    /// Letters, digits and `.-_`, lowercase, starting with a letter or digit.
    ///
    /// **Not a style rule.** The id becomes an account id — `extension#<id>` —
    /// and account ids are split on `#` and rail slots on `@`, so either
    /// character in here would cut the account in two when it is read back.
    static func isValidID(_ id: String) -> Bool {
        guard (1...64).contains(id.count), let first = id.unicodeScalars.first else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-_")
        let leading = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        return leading.contains(first) && id.unicodeScalars.allSatisfy(allowed.contains)
    }

    /// Every folder directly inside `folder`, in name order. Hidden entries and
    /// plain files are skipped: a `.DS_Store` is not a broken extension.
    static func scan(in folder: URL = folder) -> Scan {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return Scan() }

        var scan = Scan()
        var taken: Set<String> = []
        let folders = entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        for directory in folders {
            switch load(directory) {
            case .success(let found) where taken.contains(found.id):
                // The first folder in name order keeps it. Two programs
                // answering as one account would draw whichever ran last.
                scan.problems.append(Problem(folder: directory.lastPathComponent, reason: .duplicateID(found.id)))
            case .success(let found):
                taken.insert(found.id)
                scan.extensions.append(found)
            case .failure(let problem):
                scan.problems.append(Problem(folder: directory.lastPathComponent, reason: problem.reason))
            }
        }
        return scan
    }

    private struct LoadFailure: Error { let reason: Reason }

    private static func load(_ directory: URL) -> Result<PulseExtension, LoadFailure> {
        let manifestURL = directory.appending(path: manifestName)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return .failure(LoadFailure(reason: .noManifest))
        }
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return .failure(LoadFailure(reason: .unreadableManifest)) }

        guard manifest.schemaVersion == schemaVersion else {
            return .failure(LoadFailure(reason: .unsupportedSchema(manifest.schemaVersion)))
        }
        guard isValidID(manifest.id) else { return .failure(LoadFailure(reason: .invalidID)) }

        let name = manifest.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(LoadFailure(reason: .missingName)) }

        // Resolved before it is compared, so neither `..` nor a link can make
        // a program outside the folder look like one inside it. The folder
        // Settings shows is the folder whose program runs.
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let executable = root.appending(path: manifest.executable)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard !manifest.executable.hasPrefix("/"),
              executable.path.hasPrefix(root.path + "/")
        else { return .failure(LoadFailure(reason: .executableOutsideFolder)) }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: executable.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isExecutableFile(atPath: executable.path)
        else { return .failure(LoadFailure(reason: .executableMissing)) }

        let timeout = min(max(manifest.timeoutSeconds ?? defaultTimeout, timeoutRange.lowerBound), timeoutRange.upperBound)

        return .success(PulseExtension(
            id: manifest.id,
            name: String(name.prefix(60)),
            directory: root,
            executable: executable,
            timeout: timeout,
            iconData: iconData(at: manifest.icon?.value, in: root)
        ))
    }
}

/// Runs an extension and turns what it printed into a reading.
struct ExtensionUsageService: Sendable {
    let pulseExtension: PulseExtension

    /// More than any honest report needs. Past it the bytes are dropped and
    /// the report fails to parse, rather than Pulse holding whatever a runaway
    /// program cares to write.
    static let outputCeiling = 256 * 1024

    func fetch() async -> ProviderUsage {
        let account = pulseExtension.account
        // Checked again here, not only when the folder was scanned: the scan
        // was at launch, and the program may have gone since.
        guard FileManager.default.isExecutableFile(atPath: pulseExtension.executable.path) else {
            return .unavailable(account, reason: .extensionMissing)
        }

        let result = await BoundedProcess.run(
            pulseExtension.executable,
            [],
            environment: Self.environment(for: pulseExtension),
            currentDirectory: pulseExtension.directory,
            deadline: pulseExtension.timeout,
            outputCeiling: Self.outputCeiling
        )

        switch result {
        case .success(let data):
            return ExtensionReport.reading(from: data, for: account)
        case .failure(.couldNotStart):
            return .unavailable(account, reason: .extensionMissing)
        case .failure(.timedOut):
            return .unavailable(account, reason: .extensionTimedOut)
        case .failure(.exited):
            return .unavailable(account, reason: .extensionFailed)
        }
    }

    /// **Only what a program needs to run, and the proxy.** Not Pulse's own
    /// environment: whatever a launch agent or a terminal happened to leave in
    /// it — tokens exported for some other tool included — is nobody's
    /// business but the tool it was meant for.
    ///
    /// The PATH covers the system and both Homebrew prefixes, which is where a
    /// script's `#!/usr/bin/env node` or `python3` is going to be found.
    static func environment(
        for pulseExtension: PulseExtension,
        over inherited: [String: String] = NetworkSession.subprocessEnvironment()
            ?? ProcessInfo.processInfo.environment
    ) -> [String: String] {
        let passed = ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "SHELL"]
        let proxies = ["http_proxy", "https_proxy", "all_proxy", "no_proxy"]
        var environment: [String: String] = [:]
        for (key, value) in inherited
        where passed.contains(key) || proxies.contains(key.lowercased()) {
            environment[key] = value
        }
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PULSE_EXTENSION_ID"] = pulseExtension.id
        environment["PULSE_EXTENSION_SCHEMA"] = String(ExtensionCatalog.schemaVersion)
        return environment
    }
}

/// What an extension prints: one JSON object. See Docs/extensions.md.
///
/// **Pulse still invents nothing.** A limit is drawn from a percentage the
/// program states, or from a used amount and a limit it states; one with
/// neither is left off rather than drawn at zero, and a report with neither a
/// limit nor a balance left says so.
///
/// **A balance is money and nothing more.** A relay that sells prepaid credit
/// reports what is left and no allowance, so the report carries the amount and
/// its currency, and the ring it gets is every API account's — `BalanceRing`,
/// with a denominator Pulse watched, one the reader typed, or none.
///
/// **Metrics are an addition, and cannot take the reading down.** `metrics[]`
/// came after the first extensions were written (issue #80), so a metric Pulse
/// cannot use — a value written as text, a list that is not a list — drops
/// that metric, or the list, and leaves the limits and the balance as they
/// were.
enum ExtensionReport {
    /// As many as the card has room for beside a few limits and a balance.
    /// The rest are left off, in the program's order.
    static let metricLimit = 4
    /// The newest points of a series, at most. Older ones are left off rather
    /// than thinned: a point Pulse kept is a point the program stated.
    static let historyLimit = 120

    private struct Report: Decodable {
        let schemaVersion: Int
        let status: String?
        let plan: String?
        let limits: [Limit]?
        let balance: Balance?
        let metrics: Lossy<Metric>?
    }

    /// A list whose bad entries are skipped, and which is empty rather than an
    /// error when it is not a list at all.
    private struct Lossy<Element: Decodable>: Decodable {
        let elements: [Element]

        init(from decoder: Decoder) throws {
            guard var container = try? decoder.unkeyedContainer() else {
                elements = []
                return
            }
            var kept: [Element] = []
            while !container.isAtEnd {
                if let element = try? container.decode(Element.self) {
                    kept.append(element)
                } else if (try? container.decode(Skipped.self)) == nil {
                    break
                }
            }
            elements = kept
        }

        /// Anything at all, to step past an entry that did not decode.
        private struct Skipped: Decodable {
            init(from decoder: Decoder) throws {}
        }
    }

    /// Every field optional, so a wrong type drops this metric and nothing
    /// else.
    private struct Metric: Decodable {
        let id: String?
        let label: String?
        let value: Double?
        let unit: String?
        let history: Lossy<Point>?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try? container.decodeIfPresent(String.self, forKey: .id)
            label = try? container.decodeIfPresent(String.self, forKey: .label)
            value = try? container.decodeIfPresent(Double.self, forKey: .value)
            unit = try? container.decodeIfPresent(String.self, forKey: .unit)
            history = try? container.decodeIfPresent(Lossy<Point>.self, forKey: .history)
        }

        private enum CodingKeys: String, CodingKey { case id, label, value, unit, history }
    }

    private struct Point: Decodable {
        let t: String
        let v: Double
    }

    /// Optional fields, so a balance missing one is dropped rather than
    /// taking the limits beside it down with it.
    private struct Balance: Decodable {
        let amount: Double?
        let currency: String?
    }

    private struct Limit: Decodable {
        let id: String?
        let label: String
        let usedPercent: Double?
        let used: Double?
        let limit: Double?
        let resetsAt: String?
        let windowSeconds: Int?
    }

    static func reading(from data: Data, for account: AccountKey, now: Date = Date()) -> ProviderUsage {
        guard let report = try? JSONDecoder().decode(Report.self, from: data),
              report.schemaVersion == ExtensionCatalog.schemaVersion
        else { return .unavailable(account, reason: .unreadableReply) }

        // Named failures only, each one mapped to wording that names no
        // provider. Anything else is a reply Pulse cannot read.
        switch report.status ?? "ok" {
        case "ok": break
        case "signedOut": return .unavailable(account, reason: .extensionSignedOut)
        case "unreachable": return .unavailable(account, reason: .unreachable)
        case "rateLimited": return .unavailable(account, reason: .rateLimited)
        case "serverError": return .unavailable(account, reason: .serverError)
        case "noLimits": return .unavailable(account, reason: .noLimitsReported)
        default: return .unavailable(account, reason: .unreadableReply)
        }

        var seen: Set<String> = []
        let windows = (report.limits ?? []).enumerated().compactMap { index, limit -> UsageWindow? in
            guard let fraction = usedFraction(of: limit) else { return nil }
            let label = limit.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { return nil }
            // Pinning a ring to a limit is by id, so it has to stay put
            // across runs — the program's own if it gave one, else its place.
            let id = "extension." + (limit.id.map { String($0.prefix(64)) } ?? String(index))
            guard seen.insert(id).inserted else { return nil }
            let seconds = limit.windowSeconds.flatMap { $0 > 0 ? $0 : nil }
            return UsageWindow(
                id: id,
                kind: .other(seconds: seconds ?? 0),
                scope: nil,
                usedFraction: fraction,
                windowSeconds: seconds ?? 0,
                resetsAt: limit.resetsAt.flatMap(date(from:)),
                // A length only when the program stated one. Without it the
                // window clock has nothing to divide by and draws nothing.
                reportsLength: seconds != nil,
                isExhausted: fraction >= 1,
                label: String(label.prefix(60))
            )
        }

        let money = report.balance.flatMap(credit(from:))
        guard !windows.isEmpty || money != nil else { return .unavailable(account, reason: .noLimitsReported) }

        var usage = ProviderUsage(
            account: account,
            windows: windows,
            observedAt: now,
            state: .live,
            plan: report.plan.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)) }
                .flatMap { $0.isEmpty ? nil : $0 },
            creditBalance: money.map(formatted)
        )
        usage.creditRemaining = money
        usage.metrics = metrics(from: report.metrics?.elements ?? [])
        return usage.recording(.extensionProgram)
    }

    /// The metrics Pulse can draw, in the program's order: each with a label
    /// and a value that is a number, no id twice, at most `metricLimit`.
    private static func metrics(from reported: [Metric]) -> [UsageMetric] {
        var seen: Set<String> = []
        var kept: [UsageMetric] = []
        for (index, metric) in reported.enumerated() {
            guard kept.count < metricLimit else { break }
            guard let value = metric.value, value.isFinite,
                  let label = metric.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty
            else { continue }
            let id = metric.id.map { String($0.prefix(64)) } ?? String(index)
            guard seen.insert(id).inserted else { continue }
            let unit = metric.unit?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16)
            kept.append(UsageMetric(
                id: id,
                label: String(label.prefix(60)),
                value: value,
                unit: unit.flatMap { $0.isEmpty ? nil : String($0) },
                history: history(from: metric.history?.elements ?? [])
            ))
        }
        return kept
    }

    /// The points with a time and a number, oldest first, one per moment —
    /// the first stated wins — and only the newest `historyLimit` of them.
    private static func history(from points: [Point]) -> [UsageMetric.Point] {
        var seen: Set<Date> = []
        let dated = points.compactMap { point -> UsageMetric.Point? in
            guard point.v.isFinite, let at = date(from: point.t), seen.insert(at).inserted else { return nil }
            return UsageMetric.Point(at: at, value: point.v)
        }
        return Array(dated.sorted { $0.at < $1.at }.suffix(historyLimit))
    }

    /// The amount as stated, in a currency named by its ISO code. Below zero
    /// is kept — some services run an account negative and keep serving it —
    /// but a figure that is not a number, or a currency that is not a code, is
    /// no balance at all.
    private static func credit(from balance: Balance) -> ProviderUsage.CreditAmount? {
        guard let amount = balance.amount, amount.isFinite,
              let currency = balance.currency?.trimmingCharacters(in: .whitespaces).uppercased(),
              currency.count == 3,
              currency.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) })
        else { return nil }
        return ProviderUsage.CreditAmount(amount: amount, currency: currency)
    }

    private static func formatted(_ money: ProviderUsage.CreditAmount) -> String {
        return Money.reported(money.amount, code: money.currency)
    }

    /// The percentage as stated, or the used amount over the stated limit.
    /// Nothing negative, nothing that is not a number, and no division by a
    /// limit of zero.
    private static func usedFraction(of limit: Limit) -> Double? {
        if let percent = limit.usedPercent {
            return percent.isFinite && percent >= 0 ? percent / 100 : nil
        }
        guard let used = limit.used, let total = limit.limit,
              used.isFinite, total.isFinite, used >= 0, total > 0
        else { return nil }
        return used / total
    }

    /// ISO 8601, with or without fractional seconds.
    private static func date(from text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}
