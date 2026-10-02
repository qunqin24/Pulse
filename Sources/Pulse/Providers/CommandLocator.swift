// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Where a command-line tool installed by a package manager tends to live.
///
/// A GUI app inherits almost no `PATH`, so a tool the user runs every day in
/// a terminal is not found by name from here. These are the places the common
/// installers put one — Homebrew, the tools' own installers, bun, Volta, npm
/// and pnpm globals — and the version folders Node version managers keep.
enum CommandLocator {
    /// Folders that hold the command directly, in the order they are tried.
    static func directories(home: String) -> [String] {
        [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.bun/bin",
            "\(home)/.volta/bin",
            "\(home)/.npm-global/bin",
            "\(home)/Library/pnpm",
        ]
    }

    /// The command under every Node version manager's version folders, newest
    /// version first. `versions` lists a folder, so a test needs no disk.
    static func managed(_ name: String, home: String, versions: (String) -> [String]) -> [String] {
        let managers: [(root: String, bin: String)] = [
            ("\(home)/.nvm/versions/node", "bin"),
            ("\(home)/Library/Application Support/fnm/node-versions", "installation/bin"),
            ("\(home)/.local/share/fnm/node-versions", "installation/bin"),
            ("\(home)/.local/share/mise/installs/node", "bin"),
        ]
        return managers.flatMap { manager in
            versions(manager.root).reversed().map { "\(manager.root)/\($0)/\(manager.bin)/\(name)" }
        }
    }

    /// `PATH` first, then `extra`, then the usual folders, then the managers.
    static func candidates(
        _ name: String,
        home: String,
        path: String?,
        extra: [String] = [],
        versions: (String) -> [String]
    ) -> [String] {
        (path ?? "").split(separator: ":").map { "\($0)/\(name)" }
            + extra
            + directories(home: home).map { "\($0)/\(name)" }
            + managed(name, home: home, versions: versions)
    }

    /// The first executable candidate on this Mac.
    static func locate(_ name: String, extra: [String] = []) -> URL? {
        let fileManager = FileManager.default
        return candidates(
            name,
            home: NSHomeDirectory(),
            path: ProcessInfo.processInfo.environment["PATH"],
            extra: extra,
            versions: { (try? fileManager.contentsOfDirectory(atPath: $0))?.sorted() ?? [] }
        )
        .first { fileManager.isExecutableFile(atPath: $0) }
        .map { URL(fileURLWithPath: $0) }
    }
}
