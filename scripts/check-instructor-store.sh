#!/bin/bash
set -euo pipefail

task_root="$(cd "$(dirname "$0")/.." && pwd)"
test_build_dir="$(mktemp -d "${TMPDIR:-/tmp}/cqb-instructor-checks.XXXXXX")"

xcrun swiftc -parse-as-library -module-cache-path "$test_build_dir/ModuleCache" \
  "$task_root/CQB/InstructorApp/Models/LocalFloorPlan.swift" \
  "$task_root/CQB/InstructorApp/Services/FloorPlanImporting.swift" \
  "$task_root/CQB/InstructorApp/Services/Import/"*.swift \
  "$task_root/CQB/InstructorApp/Services/Geometry/"*.swift \
  "$task_root/CQB/InstructorApp/Stores/FloorPlanDraftStore.swift" \
  "$task_root/CQB/InstructorApp/Stores/InstructorPhase.swift" \
  "$task_root/CQB/InstructorApp/Stores/InstructorMockData.swift" \
  "$task_root/CQB/InstructorApp/Stores/InstructorStore.swift" \
  "$task_root/Tests/InstructorStoreChecks.swift" \
  -o "$test_build_dir/InstructorStoreChecks"
"$test_build_dir/InstructorStoreChecks"
