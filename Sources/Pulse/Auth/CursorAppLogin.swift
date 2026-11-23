// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import SQLite3

/// The login Cursor already keeps on this Mac, turned into what its account
/// pages ask for.
///
/// Cursor is an editor built on VS Code, so its own OAuth token sits in the
/// SQLite database VS Code keeps global state in. The website, though,
/// authenticates with a **cookie** rather than a bearer header — and that
/// cookie is not stored anywhere to be found. It is *built*: the account id is
/// the tail of the token's own `sub` claim, and the cookie's value is that id
/// and the token joined by `::`.
///
/// Which is the whole reason this provider needs nothing from the user. The
/// obvious route to a site cookie is to go and read the browser's, which means
/// touching Safari's and Chrome's cookie stores for every domain they hold;
/// this asks the editor for its own login instead, exactly as the Claude Code
/// and Codex routes do.
///
/// Recent Cursor builds seal that row with Electron's safeStorage before they
/// write it (`cursor-safe-storage:v1:` plus a `v10` ciphertext). The key is the
/// same shape Chromium keeps for cookies — `Cursor Safe Storage` in the login
/// keychain — and is opened through `BrowserCookies.safeStorageKey`, the same
/// helper Claude Desktop and the browser routes already use. An older plaintext
/// JWT is still accepted as it stands.
///
/// The token is used to build one request header and is never written, logged
/// or shown anywhere by Pulse.
enum CursorAppLogin {
    /// Everything a request needs, and nothing more — callers never see the
    /// token itself.
    struct Session: Equatable, Sendable {
        let cookie: String
    }

    /// What reading the editor's stored login produced, before a cookie is
    /// built from it.
    enum Load: Equatable, Sendable {
        /// A usable JWT.
        case token(String)
        /// No `cursorAuth/accessToken` row, or one that could not be read.
        case absent
        /// The row is sealed and the keychain did not hand the key over —
        /// denied, dismissed, or not yet asked. Distinct from a spent login:
        /// opening Cursor will not help, and Refresh will ask again.
        case keychainRefused
        /// The row is sealed, a key was handed over, and it does not open
        /// it — Cursor has a new key, or wrote something this cannot read.
        case unreadable
    }

    private static var database: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    private static let tokenKey = "cursorAuth/accessToken"

    /// Prefix Cursor writes when `authTokenEncryptionAtRest` is on. The rest of
    /// the cell is standard base64 of a Chromium `v10`/`v11` ciphertext.
    static let sealedPrefix = "cursor-safe-storage:v1:"

    /// Keychain service for Cursor's Electron safeStorage key. Named in full —
    /// never derived from a display string — for the same reason Edge is
    /// `Microsoft Edge Safe Storage`.
    static let keychainService = "Cursor Safe Storage"

    /// A minute's headroom. A token that expires while the request is in
    /// flight comes back refused, and nothing here can renew it — Cursor does
    /// that for itself, the next time it is used.
    private static let expiryHeadroom: TimeInterval = 60

    static func session() -> Session? {
        if case .token(let token) = load() {
            return session(from: token)
        }
        return nil
    }

    /// The stored row, unsealed when Cursor sealed it. Callers that only need
    /// a cookie use `session()`; this is the seam tests and the unavailable
    /// reasons drive.
    static func load() -> Load {
        guard let stored = storedValue() else { return .absent }
        let loaded = plaintext(fromStored: stored, keychainKey: { CursorKeychain.key() })
        guard loaded == .unreadable else { return loaded }
        // The kept key no longer opens the row: Cursor has made a new one
        // (reinstalled, or its keychain item deleted). Forget it and read the
        // keychain once more — macOS asks about the new item once, whatever
        // was allowed for the old one.
        CursorKeychain.forget()
        return plaintext(fromStored: stored, keychainKey: { CursorKeychain.key() })
    }

    /// Unwrap a stored cell into a JWT.
    ///
    /// `keychainKey` is a closure so a sealed row that is not needed (the
    /// value is already plaintext) never touches the keychain, and so a test
    /// can hand in a key derived from a password it chose.
    static func plaintext(
        fromStored value: String,
        keychainKey: () -> Data?
    ) -> Load {
        guard value.hasPrefix(sealedPrefix) else { return .token(value) }

        guard let key = keychainKey() else { return .keychainRefused }

        let encoded = String(value.dropFirst(sealedPrefix.count))
        guard
            let encrypted = Data(base64Encoded: encoded),
            let plain = BrowserCookies.decrypt(encrypted, with: key),
            !plain.isEmpty
        else { return .unreadable }

        return .token(plain)
    }

    /// The same cookie built out of a token from somewhere else — an account
    /// Pulse signed in to itself, whose token never goes near the editor's
    /// database. The arithmetic is the token's own, so it lives here beside
    /// the reader rather than being written a second time.
    static func session(from token: String) -> Session? {
        guard
            let claims = claims(in: token),
            let subject = claims["sub"] as? String,
            let expiry = number(claims["exp"]),
            Date(timeIntervalSince1970: expiry).timeIntervalSinceNow > expiryHeadroom,
            // "auth0|user_abc" — the account id is the half after the bar, and
            // a subject with no bar in it is already the id.
            let account = subject.split(separator: "|").last.map(String.init),
            !account.isEmpty
        else { return nil }

        // `%3A%3A` is `::` encoded, which is how the value appears in the
        // cookie the site sets for itself.
        return Session(cookie: "WorkosCursorSessionToken=\(account)%3A%3A\(token)")
    }

