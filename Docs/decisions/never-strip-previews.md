# Never strip `#Preview`

**Status:** still in force. **Evidence:** historical shipping failure, plus how the macro is expanded.

`#Preview` is expanded by an Xcode plugin. If `xcode-select` points at Command Line Tools, every build fails with `PreviewsMacros plugin not found`.

Stripping the blocks produces a clean `swift build` while leaving errors **inside** those blocks unreported. That already shipped a broken build to a user. Do not “fix” the toolchain mismatch that way.

A clean `swift build` is also not Xcode’s check. Actor-isolation mistakes can be warnings in the CLI and hard errors in Xcode (every `View` is `@MainActor`). One nonisolated helper reaching for a constant on a `View` produced a wall of “cannot find type X in scope” pointing anywhere but the cause.

Current commands: [../build-from-source.md](../build-from-source.md).
