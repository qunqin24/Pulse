import AppKit
import CommonCrypto
import Foundation
import SQLite3

/// Reading one site's session cookie out of the browser the user signed in
/// with, so they don't have to copy it from developer tools by hand.
///
/// **Only one host's cookies are ever looked at, and only the names that
/// actually authenticate survive** — the caller passes a filter and everything
/// else is dropped before it leaves this file. Nothing is stored here; what
/// comes back goes straight into the caller's own encrypted store.
///
/// This exists because Ollama has no quota API at all: the figures come from a
/// signed-in page, so a browser session is the only credential there is. Every
/// other provider in Pulse borrows a login its own tool stored, which is
/// cheaper and quieter, and none of them needs this.
///
/// **What it costs is different per browser, and the user has to be told.**
/// Firefox keeps cookies in plain SQLite and needs no permission at all.
/// Safari's file is inside its container and needs Full Disk Access, which is
/// granted per application — so a `swift run` build cannot have it and only
/// the bundled app can. Chromium encrypts its values with a key kept in the
/// login keychain, so reading them raises the "Pulse wants to use your
/// confidential information" prompt.
///
/// **The default browser is tried first regardless**, which is a decision
/// taken deliberately over trying the free ones first. The browser the user
/// opens links with is where they are actually signed in; the others may hold
/// a session that is months stale, and finding *that* is worse than a prompt.
/// Each browser is independent: one failing tells the next nothing.
enum BrowserCookies {
    enum Browser: String, CaseIterable, Identifiable, Sendable {
        var id: String { rawValue }

        case firefox
        case safari
        case chrome
        case edge
        case brave
        case vivaldi
        case arc

        var name: String {
            switch self {
            case .firefox: "Firefox"
            case .safari: "Safari"
            case .chrome: "Chrome"
            case .edge: "Edge"
            case .brave: "Brave"
            case .vivaldi: "Vivaldi"
            case .arc: "Arc"
            }
        }

        /// What the browser calls its key in the login keychain.
        ///
        /// **Not the display name**, which is the mistake this replaced: Edge
        /// is shown as "Edge" and stores its key under "Microsoft Edge Safe
        /// Storage", so building the service name from the display name found
        /// nothing, failed silently, and fell through to the next browser —
        /// which then reported having read the cookie from somewhere the user
        /// never signed in.
        var keychainService: String? {
            switch self {
            case .firefox, .safari: nil
            case .chrome: "Chrome Safe Storage"
            case .edge: "Microsoft Edge Safe Storage"
            case .brave: "Brave Safe Storage"
            case .vivaldi: "Vivaldi Safe Storage"
            case .arc: "Arc Safe Storage"
            }
        }

        /// Whether reading this one raises a prompt the user has to answer.
        /// Asked before anything is attempted, so the prompt is never a
        /// surprise.
        var promptsForKeychain: Bool {
            switch self {
            case .firefox, .safari: false
            case .chrome, .edge, .brave, .vivaldi, .arc: true
            }
        }
    }

    struct Found: Sendable {
        let browser: Browser
        let header: String
    }

    /// Every cookie found for `host`, browser by browser, quietest first.
    ///
    /// `keep` is the caller's filter: it is handed a `name=value; …` header and
    /// returns what is worth keeping, or nil. Anything it does not keep is
    /// discarded here and never leaves the process.
    static func session(
        forHost host: String,
        allowing browsers: [Browser] = Browser.allCases,
        keep: (String) -> String?
    ) -> Found? {
        for browser in browsers {
            let pairs: [(String, String)]
            switch browser {
            case .firefox: pairs = firefox(host: host)
            case .safari: pairs = safari(host: host)
            default: pairs = chromium(browser, host: host)
            }

            guard !pairs.isEmpty else { continue }
            let header = pairs.map { "\($0.0)=\($0.1)" }.joined(separator: "; ")
            if let kept = keep(header) { return Found(browser: browser, header: kept) }
        }

        return nil
    }

    /// Which browsers are actually installed and have a cookie store, **the
    /// default one first** — so the first thing tried is where the session
    /// actually is, and the UI can say what it is about to open.
    static func present(_ browsers: [Browser] = Browser.allCases) -> [Browser] {
        let installed = browsers.filter { browser in
            switch browser {
            case .firefox: !firefoxStores().isEmpty
            case .safari: !safariStores().isEmpty
            default: !chromiumStores(browser).isEmpty
            }
        }

        // Moved to the front rather than sorted: "is it the default" is not an
        // ordering, and `sorted` given something that isn't one is free to
        // return anything at all.
        guard let preferred = preferred(), installed.contains(preferred) else { return installed }
        return [preferred] + installed.filter { $0 != preferred }
    }

