#!/bin/bash
set -euo pipefail

task_root="$(cd "$(dirname "$0")/.." && pwd)"
test_build_dir="$(mktemp -d "${TMPDIR:-/tmp}/cqb-member-floor-plan.XXXXXX")"
trap 'rm -rf "$test_build_dir"' EXIT
developer_dir="/Applications/Xcode.app/Contents/Developer"
macos_sdk="$developer_dir/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

core_sources=(
  "$task_root/CQB/Packages/CQBCore/Sources/CQBCore/"*.swift
  "$task_root/CQB/Packages/CQBCore/Sources/CQBCore/Models/"*.swift
  "$task_root/CQB/Packages/CQBCore/Sources/CQBCore/Repositories/"*.swift
)
route_sources=("$task_root/CQB/MemberApp/Services/RouteCorrection/"*.swift)

env DEVELOPER_DIR="$developer_dir" \
  "$developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" -sdk "$macos_sdk" \
  -parse-as-library -emit-module -emit-library -module-name CQBCore \
  -module-cache-path "$test_build_dir/ModuleCache" \
  "${core_sources[@]}" \
  -o "$test_build_dir/libCQBCore.dylib"

env DEVELOPER_DIR="$developer_dir" \
  "$developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" -sdk "$macos_sdk" \
  -parse-as-library -module-cache-path "$test_build_dir/ModuleCache" \
  -I "$test_build_dir" -L "$test_build_dir" -lCQBCore \
  "${route_sources[@]}" \
  "$task_root/CQB/MemberApp/Services/BundledTrainingMapLoader.swift" \
  "$task_root/Tests/MemberFloorPlanChecks.swift" \
  -framework ImageIO -framework CoreGraphics \
  -o "$test_build_dir/MemberFloorPlanChecks"

DYLD_LIBRARY_PATH="$test_build_dir${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
  "$test_build_dir/MemberFloorPlanChecks" \
  "$task_root/CQB/MemberApp/Resources/TrainingMap"
