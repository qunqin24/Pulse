# Bundle, Spotlight, and the defaults domain

**Status:** still in force. **Evidence:** code; Spotlight marker historical.

Without a bundle there is no `Bundle.main`: no version for Sparkle to compare, no `SMAppService`, nothing to give a user but a build folder. `LSUIElement` must be true or a Dock icon flashes before `.accessory` runs.

## `build.noindex/`

Spotlight indexes an `.app` wherever it finds one. A build in the project folder appears in Launchpad beside the installed copy. Whichever is opened claims the login item and rewrites Claude Code’s status-line path to itself; deleting the build later breaks both.

A `.metadata_never_index` marker was tried first and **did not work** — the build was indexed anyway. The marker is kept as a second line; the `.noindex` directory name is what does the job (same convention as Xcode DerivedData).

## Defaults domain

`UserDefaults.standard` is named after the bundle identifier, or — with no bundle — the process name. Every `swift run` kept settings in a domain called `Pulse`; `Pulse.app` read an empty one: position, providers, language, **and the flag that opening at login was already decided**. It looked like a fresh install and would switch login-at-start back on.

`LegacyDefaults` copies the old domain once, only keys the new domain does not have. After that they diverge: an Xcode build and an installed app should not edit each other’s settings.

`LoginItem.adoptBundleIfNeeded` is the other direction: a leftover launch agent still names the old binary, so the next login starts the old build *and* `SMAppService` starts the new one.

Current: [../architecture.md](../architecture.md), [../releasing.md](../releasing.md), [../build-from-source.md](../build-from-source.md).