    /// The browser this Mac opens links with.
    ///
    /// Asked of LaunchServices rather than guessed from what is installed:
    /// having Chrome on disk says nothing about whether it is ever used.
    static func preferred() -> Browser? {
        guard
            let https = URL(string: "https://example.com"),
            let application = NSWorkspace.shared.urlForApplication(toOpen: https),
            let bundle = Bundle(url: application)?.bundleIdentifier
        else { return nil }

        return switch bundle {
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview": .safari
        case "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition": .firefox
        case "com.google.Chrome", "com.google.Chrome.canary": .chrome
        case "com.microsoft.edgemac", "com.microsoft.edgemac.Beta": .edge
        case "com.brave.Browser", "com.brave.Browser.beta": .brave
        case "com.vivaldi.Vivaldi": .vivaldi
        case "company.thebrowser.Browser": .arc
        default: nil
        }
    }

    // MARK: - Where each browser keeps them

    private static var home: URL { URL(fileURLWithPath: NSHomeDirectory()) }

    private static func firefoxStores() -> [URL] {
        let root = home.appending(path: "Library/Application Support/Firefox/Profiles")
        let profiles = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return profiles
            .map { $0.appending(path: "cookies.sqlite") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func safariStores() -> [URL] {
        [
            home.appending(path: "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"),
            home.appending(path: "Library/Cookies/Cookies.binarycookies"),
        ].filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func chromiumRoot(_ browser: Browser) -> URL? {
        let support = home.appending(path: "Library/Application Support")
        return switch browser {
        case .chrome: support.appending(path: "Google/Chrome")
        case .edge: support.appending(path: "Microsoft Edge")
        case .brave: support.appending(path: "BraveSoftware/Brave-Browser")
        case .vivaldi: support.appending(path: "Vivaldi")
        case .arc: support.appending(path: "Arc/User Data")
        case .firefox, .safari: nil
        }
    }

    private static func chromiumStores(_ browser: Browser) -> [URL] {
        guard let root = chromiumRoot(browser) else { return [] }

        let profiles = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent == "Default" || $0.lastPathComponent.hasPrefix("Profile ") }

        return profiles
            .flatMap { [$0.appending(path: "Network/Cookies"), $0.appending(path: "Cookies")] }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Firefox: plain SQLite, no permission at all

    private static func firefox(host: String) -> [(String, String)] {
        for store in firefoxStores() {
            let rows = query(
                store,
                "SELECT name, value FROM moz_cookies WHERE host = ? OR host = ? OR host LIKE ?",
                [host, ".\(host)", "%.\(host)"]
            ) { statement -> (String, String)? in
                guard
                    let name = sqlite3_column_text(statement, 0),
                    let value = sqlite3_column_text(statement, 1)
                else { return nil }
                return (String(cString: name), String(cString: value))
            }
            if !rows.isEmpty { return rows }
        }

        return []
    }

    // MARK: - Chromium: SQLite, values encrypted with a key from the keychain

    private static func chromium(_ browser: Browser, host: String) -> [(String, String)] {
        guard let key = chromiumKey(browser) else { return [] }

        for store in chromiumStores(browser) {
            let rows = query(
                store,
                "SELECT name, encrypted_value FROM cookies WHERE host_key = ? OR host_key = ? OR host_key LIKE ?",
                [host, ".\(host)", "%.\(host)"]
            ) { statement -> (String, String)? in
                guard
                    let name = sqlite3_column_text(statement, 0),
                    let blob = sqlite3_column_blob(statement, 1)
                else { return nil }

                let count = Int(sqlite3_column_bytes(statement, 1))
                let encrypted = Data(bytes: blob, count: count)
                guard let value = decrypt(encrypted, with: key) else { return nil }
                return (String(cString: name), value)
            }
            if !rows.isEmpty { return rows }
        }

        return []
    }

    /// The browser's own storage key, which lives in the login keychain — this
    /// is the read that raises the prompt.
    private static func chromiumKey(_ browser: Browser) -> Data? {
        guard let service = browser.keychainService else { return nil }

        var request: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        // Brave and Arc name the account differently from the service in some
        // versions, so the account is left unconstrained.
        request[kSecAttrAccount as String] = nil

        var item: CFTypeRef?
        guard
            SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
            let password = item as? Data
        else { return nil }

        // Chromium's own parameters, unchanged since the scheme was
        // introduced: PBKDF2-SHA1 over the keychain password, a fixed salt,
        // 1003 rounds, 16 bytes out.
        var key = Data(count: 16)
        let derived = key.withUnsafeMutableBytes { out in
            password.withUnsafeBytes { secret in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    secret.baseAddress, secret.count,
                    "saltysalt", 9,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                    out.baseAddress, 16
                )
            }
        }
        return derived == kCCSuccess ? key : nil
    }

    /// AES-128-CBC with an all-spaces IV, after the version prefix.
    ///
    /// Internal for the same reason the binary format is: it can be driven
    /// against a value encrypted on purpose with a known key, which settles
    /// the padding, the prefix and the newer 32-byte hash without going near
    /// anyone's real cookies or their keychain.
    static func decrypt(_ encrypted: Data, with key: Data) -> String? {
        guard encrypted.count > 3 else { return nil }

        let prefix = String(decoding: encrypted.prefix(3), as: UTF8.self)
        guard prefix == "v10" || prefix == "v11" else {
            // Not encrypted at all on some older profiles.
            return String(data: encrypted, encoding: .utf8)
        }

        let body = encrypted.dropFirst(3)
        var out = Data(count: body.count + kCCBlockSizeAES128)
        var moved = 0

        let status = out.withUnsafeMutableBytes { output in
            body.withUnsafeBytes { input in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyBytes.baseAddress, 16,
                        String(repeating: " ", count: 16),
                        input.baseAddress, input.count,
                        output.baseAddress, output.count,
                        &moved
                    )
                }
            }
        }
        guard status == kCCSuccess else { return nil }

        out = out.prefix(moved)
        if let text = String(data: out, encoding: .utf8) { return text }

        // Newer profiles prepend a 32-byte hash of the host to the value.
        guard out.count > 32, let text = String(data: out.dropFirst(32), encoding: .utf8) else { return nil }
        return text
    }

