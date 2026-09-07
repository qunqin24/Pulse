# Review brief — `pulse-1.0.7`

Temporary. Written 2026-09-07 to hand this branch to an outside reviewer, and
not part of the docs map — nothing links here and nothing has to keep it
current. Delete it once the review is done.

---

## What this is

**Pulse** is a macOS menu-bar app that shows AI coding-provider usage limits
(Claude Code, Codex, Cursor, Copilot, Antigravity, …). Swift 6, SwiftUI + AppKit,
macOS 14+, no Xcode project — a plain SwiftPM package. Repo:
https://github.com/qunqin24/Pulse

Branch `pulse-1.0.7` is 10 commits ahead of `main`: **51 files, +4377 / −148.**

## What you are being asked

Decide whether this ships. It has already been reviewed twice by another model;
**both rounds found real blocking defects, and both times the defects were in the
same file** — a `Process`-spawning function that was rewritten twice and was
wrong twice. Assume it is wrong a third time until you have convinced yourself
otherwise.

Please prioritise:

1. **Concurrency and process handling.** Deadlocks, unbounded waits, leaked
   threads / file descriptors / child processes, `DispatchGroup` imbalance,
   continuations resumed zero or twice, actor-isolation mistakes under Swift 6
   strict concurrency.
2. **Logic errors that produce a wrong number or a wrong alert**, especially in
   the notification state machine.
3. **Anything that silently does nothing** — a `guard` that always passes, a
   setting never read, an optional protocol method with the wrong signature.
4. Security/privacy: credential handling, what is written to disk or logged.

Please do **not** report style, naming, or comment wording. Report only defects
you verified by reading the code, each with `file:line` and a concrete failure
scenario (state/inputs → wrong behaviour).

## What changed

| Area | Files |
|---|---|
| Notification subsystem (new) | `Sources/Pulse/UsageAlerts.swift`, wired from `UsageStore.commit` |
| A new provider, Volcengine Ark | `Sources/Pulse/VolcengineUsageService.swift`, `VolcengineSigner.swift` |
| `Pulse --json` output for status lines | `Sources/Pulse/UsageReport.swift`, `AppSettings.storedRail()` |
| Antigravity: a second language-server origin, try every candidate | `Sources/Pulse/AntigravityUsageService.swift` |
| Settings usability: search, drag-reorder, sizing | `Sources/Pulse/SettingsView.swift` |
| First test target in the project's history | `Tests/PulseTests/`, `Package.swift` |

`CLAUDE.md` in the repo root states the project's rules. The ones a reviewer
should hold the code to:

- **Pulse never invents a usage percentage.** If a provider reports none, say so.
- **Warnings are failures** (`swift build -Xswiftc -swift-version -Xswiftc 6`).
- Localization goes through `String.localized(_:)` only.
- Notifications must say nothing Pulse did not witness.

## The two prior review rounds

Round 1 found ten defects. Round 2 reviewed the fixes and found four more —
**two of which were fixes that were themselves wrong**, including the process
runner, which was fixed in a way that moved the hang rather than removing it.
Both rounds' findings are now fixed. Do not spend time re-deriving them; they
are listed so you can look *past* them:

Round 1: (1) the process runner had no deadline, no output cap, and deadlocked
reading stdout-then-stderr; (2) `arkcli` exit classified by the substring
`"auth"`, which matches its own help text; (3) notification permission read only
at launch; (4) a *push* route going quiet counted as a failed fetch; (5)(6)
Antigravity's terminal reason and an aborted candidate search; (7) an oscillating
window re-announced for ever; (8) `Dictionary(uniqueKeysWithValues:)` traps on a
duplicate; (9) an atomic disk write on the main actor per pass; (10) `CLAUDE.md`
contradicted its own shipped code.

Round 2: (1) the runner's deadline bounded only the pipe readers, then called
`waitUntilExit()`, which has **no timeout** — a child ignoring SIGTERM, or one
closing its pipes and staying alive, hung the call for ever; (2) the push-route
flag was put on `Provider` when it is a property of the *route* — it silenced
real outages on three of Claude Code's four routes; (3) the replacement
Antigravity reason was *also* in the failure list, so the banner it was written
to stop kept firing; (4) two new build warnings.

## Highest-risk code: `VolcengineUsageService.blocking(_:_:deadline:)`

Third version. Wrong twice already. Comments stripped for brevity — read the
real file.

