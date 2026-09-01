# Build from source

```bash
swift run Pulse              # build and run
swift build                  # type-check everything, previews included
./Scripts/bundle.sh          # → build.noindex/Pulse.app
./Scripts/dmg.sh             # → build.noindex/Pulse-<version>.dmg
```

`xcode-select` has to point at Xcode rather than CommandLineTools — the
`#Preview` macro is expanded by a plugin that ships with Xcode. If a build
fails with `PreviewsMacros plugin not found`:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Swift tools 6.0; the package opens directly in Xcode through `Package.swift`.
There is no test target and no linter.
