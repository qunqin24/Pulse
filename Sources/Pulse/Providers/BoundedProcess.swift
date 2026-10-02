// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Runs a helper program with a ceiling on both time and output, off the
/// cooperative pool.
///
/// Written for `arkcli` (see `VolcengineUsageService`) and shared with the
/// extension runner, which starts programs Pulse knows even less about. Three
/// things this has to get right, and the first version got none of them:
///
/// 1. **Both pipes are drained at once.** Reading stdout to EOF and only then
///    reading stderr deadlocks the moment the child writes more than a pipe
///    buffer (64 KiB) to stderr before closing stdout — a panic, a debug
///    build, a TLS dump. The child blocks writing, we block reading, and
///    neither ever returns.
/// 2. **Reading never stops early.** Past the output ceiling the bytes are
///    dropped but the pipe is still drained, because a reader that walks away
///    is the same deadlock wearing a different hat.
/// 3. **It runs on a global queue, not the cooperative pool.** This is
///    blocking work called from an `async` function; parked on a cooperative
///    thread it takes one of a core-width pool with it, and a few of those
///    stop Swift concurrency across the whole app.
///
/// A pass that never finishes never calls `scheduleNext`, so a hang here is
/// not one provider being slow — it is the rail freezing until something else
/// happens to call `refresh`.
enum BoundedProcess {
    /// A helper's environment: `inherited`, with the folder `binary` was
    /// found in at the front of `PATH`. **Every launcher of another tool's
    /// CLI goes through this.**
    ///
    /// An npm install of a CLI is a Node script — `#!/usr/bin/env node` — and
    /// a GUI app's `PATH` is `/usr/bin:/bin:/usr/sbin:/sbin`, which has no
    /// `node` in it. So a `codex` found under `~/.nvm/…/bin` started and died
    /// at once with "env: node: No such file or directory", and everything
    /// only its app server reports never arrived (issue #67). nvm, Homebrew
    /// and Volta all put `node` beside the CLI they installed, so that folder
    /// is where to look first. The path as found, not the link resolved:
    /// nvm's `codex` links into `lib/node_modules`, where there is no `node`.
    static func environment(leading binary: URL, over inherited: [String: String]) -> [String: String] {
        var environment = inherited
        let folder = binary.deletingLastPathComponent().path
        let path = inherited["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let rest = path.split(separator: ":").map(String.init).filter { $0 != folder }
        environment["PATH"] = ([folder] + rest).joined(separator: ":")
        return environment
    }

    /// What a helper inherits: the proxy the user chose, over Pulse's own.
    static var inheritedEnvironment: [String: String] {
        NetworkSession.subprocessEnvironment() ?? ProcessInfo.processInfo.environment
    }

    enum Failure: Error, Equatable {
        /// The program could not be started at all: missing, not executable.
        case couldNotStart
        /// It ran past the deadline, or closed its pipes and kept running.
        case timedOut
        /// It finished, unsuccessfully. What it wrote to stderr, which is the
        /// only account of why there is.
        case exited(status: Int32, standardError: String)
    }

    static func run(
        _ binary: URL,
        _ arguments: [String],
        environment: [String: String]?,
        currentDirectory: URL? = nil,
        deadline: TimeInterval,
        outputCeiling: Int
    ) async -> Result<Data, Failure> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: blocking(
                    binary, arguments,
                    environment: environment,
                    currentDirectory: currentDirectory,
                    deadline: deadline,
                    outputCeiling: outputCeiling
                ))
            }
        }
    }

    private static func blocking(
        _ binary: URL,
        _ arguments: [String],
        environment: [String: String]?,
        currentDirectory: URL?,
        deadline: TimeInterval,
        outputCeiling: Int
    ) -> Result<Data, Failure> {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.environment = environment
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        // Nothing to answer with, so a CLI that asks gets EOF rather than
        // blocking on a terminal that is not there.
        process.standardInput = FileHandle.nullDevice

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        // **Never `waitUntilExit()`.** It has no timeout, and bounding only the
        // readers moved the hang rather than removing it: a child that ignores
        // SIGTERM, or one that closes its pipes and keeps running, sailed past
        // the deadline and parked here for ever. The handler is set before the
        // process starts so an exit cannot be missed between the two.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            return .failure(.couldNotStart)
        }

        // Darwin Foundation normally creates a group led by the child. Verify
        // it before signalling a group, and never target Pulse's own group.
        // A fast-exiting leader may already be reaped while its group survives.
        // That last check confirms a group with this id exists *now*; a pid
        // freed and reused before `stop()` would be somebody else's. It needs
        // the child reaped, the pid reissued within milliseconds, and the new
        // owner to be a group leader — accepted against leaving descendants
        // running, which is what this branch is for.
        let pid = process.processIdentifier
        let ownGroup = getpgrp()
        let reportedGroup = getpgid(pid)
        let hasGroup = reportedGroup == pid
            || (reportedGroup == -1 && errno == ESRCH && kill(-pid, 0) == 0)
        let processGroup = pid > 1 && pid != ownGroup && hasGroup ? pid : nil

        let collected = Collected()
        let readers = DispatchGroup()
        for (pipe, isStandardOutput) in [(out, true), (err, false)] {
            readers.enter()
            // **A handler, not a blocking read loop.** A loop parks a thread
            // per pipe, and a grandchild inheriting the write end keeps it
            // parked after this call has given up — a leak that repeats until
            // libdispatch's per-QoS thread cap starves everything else. A
            // handler holds no thread: if the far end never closes, it simply
            // stops being called.
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    // EOF. Clearing the handler is what releases the file
                    // descriptor, and `leave` must happen exactly once.
                    handle.readabilityHandler = nil
                    readers.leave()
                    return
                }
                collected.append(chunk, toStandardOutput: isStandardOutput, ceiling: outputCeiling)
            }
        }

        /// Detaches from both pipes. Anything still holding a write end is no
        /// longer this call's problem, and nothing is left blocked on it.
        func releasePipes() {
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
        }

        /// SIGTERM, then SIGKILL, then give up — each bounded. `terminate()`
        /// alone is a request, and a CLI with a stuck graceful-shutdown path
        /// is exactly the thing being escaped from.
        func stop() {
            if let processGroup {
                kill(-processGroup, SIGTERM)
                let until = DispatchTime.now() + 2
                // The leader exiting is not enough: a descendant can retain
                // the pipes and ignore TERM. Give the whole group its grace.
                while kill(-processGroup, 0) == 0, DispatchTime.now() < until {
                    Thread.sleep(forTimeInterval: 0.02)
                }
                if kill(-processGroup, 0) == 0 { kill(-processGroup, SIGKILL) }
                _ = exited.wait(timeout: .now() + 2)
                return
            }
            process.terminate()
            guard exited.wait(timeout: .now() + 2) == .timedOut else { return }
            kill(process.processIdentifier, SIGKILL)
            _ = exited.wait(timeout: .now() + 2)
        }

        if readers.wait(timeout: .now() + deadline) == .timedOut {
            stop()
            // A moment for the readers to see the pipes close, and no more.
            _ = readers.wait(timeout: .now() + 1)
            releasePipes()
            return .failure(.timedOut)
        }

        // The pipes are closed, which is not the same as the process being
        // gone — it can hold both open through a child of its own, or simply
        // close them and carry on.
        if exited.wait(timeout: .now() + 2) == .timedOut {
            stop()
            releasePipes()
            return .failure(.timedOut)
        }

        releasePipes()
        let (data, problem) = collected.taken()

        guard process.terminationStatus == 0 else {
            return .failure(.exited(status: process.terminationStatus, standardError: problem))
        }

        return .success(data)
    }
}

/// The two pipes' bytes, written from two queues and read once after both have
/// finished. The lock is what makes that safe; the `DispatchGroup` is what
/// makes "after both have finished" true.
private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var standardOutput = Data()
    private var standardError = Data()

    func append(_ chunk: Data, toStandardOutput: Bool, ceiling: Int) {
        lock.lock()
        defer { lock.unlock() }
        // Past the ceiling the bytes are dropped, never the reading — see
        // `BoundedProcess.blocking`.
        if toStandardOutput {
            if standardOutput.count < ceiling { standardOutput.append(chunk) }
        } else if standardError.count < ceiling {
            standardError.append(chunk)
        }
    }

    func taken() -> (output: Data, problem: String) {
        lock.lock()
        defer { lock.unlock() }
        return (standardOutput, String(data: standardError, encoding: .utf8) ?? "")
    }
}
