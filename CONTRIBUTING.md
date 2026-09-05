# Contributing

Pulse is a macOS menu-bar app. There is no test target and no linter. Review is human plus whatever the author ran. This file is for people changing the repo; [CLAUDE.md](CLAUDE.md) is the short AI entry.

## Workflow

1. Read the **topic doc** for the area you are changing ([Docs/README.md](Docs/README.md)). If the change is about *why* something is the way it is, also read the linked decision.
2. Change code and the **authoritative topic doc in the same patch**. Do not leave CLAUDE.md as a second source of truth, and do not grow it with new architecture.
3. Run the verification that area needs ([Docs/development.md](Docs/development.md), [Docs/build-from-source.md](Docs/build-from-source.md)). At minimum, a Swift 6 warning-clean build if you touched Swift, and `./Scripts/check-localization.sh` if you touched user-visible strings.
4. Do not claim a behaviour is verified unless you used a method that can actually see it. See evidence levels below.

Provider routes, auth, cookies, and extra-account login belong in [Docs/providers/README.md](Docs/providers/README.md), not in UI or architecture docs.

## Authoritative docs vs this file

| Kind | Where it lives | When to update |
|---|---|---|
| Nonnegotiable constraints for agents | [CLAUDE.md](CLAUDE.md) — keep short | Only when a constraint is new or wrong |
| How it works *now* | Topic docs under `Docs/` | Same patch as the code |
| Why / what failed / measured once | [Docs/decisions/](Docs/decisions/README.md) | When the *reason* changes, or a new lesson is worth keeping |
| Human process | This file | When the process changes |
| User-facing product copy | [README.md](README.md) and [README.zh-CN.md](README.zh-CN.md) | Keep bilingual parity |

`Docs/` is the capitalized directory. Do not add a second `docs/` tree.

## Current facts vs decisions

**Current facts** are things that must stay true of *this* tree (provider count, timer shape, which accounts can be added). They belong in the topic doc, and a one-line reminder may sit at the bottom of CLAUDE.md. If the code disagrees with the doc, the code wins until the doc is fixed — verify, then patch both.

**Decisions** are historical: why a rule exists, what shipped broken, numbers measured on one machine. They are **not** newly verified by being copied forward. Phrase them as “measured then,” not “is still.” Link them from the current doc; do not duplicate the full story in both places.

When a current fact changes (for example a fifteenth provider), update the topic doc and CLAUDE’s facts line. Do not rewrite the decision unless the *reason* changed.

## Evidence levels

State which you used. Do not promote a lower level to a higher one in prose.

| Level | Means | Not enough for |
|---|---|---|
| **Code** | Read or compiled this tree | Real pointer / glass / Gatekeeper behaviour |
| **Historical** | Written in an old CLAUDE note or decision; not re-run | Claiming the measurement still holds |
| **Local probe** | `hitTest`, synthesised `NSEvent`, unit-style geometry asserts | Whether a real click arrives (those probes have lied here) |
| **Real input** | A person pressed, dragged, or launched the bundled app | — |

If a symptom survived every local probe, say so and stop. Do not invent a fourth probe that agrees with the first three. [Docs/ui/input.md](Docs/ui/input.md) and [Docs/decisions/liquid-glass.md](Docs/decisions/liquid-glass.md) exist because that happened.

## Docs review checklist

Before merging a docs-or-behaviour change:

- [ ] The topic doc, not CLAUDE.md, is the source of truth for the behaviour.
- [ ] A linked decision holds why/history; the topic doc does not retell the whole failure.
- [ ] Provider/auth/cookie detail is only in `Docs/providers/` (or a provider investigation note it points at).
- [ ] Current facts (counts, intervals, which accounts are multi) match the code you just read.
- [ ] Historical measurements are labelled historical.
- [ ] README and README.zh-CN.md still match if you touched user-facing claims.
- [ ] Links from CLAUDE.md’s “Read by task” table still resolve.
- [ ] You did not add build or shipping instructions that contradict [Docs/build-from-source.md](Docs/build-from-source.md) / [Docs/releasing.md](Docs/releasing.md).

## Code of the house (short)

- Do not strip `#Preview` to get a green `swift build`.
- Do not treat remaining Swift 6 warnings as noise.
- Do not resize the panel window while a details card opens.
- Do not reintroduce SwiftUI `.onHover` or exit-event closes on the panel.
- Do not invent a usage percentage the provider did not report.
- Layout constants are budgets (`PanelMetrics` computed `var`, never `static let`).
