import Foundation
import Testing
@testable import Pulse

/// A folder of extensions on disk, removed afterwards.
private struct Sandbox {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "PulseExtensionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    /// A folder holding a manifest and, unless told otherwise, an executable
    /// shell script called `run`.
    @discardableResult
    func add(
        _ folder: String,
        manifest: String?,
        script: String? = "#!/bin/sh\necho '{}'\n",
        executable: Bool = true
    ) throws -> URL {
        let directory = root.appending(path: folder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let manifest {
            try Data(manifest.utf8).write(to: directory.appending(path: ExtensionCatalog.manifestName))
        }
        if let script {
            let program = directory.appending(path: "run")
            try Data(script.utf8).write(to: program)
            try FileManager.default.setAttributes(
                [.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: program.path
            )
        }
        return directory
    }

    static func manifest(id: String = "acme", name: String = "Acme", executable: String = "run",
                         schema: Int = 1, timeout: Double? = nil) -> String {
        let timeoutField = timeout.map { #", "timeoutSeconds": \#($0)"# } ?? ""
        return #"{"schemaVersion": \#(schema), "id": "\#(id)", "name": "\#(name)", "executable": "\#(executable)"\#(timeoutField)}"#
    }
}

@Suite("Extension discovery")
struct ExtensionCatalogTests {
    @Test("A folder with a manifest and a program inside it is an extension")
    func findsValidExtension() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.add("acme", manifest: Sandbox.manifest(name: "  Acme Quota  ", timeout: 5))

        let scan = ExtensionCatalog.scan(in: sandbox.root)
        #expect(scan.problems.isEmpty)
        let found = try #require(scan.extensions.first)
        #expect(found.id == "acme")
        #expect(found.name == "Acme Quota")
        #expect(found.timeout == 5)
        #expect(found.account == AccountKey(.pulseExtension, slot: "acme"))
        #expect(found.account.id == "extension#acme")
        // The account id reads back as the same account, so switches, order
        // and pinned windows stored under it find it again.
        #expect(AccountKey(id: found.account.id) == found.account)
    }

    @Test("A time limit outside the range is brought inside it")
    func clampsTimeout() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.add("slow", manifest: Sandbox.manifest(id: "slow", timeout: 600))
        try sandbox.add("fast", manifest: Sandbox.manifest(id: "fast", timeout: 0))
        try sandbox.add("plain", manifest: Sandbox.manifest(id: "plain"))

        let timeouts = Dictionary(uniqueKeysWithValues: ExtensionCatalog.scan(in: sandbox.root).extensions.map { ($0.id, $0.timeout) })
        #expect(timeouts["slow"] == ExtensionCatalog.timeoutRange.upperBound)
        #expect(timeouts["fast"] == ExtensionCatalog.timeoutRange.lowerBound)
        #expect(timeouts["plain"] == ExtensionCatalog.defaultTimeout)
    }

    @Test("Each folder that can't be used says why, and none of them is run")
    func reportsProblems() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.add("a-empty", manifest: nil)
        try sandbox.add("b-garbage", manifest: "not json")
        try sandbox.add("c-future", manifest: Sandbox.manifest(id: "future", schema: 2))
        try sandbox.add("d-hash", manifest: Sandbox.manifest(id: "acme#two"))
        try sandbox.add("e-upper", manifest: Sandbox.manifest(id: "Acme"))
        try sandbox.add("f-noname", manifest: Sandbox.manifest(id: "noname", name: "   "))
        try sandbox.add("g-escape", manifest: Sandbox.manifest(id: "escape", executable: "../a-empty/run"))
        try sandbox.add("h-absolute", manifest: Sandbox.manifest(id: "absolute", executable: "/bin/sh"))
        try sandbox.add("i-missing", manifest: Sandbox.manifest(id: "missing"), script: nil)
        try sandbox.add("j-notexec", manifest: Sandbox.manifest(id: "notexec"), executable: false)

        let reasons = Dictionary(uniqueKeysWithValues: ExtensionCatalog.scan(in: sandbox.root).problems.map { ($0.folder, $0.reason) })
        #expect(reasons["a-empty"] == .noManifest)
        #expect(reasons["b-garbage"] == .unreadableManifest)
        #expect(reasons["c-future"] == .unsupportedSchema(2))
        #expect(reasons["d-hash"] == .invalidID)
        #expect(reasons["e-upper"] == .invalidID)
        #expect(reasons["f-noname"] == .missingName)
        #expect(reasons["g-escape"] == .executableOutsideFolder)
        #expect(reasons["h-absolute"] == .executableOutsideFolder)
        #expect(reasons["i-missing"] == .executableMissing)
        #expect(reasons["j-notexec"] == .executableMissing)
    }

