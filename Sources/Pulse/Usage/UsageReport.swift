import Foundation

/// `Pulse --json`: the app's last readings, on stdout, for anything that isn't
/// the panel — a tmux status line, sketchybar, Raycast, a shell prompt.
///
/// **It prints the cache and never fetches.** A status line polls every couple
/// of seconds; sixteen providers cannot be asked at that rate, and a command
/// that opened network connections and touched the keychain every time a
/// terminal redrew would be a worse citizen than no command at all. So this
/// reads what the running app last banked, and says how old it is — every
/// account carries `observedAt` and `ageSeconds` so the consumer can decide
/// what counts as too old. With the app not running, the figures simply stop
/// moving; they are never presented as current.
///
/// The output is a **contract**, so nothing in it is translated. Window names
/// are localized in the app and would change under a script's feet, so they
/// are not here: `kind` is a stable token, and `scope` and the provider's name
/// are product names that are the same in every language. See
/// [Docs/json-output.md](../../Docs/json-output.md).
enum UsageReport {
    static let modeArgument = "--json"

    /// Prints the report. Returns the process's exit code.
    static func run() -> Int32 {
        // The cache is an actor and `main()` is not async. A semaphore is the
        // plain way across for a command that does one thing and exits; the
        // alternative is `dispatchMain()`, which never returns and would have
        // to be unwound with `exit` from inside the task anyway.
        let rail = AppSettings.storedRail()
        let readings = UnsafeBox<[String: ProviderUsage]>([:])
        let done = DispatchSemaphore(value: 0)

        Task {
            var found: [String: ProviderUsage] = [:]
            for account in rail.accounts {
                found[account.id] = await UsageCache.shared.lastReading(for: account)
            }
            readings.value = found
            done.signal()
        }
        done.wait()

        guard let data = encode(rail: rail, readings: readings.value, generatedAt: Date()) else {
            FileHandle.standardError.write(Data("Pulse: could not encode the report\n".utf8))
            return 1
        }

        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        return 0
    }

    /// The whole of the formatting, with nothing to reach for: hand it a rail
    /// and some readings and it hands back the bytes.
    static func encode(
        rail: AppSettings.StoredRail,
        readings: [String: ProviderUsage],
        generatedAt: Date
    ) -> Data? {
        let report = Report(
            generatedAt: generatedAt,
            accounts: rail.accounts.map { account in
                Account(
                    account,
                    reading: readings[account.id],
                    label: rail.labels[account.id],
                    pinned: rail.pinnedWindows[account.id],
                    generatedAt: generatedAt
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Sorted so a diff between two runs is about the numbers, and pretty
        // so `pulse --json` is readable when somebody runs it by hand to see
        // what the fields are called.
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try? encoder.encode(report)
    }

    // MARK: - Shape

    private struct Report: Encodable {
        let generatedAt: Date
        let accounts: [Account]
    }

    private struct Account: Encodable {
        let id: String
        let provider: String
        let name: String
        let label: String
        let plan: String?
        let creditBalance: String?
        let observedAt: Date?
        let ageSeconds: Int?
        /// The window the ring shows, repeated from `windows` so the common
        /// case — one number in a status line — is one field rather than a
        /// re-implementation of which limit matters.
        let headline: Headline?
        let windows: [Window]

        init(
            _ account: AccountKey,
            reading: ProviderUsage?,
            label: String?,
            pinned: String?,
            generatedAt: Date
        ) {
            id = account.id
            provider = account.provider.rawValue
            name = account.provider.displayName
            self.label = label ?? account.provider.displayName
            plan = reading?.plan
            creditBalance = reading?.creditBalance
            observedAt = reading?.observedAt
            ageSeconds = reading?.observedAt.map { Int(generatedAt.timeIntervalSince($0).rounded()) }
            windows = (reading?.windows ?? []).map(Window.init)
            headline = reading?.headlineWindow(preferring: pinned).map(Headline.init)
        }
    }

    private struct Headline: Encodable {
        let windowId: String
        let usedPercent: Int
        let exhausted: Bool
        let resetsAt: Date?

        init(_ window: UsageWindow) {
            windowId = window.id
            usedPercent = window.percentValue()
            exhausted = window.isExhausted
            resetsAt = window.resetsAt
        }
    }

    private struct Window: Encodable {
        let id: String
        /// A stable token, not the localized name the card shows.
        let kind: String
        let scope: String?
        /// The figure the ring shows — the display rule, so a status line
        /// built from this agrees with the panel.
        let usedPercent: Int
        /// The reading itself, unrounded, for anything that wants to do its
        /// own arithmetic.
        let usedFraction: Double
        let exhausted: Bool
        let windowSeconds: Int
        /// False when `windowSeconds` is only a sort key. Do not divide by it.
        let reportsLength: Bool
        /// True where the provider stated how much of an allowance is left but
        /// never how large it is, so the denominator behind `usedFraction` was
        /// inferred rather than reported. Anything holding Pulse to "figures
        /// the provider reported" should filter on this.
        let estimated: Bool
        /// Which inference, as a stable token: `planPrice`, `sinceTopUp` or
        /// `yourBudget`. Absent when `estimated` is false. Not translated —
        /// the wording shown on the card is, this is not.
        let estimatedFrom: String?
        let resetsAt: Date?

        init(_ window: UsageWindow) {
            id = window.id
            kind = Self.token(for: window.kind)
            scope = window.scope
            usedPercent = window.percentValue()
            usedFraction = window.usedFraction
            exhausted = window.isExhausted
            windowSeconds = window.windowSeconds
            reportsLength = window.reportsLength
            estimated = window.isEstimated
            estimatedFrom = window.estimate?.rawValue
            resetsAt = window.resetsAt
        }

        /// `UsageWindow.Kind` is `Codable`, but its synthesised form is an
        /// object with an associated value in it — fine on disk, awkward in a
        /// contract somebody writes a `jq` filter against. A flat token that
        /// falls back to the length in seconds is what a script can switch on.
        private static func token(for kind: UsageWindow.Kind) -> String {
            switch kind {
            case .fiveHour: "fiveHour"
            case .weekly: "weekly"
            case .spend: "spend"
            case .balance: "balance"
            case .monthly: "monthly"
            case .other(let seconds): "other:\(seconds)"
            }
        }
    }
}

/// Carries one value out of a task the caller is blocking on.
///
/// Safe here and nowhere else: the semaphore is what orders the write against
/// the read, and there is exactly one of each.
private final class UnsafeBox<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}
