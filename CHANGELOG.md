# Changelog

What each release changed, written for somebody deciding whether to install it.

This file is the source for both the GitHub release page and the text Sparkle
shows in the update window — see [Scripts/changelog.py](Scripts/changelog.py).
Add the entry **before** tagging, in the small grammar the converter knows:
bullets, `**bold**`, `` `code` `` and `[links](https://example.com)`.

## 1.0.4

- **Claude Code's card names the plan**, as every other provider's already did — "Max 5x", "Pro", "Team". The multiplier is part of it, since a Max 5x and a Max 20x are different products.

- **The panel could quietly stop refreshing** after running for a long time, and only come back when you started Claude Code in a terminal. It now notices when its own readings have gone stale and asks again, recovers from a fetch that never returned, and refreshes when the Mac wakes as well as when the display does.

- **Whether a limit will last.** Switched on in Settings, Claude Code and Codex cards say "expected to last the window" under each limit, or roughly when it runs out. The time only appears when it falls before the reset — the rest of the time there is nothing to predict — and it is rounded, because usage comes in bursts and a figure to the minute would be made up.

- **GitHub Copilot.** Signs in with a device code — Pulse asks GitHub for `read:user` and nothing else, so no token to paste and no access to your repositories. Shows the completions, chat and premium-request allowances your plan actually has.

- **Show what's left instead of what's spent.** A switch in Settings turns the figure and the ring over together, so a limit reads "88% left" rather than "12% used". The colour still means how close you are, so a nearly empty ring is still red.

## 1.0.3

- **The panel can go on a second display.** Drag it across; it remembers which screen you left it on, and comes home if that screen is unplugged.
- **Four more providers**: the GLM Coding Plan and MiniMax, each with a separate entry for the international and the mainland service, since they are separate accounts with separate keys.
- **A second arc can show how far through the window the clock is**, so "80% used" can be read against how much of the window is left. Off by default, in Settings.
- **The figure can sit above the ring** instead of below it. Also in Settings.
- A provider that needs an API key is no longer switched on by itself — it waits in Settings rather than taking a place on the rail to ask for a key.
- One that has no key says so, instead of saying "Reading…" for ever.
- Claude Code no longer shows a limit that has already reset. If its saved login has expired and no session has run for a while, the stale window is dropped rather than shown with an old reset time.
- The update window now shows the release notes itself, rather than loading the GitHub page inside it.

## 1.0.2

- **Multiple accounts.** Sign in to a second Claude Code or Codex subscription and watch both at once, each with its own ring.
- **Cursor**, reported as the two pools its own account page shows.
- **Ollama Cloud**, from PcOffeeP's pull request — with the session read out of your browser rather than copied by hand.
- **The rail can dock along the top of the screen**, above the menu bar.
- **A colour of your own for any ring**, and the gap between rings is now adjustable.
- **Percentages can be switched off** on either rail.
- The rail opens with the last reading instead of sitting blank.
- The activity mark no longer keeps turning for a minute after a turn has ended.
- The API-key field in Settings lets go when you click away from it.
- A limit you have used never reads as 0% any more.
- Quitting Codex no longer takes Pulse down with it.
- A new app icon, drawn on Apple's icon grid.

## 1.0.1

- **OpenCode Go** and **Kimi Code**, bringing it to five agents.
- **Put the rings in your own order**, in Settings.
- **A refresh button on every provider's pane**, with the age of the reading beside it.
- A new install starts with the agents you actually have, rather than five rings that say "not configured".
- The panel can be dragged by any part of the capsule, not only by its rings.
- Clicking a ring refreshes the one you clicked, whatever order the rail is in.
- The detail card no longer truncates itself at Small or sit half empty at Large.

## 1.0.0

- The first release. A floating rail of rings against the edge of the screen, one per coding agent, showing how much of each limit is left.
