#!/bin/bash
set -euo pipefail

task_root="$(cd "$(dirname "$0")/.." && pwd)"
test_build_dir="$(mktemp -d "${TMPDIR:-/tmp}/cqb-instructor-checks.XXXXXX")"
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
  "$task_root/CQB/InstructorApp/Models/InstructorFloorPlan.swift" \
  "$task_root/CQB/InstructorApp/Models/LocalFloorPlan.swift" \
  "$task_root/CQB/InstructorApp/Models/LocalWorldMap.swift" \
  "$task_root/CQB/InstructorApp/Services/FloorPlanImporting.swift" \
  "$task_root/CQB/InstructorApp/Services/WorldMapScanning.swift" \
  "$task_root/CQB/InstructorApp/Services/Persistence/FloorPlanCatalogRepository.swift" \
  "$task_root/CQB/InstructorApp/Services/Import/"*.swift \
  "$task_root/CQB/InstructorApp/Services/Geometry/"*.swift \
  "$task_root/CQB/InstructorApp/Services/AAR/AARFloorPlanLayout.swift" \
  "$task_root/CQB/InstructorApp/Services/Storage/"*.swift \
  "$task_root/CQB/InstructorApp/Stores/FloorPlanDraftStore.swift" \
  "$task_root/CQB/InstructorApp/Stores/InstructorPhase.swift" \
  "$task_root/CQB/InstructorApp/Stores/InstructorMockData.swift" \
  "$task_root/CQB/InstructorApp/Stores/InstructorStore.swift" \
  "$task_root/CQB/InstructorApp/Stores/TrainingRecordStore.swift" \
  "$task_root/Tests/InstructorStoreChecks.swift" \
  "$task_root/Tests/TrainingLifecycleChecks.swift" \
  -o "$test_build_dir/InstructorStoreChecks"
DYLD_LIBRARY_PATH="$test_build_dir${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
  "$test_build_dir/InstructorStoreChecks"
