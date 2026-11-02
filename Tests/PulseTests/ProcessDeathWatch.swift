// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import Darwin

/// When a spawned process actually died, timed from a thread of its own.
///
/// **Why not time the `await`.** A runner's deadline is enforced on a global
/// queue, but the caller only learns of it when its task resumes, and that
/// needs a free cooperative thread. Swift Testing runs synchronous tests on
/// that pool too, so on a three-core CI runner a few long ones held it for
/// ~19 seconds and every test that started meanwhile — pure parsing ones
/// included — reported 18–19 seconds. A child killed at three seconds was
/// measured at twenty-two and failed `< 20` (the 1.12.1 build, 2026-10-16).
/// Saturating the pool locally reproduces it: the child dies on time, the
/// caller resumes when the pool frees.
///
/// So the claim "killed at the deadline" is timed here, by polling `kill(pid,
/// 0)` on a dedicated thread that no test can starve. The script writes its
/// own pid to `pidFile`; anything still alive at `giveUpAfter` is killed so a
/// failing test does not leak it.
///
/// **A program stopped before its first line writes no pid.** On a loaded
/// machine `/bin/sh` can take longer than a one-second deadline to start, so
/// the runner kills it before `echo $$` runs — correctly — and a watch waiting
/// for the pid waited thirty seconds and called it a survivor. That failed
/// most local full runs of 1.12.5's checks. So the caller says when the run
/// has returned (`runReturned()`); by then the runner has stopped the whole
/// group, and a pid still unwritten a moment later never will be: the watch
/// ends with `neverStarted` set instead.
final class ProcessDeathWatch: @unchecked Sendable {
    let pidFile: URL
    private let lock = NSLock()
    private var outcome: ContinuousClock.Instant??
    private var waiter: CheckedContinuation<ContinuousClock.Instant?, Never>?
    private var returnedAt: ContinuousClock.Instant?
    private var stoppedEarly = false

    /// Read after `death`: the program was stopped before it wrote its pid,
    /// so there was nothing left to outlive the run.
    var neverStarted: Bool { lock.withLock { stoppedEarly } }

    /// The run has returned. See the type's comment.
    func runReturned() {
        lock.withLock { if returnedAt == nil { returnedAt = .now } }
    }

    init(giveUpAfter: Duration = .seconds(30)) {
        pidFile = FileManager.default.temporaryDirectory.appending(path: "pulse-watched-\(UUID()).pid")
        let thread = Thread { [self] in watch(until: .now + giveUpAfter) }
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    /// The moment the process was first seen gone, or nil if it outlived the
    /// watch. Waits for the watch to finish; the instant itself was taken on
    /// the watching thread, so a slow resumption here cannot inflate it.
    var death: ContinuousClock.Instant? {
        get async {
            await withCheckedContinuation { continuation in
                let finished: ContinuousClock.Instant?? = lock.withLock {
                    if outcome == nil { waiter = continuation }
                    return outcome
                }
                if let finished { continuation.resume(returning: finished) }
            }
        }
    }

    private func watch(until giveUp: ContinuousClock.Instant) {
        var pid: Int32?
        while ContinuousClock.now < giveUp {
            if pid == nil,
               let text = try? String(contentsOf: pidFile, encoding: .utf8),
               let written = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), written > 1 {
                pid = written
            }
            if let pid, kill(pid, 0) == -1, errno == ESRCH {
                return finish(.now)
            }
            if pid == nil, let returnedAt = lock.withLock({ returnedAt }),
               ContinuousClock.now > returnedAt + .seconds(2) {
                lock.withLock { stoppedEarly = true }
                return finish(nil)
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        if let pid { kill(pid, SIGKILL) }
        finish(nil)
    }

    private func finish(_ instant: ContinuousClock.Instant?) {
        try? FileManager.default.removeItem(at: pidFile)
        let waiting = lock.withLock {
            outcome = .some(instant)
            defer { waiter = nil }
            return waiter
        }
        waiting?.resume(returning: instant)
    }
}
