#!/bin/sh
# Builds a debug copy of the current branch beside the others, so two branches can be
# tried one after the other: build/dev/Skillori (<branch>).app. Quit any other Skillori
# first; they share their settings and their saved readings.
set -e
cd "$(dirname "$0")/.."
branch=$(git branch --show-current)
name="Skillori ($branch)"
xcodegen generate >/dev/null
xcodebuild -project Skillori.xcodeproj -scheme Skillori -configuration Debug \
    -derivedDataPath "build/DerivedData-dev/$branch" build -quiet
mkdir -p build/dev
rm -rf "build/dev/$name.app"
cp -R "build/DerivedData-dev/$branch/Build/Products/Debug/Skillori.app" "build/dev/$name.app"
echo "build/dev/$name.app"
