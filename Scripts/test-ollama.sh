#!/bin/bash
# Tests the production Foundation-only adapter without launching Pulse or using credentials.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -warnings-as-errors \
    Sources/Pulse/OllamaCloudClient.swift Tests/OllamaCloudTests.swift \
    -o "$TEST_DIR/ollama-tests"
"$TEST_DIR/ollama-tests"
