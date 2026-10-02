// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Sends one "hi" through a provider's own command-line tool, so a usage
/// window that only starts counting at the first message starts now.
///
/// **Why this exists.** Claude Code's five-hour window, and Codex's windows,
/// start at the first message after a reset, not at the reset. Somebody who
/// comes back three hours after a reset starts a fresh five hours then, and
/// waits all of it out if they run dry — where a window started at the reset
/// would already be three hours through. `WindowPrimer` decides when; this
/// only sends.
///
/// **The cheapest thing that counts, and nothing kept.** The smallest model,
/// no tools, no MCP servers, none of the user's hooks or settings, run in an
/// empty folder of Pulse's own, and told not to save the session — so no
/// transcript is written, nothing appears in the tool's history, and Pulse's
/// own spend figures never see it. Pulse holds no credential for this: each
/// tool uses the login it already has.
enum WindowStarter {
    static let prompt = "hi"

    enum Outcome: String, Equatable, Sendable {
        case sent
        /// The tool is not installed anywhere Pulse looks.
        case toolMissing
        /// It ran and failed — signed out, offline, a model gone.
        case failed
        case timedOut
    }

    /// Where the tools are run from: empty, and Pulse's own, so no project's
    /// settings or instructions are picked up.
    static var folder: URL { PulseStorage.directory.appending(path: "Window starter") }

    /// A message takes seconds; a tool stuck on a prompt nobody will answer
    /// must not hold anything up for longer than this.
    static let deadline: TimeInterval = 120

    /// `claude -p` with Haiku, and with everything that could do more than
    /// answer "hi" turned off. `--setting-sources project` loads only the
    /// empty folder's settings, which is to say none: the user's own hooks —
    /// sounds, notifications, Pulse's own status line — do not run for this.
    static func claudeArguments() -> [String] {
        [
            "-p", prompt,
            "--model", "haiku",
            "--no-session-persistence",
            "--tools", "",
            "--strict-mcp-config",
            "--setting-sources", "project",
        ]
    }

    /// `codex exec`, ephemeral, read-only, in Pulse's folder, at the lowest
    /// reasoning effort — and with `model` when one cheaper than the default
    /// was found (`cheapestCodexModel`).
    static func codexArguments(model: String?, folder: URL) -> [String] {
        var arguments = [
            "exec",
            "--ephemeral",
            "--skip-git-repo-check",
            "-s", "read-only",
            "-C", folder.path,
            "-c", "model_reasoning_effort=\"low\"",
        ]
        if let model { arguments += ["-m", model] }
        return arguments + [prompt]
    }

    /// The cheapest model in Codex's own list: one named Luna — the fast,
    /// efficient tier at the time of writing — else one described as fast,
    /// efficient or mini. Nil keeps the account's default, which still costs
    /// next to nothing for one word. Read from the list each time rather than
    /// written down here, because OpenAI renames these.
    static func cheapestCodexModel(in reply: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: reply) as? [String: Any],
              let models = (root["data"] as? [[String: Any]]) ?? ((root["result"] as? [String: Any])?["data"] as? [[String: Any]])
        else { return nil }
        let offered = models.filter { ($0["hidden"] as? Bool) != true }
        func id(_ model: [String: Any]) -> String? { (model["id"] as? String) ?? (model["model"] as? String) }
        if let luna = offered.first(where: { id($0)?.lowercased().contains("luna") == true }) {
            return id(luna)
        }
        let light = offered.first { model in
            let words = ((model["description"] as? String) ?? "").lowercased() + " " + (id(model) ?? "").lowercased()
            return ["fast", "efficient", "mini"].contains(where: words.contains)
        }
        return light.flatMap(id)
    }

    static func start(_ provider: Provider) async -> Outcome {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        switch provider {
        case .claudeCode:
            let home = NSHomeDirectory()
            guard let claude = CommandLocator.locate("claude", extra: ["\(home)/.claude/local/claude"]) else {
                return .toolMissing
            }
            let outcome = await run(claude, claudeArguments())
            removeEmptyClaudeProject(home: home)
            return outcome
        case .codex:
            guard let codex = CodexAppServer.locateCodex() else { return .toolMissing }
            let server = CodexAppServer(executable: codex)
            let model = (try? await server.models()).flatMap(cheapestCodexModel(in:))
            await server.shutDown()
            return await run(codex, codexArguments(model: model, folder: folder))
        default:
            return .failed
        }
    }

    /// The folder Claude Code keeps for a working directory: the path with
    /// everything but letters and digits turned into dashes.
    static func claudeProjectFolder(for directory: URL, home: String) -> URL {
        let name = String(directory.path.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
        return URL(fileURLWithPath: home).appending(path: ".claude/projects").appending(path: name)
    }

    /// Claude Code makes a project folder for the starter's directory even
    /// when told not to keep the session — empty, but listed with the user's
    /// real ones. Removed when it holds no file at all; anything with a file
    /// in it is left exactly as it is.
    private static func removeEmptyClaudeProject(home: String) {
        let project = claudeProjectFolder(for: folder, home: home)
        let fileManager = FileManager.default
        guard let walker = fileManager.enumerator(at: project, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        for case let item as URL in walker
        where (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            return
        }
        try? fileManager.removeItem(at: project)
    }

    private static func run(_ binary: URL, _ arguments: [String]) async -> Outcome {
        let result = await BoundedProcess.run(
            binary,
            arguments,
            environment: BoundedProcess.environment(leading: binary, over: BoundedProcess.inheritedEnvironment),
            currentDirectory: folder,
            deadline: deadline,
            outputCeiling: 64 * 1024
        )
        switch result {
        case .success: return .sent
        case .failure(.couldNotStart): return .toolMissing
        case .failure(.timedOut): return .timedOut
        case .failure(.exited): return .failed
        }
    }
}
