#!/bin/bash
# Optional local regression; external experiment data never enters app resources.
set -euo pipefail
if [ "$#" -ne 3 ]; then
  echo 'Usage: bash scripts/check-recorded-track-regression.sh <Plans.zip> <experiment.json> <floorplanPoC directory>' >&2
  exit 2
fi
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
zip_path="$1"
experiment_path="$2"
poc_root="$3/FloorPlanPoC"
run_root="$(mktemp -d /private/tmp/cqb-recorded-regression.XXXXXX)"
# UUID-only path components and exactly one of each file; extract only this revision.
map_relative="$(node - "$zip_path" "$experiment_path" <<'NODE'
const fs=require('fs'), cp=require('child_process');
const [zip, file]=process.argv.slice(2), b=JSON.parse(fs.readFileSync(file)).navigationBinding;
const uuid=/^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/;
if(!b || !uuid.test(b.planID) || !uuid.test(b.revisionID)) throw Error('Invalid navigation binding');
const root=`Plans/${b.planID}/Revisions/${b.revisionID}`;
const entries=cp.execFileSync('/usr/bin/unzip',['-Z1',zip],{encoding:'utf8',maxBuffer:16*1024*1024}).split('\n');
for(const name of ['original.png','floorplan.json','navigation-map.json','base-mask.bin','resolved-mask.bin']) {
  if(entries.filter(x=>x===`${root}/${name}`).length!==1) throw Error(`Missing/duplicate ${name}`);
}
console.log(root);
NODE
)"
unzip -q "$zip_path" "$map_relative/original.png" "$map_relative/floorplan.json" \
  "$map_relative/navigation-map.json" "$map_relative/base-mask.bin" "$map_relative/resolved-mask.bin" -d "$run_root"
core_root="$repo_root/CQB/Packages/CQBCore/Sources/CQBCore"
swiftc -O -swift-version 6 -emit-library -emit-module -module-name CQBCore \
  -module-cache-path "$run_root/module-cache" -emit-module-path "$run_root/CQBCore.swiftmodule" \
  "$core_root"/Models/*.swift "$core_root"/Services/*.swift -o "$run_root/libCQBCore.dylib"
poc_sources=(
  AnchoredRouteCorrector MapMatching NonrigidRouteMatcher InitialHeadingMatcher RouteHeading
  RecordingStore TestBuild FloorPlanWallDetector NavigationMapIdentity Models Geometry
  NavigationMask WallMapAnalyzer GuidedWallRecognizer
)
compile_sources=()
for source in "${poc_sources[@]}"; do compile_sources+=("$poc_root/$source.swift"); done
swiftc -O -swift-version 6 -module-cache-path "$run_root/module-cache" \
  -I "$run_root" -L "$run_root" -lCQBCore -Xlinker -rpath -Xlinker "$run_root" \
  "${compile_sources[@]}" \
  "$repo_root/CQB/Packages/CQBCore/Sources/CQBImageIO/PNGFloorPlanImageValidator.swift" \
  "$repo_root/scripts/RecordedTrackRegression.swift" -o "$run_root/RecordedTrackRegression"
echo "Derived artifacts (originals untouched): $run_root"
"$run_root/RecordedTrackRegression" "$experiment_path" "$run_root/$map_relative" "$run_root" "$poc_root"
