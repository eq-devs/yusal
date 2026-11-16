#!/usr/bin/env bash
# Builds the app for testing and installs it on every phone plugged into
# this computer. Test builds always have the test login and voice control
# on (config/dart_defines.dev.json); nothing needs to be remembered.
#
#   scripts/install_dev.sh            # every connected Android phone and iPhone
#   scripts/install_dev.sh android    # Android only
#   scripts/install_dev.sh ios        # iPhone only
set -euo pipefail
cd "$(dirname "$0")/.."

defines=config/dart_defines.dev.json
what=${1:-all}

flutter pub get

if [[ $what == all || $what == android ]]; then
  phones=$(adb devices | awk 'NR > 1 && $2 == "device" { print $1 }')
  if [[ -z $phones ]]; then
    echo "No Android phone connected (plug it in, unlock it, allow USB debugging)."
  else
    flutter build apk --release --dart-define-from-file="$defines"
    for phone in $phones; do
      adb -s "$phone" install -r build/app/outputs/flutter-apk/app-release.apk
      echo "Installed on Android $phone"
    done
  fi
fi

if [[ $what == all || $what == ios ]]; then
  # Rows of `flutter devices` look like: name • id • ios • iOS 18.1
  iphones=$(flutter devices 2>/dev/null |
    awk -F' • ' '$3 ~ /^ios/ && $4 !~ /simulator/ { print $2 }')
  if [[ -z $iphones ]]; then
    echo "No iPhone connected (plug it in, unlock it, tap Trust, turn on Developer Mode)."
  else
    flutter build ios --release --dart-define-from-file="$defines"
    for iphone in $iphones; do
      flutter install --release -d "$iphone"
      echo "Installed on iPhone $iphone"
    done
  fi
fi
