#!/usr/bin/env bash
# Run from any directory; use a booted simulator/emulator ID from `flutter devices`.
set -euo pipefail
if [[ $# -ne 1 || -z "$1" ]]; then
  echo 'Usage: bash tool/validate_optimization.sh <simulator-or-emulator-id>' >&2
  exit 64
fi
cd "$(dirname "$0")/.."
flutter analyze
flutter test
flutter build web --release
flutter test integration_test/platform_smoke_test.dart -d "$1"
flutter test integration_test/app_test.dart -d "$1"
echo 'Static analysis, automated tests, Web build and both device suites passed.'