    // MARK: - Safari: a binary file, behind Full Disk Access

    /// Apple's `binarycookies` format: a header, then pages, then cookies with
    /// their strings at offsets from each record's own start.
    private static func safari(host: String) -> [(String, String)] {
        for store in safariStores() {
            guard let data = try? Data(contentsOf: store) else { continue }
            let found = binaryCookies(data, host: host)
            if !found.isEmpty { return found }
        }

        return []
    }

    /// Internal rather than private so the format can be driven against a file
    /// built on purpose — a binary parser is exactly the kind of thing that
    /// looks right and reads the wrong four bytes, and nobody's real cookies
    /// need to be opened to find that out.
    static func binaryCookies(_ data: Data, host: String) -> [(String, String)] {
        guard data.count > 8, data.prefix(4) == Data("cook".utf8) else { return [] }

        var found: [(String, String)] = []
        do {
            // The page table is big-endian; everything inside a page is little.
            // Reading either one the other way gives sizes in the millions and
            // a parser that walks off the end, which is why this is testable.
            let pageCount = Int(be32(data, at: 4))
            var sizes: [Int] = []
            var cursor = 8
            for _ in 0..<pageCount {
                guard cursor + 4 <= data.count else { break }
                sizes.append(Int(be32(data, at: cursor)))
                cursor += 4
            }

            for size in sizes {
                let page = cursor
                cursor += size
                guard cursor <= data.count, page + 8 <= data.count else { break }

                let cookieCount = Int(le32(data, at: page + 4))
                for index in 0..<cookieCount {
                    let offsetAt = page + 8 + index * 4
                    guard offsetAt + 4 <= data.count else { break }
                    let record = page + Int(le32(data, at: offsetAt))
                    guard record + 48 <= data.count else { continue }

                    // Scoped to the host, exactly as the two SQL routes are.
                    // `hasSuffix` is not that test: asking for `ollama.com`
                    // also matched `notollama.com` and `evil-ollama.com`,
                    // which are unrelated registrable domains — and whatever
                    // it returned would have been joined into the header sent
                    // to the real one.
                    let url = string(data, at: record + Int(le32(data, at: record + 16)))
                    guard url == host || url == "." + host || url.hasSuffix("." + host)
                    else { continue }

                    let name = string(data, at: record + Int(le32(data, at: record + 20)))
                    let value = string(data, at: record + Int(le32(data, at: record + 28)))
                    if !name.isEmpty, !value.isEmpty { found.append((name, value)) }
                }
            }

            if !found.isEmpty { return found }
        }

        return []
    }

    private static func be32(_ data: Data, at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for byte in data[data.startIndex + offset..<data.startIndex + offset + 4] {
            value = value << 8 | UInt32(byte)
        }
        return value
    }

    private static func le32(_ data: Data, at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for (shift, byte) in data[data.startIndex + offset..<data.startIndex + offset + 4].enumerated() {
            value |= UInt32(byte) << (8 * shift)
        }
        return value
    }

    private static func string(_ data: Data, at offset: Int) -> String {
        guard offset > 0, offset < data.count else { return "" }
        var end = data.startIndex + offset
        while end < data.endIndex, data[end] != 0 { end = data.index(after: end) }
        return String(decoding: data[(data.startIndex + offset)..<end], as: UTF8.self)
    }

    // MARK: - SQLite, read-only and in place

    /// Opened read-only: the browser may be running, and its journal belongs
    /// to that process — the same reason `CursorAppLogin` does not copy the
    /// file aside.
    private static func query<T>(
        _ file: URL,
        _ sql: String,
        _ bindings: [String],
        _ read: (OpaquePointer?) -> T?
    ) -> [T] {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(file.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return []
        }
        defer { sqlite3_close(handle) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, binding) in bindings.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), binding, -1, transient)
        }

        var rows: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let row = read(statement) { rows.append(row) }
        }
        return rows
    }
}
