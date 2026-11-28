# Windows preview

This directory contains an experimental, unofficial Windows Electron port of Pulse. It is a separate implementation, not a Windows build of the Swift/macOS app. The Windows port is a work in progress: UI fidelity, provider authentication paths, multiple accounts and live-account compatibility need further review.

## Run and test

On Windows with Node.js 22.12 or later and npm installed:

```powershell
cd Windows
npm ci
npm start
npm test
```

The tests use public provider fixtures from the repository's `Tests/PulseTests/Fixtures` directory. They cover parsers and isolated behaviour; passing them does not establish that every provider works with a live account. Codex and Antigravity were checked with live local installations on one Windows machine. The app stores settings under the current user's Windows application-data directory, and the user chooses which providers to enable.

The application is unsigned and is not an official Pulse release. See [the Windows design and limitations](../Docs/windows.md), the repository's Apache-2.0 license, and [third-party notices](THIRD_PARTY_NOTICES.md).
