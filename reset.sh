#!/bin/bash

set -e

echo "👉 Flutter clean..."
flutter clean

echo "👉 Flutter pub get..."
flutter pub get

echo "👉 iOS pod install..."
cd ios
pod install
cd ..

echo "✅ Done!"
