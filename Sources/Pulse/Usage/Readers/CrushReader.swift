// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Crush's project registry and the per-project databases it references.
///
/// Crush keeps a `projects.json` registry whose `projects[]` entries name a
/// working `path` and a `data_dir`; the database is `<data_dir>/crush.db` when
/// that is absolute, else `<path>/<data_dir>/crush.db`.
///
/// **There are no token records here, by design.** The schema's per-message
/// token columns are not trustworthy and the only figure Crush reports is a
/// session `cost` in dollars. Pulse's money comes from tokens at published
/// rates, so converting a cost back into tokens would be inventing a count
/// nobody measured — the exact thing this boundary forbids. `records` is
/// therefore empty, and **inputs are still declared** so the store is watched
/// and the UI can mark it as recognised-but-without-token-counts rather than
/// silently absent.
enum CrushReader {
    /// The registry candidates — every one watched, so a registry appearing
    /// later moves the fingerprint — plus every project database an existing
    /// registry references.
    static func inputs(home: URL, environment: [String: String]) -> [URL] {
        var roots: [URL] = []

        var candidates: [URL] = []
        if let global = DatabaseReaderSupport.environment("CRUSH_GLOBAL_DATA", environment) {
            candidates.append(DatabaseReaderSupport.directory(global).appending(path: "projects.json"))
        }
        candidates.append(
            DatabaseReaderSupport.xdgDataHome(home: home, environment: environment)
                .appending(path: "crush/projects.json")
        )
        if let local = DatabaseReaderSupport.localAppData(environment: environment) {
            candidates.append(local.appending(path: "crush/projects.json"))
        }
        candidates.append(home.appending(path: "AppData/Local/crush/projects.json"))

        for registry in candidates {
            // The registry itself is a real input: adding or removing a
            // project changes it without touching any database's stamp.
            roots.append(registry)
            roots.append(contentsOf: databases(in: registry))
        }
        return roots
    }

    /// **No records.** Crush reports cost, not tokens, and a cost is not a
    /// token count. See the type's own note.
    static func records(roots: [URL]) -> [AgentUsageRecord] { [] }

    /// The database each project in a registry names, with `..` resolved.
    private static func databases(in registry: URL) -> [URL] {
        guard
            let json = AgentLogIO.json(at: registry),
            let object = AgentLogIO.object(json),
            let projects = object["projects"] as? [[String: Any]]
        else { return [] }

        return projects.compactMap { project in
            guard
                let path = AgentLogIO.text(project["path"]),
                let dataDir = AgentLogIO.text(project["data_dir"])
            else { return nil }

            let directory: URL
            if dataDir.hasPrefix("/") {
                directory = URL(fileURLWithPath: dataDir, isDirectory: true)
            } else {
                directory = URL(fileURLWithPath: path, isDirectory: true)
                    .appending(path: dataDir, directoryHint: .isDirectory)
            }
            return directory.appending(path: "crush.db").standardizedFileURL
        }
    }
}