    /// When a token stops being accepted, read from the token itself. Cursor
    /// issues these for **60 days** — measured against this Mac's own, which
    /// is why an account Pulse signs in to here does not need renewing every
    /// few hours the way a Codex or Claude Code login does.
    static func expiry(of token: String) -> Date? {
        number(claims(in: token)?["exp"]).map(Date.init(timeIntervalSince1970:))
    }

    /// Whether a token is stored at all, as against a *usable* one.
    ///
    /// The difference decides what the user is told. A token that is present
    /// but past its life means they are signed in and Cursor needs opening to
    /// renew it — a different remedy from signing in, and the wrong one to be
    /// given when the right one is already written. A sealed row whose key was
    /// refused is still "stored": the editor signed in; the keychain is what
    /// is missing.
    static func hasStoredToken() -> Bool { storedValue() != nil }

    /// Whether Cursor has ever been signed in here — the file's presence, not
    /// its contents, so this stays cheap enough to ask on a first run.
    static func hasStoredLogin() -> Bool {
        FileManager.default.fileExists(atPath: database.path)
    }

    // MARK: - The database

    /// The cell as Cursor wrote it — plaintext JWT or sealed blob — before any
    /// keychain touch.
    ///
    /// Opened read-only, in place. Cursor is usually running, which means the
    /// database is in WAL mode and its `-wal` and `-shm` sidecars belong to
    /// that process. Copying the file aside would take the main database
    /// without the journal holding the newest writes, and opening it writable
    /// would touch a directory that isn't ours. Read-only leaves all three
    /// alone.
    private static func storedValue() -> String? {
        guard FileManager.default.fileExists(atPath: database.path) else { return nil }

        var handle: OpaquePointer?
        guard sqlite3_open_v2(database.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return nil
        }
        defer { sqlite3_close(handle) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            handle,
            "SELECT value FROM ItemTable WHERE key = ? LIMIT 1",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, tokenKey, -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        switch sqlite3_column_type(statement, 0) {
        case SQLITE_TEXT:
            return sqlite3_column_text(statement, 0).map { String(cString: $0) }
        case SQLITE_BLOB:
            guard let bytes = sqlite3_column_blob(statement, 0) else { return nil }
            return text(in: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0))))
        default:
            return nil
        }
    }

    /// SQLite's "copy this before returning", which has no Swift constant.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// The row is normally text, and has been seen as a blob. When it is, it
    /// is UTF-16 with no byte-order mark — read as UTF-8 that comes out as the
    /// token with a null byte after every character, which is a string, parses
    /// as nothing, and explains itself to nobody. The zero in the second byte
    /// of an ASCII-range character is what gives it away.
    private static func text(in data: Data) -> String? {
        if data.count >= 2, data.count.isMultiple(of: 2), data[data.startIndex] != 0,
           data[data.index(after: data.startIndex)] == 0,
           let wide = String(data: data, encoding: .utf16LittleEndian) {
            return wide
        }

        return String(data: data, encoding: .utf8)
    }

    // MARK: - The token

    /// The token's middle section, which is where `sub` and `exp` live.
    ///
    /// Base64**URL**, and unpadded — neither of which `Data(base64Encoded:)`
    /// accepts as it stands.
    private static func claims(in token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }

        var encoded = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)

        guard
            let data = Data(base64Encoded: encoded),
            let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        return claims
    }

    /// `JSONSerialization` hands numbers back as `NSNumber`; a bare `as? Double`
    /// misses the integer form Cursor puts in `exp`.
    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: value
        case let value as Int: Double(value)
        case let value as NSNumber: value.doubleValue
        default: nil
        }
    }
}

/// Cursor's safeStorage key, asked of the login keychain as seldom as the
/// reader allows.
///
/// **Not once per refresh.** Every read of the item raises macOS's "Pulse
/// wants to use your confidential information" unless the reader chose Always
/// Allow, and Cursor and Grok Bot both borrow this login — so asking on each
/// automatic pass put the dialog up every few minutes, twice. Instead:
///
/// - A key handed over is kept in memory until Pulse quits; never written.
/// - Refused (denied or dismissed), it is not asked again by an automatic
///   pass until Pulse is next launched, but a manual refresh of Cursor or
///   Grok Bot asks at once (`allowAsking`).
/// - The two providers' reads wait on one another, so one pass asks once.
/// - A kept key that stops opening the row is forgotten (`forget`) and the
///   keychain is read once more.
enum CursorKeychain {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var kept: Data?
    nonisolated(unsafe) private static var refused = false

    /// The key, from memory or the keychain; nil when refused, or when asking
    /// is held back after a refusal. `read` stands in for the keychain in
    /// tests.
    static func key(
        read: () -> Data? = { BrowserCookies.safeStorageKey(service: CursorAppLogin.keychainService) }
    ) -> Data? {
        // Held across the read, so a second caller waits for the first
        // dialog's answer instead of raising its own.
        lock.lock()
        defer { lock.unlock() }
        if let kept { return kept }
        guard !refused else { return nil }
        let key = read()
        kept = key
        refused = key == nil
        return key
    }

    /// A manual refresh: the next read may ask the keychain again.
    static func allowAsking() {
        lock.withLock { refused = false }
    }

    /// The kept key no longer opens the row.
    static func forget() {
        lock.withLock { kept = nil }
    }

    /// Back to a fresh launch, for tests.
    static func reset() {
        lock.withLock {
            kept = nil
            refused = false
        }
    }
}
