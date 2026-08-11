#!/bin/bash
#
# Repro harness for "I allowed location and the map didn't pan".
#
# The permission has to be reset and a fix simulated before the app launches,
# which only the shell can do — so 3WoodUITests/LocationProbe skips itself
# unless this script is driving. It taps "Allow Once" and attaches before/after
# screenshots; check the "after" shot for whether the camera actually moved.
#
# WORTH KNOWING: a simulator answers requestLocation() instantly with a perfect
# fix, so this harness cannot reproduce the device-only failure it was written
# for — a real iPhone often returns kCLErrorLocationUnknown on the first
# attempt. This proves the happy path still works; it does not prove the retry
# in LocationProvider does. That one needs a real device.
#
# Requires a booted iPhone 17 Pro and the local stack running.
#
set -uo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
LOG=$(mktemp -t location-probe)
cd "$REPO"

if ! xcrun simctl list devices booted | grep -q "iPhone 17 Pro"; then
  echo "Booting iPhone 17 Pro..."
  xcrun simctl boot "iPhone 17 Pro" || true
  sleep 8
fi

xcrun simctl privacy booted reset location com.leonan.threewood || true
# Pebble Beach — far enough from the US-wide default that a pan is unmistakable.
xcrun simctl location booted set 36.5725,-121.9486 || true
echo "Permission reset, location set to Pebble Beach."

TEST_RUNNER_LOCATION_PROBE=1 \
xcodebuild -project 3Wood.xcodeproj -scheme 3Wood \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:3WoodUITests/LocationProbe test >"$LOG" 2>&1
echo "exit=$?"

grep -E "Test Case .* (passed|failed)|error:|TEST (SUCCEEDED|FAILED)" "$LOG" | head

RESULT=$(ls -td "$HOME"/Library/Developer/Xcode/DerivedData/3Wood-*/Logs/Test/*.xcresult 2>/dev/null | head -1)
echo
echo "Screenshots: xcrun xcresulttool export attachments --path $RESULT --output-path <dir>"
