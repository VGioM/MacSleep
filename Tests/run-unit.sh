#!/bin/bash
# Unit tests (release.sh runs them before publishing).
set -euo pipefail
cd "$(dirname "$0")/.."
swift test "$@"
