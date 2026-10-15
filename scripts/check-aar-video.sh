#!/bin/bash
set -euo pipefail

task_root="$(cd "$(dirname "$0")/.." && pwd)"
test_build_dir="$(mktemp -d "${TMPDIR:-/tmp}/cqb-aar-video.XXXXXX")"
core_sources=(
  "$task_root/CQB/Packages/CQBCore/Sources/CQBCore/"*.swift
  "$task_root/CQB/Packages/CQBCore/Sources/CQBCore/"*/*.swift
)
xcrun swiftc -parse-as-library -emit-module -emit-library -module-name CQBCore \
  -module-cache-path "$test_build_dir/ModuleCache" \
  "${core_sources[@]}" \
  -o "$test_build_dir/libCQBCore.dylib"

xcrun swiftc -parse-as-library -module-cache-path "$test_build_dir/ModuleCache" \
  -I "$test_build_dir" -L "$test_build_dir" -lCQBCore \
  "$task_root/CQB/InstructorApp/Services/AAR/"*.swift \
  "$task_root/Tests/AARVideoChecks.swift" \
  -o "$test_build_dir/AARVideoChecks"
DYLD_LIBRARY_PATH="$test_build_dir${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
  "$test_build_dir/AARVideoChecks"
