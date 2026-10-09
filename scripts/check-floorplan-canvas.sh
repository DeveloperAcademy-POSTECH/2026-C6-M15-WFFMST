#!/bin/bash
set -euo pipefail

# Pass the UDID of an already booted iPad Simulator. No project or device settings are changed.
test_device="${1:?Usage: bash scripts/check-floorplan-canvas.sh <booted-simulator-UDID>}"
task_root="$(cd "$(dirname "$0")/.." && pwd)"
test_build_dir="$(mktemp -d "${TMPDIR:-/tmp}/cqb-floorplan-canvas.XXXXXX")"
test_app="$test_build_dir/FloorPlanCanvasChecks.app"
test_bundle="com.cqb.tests.floorplan-canvas"
mkdir -p "$test_app"
test_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
test_arch="$(uname -m)"
xcrun --sdk iphonesimulator swiftc -parse-as-library -swift-version 5 \
  -sdk "$test_sdk" -target "${test_arch}-apple-ios17.0-simulator" \
  -module-cache-path "$test_build_dir/ModuleCache" \
  "$task_root/CQB/InstructorApp/Models/LocalFloorPlan.swift" \
  "$task_root/CQB/InstructorApp/Features/FloorPlan/Editing/LocalFloorPlanCanvas.swift" \
  "$task_root/Tests/FloorPlanCanvasChecks.swift" \
  -o "$test_app/FloorPlanCanvasChecks"
plutil -create xml1 "$test_app/Info.plist"
plutil -insert CFBundleIdentifier -string "$test_bundle" "$test_app/Info.plist"
plutil -insert CFBundleExecutable -string FloorPlanCanvasChecks "$test_app/Info.plist"
plutil -insert CFBundleName -string FloorPlanCanvasChecks "$test_app/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$test_app/Info.plist"
plutil -insert CFBundleVersion -string 1 "$test_app/Info.plist"
plutil -insert CFBundleShortVersionString -string 1.0 "$test_app/Info.plist"
plutil -insert MinimumOSVersion -string 17.0 "$test_app/Info.plist"
plutil -insert UIDeviceFamily -json '[2]' "$test_app/Info.plist"
plutil -insert UIApplicationSceneManifest -json '{"UIApplicationSupportsMultipleScenes":false}' "$test_app/Info.plist"
codesign --force --sign - "$test_app"
xcrun simctl install "$test_device" "$test_app"
test_data="$(xcrun simctl get_app_container "$test_device" "$test_bundle" data)"
# Move previous output aside so this run cannot pass with an old result.
test_result="$test_data/Documents/canvas-check-result.txt"
if [ -f "$test_result" ]; then mv "$test_result" "$test_build_dir/previous-result.txt"; fi
xcrun simctl launch --terminate-running-process "$test_device" "$test_bundle"
for attempt in $(seq 1 100); do
  if [ -f "$test_result" ]; then
    cat "$test_result"
    if rg -q '^PASS:' "$test_result"; then exit 0; else exit 1; fi
  fi
  sleep 0.2
done
echo "FAIL: Canvas harness timed out after 20 seconds"
exit 1
