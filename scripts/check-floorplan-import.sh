#!/bin/bash
set -euo pipefail

task_root="$(cd "$(dirname "$0")/.." && pwd)"
test_build_dir="$(mktemp -d "${TMPDIR:-/tmp}/cqb-floorplan-import.XXXXXX")"
xcrun swiftc -parse-as-library -module-cache-path "$test_build_dir/ModuleCache" \
  "$task_root/CQB/InstructorApp/Models/LocalFloorPlan.swift" \
  "$task_root/CQB/InstructorApp/Services/FloorPlanImporting.swift" \
  "$task_root/CQB/InstructorApp/Services/Import/LocalV13WallDetector.swift" \
  "$task_root/CQB/InstructorApp/Services/Import/LocalFloorPlanImportService.swift" \
  "$task_root/Tests/FloorPlanImportChecks.swift" \
  -o "$test_build_dir/FloorPlanImportChecks"
"$test_build_dir/FloorPlanImportChecks"
