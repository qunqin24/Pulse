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
/// The token is used to build one request header and is never written, logged
/// or shown anywhere by Pulse.
enum CursorAppLogin {
    /// Everything a request needs, and nothing more — callers never see the
    /// token itself.
    struct Session: Sendable {
        let cookie: String
    }

    private static var database: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    private static let tokenKey = "cursorAuth/accessToken"

    /// A minute's headroom. A token that expires while the request is in
    /// flight comes back refused, and nothing here can renew it — Cursor does
    /// that for itself, the next time it is used.
    private static let expiryHeadroom: TimeInterval = 60

    static func session() -> Session? {
        guard
            let token = accessToken(),
            let claims = claims(in: token),
            let subject = claims["sub"] as? String,
            let expiry = claims["exp"] as? Double,
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

    /// Whether Cursor has ever been signed in here — the file's presence, not
    /// its contents, so this stays cheap enough to ask on a first run.
    static func hasStoredLogin() -> Bool {
        FileManager.default.fileExists(atPath: database.path)
    }

    // MARK: - The database

    /// Opened read-only, in place.
    ///
    /// Cursor is usually running, which means the database is in WAL mode and
    /// its `-wal` and `-shm` sidecars belong to that process. Copying the file
    /// aside would take the main database without the journal holding the
    /// newest writes, and opening it writable would touch a directory that
    /// isn't ours. Read-only leaves all three alone.
    private static func accessToken() -> String? {
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
}
