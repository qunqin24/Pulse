// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import SQLite3

/// Read-only SQLite access for the agents that keep their records in a
/// database.
///
/// **Open read-only and never write.** `SQLITE_OPEN_READONLY` will not create
/// a missing file and cannot modify an existing one, which matters because the
/// database belongs to another application that may be running: Pulse reads
/// its journal in place and leaves it exactly as it found it.
///
/// **A closed WAL database is opened as immutable.** A read-only connection
/// to a WAL-mode database needs its `-shm` file, and may not create one. While
/// the owner has the database open, `-wal` and `-shm` exist and the ordinary
/// open works. When the owner closes it, SQLite checkpoints the log into the
/// `.db` and deletes both files, and every later read-only query fails with
/// `SQLITE_CANTOPEN` (Antigravity's conversation stores, #117). With neither
/// file present the `.db` holds every committed page, so `immutable=1` reads
/// exactly what is there, still without writing or creating anything.
///
/// A database whose schema does not match — no table, no column, an older
/// version — simply yields no rows. A failed `prepare` is an ordinary outcome
/// here, not an error to surface, so a reader built against one shape stays
/// silent rather than throwing against another.
enum AgentSQLite {
    /// Opens `url` read-only and hands the connection to `body`.
    ///
    /// Nil when the file is missing or cannot be opened. The connection is
    /// closed on every path out, including after `body` returns.
    static func read<T>(at url: URL, _ body: (OpaquePointer) -> T) -> T? {
        guard !Task.isCancelled else { return nil }
        var handle: OpaquePointer?
        let opened = isClosedWAL(url)
            ? sqlite3_open_v2(immutableURI(url), &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
            : sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil)
        guard opened == SQLITE_OK, let database = handle else {
            sqlite3_close(handle)
            return nil
        }
        defer { sqlite3_close(database) }
        return body(database)
    }

    /// Whether `url` is a WAL-mode database with neither `-wal` nor `-shm`
    /// beside it: one its owner has closed, which a read-only open cannot read.
    ///
    /// The mode comes from the file header (bytes 18 and 19 are 2 for WAL), so
    /// a rollback-journal database is never opened as immutable: its writer
    /// changes the `.db` in place, and an immutable read takes no lock. A
    /// `-wal` left without its `-shm` may hold pages the `.db` lacks, so that
    /// case keeps the ordinary open rather than reading stale pages.
    static func isClosedWAL(_ url: URL) -> Bool {
        let manager = FileManager.default
        guard
            !manager.fileExists(atPath: url.path + "-wal"),
            !manager.fileExists(atPath: url.path + "-shm"),
            let file = try? FileHandle(forReadingFrom: url)
        else { return false }
        defer { try? file.close() }
        guard let header = try? file.read(upToCount: 20), header.count == 20 else { return false }
        return header[18] == 2 && header[19] == 2
    }

    /// `url` as an SQLite URI that opens it immutable. The path is
    /// percent-encoded, so a space, `?` or `#` in it stays part of the path.
    private static func immutableURI(_ url: URL) -> String {
        URL(fileURLWithPath: url.path).absoluteString + "?immutable=1"
    }

    /// Runs `sql` and calls `body` once per row.
    ///
    /// A statement that will not prepare yields nothing and no error; this is
    /// how a schema mismatch reads as "no rows" rather than as a failure.
    static func each(_ db: OpaquePointer, sql: String, _ body: (OpaquePointer) -> Void) {
        guard !Task.isCancelled else { return }
        // Also interrupts an expensive query *before* it produces its first
        // row. Checking only sqlite3_step's result cannot stop a JOIN/sort.
        sqlite3_progress_handler(db, 1_000, { _ in Task.isCancelled ? 1 : 0 }, nil)
        defer { sqlite3_progress_handler(db, 0, nil, nil) }
        var statement: OpaquePointer?
        guard
            sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
            let prepared = statement
        else {
            sqlite3_finalize(statement)
            return
        }
        defer { sqlite3_finalize(prepared) }
        while !Task.isCancelled, sqlite3_step(prepared) == SQLITE_ROW {
            autoreleasepool { body(prepared) }
        }
    }

    /// A column as a string. NULL is nil, never the empty string.
    static func text(_ stmt: OpaquePointer, column: Int32) -> String? {
        guard
            sqlite3_column_type(stmt, column) != SQLITE_NULL,
            let pointer = sqlite3_column_text(stmt, column)
        else { return nil }
        return String(cString: pointer)
    }

    /// A column as a blob. NULL is nil; a zero-length blob is empty `Data`.
    static func data(_ stmt: OpaquePointer, column: Int32) -> Data? {
        guard sqlite3_column_type(stmt, column) != SQLITE_NULL else { return nil }
        let length = sqlite3_column_bytes(stmt, column)
        guard length > 0 else { return Data() }
        guard let pointer = sqlite3_column_blob(stmt, column) else { return nil }
        return Data(bytes: pointer, count: Int(length))
    }
}