```swift
private static func blocking(
    _ binary: URL, _ arguments: [String], deadline: TimeInterval
) -> Result<Data, Refusal> {
    let process = Process()
    process.executableURL = binary
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    let out = Pipe(); let err = Pipe()
    process.standardOutput = out
    process.standardError = err

    let exited = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in exited.signal() }

    do { try process.run() }
    catch { return .failure(Refusal(reason: .volcengineCLIMissing)) }

    let collected = Collected()                 // NSLock-guarded, @unchecked Sendable
    let readers = DispatchGroup()
    for (pipe, isStandardOutput) in [(out, true), (err, false)] {
        readers.enter()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                readers.leave()
                return
            }
            collected.append(chunk, toStandardOutput: isStandardOutput, ceiling: outputCeiling)
        }
    }

    func releasePipes() {
        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil
    }

    func stop() {
        process.terminate()                                   // SIGTERM
        guard exited.wait(timeout: .now() + 2) == .timedOut else { return }
        kill(process.processIdentifier, SIGKILL)
        _ = exited.wait(timeout: .now() + 2)
    }

    if readers.wait(timeout: .now() + deadline) == .timedOut {
        stop()
        _ = readers.wait(timeout: .now() + 1)
        releasePipes()
        return .failure(Refusal(reason: .unreachable))
    }

    if exited.wait(timeout: .now() + 2) == .timedOut {
        stop()
        releasePipes()
        return .failure(Refusal(reason: .unreachable))
    }

    releasePipes()
    let (data, problem) = collected.taken()
    guard process.terminationStatus == 0 else {
        return .failure(Refusal(reason: Self.reason(forExitOf: problem)))
    }
    return .success(data)
}
```

Called from `run(_:_:deadline:)`, which wraps it in
`withCheckedContinuation` + `DispatchQueue.global(qos: .utility).async`
so the blocking work stays off the Swift cooperative pool.

Questions worth answering explicitly:

- Can this still hang, on **any** child behaviour?
- Is `readers.leave()` guaranteed to run at most once per pipe? What if
  `readabilityHandler` fires again after `releasePipes()` on another queue?
- Is clearing a `readabilityHandler` while it is executing on libdispatch's queue
  safe here?
- Is `collected.taken()` guaranteed to see all bytes on the success path?
- Can `process.terminationStatus` be read before the process is reaped?
- Does anything leak if the deadline fires: fds, the `Collected` buffer, the
  child, a grandchild?

**Why a hang here is severe:** `UsageStore.scheduleNext()` only runs when a
refresh pass *finishes*, and the refresh timer is one-shot. A pass that never
returns stops the refresh loop for **all fifteen providers**, not just this one,
until some unrelated event happens to call `refresh()` again.

## Second-highest risk: the notification state machine

`Sources/Pulse/UsageAlerts.swift`, `AlertMemory.alerts(for:as:threshold:announcesReset:announcesFailure:staleMeansFailure:now:)`.

Pure apart from its own state — no clock, no disk, no notification centre — so it
can be reasoned about completely. It decides four things: a limit passing a
threshold, a limit the provider calls spent, a window that has reset, and an
account whose readings have stopped arriving. Persisted to disk so a relaunch
does not re-announce.

Look for sequences of readings that double-announce, never announce, or announce
something untrue. Two known-subtle rules:

- The announced step is cleared only by *unambiguous* reset evidence (the
  provider's reset time moving forward, or a 40-point drop) — not by any drop.
- A `.stale` reading is judged on the **age** of the figures, not on being stale,
  because `UsageCache.reconciled` returns `.stale` for a *successful* fetch too.

## What cannot be verified, and is not a finding

- **Nobody has a Volcengine Ark account.** Its reply shapes are second-hand from
  another open-source project (CodexBar, MIT) rather than captured live, and no
  signature this code produces has ever been accepted by Volcengine. This is
  stated plainly in `Docs/providers/volcengine.md`. "You cannot prove this works"
  is known — report *defects*, not the absence of a live account.
- Notification delivery end-to-end needs a granted macOS permission.
- UI behaviour of the floating panel: `.onHover` does not work on this
  accessory, non-key panel, and synthesised events lie about it. There are no UI
  tests on purpose.

## How to build and check

```bash
swift build -Xswiftc -swift-version -Xswiftc 6   # must be warning-free
swift test                                        # 89 tests, 8 suites
./Scripts/check-localization.sh                   # 290 keys
./Scripts/bundle.sh                               # builds Pulse.app
```

Current status: all four pass. Warnings are treated as failures by project rule.

## Files worth reading, in order

1. `Sources/Pulse/VolcengineUsageService.swift` — the process runner
2. `Sources/Pulse/UsageAlerts.swift` — the alert rules and their persistence
3. `Sources/Pulse/AntigravityUsageService.swift` — the candidate search
4. `Sources/Pulse/UsageReport.swift` — the `--json` command, a semaphore/Task bridge
5. `Sources/Pulse/VolcengineSigner.swift` — request signing (HMAC, canonical form)
6. `Sources/Pulse/UsageStore.swift` — the refresh loop everything hangs off
7. `Tests/PulseTests/` — do the tests test what they claim, and would they fail
   against the bugs they name?

## Deliverable

Findings with `file:line` + failure scenario, then **SHIP** or **DO NOT SHIP**
with the specific blocking items.
