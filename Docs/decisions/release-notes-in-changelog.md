# Changelog is the release notes

**Status:** still in force. **Evidence:** historical Sparkle/GitHub mistakes; current scripts.

`CHANGELOG.md` is the GitHub release body **and** the Sparkle update window. The workflow refuses to start without a matching `##` section, *before* it builds, so a forgotten entry costs a re-tag rather than a release whose notes went out wrong.

Notes used to be `sparkle:releaseNotesLink` pointing at the GitHub release page. Sparkle loads that into a WebView **inside** the update window, so the whole GitHub page rendered in a small panel and showed nothing offline. The item carries `<description>` instead; if both are present the **link wins**, so the link must be absent.

Generating copy from commit subjects was tried: this repo takes direct commits, so the range ran to ~40 subjects a release, half of them “Update README”. Kept only as a fallback so a forgotten entry ships something rather than an empty dialog.

`Scripts/changelog.py` understands bullets, bold, code, and links. Description carries **spacing only** — Sparkle injects `ReleaseNotesColorStyle.css` (white text in dark mode, transparent background). A feed that brings its own palette fights that. Historical check: description rendered in a `WKWebView` with Sparkle’s stylesheet, both appearances.

Apple signing was once treated as required for Sparkle; that cost a release cycle of waiting for a Developer ID. EdDSA is what makes updates safe without it. Notarisation still matters for Gatekeeper on **first** launch, which no updater can fix.

Current: [../releasing.md](../releasing.md).
