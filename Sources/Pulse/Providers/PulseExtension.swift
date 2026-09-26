import Foundation

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
            timeout: timeout
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
enum ExtensionReport {
    private struct Report: Decodable {
        let schemaVersion: Int
        let status: String?
        let plan: String?
        let limits: [Limit]?
        let balance: Balance?
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
        return usage.recording(.extensionProgram)
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
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = money.currency
        formatter.locale = LocalizationSource.locale
        return formatter.string(from: NSNumber(value: money.amount))
            ?? "\(money.amount) \(money.currency)"
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
