# Windows preview

`Windows/` is an experimental Electron port, separate from the macOS Swift application. It includes a Windows floating rail, settings, provider readers, notifications, extensions and local usage summaries. The macOS target remains unchanged.

Run `npm ci`, `npm start` and `npm test` from `Windows/` on Windows with Node.js 22.12 or later. Tests use the existing upstream fixtures. The application uses the current user's application-data directory for settings; local credentials are protected with Windows encryption where supported. Temporary files are scoped under the current user's local application data.

This is a review preview. UI fidelity, provider login and account coverage, Windows packaging, accessibility, live-account compatibility and long-running behaviour have not been comprehensively validated. Some providers require manual credentials or have only sample and mocked coverage. Windows builds and tests do not replace macOS build, localization or release verification. The current directory is not an official signed release or installer.

The Antigravity reader checks the process and listening port before using a current local hub record, and connects over loopback; on this development machine the local service returned Gemini and Claude/GPT quota windows. Provider endpoints and local formats can change.
