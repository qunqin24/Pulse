# Changelog

What each release changed, written for somebody deciding whether to install it.

This file is the source for both the GitHub release page and the text Sparkle
shows in the update window — see [Scripts/changelog.py](Scripts/changelog.py).
Add the entry **before** tagging, in the small grammar the converter knows:
bullets, `**bold**`, `` `code` `` and `[links](https://example.com)`.

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
