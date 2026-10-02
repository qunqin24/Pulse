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
        guard
            sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
            let database = handle
        else {
            sqlite3_close(handle)
            return nil
        }
        defer { sqlite3_close(database) }
        return body(database)
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
