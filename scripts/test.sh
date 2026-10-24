#!/usr/bin/env bash
# Runs the Whoosh unit tests. Used by the Kiro "run-tests-after-task" hook and by hand.
# Skips cleanly until the Xcode project exists (task 1).
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="Whoosh.xcodeproj"
SCHEME="Whoosh"
DEST="${WHOOSH_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 16,OS=18.6}"

if [ ! -d "$PROJECT" ]; then
  echo "[whoosh-tests] $PROJECT not found yet (task 1 not done); skipping."
  exit 0
fi

xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DEST" \
  -quiet 2>&1 | tail -40
