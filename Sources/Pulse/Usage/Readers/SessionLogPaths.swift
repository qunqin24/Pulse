// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Where each Group A client keeps its records.
///
/// **Only documented roots.** A path here is one the client's own format
/// specification names; nothing is inferred by walking the home directory for
/// something that looks right, because a guessed root reads the wrong tree and
/// produces a number nobody can check. A missing root is still returned: the
/// caller decides whether a client is present.
///
/// The environment keys are honoured exactly where the format facts say the
/// client honours them, and deliberately **not** where two clients share one
/// (`PI_CODING_AGENT_DIR` is read by both Pi and omp, so neither uses it here —
/// watching it twice would double-count one tree).
enum SessionLogPaths {
    static func inputs(client: String, home: URL, environment: [String: String]) -> [URL] {
        switch client {
        case "pi":
            [home.appending(path: ".pi/agent/sessions")]
        case "omp":
            [home.appending(path: ".omp/agent/sessions")]
        case "senpi":
            senpi(home: home, environment: environment)
        case "kimchi":
            kimchi(home: home, environment: environment)
        case "prime-agent":
            primeAgent(home: home, environment: environment)
        case "gemini":
            gemini(home: home, environment: environment)
        case "qwen":
            [home.appending(path: ".qwen/projects")]
        case "amp":
            [home.appending(path: ".local/share/amp/threads")]
        case "droid":
            [home.appending(path: ".factory/sessions")]
        case "openclaw":
            openClaw(home: home)
        default:
            []
        }
    }

    // MARK: - Family roots

    /// Senpi keeps its own sessions under an overridable base, and one OmO task
    /// child tree per project a header names.
    private static func senpi(home: URL, environment: [String: String]) -> [URL] {
        let base = environment["SENPI_CODING_AGENT_DIR"].flatMap { value($0, home: home) }
            ?? home.appending(path: ".senpi/agent")
        var roots: [URL] = [base.appending(path: "sessions")]
        if let state = environment["SENPI_CODING_AGENT_SESSION_DIR"].flatMap({ value($0, home: home) }) {
            roots.append(state)
        }
        roots.append(contentsOf: senpiChildren(in: roots))
        return unique(roots)
    }

    /// `<cwd>/.omo/senpi-task/children` for every working directory a session
    /// header in `roots` recorded.
    static func senpiChildren(in roots: [URL]) -> [URL] {
        PiTranscript.cwdValues(in: roots).map {
            URL(fileURLWithPath: $0).appending(path: ".omo/senpi-task/children")
        }
    }

    private static func kimchi(home: URL, environment: [String: String]) -> [URL] {
        if let root = environment["KIMCHI_CODING_AGENT_DIR"].flatMap({ value($0, home: home) }) {
            return [root.appending(path: "sessions")]
        }
        return [home.appending(path: ".config/kimchi/harness/sessions")]
    }

    /// Prime's first matching base wins, then an honoured `sessionDir` in a
    /// project or global `settings.json` replaces its sessions directory.
    private static func primeAgent(home: URL, environment: [String: String]) -> [URL] {
        var roots: [URL]
        if let dir = (environment["PRIME_AGENT_SESSION_DIR"]
            ?? environment["PRIME_AGENT_CODING_AGENT_SESSION_DIR"])
            .flatMap({ value($0, home: home) }) {
            roots = [dir, dir.deletingLastPathComponent().appending(path: "session-artifacts")]
        } else if let dir = environment["PRIME_AGENT_CODING_AGENT_DIR"].flatMap({ value($0, home: home) }) {
            roots = [dir.appending(path: "sessions"), dir.appending(path: "session-artifacts")]
        } else {
            let base = home.appending(path: ".prime/agent")
            roots = [base.appending(path: "sessions"), base.appending(path: "session-artifacts")]
        }

        if let settings = roots.first?.deletingLastPathComponent().appending(path: "settings.json"),
           let redirected = settingsSessionDir(at: settings, home: home) {
            roots.append(contentsOf: redirected)
        }
        for cwd in PiTranscript.cwdValues(in: roots) {
            let project = URL(fileURLWithPath: cwd).appending(path: ".prime/agent/settings.json")
            if let redirected = settingsSessionDir(at: project, home: home) {
                roots.append(contentsOf: redirected)
            }
        }
        return unique(roots)
    }

    /// A `settings.json`'s `sessionDir`, resolved to a sessions directory and
    /// its sibling artifacts directory.
    ///
    /// `null` means the default and an empty string means the settings file's
    /// own directory; a path is tilde-expanded. A missing or unreadable file is
    /// the default too — nothing is redirected on a guess.
    static func settingsSessionDir(at url: URL, home: URL) -> [URL]? {
        guard
            !Task.isCancelled,
            let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let raw = object["sessionDir"]
        else { return nil }

        if raw is NSNull { return nil }
        guard let text = raw as? String else { return nil }

        let sessions: URL
        if text.isEmpty {
            sessions = url.deletingLastPathComponent()
        } else if let resolved = value(text, home: home) {
            sessions = resolved
        } else {
            return nil
        }
        return [sessions, sessions.deletingLastPathComponent().appending(path: "session-artifacts")]
    }

    private static func gemini(home: URL, environment: [String: String]) -> [URL] {
        let base = environment["GEMINI_CLI_HOME"].flatMap { value($0, home: home) }
            ?? home.appending(path: ".gemini")
        return [base.appending(path: "tmp")]
    }

    /// The current OpenClaw tree plus the legacy product names its format facts
    /// still recognise.
    private static func openClaw(home: URL) -> [URL] {
        [
            home.appending(path: ".openclaw/agents"),
            home.appending(path: ".clawdbot"),
            home.appending(path: ".moltbot"),
            home.appending(path: ".moldbot"),
        ]
    }

    // MARK: - Helpers

    /// A stated path, with `~` and `~/…` resolved against the given home. An
    /// empty string is absent rather than the current directory.
    static func value(_ raw: String, home: URL) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == "~" { return home }
        if trimmed.hasPrefix("~/") { return home.appending(path: String(trimmed.dropFirst(2))) }
        return URL(fileURLWithPath: trimmed)
    }

    private static func unique(_ roots: [URL]) -> [URL] {
        var seen: Set<String> = []
        return roots
            .map { $0.standardizedFileURL }
            .filter { seen.insert($0.path).inserted }
    }
}
