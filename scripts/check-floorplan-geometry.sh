#!/bin/bash
set -euo pipefail

task_root="$(cd "$(dirname "$0")/.." && pwd)"
test_build_dir="$(mktemp -d "${TMPDIR:-/tmp}/cqb-floorplan-geometry.XXXXXX")"

xcrun swiftc -parse-as-library -module-cache-path "$test_build_dir/ModuleCache" \
  "$task_root/CQB/InstructorApp/Models/LocalFloorPlan.swift" \
  "$task_root/CQB/InstructorApp/Services/Geometry/LocalFloorPlanGeometry.swift" \
  "$task_root/CQB/InstructorApp/Services/Geometry/LocalFloorPlanMaskRenderer.swift" \
  "$task_root/Tests/FloorPlanGeometryChecks.swift" \
  -o "$test_build_dir/FloorPlanGeometryChecks"
"$test_build_dir/FloorPlanGeometryChecks"