    @Test("A link out of the folder does not count as a program inside it")
    func symlinkOutsideIsRefused() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let directory = try sandbox.add("linked", manifest: Sandbox.manifest(id: "linked", executable: "tool"), script: nil)
        try FileManager.default.createSymbolicLink(
            at: directory.appending(path: "tool"),
            withDestinationURL: URL(fileURLWithPath: "/bin/sh")
        )

        let scan = ExtensionCatalog.scan(in: sandbox.root)
        #expect(scan.extensions.isEmpty)
        #expect(scan.problems.first?.reason == .executableOutsideFolder)
    }

    @Test("Two folders with one id: the first in name order keeps it")
    func duplicateIDs() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.add("one", manifest: Sandbox.manifest(id: "same", name: "First"))
        try sandbox.add("two", manifest: Sandbox.manifest(id: "same", name: "Second"))

        let scan = ExtensionCatalog.scan(in: sandbox.root)
        #expect(scan.extensions.map(\.name) == ["First"])
        #expect(scan.problems == [.init(folder: "two", reason: .duplicateID("same"))])
    }

    @Test("A folder that doesn't exist is no extensions, not an error")
    func missingFolder() {
        let scan = ExtensionCatalog.scan(in: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)"))
        #expect(scan == ExtensionCatalog.Scan())
    }
}

@Suite("Extension report")
struct ExtensionReportTests {
    private let account = AccountKey(.pulseExtension, slot: "acme")

    private func reading(_ json: String) -> ProviderUsage {
        ExtensionReport.reading(from: Data(json.utf8), for: account, now: Date(timeIntervalSince1970: 1_000))
    }

