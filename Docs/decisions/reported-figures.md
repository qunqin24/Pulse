# Reported figures; the estimate is labelled

**Status:** still in force. **Evidence:** product rule (code); activity/ledger/burn-rate numbers historical, one machine.

Pulse never computes a usage percentage. Token budgets behind these limits are not published. A guess presented as a fact is worse than “not reported.” Shared `Unavailability` copy originally said “Codex” for every provider.

`windowSeconds > 0` is not “the provider stated a length.” Sort keys (rolling weeks, 30-day stand-ins for 28–31 day cycles) would drive the window clock and burn rate if that were the test. `reportsLength` exists because of that. `UsageDetailCard.resetText` once fell back to `lengthText` when `resetsAt` was nil and printed “7 days” for a length nobody reported.

Countdown: `usedFraction ?? 0` inverted into a **full green ring** for “100% left” when there was no reading (historical: 720/720 points coloured). A spent limit counting down drew **no** arc. Card said “Used” whichever way the rail counted.

## Activity is not mtime

A short “recently written” window stops the spinner mid-tool; a long one spins after the turn is dead. Interrupt `[Request interrupted by user]` as an ordinary prompt spun for the whole grace. Assistant records with no `stop_reason` were mostly subagents (`isSidechain`); treating them as the live turn was wrong.

Historical: 3,110 turns / 2,783 tool calls — waiting for the model median 7s, 99% inside 70s (grace 90s); waiting for a tool median 2s, writes nothing for as long as a build, 15 min extreme (grace 5 min). File mtime stays fresh from bookkeeping; grace runs from the record timestamp.

## Ledger and burn rate

Codex per-turn `last_token_usage` summed ~6% high on one long session vs differencing the running total. Independent arithmetic check (historical): $235.52 / 413,932,186 tokens, agreed to the cent.

Trailing burn-rate samples vs cumulative: on one bursty five-hour window the trailing estimate ranged over a factor of **24**, cumulative 9–13. Trailing needed storage, sampling, reset detection. Pace as a number (“8% in reserve” under “20% used”) was read as *8% left*. Usage burstiness (historical, three days of transcripts): 3% of five-minute slots had any activity; busiest six times the median. Anything that reads as precise is wrong.

Estimate withheld under 2% used, logs starting after the window, model-scoped windows (a 2%-used Fable window priced at ten thousand dollars because the money had gone through Opus).

Current rules: [../refresh-and-data.md](../refresh-and-data.md).
