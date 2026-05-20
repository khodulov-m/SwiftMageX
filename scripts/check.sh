#!/usr/bin/env bash
# Local pre-commit gate: build + test, matching what CI will run when it lands.
# Keep this script a one-liner of intent so a future CI hook is one line too.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build
swift test