    @Test("Stated percentages and stated amounts are both drawn")
    func limits() throws {
        let usage = reading(#"""
        {"schemaVersion": 1, "plan": " Team ", "limits": [
          {"id": "month", "label": "Monthly requests", "usedPercent": 42.5,
           "resetsAt": "2026-10-01T00:00:00Z", "windowSeconds": 2592000},
          {"label": "Tokens", "used": 30, "limit": 120, "resetsAt": "2026-10-01T00:00:00.250Z"}
        ]}
        """#)

        #expect(usage.state == .live)
        #expect(usage.plan == "Team")
        #expect(usage.origin == .extensionProgram)
        #expect(usage.windows.map(\.id) == ["extension.month", "extension.1"])
        #expect(usage.windows.map(\.name) == ["Monthly requests", "Tokens"])
        #expect(usage.windows[0].usedFraction == 0.425)
        #expect(usage.windows[0].windowSeconds == 2_592_000)
        #expect(usage.windows[0].reportsLength)
        #expect(usage.windows[0].resetsAt == ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z"))
        #expect(usage.windows[1].usedFraction == 0.25)
        // No length stated, so none claimed: the window clock stays empty.
        #expect(!usage.windows[1].reportsLength)
        #expect(usage.windows[1].resetsAt != nil)
    }

    @Test("A limit with no figure is left off rather than drawn at zero")
    func noInventedFigures() {
        let usage = reading(#"""
        {"schemaVersion": 1, "limits": [
          {"label": "No figure"},
          {"label": "Only used", "used": 10},
          {"label": "Zero limit", "used": 1, "limit": 0},
          {"label": "Negative", "usedPercent": -5},
          {"label": "   ", "usedPercent": 10},
          {"label": "Kept", "usedPercent": 110}
        ]}
        """#)

        #expect(usage.windows.map(\.name) == ["Kept"])
        #expect(usage.windows.first?.usedFraction == 1.1)
        #expect(usage.windows.first?.isExhausted == true)
    }

    @Test("Nothing drawable is a reply with no limits in it")
    func emptyReport() {
        #expect(reading(#"{"schemaVersion": 1, "limits": []}"#).state == .unavailable(.noLimitsReported))
        #expect(reading(#"{"schemaVersion": 1}"#).state == .unavailable(.noLimitsReported))
    }

    @Test("A balance with no limits is a reading: money, in the currency stated")
    func balanceOnly() {
        let usage = reading(#"{"schemaVersion": 1, "balance": {"amount": 16.33538288, "currency": "usd"}}"#)
        #expect(usage.state == .live)
        #expect(usage.windows.isEmpty)
        #expect(usage.creditRemaining == .init(amount: 16.33538288, currency: "USD"))
        #expect(usage.creditBalance != nil)
        #expect(usage.origin == .extensionProgram)
    }

    @Test("A balance beside limits is kept, and the limits still drive the ring")
    func balanceAndLimits() {
        let usage = reading(#"""
        {"schemaVersion": 1, "limits": [{"label": "Daily", "usedPercent": 30}],
         "balance": {"amount": -2, "currency": "CNY"}}
        """#)
        #expect(usage.windows.map(\.name) == ["Daily"])
        // Below zero is the service's figure, not a malformed one.
        #expect(usage.creditRemaining == .init(amount: -2, currency: "CNY"))
    }

    @Test("A balance without an amount or a currency code is no balance", arguments: [
        #"{"amount": 5, "currency": "dollars"}"#,
        #"{"amount": 5, "currency": ""}"#,
        #"{"amount": 5, "currency": "U1D"}"#,
        #"{"amount": 5}"#,
        #"{"currency": "USD"}"#,
    ])
    func unusableBalance(balance: String) {
        #expect(reading(#"{"schemaVersion": 1, "balance": \#(balance)}"#).state == .unavailable(.noLimitsReported))
        // And it does not take the limits beside it down with it.
        let beside = reading(#"{"schemaVersion": 1, "balance": \#(balance), "limits": [{"label": "x", "usedPercent": 5}]}"#)
        #expect(beside.windows.count == 1)
        #expect(beside.creditRemaining == nil)
    }

    @Test("An amount written as text is not this schema's number")
    func textAmount() {
        let usage = reading(#"{"schemaVersion": 1, "balance": {"amount": "5", "currency": "USD"}}"#)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @MainActor
    @Test("An extension's balance takes the ring every API account's does")
    func balanceRing() {
        let usage = reading(#"{"schemaVersion": 1, "balance": {"amount": 40, "currency": "USD"}}"#)
        let ringed = BalanceRing.applying(basis: .budget, budget: 100, to: usage,
                                          baselines: BalanceBaselines(file: nil))
        #expect(ringed.windows.map(\.estimate) == [.yourBudget])
        #expect(ringed.windows.first?.usedFraction == 0.6)
        #expect(ringed.windows.first?.isExhausted == false)
    }

    @Test("Named failures map to wording that names no provider", arguments: [
        ("signedOut", ProviderUsage.Unavailability.extensionSignedOut),
        ("unreachable", .unreachable),
        ("rateLimited", .rateLimited),
        ("serverError", .serverError),
        ("noLimits", .noLimitsReported),
        ("somethingElse", .unreadableReply),
    ])
    func statuses(status: String, reason: ProviderUsage.Unavailability) {
        let usage = reading(#"{"schemaVersion": 1, "status": "\#(status)", "limits": [{"label": "x", "usedPercent": 1}]}"#)
        #expect(usage.state == .unavailable(reason))
    }

    @Test("Anything that isn't this schema's object can't be read", arguments: [
        "", "not json", "[]", #"{"limits": []}"#, #"{"schemaVersion": 2, "limits": []}"#,
    ])
    func unreadable(json: String) {
        #expect(reading(json).state == .unavailable(.unreadableReply))
    }

    @Test("A repeated limit id is drawn once")
    func duplicateLimitIDs() {
        let usage = reading(#"""
        {"schemaVersion": 1, "limits": [
          {"id": "a", "label": "First", "usedPercent": 10},
          {"id": "a", "label": "Second", "usedPercent": 20}
        ]}
        """#)
        #expect(usage.windows.map(\.name) == ["First"])
    }

    @Test("A label survives the cache")
    func labelRoundTrip() throws {
        let window = UsageWindow(id: "extension.0", kind: .other(seconds: 0), scope: nil,
                                 usedFraction: 0.5, windowSeconds: 0, resetsAt: nil,
                                 reportsLength: false, label: "Seats")
        let decoded = try JSONDecoder().decode(UsageWindow.self, from: JSONEncoder().encode(window))
        #expect(decoded == window)
        #expect(decoded.name == "Seats")
    }
}

@Suite("Extension runs")
struct ExtensionRunTests {
    private func service(_ script: String, timeout: Double? = nil) throws -> (ExtensionUsageService, Sandbox) {
        let sandbox = try Sandbox()
        try sandbox.add("acme", manifest: Sandbox.manifest(timeout: timeout), script: script)
        let found = try #require(ExtensionCatalog.scan(in: sandbox.root).extensions.first)
        return (ExtensionUsageService(pulseExtension: found), sandbox)
    }

    @Test("What the program prints is the reading")
    func success() async throws {
        let (service, sandbox) = try service("""
        #!/bin/sh
        echo '{"schemaVersion": 1, "limits": [{"label": "Quota", "usedPercent": 64}]}'
        """)
        defer { sandbox.remove() }

        let usage = await service.fetch()
        #expect(usage.state == .live)
        #expect(usage.windows.first?.usedFraction == 0.64)
        #expect(usage.account == AccountKey(.pulseExtension, slot: "acme"))
    }

    @Test("It runs in its own folder and is told which extension it is")
    func environmentAndDirectory() async throws {
        let (service, sandbox) = try service("""
        #!/bin/sh
        if [ "$PULSE_EXTENSION_ID" = acme ] && [ "$PULSE_EXTENSION_SCHEMA" = 1 ] && [ -f pulse-extension.json ]; then
          echo '{"schemaVersion": 1, "limits": [{"label": "ok", "usedPercent": 1}]}'
        else
          echo '{"schemaVersion": 1, "status": "serverError"}'
        fi
        """)
        defer { sandbox.remove() }

        #expect(await service.fetch().state == .live)
    }

    @Test("Pulse's own environment is not handed on, apart from the basics and the proxy")
    func environmentIsMinimal() throws {
        let found = PulseExtension(id: "acme", name: "Acme", directory: URL(fileURLWithPath: "/tmp"),
                                   executable: URL(fileURLWithPath: "/tmp/run"), timeout: 5)
        let environment = ExtensionUsageService.environment(for: found, over: [
            "HOME": "/Users/me", "LANG": "en_US.UTF-8", "HTTPS_PROXY": "http://proxy:8080",
            "OPENAI_API_KEY": "sk-secret", "GITHUB_TOKEN": "ghp_secret", "PATH": "/somewhere/odd",
        ])
        #expect(environment["HOME"] == "/Users/me")
        #expect(environment["LANG"] == "en_US.UTF-8")
        #expect(environment["HTTPS_PROXY"] == "http://proxy:8080")
        #expect(environment["OPENAI_API_KEY"] == nil)
        #expect(environment["GITHUB_TOKEN"] == nil)
        #expect(environment["PATH"]?.hasPrefix("/opt/homebrew/bin:") == true)
        #expect(environment["PULSE_EXTENSION_ID"] == "acme")
    }

    @Test("A program that fails says it failed")
    func failure() async throws {
        let (service, sandbox) = try service("#!/bin/sh\necho oops >&2\nexit 3\n")
        defer { sandbox.remove() }
        #expect(await service.fetch().state == .unavailable(.extensionFailed))
    }

    @Test("A program that never answers is stopped at its time limit")
    func timeout() async throws {
        let (service, sandbox) = try service("#!/bin/sh\nsleep 30\n", timeout: 1)
        defer { sandbox.remove() }

        let started = Date()
        let usage = await service.fetch()
        #expect(usage.state == .unavailable(.extensionTimedOut))
        // The time limit plus the stop's own grace, and nowhere near the
        // thirty seconds the program asked for.
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test("A program deleted since the scan is reported missing")
    func deletedSinceScan() async throws {
        let (service, sandbox) = try service("#!/bin/sh\necho '{}'\n")
        sandbox.remove()
        #expect(await service.fetch().state == .unavailable(.extensionMissing))
    }
}

@Suite("Extension accounts")
@MainActor
struct ExtensionAccountTests {
    private let found = PulseExtension(id: "acme", name: "Acme Quota", directory: URL(fileURLWithPath: "/tmp"),
                                       executable: URL(fileURLWithPath: "/tmp/run"), timeout: 5)

    @Test("A found extension is an account, named by its manifest and off until switched on")
    func accountFromScan() {
        let settings = AppSettings(enabledAccounts: ["claudeCode"])
        settings.apply(ExtensionCatalog.Scan(extensions: [found]))

        #expect(settings.allAccounts.contains(found.account))
        #expect(settings.label(for: found.account) == "Acme Quota")
        #expect(settings.pulseExtension(for: found.account) == found)
        #expect(!settings.shownAccounts.contains(found.account))

        settings.setEnabled(true, for: found.account)
        #expect(settings.shownAccounts.contains(found.account))

        // Taken out of the folder: gone from every list, whatever its switch
        // still says.
        settings.apply(ExtensionCatalog.Scan())
        #expect(!settings.allAccounts.contains(found.account))
        #expect(!settings.shownAccounts.contains(found.account))
    }

    @Test("Its switch survives a launch while its folder is there, and only then")
    func selectionKeepsExtension() {
        let name = "PulseTests.extensionSelection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let builtIn = Set(Provider.builtIn.map(\.rawValue))
        defaults.set(["claudeCode", found.account.id], forKey: ProviderSelection.enabledKey)

        let kept = ProviderSelection.restore(in: defaults, knownAccounts: builtIn.union([found.account.id]), detected: [])
        #expect(kept.enabledAccounts == ["claudeCode", found.account.id])

        let dropped = ProviderSelection.restore(in: defaults, knownAccounts: builtIn, detected: [])
        #expect(dropped.enabledAccounts == ["claudeCode"])
    }

    @Test("The extension type is never offered as a service of its own")
    func notABuiltInProvider() {
        #expect(!Provider.builtIn.contains(.pulseExtension))
        #expect(Provider.builtIn.count == Provider.allCases.count - 1)
        #expect(UsageRoute.soleRoute(for: found.account) == .extensionProgram)
    }

    @Test("A settings link to an extension opens it")
    func link() throws {
        let url = try #require(URL(string: "pulse://account/extension%23acme"))
        #expect(PulseLink(url: url) == .account(found.account))
    }
}
